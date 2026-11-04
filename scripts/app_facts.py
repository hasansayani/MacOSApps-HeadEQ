#!/usr/bin/env python3
"""App Facts — the standard "nutrition facts" label for every app in this workspace.

Measures the code and the built apps, then writes for each app in docs/app-facts.config.json:

  docs/app-facts-<id>.svg         the label (embedded in README)
  docs/app-facts-<id>.json        the raw measurements behind it
  docs/app-facts-<id>.label.json  the label as drawing ops (bundled into the app for its in-app panel)

Every app gets the same sections, in the same order (format introduced by Cascade):
  Serving size · Amount per download (download, installed size, slices, dependencies, private APIs)
  · Code · Tests · Permissions & Privacy · Performance · Compatibility · INGREDIENTS · CONTAINS · footnotes

Usage:
  scripts/app_facts.py                      # build, test, measure everything, regenerate
  scripts/app_facts.py --only macos         # one app (ids from the config)
  scripts/app_facts.py --skip-runtime       # keep previous CPU/memory/benchmark numbers
  scripts/app_facts.py --render-only        # redraw from the existing docs/app-facts-<id>.json

Config keys per app (see docs/app-facts.config.json): id, name, tagline, platform (macos|ios), serving,
code_targets {label: [dirs]}, sources [dirs], test_dirs, permissions [[name, value, bold]],
privacy [[name, value]], background, ui_layer, compatibility [[name, value, bold]], contains, footnotes,
plus platform keys (macOS: app, build, test, benchmark_env, bundle_process; iOS: project, scheme, simulator,
bundle_id, entitlements).
Optional: test_kind "selftest" with selftest_product (a `swift run` assertion executable printing
"✓ N checks passed"; coverage comes from an instrumented build of it), and benchmark_detail, a format string over
the benchmark JSON for the row under the median (default "({sensors} probes, {runs} runs)"). A benchmark may also
return "extra": [[name, value], …] rows.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
CONFIG = DOCS / "app-facts.config.json"


def sh(*cmd, check=True, cwd=ROOT, env=None, timeout=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env, timeout=timeout)
    if check and p.returncode != 0:
        sys.exit(f"✗ {' '.join(map(str, cmd))} failed:\n{(p.stdout + p.stderr)[-3000:]}")
    return p.stdout.strip() + ("\n" + p.stderr.strip() if p.stderr.strip() and not check else "")


def log(msg):
    print(msg, flush=True)


# ---------------------------------------------------------------------------------------------
# Source measurements (platform independent)

def swift_files(dirs):
    return sorted(f for d in dirs for f in (ROOT / d).rglob("*.swift") if ".build" not in f.parts)


def code_stats(targets):
    stats = {}
    for label, dirs in targets.items():
        files = swift_files(dirs)
        code = comments = blank = 0
        for f in files:
            for line in f.read_text().splitlines():
                s = line.strip()
                if not s:
                    blank += 1
                elif s.startswith("//"):
                    comments += 1
                else:
                    code += 1
        stats[label] = {"files": len(files), "code": code, "comments": comments, "blank": blank}
    return stats


def platform_imports(text, platform):
    """`import X` lines that apply to `platform`, honouring simple #if os(macOS)/#else/#endif blocks."""
    active, stack, found = True, [], set()
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"#if\s+(!?)os\((\w+)\)", s)
        if m:
            neg, os_name = m.group(1) == "!", m.group(2).lower()
            cond = (os_name == platform) != neg
            stack.append((active, cond))
            active = active and cond
        elif s.startswith("#if"):
            stack.append((active, True))
        elif s.startswith("#else") and stack:
            parent, cond = stack[-1]
            active = parent and not cond
        elif s.startswith("#endif") and stack:
            active, _ = stack.pop()
        elif active:
            m = re.match(r"(?:@\w+\s+)?import\s+(\w+)", s)
            if m:
                found.add(m.group(1))
    return found


def security_stats(app_cfg):
    files = swift_files(app_cfg["sources"])
    texts = {f: f.read_text() for f in files}
    platform = "macos" if app_cfg["platform"] == "macos" else "ios"
    sources = "\n".join(texts.values())
    frameworks = set()
    for t in texts.values():
        frameworks |= platform_imports(t, platform)
    # Private symbols resolved at runtime via dlsym (or a `sym("…")` helper). The iOS build compiles none of them.
    private = set(re.findall(r'(?:dlsym\(\w+,\s*|sym\()"(\w+)"', sources)) if platform == "macos" else set()
    # Private Objective-C classes resolved by name (NSClassFromString / a className: argument).
    private |= {c for c in re.findall(r'(?:NSClassFromString\(|className:\s*)"(\w+)"', sources)} if platform == "macos" else set()
    private_frameworks = sorted(set(re.findall(r"PrivateFrameworks/(\w+)\.framework", sources))
                                | set(re.findall(r'PrivateSettings\(framework:\s*"(\w+)"', sources))) if platform == "macos" else []
    package = (ROOT / "Package.swift").read_text() if (ROOT / "Package.swift").exists() else ""
    return {
        "frameworks": sorted(frameworks - {"Foundation"} - {p.name for p in (ROOT / "Sources").glob("*") if p.is_dir()}),
        "private_apis": sorted(private),
        "private_frameworks": private_frameworks,
        "dependencies": len(re.findall(r"\.package\(", package)),
        "internet_call_sites": len(re.findall(r"\bURLSession\b|\bURLRequest\b|NSURLConnection", sources)),
        "local_network": bool(re.search(r"\bNWListener\b|\bNWBrowser\b|\bNWConnection\b", sources)),
    }


def machine():
    chip = sh("sysctl", "-n", "machdep.cpu.brand_string", check=False).splitlines()[0]
    return f"{chip}, macOS {sh('sw_vers', '-productVersion')}"


def dir_bytes(path):
    return sum(f.stat().st_size for f in Path(path).rglob("*") if f.is_file() and not f.is_symlink())


def slices(binary):
    out = {}
    for arch in sh("lipo", "-archs", str(binary)).split():
        with tempfile.NamedTemporaryFile() as t:
            sh("lipo", str(binary), "-thin", arch, "-output", t.name, check=False)
            out[arch] = os.path.getsize(t.name) if os.path.getsize(t.name) else binary.stat().st_size
    return out


def zip_bytes(app, payload=False):
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(app)
        if payload:  # an .ipa is a zip with the app inside Payload/
            (Path(tmp) / "Payload").mkdir()
            shutil.copytree(app, Path(tmp) / "Payload" / src.name, symlinks=True)
            src = Path(tmp) / "Payload"
        z = Path(tmp) / "out.zip"
        sh("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(src), str(z))
        return z.stat().st_size


def xctest_summary(output):
    """`swift test` XCTest output: the last "Executed N tests, with S tests skipped and F failures" line."""
    runs = re.findall(r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?", output)
    if not runs:
        return None
    total, skipped, failed = (int(x or 0) for x in runs[-1])
    suites = {m for m in re.findall(r"Test Suite '([^']+)' started", output)
              if m not in ("All tests", "Selected tests") and not m.endswith(".xctest")}
    return {"passed": total - skipped - failed, "failed": failed, "skipped": skipped, "suites": len(suites)}


def swift_testing_summary(output):
    runs = re.findall(r"Test run with (\d+) tests? in (\d+) suites? (passed|failed)(?:.*?with (\d+) issues?)?", output)
    if not runs:
        return None
    total, suites, status, issues = runs[-1]
    skipped = len(re.findall(r"➜ Test \S.* skipped", output))
    failed = int(issues or 0) if status == "failed" else 0
    return {"passed": int(total) - skipped - failed, "failed": failed, "skipped": skipped, "suites": int(suites)}


def llvm_cov_summary(export_json, prefix):
    lines = [0, 0]
    funcs = [0, 0]
    for f in export_json["data"][0]["files"]:
        if f"/{prefix}/" in f["filename"]:
            s = f["summary"]
            lines[0] += s["lines"]["covered"]; lines[1] += s["lines"]["count"]
            funcs[0] += s["functions"]["covered"]; funcs[1] += s["functions"]["count"]
    pct = lambda c, n: round(100 * c / n, 1) if n else 0.0
    return {"lines_pct": pct(*lines), "functions_pct": pct(*funcs)}


def selftest_results(cfg):
    """Runs a self-test executable, then an instrumented build of it for coverage of cfg["coverage_dir"]."""
    product = cfg["selftest_product"]
    out = sh(*cfg["test"], check=False)
    m = re.search(r"✓ (\d+) checks passed(?: in (\d+) suites)?", out)
    f = re.search(r"✗ (\d+) of (\d+) checks failed", out)
    if m:
        tests = {"passed": int(m.group(1)), "failed": 0, "skipped": 0, "suites": int(m.group(2) or 1)}
    elif f:
        tests = {"passed": int(f.group(2)) - int(f.group(1)), "failed": int(f.group(1)), "skipped": 0,
                 "suites": len(re.findall(r"^  [✓✗] ", out, re.M)) or 1}
    else:
        tests = {"passed": 0, "failed": 0, "skipped": 0, "suites": 0}
    scratch = str(ROOT / ".build" / "coverage")
    flags = ["-Xswiftc", "-profile-generate", "-Xswiftc", "-profile-coverage-mapping"]
    sh("swift", "build", "--scratch-path", scratch, "--product", product, *flags)
    binary = Path(sh("swift", "build", "--scratch-path", scratch, "--product", product, "--show-bin-path")) / product
    with tempfile.TemporaryDirectory() as tmp:
        raw, data = Path(tmp) / "cov.profraw", Path(tmp) / "cov.profdata"
        subprocess.run([str(binary)], cwd=ROOT, env={**os.environ, "LLVM_PROFILE_FILE": str(raw)}, capture_output=True)
        sh("xcrun", "llvm-profdata", "merge", "-sparse", str(raw), "-o", str(data))
        export = json.loads(sh("xcrun", "llvm-cov", "export", str(binary), f"-instr-profile={data}", "-summary-only"))
    return tests, llvm_cov_summary(export, cfg["coverage_dir"])


def sample_process(pid, window=20):
    def cpu_seconds():
        t = sh("ps", "-o", "time=", "-p", str(pid), check=False).strip()
        parts = [float(p) for p in t.replace("-", ":").split(":") if p]
        return sum(v * 60 ** i for i, v in enumerate(reversed(parts)))
    start = cpu_seconds()
    time.sleep(window)
    return {
        "idle_cpu_pct": round((cpu_seconds() - start) / window * 100, 2),
        "idle_memory_mb": round(int(sh("ps", "-o", "rss=", "-p", str(pid))) / 1024, 1),
        "threads": len(sh("ps", "-M", "-p", str(pid)).splitlines()) - 1,
    }


# ---------------------------------------------------------------------------------------------
# macOS app

def measure_macos(cfg, previous, skip_runtime):
    app = ROOT / cfg["app"]
    log("  building"); sh(*cfg["build"])
    log("  testing (with coverage)")
    if cfg.get("test_kind") == "selftest":
        tests, coverage = selftest_results(cfg)
    else:
        out = sh(*cfg["test"], "--enable-code-coverage", check=False)
        xc = xctest_summary(out)
        st = swift_testing_summary(out)
        tests = xc if xc and (not st or xc["passed"] + xc["failed"] >= st["passed"] + st["failed"]) else \
            (st or {"passed": 0, "failed": 0, "skipped": 0, "suites": 0})
        cov_path = sh(*cfg["test"], "--show-codecov-path", check=False).splitlines()[0]
        coverage = llvm_cov_summary(json.loads(Path(cov_path).read_text()), cfg["coverage_dir"])

    plist = app / "Contents" / "Info.plist"
    binary = app / "Contents" / "MacOS" / sh("/usr/libexec/PlistBuddy", "-c", "Print CFBundleExecutable", str(plist))
    sig = subprocess.run(["codesign", "-dvv", str(app)], capture_output=True, text=True).stderr
    ent = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)], capture_output=True, text=True).stdout
    report = {
        "version": sh("/usr/libexec/PlistBuddy", "-c", "Print CFBundleShortVersionString", str(plist)),
        "min_os": sh("/usr/libexec/PlistBuddy", "-c", "Print LSMinimumSystemVersion", str(plist)),
        "tests": tests,
        "coverage": coverage,
        "size": {"app_bytes": dir_bytes(app), "slices": slices(binary), "download_bytes": zip_bytes(app)},
        "signing": {
            "signature": "Ad-hoc" if "Signature=adhoc" in sig else "Developer ID",
            "hardened_runtime": "runtime" in re.findall(r"flags=0x\w+\(([^)]*)\)", sig)[0] if "flags=" in sig else False,
            "entitlements": len(re.findall(r"<key>", ent)),
            "sandbox": "com.apple.security.app-sandbox" in ent,
        },
    }
    rt = dict(previous.get("runtime", {}))
    if not skip_runtime:
        log("  benchmarking")
        with tempfile.TemporaryDirectory() as tmp:
            out_json = Path(tmp) / "bench.json"
            env = {**os.environ, cfg["benchmark_env"]: str(out_json)}
            subprocess.run([str(binary)], env=env, capture_output=True, timeout=180)
            if out_json.exists():
                rt["benchmark"] = json.loads(out_json.read_text())
        log("  sampling the running app for 20 s")
        pid = sh("pgrep", "-x", cfg["bundle_process"], check=False).split()
        launched = False
        if not pid:
            subprocess.run(["open", "-g", str(app)])
            launched = True
            time.sleep(10)  # let it settle
            pid = sh("pgrep", "-x", cfg["bundle_process"], check=False).split()
        if pid:
            rt.update(sample_process(pid[0]))
        if launched and pid:
            subprocess.run(["kill", pid[0]])
    report["runtime"] = rt
    return report


# ---------------------------------------------------------------------------------------------
# iOS app

def measure_ios(cfg, previous, skip_runtime):
    proj, scheme, sim = str(ROOT / cfg["project"]), cfg["scheme"], cfg["simulator"]
    with tempfile.TemporaryDirectory() as tmp:
        result = Path(tmp) / "tests.xcresult"
        log("  testing in the Simulator (with coverage)")
        subprocess.run(["xcodebuild", "-project", proj, "-scheme", scheme, "-destination", f"platform=iOS Simulator,name={sim}",
                        "-derivedDataPath", f"{tmp}/dd", "-resultBundlePath", str(result), "-enableCodeCoverage", "YES", "test"],
                       capture_output=True, text=True)
        tree = json.loads(sh("xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result)))
        suites = 0

        def tally(node, acc):
            nonlocal suites
            if node.get("nodeType") == "Test Suite":
                suites += 1
            if node.get("nodeType") == "Test Case":
                acc[node.get("result")] = acc.get(node.get("result"), 0) + 1
            for c in node.get("children", []):
                tally(c, acc)
            return acc
        counts = {}
        for plan in tree.get("testNodes", []):
            tally(plan, counts)
        tests = {"passed": counts.get("Passed", 0), "failed": counts.get("Failed", 0),
                 "skipped": counts.get("Skipped", 0), "suites": suites}
        cov = json.loads(sh("xcrun", "xccov", "view", "--report", "--json", str(result)))
        app_target = next((t for t in cov.get("targets", []) if t["name"].endswith(".app")), None)
        core_files = [f for t in cov.get("targets", []) for f in t.get("files", []) if f"/{cfg['coverage_dir']}/" in f["path"]]
        core_lines = sum(f["coveredLines"] for f in core_files), sum(f["executableLines"] for f in core_files)
        coverage = {
            "app_lines_pct": round(app_target["lineCoverage"] * 100, 1) if app_target else 0.0,
            "lines_pct": round(100 * core_lines[0] / core_lines[1], 1) if core_lines[1] else 0.0,
        }

        log("  release build for device (unsigned) and Simulator")
        sh("xcodebuild", "-project", proj, "-scheme", scheme, "-configuration", "Release", "-destination", "generic/platform=iOS",
           "-derivedDataPath", f"{tmp}/dev", "CODE_SIGNING_ALLOWED=NO", "build")
        app = next(Path(tmp, "dev", "Build", "Products", "Release-iphoneos").glob("*.app"))
        plist = app / "Info.plist"
        exe = sh("/usr/libexec/PlistBuddy", "-c", "Print CFBundleExecutable", str(plist))
        ent_file = ROOT / cfg["entitlements"]
        ent = ent_file.read_text() if ent_file.exists() else ""
        report = {
            "version": sh("/usr/libexec/PlistBuddy", "-c", "Print CFBundleShortVersionString", str(plist)),
            "min_os": sh("/usr/libexec/PlistBuddy", "-c", "Print MinimumOSVersion", str(plist)).split(".")[0],
            "sdk": sh("xcrun", "--sdk", "iphoneos", "--show-sdk-version").split(".")[0],
            "tests": tests,
            "coverage": coverage,
            "size": {"app_bytes": dir_bytes(app), "slices": slices(app / exe), "download_bytes": zip_bytes(app, payload=True)},
            "signing": {"signature": "Development (Xcode)", "hardened_runtime": None, "sandbox": True,
                        "entitlements": len(re.findall(r"<key>", ent))},
            "privacy_manifest": (ROOT / cfg["privacy_manifest"]).exists(),
        }
        rt = dict(previous.get("runtime", {}))
        if not skip_runtime:
            log("  sampling the app in the Simulator for 20 s")
            sh("xcodebuild", "-project", proj, "-scheme", scheme, "-configuration", "Release",
               "-destination", f"platform=iOS Simulator,name={sim}", "-derivedDataPath", f"{tmp}/sim", "build")
            sim_app = next(Path(tmp, "sim", "Build", "Products", "Release-iphonesimulator").glob("*.app"))
            sh("xcrun", "simctl", "boot", sim, check=False)
            sh("xcrun", "simctl", "install", sim, str(sim_app))
            sh("xcrun", "simctl", "terminate", sim, cfg["bundle_id"], check=False)
            launched = sh("xcrun", "simctl", "launch", sim, cfg["bundle_id"])
            pid = re.search(r":\s*(\d+)", launched)
            if pid:
                time.sleep(10)
                rt.update(sample_process(pid.group(1)))
                rt["where"] = f"{sim} Simulator"
            sh("xcrun", "simctl", "terminate", sim, cfg["bundle_id"], check=False)
        report["runtime"] = rt
    return report


# ---------------------------------------------------------------------------------------------
# Label as drawing ops (shared by the SVG and the in-app panel)

def fmt_bytes(n):
    return "–" if n is None else (f"{n / 1024 / 1024:.1f} MB" if n >= 1024 * 1024 else f"{n / 1024:.0f} KB")


OS_NAMES = {"macos": {"13": "Ventura", "14": "Sonoma", "15": "Sequoia", "26": "Tahoe", "27": ""}, "ios": {}}
ARCH_NAMES = {"arm64": "Apple silicon slice", "x86_64": "Intel slice", "arm64e": "arm64e slice"}


def label_ops(cfg, r):
    ops = []
    row = lambda name, value, bold=False, indent=0, line=True: ops.append(
        {"op": "row", "name": name, "value": value, "bold": bold, "indent": indent, "line": line})
    heading = lambda name, right="": ops.append({"op": "heading", "name": name, "right": right})
    bar = lambda h: ops.append({"op": "bar", "h": h})
    gap = lambda h: ops.append({"op": "gap", "h": h})
    para = lambda text, size=10.5, bold_prefix=None: ops.append({"op": "para", "text": text, "size": size, "bold_prefix": bold_prefix})

    c, t, cov, s, sec, sig, rt = r["code"], r["tests"], r["coverage"], r["size"], r["security"], r["signing"], r.get("runtime", {})
    total_code = sum(v["code"] for v in c.values())
    total_comments = sum(v["comments"] for v in c.values())
    total_files = sum(v["files"] for v in c.values())

    ops.append({"op": "title", "text": "App Facts"})
    ops.append({"op": "text", "dy": 16, "left": f"{cfg['name']} {r['version']} · {cfg['tagline']}", "size": 13, "weight": 400})
    ops.append({"op": "text", "dy": 18, "left": "Serving size", "right": cfg["serving"], "size": 15, "weight": 800})
    gap(6); bar(10)

    ops.append({"op": "small", "text": "Amount per download"})
    ops.append({"op": "big", "left": cfg.get("download_label", "Download"), "right": fmt_bytes(s["download_bytes"])})
    gap(6); bar(5)
    row("Installed size", fmt_bytes(s["app_bytes"]), True)
    for arch, n in s["slices"].items():
        row(ARCH_NAMES.get(arch, arch), fmt_bytes(n), indent=14)
    row("Third-party dependencies", str(sec["dependencies"]), True)
    pa = sec["private_apis"]
    groups = cfg.get("private_api_groups", sec["private_frameworks"])
    row("Private APIs", f"{len(pa)}" + (f" (from {len(groups)} frameworks)" if pa and groups else ""), True, line=False)
    gap(3); bar(10)

    heading("Code", f"{total_files} files")
    row("Lines of code", f"{total_code:,}", True)
    for label, v in c.items():
        row(label, f"{v['code']:,}", indent=14)
    row("Comment lines", f"{total_comments:,}  ({total_comments * 100 // max(total_code, 1)}% of code)")
    row("Language", "Swift (no Objective-C)", line=False)
    gap(3); bar(5)

    heading("Tests")
    passed, failed = t["passed"], t["failed"]
    run = passed + failed
    row("Tests passing", f"{passed}/{run}  ({passed * 100 // max(run, 1)}%)", True)
    row("Test suites", str(t["suites"]), indent=14)
    if t.get("skipped"):
        row("Skipped here", cfg.get("skipped_note", "{n} (run on macOS)").format(n=t["skipped"]), indent=14)
    row("Core logic line coverage", f"{cov['lines_pct']}%", True)
    if "functions_pct" in cov:
        row("Core function coverage", f"{cov['functions_pct']}%", indent=14)
    if "app_lines_pct" in cov:
        row("Whole-app line coverage", f"{cov['app_lines_pct']}%", indent=14)
    row("App / UI layer", cfg["ui_layer"], line=False)
    gap(3); bar(5)

    heading("Permissions & Privacy")
    for name, value, bold in cfg["permissions"]:
        row(name, value, bold)
    net = ("None" if not sec["local_network"] else "Local network only") if sec["internet_call_sites"] == 0 \
        else f"Internet ({sec['internet_call_sites']} call sites)"
    row("Network access", net)
    for name, value in cfg["privacy"]:
        row(name, value)
    row("Entitlements", str(sig["entitlements"]))
    row("App Sandbox", cfg.get("sandbox_note") or ("Yes" if sig["sandbox"] else "No"))
    if sig.get("hardened_runtime") is not None:
        row("Hardened runtime", "Yes" if sig["hardened_runtime"] else "No")
    if "privacy_manifest" in r:
        row("Privacy manifest", "Yes" if r["privacy_manifest"] else "No")
    row("Code signature", cfg.get("signature_note", sig["signature"]), line=False)
    gap(3); bar(5)

    heading("Performance", "measured")
    if "idle_cpu_pct" in rt:
        row("CPU while idle", f"{rt['idle_cpu_pct']:.2f}%", True)
        row("Memory while idle", f"{rt['idle_memory_mb']:.0f} MB", True)
        row("Threads while idle", str(rt["threads"]))
    if "benchmark" in rt:
        b = rt["benchmark"]
        row(cfg["benchmark_label"], f"{b['median_ms']} ms median", True)
        row(cfg.get("benchmark_detail", "({sensors} probes, {runs} runs)").format(**b), f"{b['p95_ms']} ms p95", indent=14)
        for name, value in b.get("extra", []):
            row(name, value)
        if "bluetooth_median_ms" in b:
            row("Bluetooth device scan", f"{b['bluetooth_median_ms']} ms median")
    row("Background work", cfg["background"], line=False)
    gap(3); bar(5)

    heading("Compatibility")
    platform = cfg["platform"]
    os_label = "macOS" if platform == "macos" else "iOS / iPadOS"
    major = str(r["min_os"]).split(".")[0]
    shown = str(r["min_os"]).removesuffix(".0")
    row(os_label, f"{shown} {OS_NAMES[platform].get(major, '')} or later".replace("  ", " "), True)
    for name, value, bold in cfg["compatibility"]:
        row(name, value, bold)
    ops[-1]["line"] = False
    gap(3); bar(10)

    gap(2)
    para("INGREDIENTS: Swift, " + ", ".join(sec["frameworks"]) + ".", bold_prefix="INGREDIENTS:")
    gap(4)
    contains = "CONTAINS: "
    if pa:
        contains += f"{len(pa)} private API symbols from {', '.join(cfg.get('private_api_groups', sec['private_frameworks']))}. "
    para(contains + cfg["contains"], bold_prefix="CONTAINS:")
    gap(6)
    for note in cfg.get("footnotes", []):
        para(note, size=9.5)
    gap(2)
    where = f" ({rt['where']})" if rt.get("where") else ""
    para(f"Measured {r['date']} on {r['machine']}{where}.", size=9.5)
    return ops


# ---------------------------------------------------------------------------------------------
# SVG renderer (geometry identical to the original Cascade label)

def render_svg(ops, title):
    W, PAD = 380, 12
    y = PAD
    out = []

    def text(x, ty, s, size=13, weight=400, anchor="start"):
        out.append(f'<text x="{x}" y="{ty}" font-size="{size}" font-weight="{weight}" '
                   f'text-anchor="{anchor}">{escape(str(s))}</text>')

    def rule():
        out.append(f'<rect x="{PAD}" y="{y}" width="{W - 2 * PAD}" height="0.8"/>')

    for o in ops:
        k = o["op"]
        if k == "title":
            y += 34; text(PAD - 1, y, o["text"], 38, 900); y += 8
            out.append(f'<rect x="{PAD}" y="{y}" width="{W - 2 * PAD}" height="1"/>'); y += 1
        elif k == "text":
            y += o["dy"]
            text(PAD, y, o["left"], o["size"], o["weight"])
            if o.get("right"):
                text(W - PAD, y, o["right"], o["size"], o["weight"], "end")
        elif k == "small":
            y += 4; text(PAD, y + 12, o["text"], 11, 800); y += 16
        elif k == "big":
            y += 24; text(PAD, y, o["left"], 26, 900); text(W - PAD, y, o["right"], 26, 900, "end")
        elif k == "gap":
            y += o["h"]
        elif k == "bar":
            out.append(f'<rect x="{PAD}" y="{y}" width="{W - 2 * PAD}" height="{o["h"]}"/>'); y += o["h"]
        elif k == "row":
            y += 17
            w = 800 if o["bold"] else 400
            text(PAD + o["indent"], y - 4, o["name"], 12.5, w)
            text(W - PAD, y - 4, o["value"], 12.5, w, "end")
            if o["line"]:
                rule()
        elif k == "heading":
            y += 18; text(PAD, y - 4, o["name"], 14, 900)
            if o["right"]:
                text(W - PAD, y - 4, o["right"], 10.5, 700, "end")
            rule()
        elif k == "para":
            size, prefix = o["size"], o.get("bold_prefix")
            limit = int((W - 2 * PAD) / (size * 0.53))
            lines, cur = [], []
            for word in o["text"].split():
                if len(" ".join(cur + [word])) > limit:
                    lines.append(" ".join(cur)); cur = []
                cur.append(word)
            lines.append(" ".join(cur))
            for i, l in enumerate(lines):
                y += size + 3
                if i == 0 and prefix and l.startswith(prefix):
                    out.append(f'<text x="{PAD}" y="{y}" font-size="{size}"><tspan font-weight="800">'
                               f'{escape(prefix)}</tspan>{escape(l[len(prefix):])}</text>')
                else:
                    text(PAD, y, l, size)
    y += PAD
    H = y
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W + 8}" height="{H + 8}" viewBox="-4 -4 {W + 8} {H + 8}" '
            f'role="img" aria-label="{escape(title)}" '
            f'font-family="Helvetica Neue, Helvetica, Arial, sans-serif" fill="#000">'
            f'<rect x="-4" y="-4" width="{W + 8}" height="{H + 8}" fill="#fff"/>'
            f'<rect x="1" y="1" width="{W - 2}" height="{H - 2}" fill="none" stroke="#000" stroke-width="2"/>'
            + "".join(out) + "</svg>\n")


# ---------------------------------------------------------------------------------------------

def write(app_cfg, report):
    i = app_cfg["id"]
    ops = label_ops(app_cfg, report)
    (DOCS / f"app-facts-{i}.json").write_text(json.dumps(report, indent=2) + "\n")
    (DOCS / f"app-facts-{i}.label.json").write_text(json.dumps({"id": i, "ops": ops}, indent=1, ensure_ascii=False) + "\n")
    (DOCS / f"app-facts-{i}.svg").write_text(render_svg(ops, f"App Facts label for {app_cfg['name']} {report['version']}"))
    log(f"✓ docs/app-facts-{i}.svg (+ .json, .label.json)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", action="append")
    ap.add_argument("--skip-runtime", action="store_true")
    ap.add_argument("--render-only", action="store_true")
    args = ap.parse_args()

    config = json.loads(CONFIG.read_text())
    for app_cfg in config["apps"]:
        if args.only and app_cfg["id"] not in args.only:
            continue
        path = DOCS / f"app-facts-{app_cfg['id']}.json"
        previous = json.loads(path.read_text()) if path.exists() else {}
        if args.render_only:
            write(app_cfg, previous)
            continue
        log(f"→ {app_cfg['name']}")
        measure = measure_macos if app_cfg["platform"] == "macos" else measure_ios
        report = measure(app_cfg, previous, args.skip_runtime)
        report.update({
            "date": datetime.date.today().isoformat(),
            "machine": machine(),
            "code": code_stats(app_cfg["code_targets"]),
            "security": security_stats(app_cfg),
        })
        write(app_cfg, report)
        if report["tests"]["failed"]:
            log(f"✗ {report['tests']['failed']} failing tests — the label says so; fix before publishing")


if __name__ == "__main__":
    main()
