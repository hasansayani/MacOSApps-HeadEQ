import re, sys, urllib.request, json
index, outdir = sys.argv[1], sys.argv[2]
want = {
 "airpods-pro-2": ["Apple AirPods Pro 2", "Apple AirPods Pro2"],
 "airpods-max": ["Apple AirPods Max"],
 "airpods": ["Apple AirPods (3rd generation)", "Apple AirPods 3", "Apple AirPods (3rd gen)", "Apple AirPods 4"],
 "beats-studio-pro": ["Beats Studio Pro"],
 "sony-xm5": ["Sony WH-1000XM5"],
 "sony-xm4": ["Sony WH-1000XM4"],
 "sony-wf-xm5": ["Sony WF-1000XM5"],
 "bose-qc-ultra": ["Bose QuietComfort Ultra Headphones", "Bose QC Ultra Headphones", "Bose QuietComfort Ultra"],
 "bose-qc45": ["Bose QuietComfort 45", "Bose QC45"],
 "bose-soundsport": ["Bose SoundSport Free", "Bose SoundSport Wireless"],
 "powerbeats-pro": ["Beats Powerbeats Pro"],
 "hd600": ["Sennheiser HD 600", "Sennheiser HD 650"],
 "dt770": ["Beyerdynamic DT 770 Pro 80 Ohm", "Beyerdynamic DT 770 Pro 250 Ohm", "Beyerdynamic DT 770 Pro"],
 "m50x": ["Audio-Technica ATH-M50x"],
 "galaxy-buds": ["Samsung Galaxy Buds Pro", "Samsung Galaxy Buds2 Pro", "Samsung Galaxy Buds 2 Pro"],
}
rank = ["oratory1990", "crinacle", "Rtings", "Innerfidelity", "Super Review"]
entries = []
for line in open(index, encoding="utf-8"):
    m = re.match(r"- \[(.+?)\]\(\./(.+?)\) by (.+)$", line.strip())
    if m: entries.append((m.group(1), m.group(2), m.group(3)))
result = {}
for pid, names in want.items():
    found = None
    for n in names:
        cands = [e for e in entries if e[0].lower() == n.lower()]
        cands.sort(key=lambda e: next((i for i, r in enumerate(rank) if e[2].startswith(r)), 9))
        if cands: found = cands[0]; break
    if not found: print("MISSING", pid); continue
    name, path, src = found
    last = path.split("/")[-1]
    url = f"https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/{path}/{last}%20ParametricEQ.txt"
    try:
        text = urllib.request.urlopen(url, timeout=20).read().decode()
    except Exception as ex:
        print("FAIL", pid, ex); continue
    filters = []
    for l in text.splitlines():
        m = re.match(r"Filter \d+: ON (PK|LSC|HSC) Fc ([\d.]+) Hz Gain ([-\d.]+) dB Q ([\d.]+)", l)
        if m: filters.append((m.group(1), float(m.group(2)), float(m.group(3)), float(m.group(4))))
    result[pid] = {"name": name, "path": path, "source": src, "filters": filters}
    print(pid, "←", name, "|", src, "|", len(filters), "filters")
json.dump(result, open(f"{outdir}/measured.json", "w"), indent=1)
