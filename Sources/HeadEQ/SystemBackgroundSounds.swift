import AppKit
import EQCore
import Foundation
import ObjectiveC

/// Controls macOS's Accessibility ▸ Audio ▸ Background Sounds.
///
/// There is no public API, so this talks to the same private settings object
/// System Settings uses (HearingUtilities' HUComfortSoundsSettings); the
/// system daemon (`heard`) observes it and plays the sounds. Every call is
/// guarded: if a future macOS renames anything, `isAvailable` becomes false
/// and the UI falls back to opening System Settings.
final class SystemBackgroundSounds: BackgroundSoundsBackend {
    private let settings: NSObject?
    private let soundClass: AnyClass?

    /// Friendly names for the built-in sounds (asset names → System Settings labels).
    private static let builtInNames: [Int: String] = [
        1: "Balanced Noise", 2: "Bright Noise", 3: "Dark Noise", 4: "Ocean", 5: "Rain",
        6: "Stream", 7: "Night", 8: "Fire", 9: "Babble",
    ]

    init() {
        dlopen("/System/Library/PrivateFrameworks/HearingUtilities.framework/HearingUtilities", RTLD_NOW)
        let cls: AnyClass? = NSClassFromString("HUComfortSoundsSettings")
        soundClass = NSClassFromString("HUComfortSound")
        settings = cls.flatMap { Self.callClassObject($0, "sharedInstance") as? NSObject }
    }

    var isAvailable: Bool {
        guard let settings, settings.responds(to: NSSelectorFromString("setComfortSoundsEnabled:")) else { return false }
        return getBool("comfortSoundsAvailable") ?? true
    }

    lazy var sounds: [BackgroundSound] = {
        guard let soundClass else { return [] }
        return (1...20).compactMap { group -> BackgroundSound? in
            guard let s = Self.defaultSound(soundClass, group: group) else { return nil }
            let raw = (s.value(forKey: "name") as? String) ?? "Sound \(group)"
            return BackgroundSound(id: "group-\(group)", name: Self.builtInNames[group] ?? Self.prettify(raw), group: group)
        }
    }()

    func read() -> BackgroundSoundsState {
        var st = BackgroundSoundsState()
        st.available = isAvailable
        guard st.available else { return st }
        st.enabled = getBool("comfortSoundsEnabled") ?? false
        st.volume = getDouble("relativeVolume") ?? 0.5
        st.playWithMedia = getBool("mixesWithMedia") ?? false
        st.mediaVolume = getDouble("mediaVolume") ?? 0.2
        st.stopOnLock = getBool("stopsOnLock") ?? true
        st.timerEnabled = getBool("timerEnabled") ?? false
        st.timerSeconds = getDouble("timerDurationInSeconds") ?? 3600
        st.tinnitusFilterEnabled = getBool("tinnitusFilterEnabled") ?? false
        st.tinnitusFine = (getUInt("tinnitusFilterMode") ?? 0) == 1
        st.tinnitusBalance = getDouble("tinnitusBalance") ?? 0
        if let point = settings?.value(forKey: "tinnitusFilterPoint") as? NSObject {
            st.tinnitusX = (point.value(forKey: "xValue") as? NSNumber)?.doubleValue ?? 0
            st.tinnitusY = (point.value(forKey: "yValue") as? NSNumber)?.doubleValue ?? 0
            st.tinnitusFrequency = (point.value(forKey: "frequencyForBandPass") as? NSNumber)?.doubleValue ?? 1000
            st.tinnitusWidth = (point.value(forKey: "widthForBandPass") as? NSNumber)?.doubleValue ?? 0.58
        }
        if st.timerEnabled, let end = getDouble("activeTimerEndTimeStamp"), end > 0 { st.timerEndReference = end }
        if let selected = settings?.value(forKey: "selectedComfortSound") as? NSObject,
           let group = (selected.value(forKey: "soundGroup") as? NSNumber)?.intValue {
            st.selectedSoundID = "group-\(group)"
        }
        return st
    }

    func setEnabled(_ on: Bool) { setBool("setComfortSoundsEnabled:", on) }
    func setVolume(_ v: Double) { setDouble("setRelativeVolume:", min(max(v, 0), 1)) }
    func setPlayWithMedia(_ on: Bool) { setBool("setMixesWithMedia:", on) }
    func setMediaVolume(_ v: Double) { setDouble("setMediaVolume:", min(max(v, 0), 1)) }
    func setStopOnLock(_ on: Bool) { setBool("setStopsOnLock:", on) }
    func setTinnitusFilter(_ on: Bool) { setBool("setTinnitusFilterEnabled:", on) }

    func setTinnitusFine(_ fine: Bool) { setUInt("setTinnitusFilterMode:", fine ? 1 : 0) }
    func setTinnitusBalance(_ balance: Double) { setDouble("setTinnitusBalance:", min(max(balance, -1), 1)) }

    func setTinnitusPoint(x: Double, y: Double) {
        guard let settings, let cls = NSClassFromString("HUComfortSoundsFilterPoint") as? NSObject.Type else { return }
        let initSel = NSSelectorFromString("initWithPoint:")
        guard class_respondsToSelector(cls, initSel), let initIMP = class_getMethodImplementation(cls, initSel) else { return }
        typealias Init = @convention(c) (AnyObject, Selector, CGPoint) -> Unmanaged<AnyObject>?
        let raw = cls.perform(NSSelectorFromString("alloc")).takeUnretainedValue()
        guard let point = unsafeBitCast(initIMP, to: Init.self)(raw, initSel, CGPoint(x: min(max(x, -1), 1), y: min(max(y, -1), 1)))?
            .takeRetainedValue() else { return }
        let sel = NSSelectorFromString("setTinnitusFilterPoint:")
        guard let imp = Self.imp(settings, sel) else { return }
        typealias F = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        unsafeBitCast(imp, to: F.self)(settings, sel, point)
    }

    func setTimer(enabled: Bool, seconds: Double) {
        setDouble("setTimerDurationInSeconds:", max(60, seconds))
        setBool("setTimerEnabled:", enabled)
    }

    func select(_ sound: BackgroundSound) {
        guard let settings, let soundClass, let obj = Self.defaultSound(soundClass, group: sound.group) else { return }
        let sel = NSSelectorFromString("setSelectedComfortSound:")
        guard let imp = Self.imp(settings, sel) else { return }
        typealias F = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        unsafeBitCast(imp, to: F.self)(settings, sel, obj)
    }

    /// Opens Accessibility ▸ Audio in System Settings (for sound downloads, tinnitus fine-tuning, etc.).
    static func openSystemSettings() {
        let urls = ["x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Audio",
                    "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"]
        for s in urls { if let u = URL(string: s), NSWorkspace.shared.open(u) { return } }
    }

    // MARK: Guarded Objective-C calls (typed IMPs — no `perform` with scalars)

    private static func imp(_ obj: NSObject, _ sel: Selector) -> IMP? {
        obj.responds(to: sel) ? obj.method(for: sel) : nil
    }

    private func getBool(_ name: String) -> Bool? {
        guard let settings, let imp = Self.imp(settings, NSSelectorFromString(name)) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(imp, to: F.self)(settings, NSSelectorFromString(name))
    }

    private func getDouble(_ name: String) -> Double? {
        guard let settings, let imp = Self.imp(settings, NSSelectorFromString(name)) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Double
        return unsafeBitCast(imp, to: F.self)(settings, NSSelectorFromString(name))
    }

    private func getUInt(_ name: String) -> UInt? {
        guard let settings, let imp = Self.imp(settings, NSSelectorFromString(name)) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> UInt
        return unsafeBitCast(imp, to: F.self)(settings, NSSelectorFromString(name))
    }

    private func setUInt(_ name: String, _ value: UInt) {
        guard let settings, let imp = Self.imp(settings, NSSelectorFromString(name)) else { return }
        typealias F = @convention(c) (AnyObject, Selector, UInt) -> Void
        unsafeBitCast(imp, to: F.self)(settings, NSSelectorFromString(name), value)
    }

    private func setBool(_ name: String, _ value: Bool) {
        guard let settings, let imp = Self.imp(settings, NSSelectorFromString(name)) else { return }
        typealias F = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(imp, to: F.self)(settings, NSSelectorFromString(name), value)
    }

    private func setDouble(_ name: String, _ value: Double) {
        guard let settings, let imp = Self.imp(settings, NSSelectorFromString(name)) else { return }
        typealias F = @convention(c) (AnyObject, Selector, Double) -> Void
        unsafeBitCast(imp, to: F.self)(settings, NSSelectorFromString(name), value)
    }

    private static func callClassObject(_ cls: AnyClass, _ name: String) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard let meta = object_getClass(cls), class_respondsToSelector(meta, sel),
              let imp = class_getMethodImplementation(meta, sel) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        return unsafeBitCast(imp, to: F.self)(cls, sel)?.takeUnretainedValue()
    }

    private static func defaultSound(_ cls: AnyClass, group: Int) -> NSObject? {
        let sel = NSSelectorFromString("defaultComfortSoundForGroup:")
        guard let meta = object_getClass(cls), class_respondsToSelector(meta, sel),
              let imp = class_getMethodImplementation(meta, sel) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector, Int) -> Unmanaged<AnyObject>?
        return unsafeBitCast(imp, to: F.self)(cls, sel, group)?.takeUnretainedValue() as? NSObject
    }

    private static func prettify(_ raw: String) -> String {
        var out = ""
        for ch in raw {
            if ch.isUppercase, !out.isEmpty { out.append(" ") }
            out.append(ch)
        }
        return out
    }
}

/// UI-facing state: reads on demand, writes through, and picks up changes made
/// in System Settings while the card is visible.
@MainActor
final class BackgroundSoundsModel: ObservableObject {
    let backend = SystemBackgroundSounds()
    @Published private(set) var state = BackgroundSoundsState()
    private var timer: Timer?

    var sounds: [BackgroundSound] { backend.sounds }

    init() { refresh() }

    func refresh() {
        let new = backend.read()
        if new != state { state = new }
    }

    func startObserving() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopObserving() {
        timer?.invalidate()
        timer = nil
    }

    func update(_ change: (BackgroundSoundsBackend) -> Void) {
        change(backend)
        refresh()
    }
}
