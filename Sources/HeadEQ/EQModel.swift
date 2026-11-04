import EQCore
import Foundation
import SwiftUI

@MainActor
final class EQModel: ObservableObject {
    @Published var settings: EQSettings {
        didSet { if settings != oldValue { settingsChanged(from: oldValue) } }
    }
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var activeDevice: OutputDevice?
    @Published private(set) var status: BackendStatus = .stopped
    @Published private(set) var customPresets: [MusicPreset] = []
    @Published private(set) var customHeadphones: [HeadphoneProfile] = []
    @Published private(set) var lastGenerated: GeneratedPreset?
    @Published private(set) var exposure = ExposureMeter(day: EQModel.today())
    @Published private(set) var estimatedSPL: Double?
    @Published private(set) var deviceVolumeDB: Double?
    @Published private(set) var protectionReductionDB: Float = 0
    let library = HeadphoneLibrary()

    /// While the headphone editor is open, its draft is auditioned live.
    @Published var previewHeadphone: HeadphoneProfile? { didSet { pushDSP() } }

    var headphoneProfiles: [HeadphoneProfile] { customHeadphones + HeadphoneProfile.builtIn }
    var musicPresets: [MusicPreset] { MusicPreset.builtIn + customPresets }

    let backend: AudioBackend
    private let defaults = UserDefaults.standard
    private static let settingsKey = "settings.v1"
    private static let customPresetsKey = "customPresets.v1"
    private static let customHeadphonesKey = "customHeadphones.v1"
    private static let exposureKey = "exposure.v1"
    private var hearingTimer: Timer?
    private var lastCapDBFS: Double = .nan
    private var tickCount = 0
    static let customPresetID = "custom"
    /// Auto-detect only fires when the output device actually changes, so it
    /// never overrides a profile the user picked by hand.
    private var autoDetectedForUID: String?

    init(backend: AudioBackend = TapBackend()) {
        self.backend = backend
        settings = Self.load(EQSettings.self, key: Self.settingsKey) ?? EQSettings()
        customPresets = Self.load([MusicPreset].self, key: Self.customPresetsKey) ?? []
        customHeadphones = Self.load([HeadphoneProfile].self, key: Self.customHeadphonesKey) ?? []
        if let saved = Self.load(ExposureMeter.self, key: Self.exposureKey), saved.day == Self.today() {
            exposure = saved
        }
        backend.onDevicesChanged = { [weak self] in
            Task { @MainActor in self?.refreshDevices() }
        }
        refreshDevices()
        hearingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickHearing() }
        }
    }

    // MARK: Derived state

    var headphoneProfile: HeadphoneProfile {
        previewHeadphone ?? headphoneProfiles.first { $0.id == settings.headphoneProfileID } ?? .none
    }

    var currentMusicPreset: MusicPreset? { musicPresets.first { $0.id == settings.musicPresetID } }

    var filters: [FilterSpec] { settings.filters(headphone: headphoneProfile) }
    var effectivePreamp: Double { settings.effectivePreamp(filters: filters) }

    var isRunning: Bool { if case .running = status { return true } else { return false } }

    var statusText: String {
        switch status {
        case .stopped: return settings.enabled ? "Starting…" : "Bypassed — audio untouched"
        case .running(let name, let rate): return "Active on \(name) · " + String(format: "%.1f kHz", rate / 1000)
        case .failed(let message): return message
        }
    }

    // MARK: Music presets

    func selectMusicPreset(_ preset: MusicPreset) {
        var s = settings
        s.musicPresetID = preset.id
        s.bandGains = preset.gains
        settings = s
    }

    /// Editing a band live-updates your own presets; built-ins become "Custom".
    func setBand(_ index: Int, gain: Double, step: Double = 0.5) {
        var s = settings
        s.bandGains[index] = min(max((gain / step).rounded() * step, GraphicEQ.gainRange.lowerBound), GraphicEQ.gainRange.upperBound)
        if let i = customPresets.firstIndex(where: { $0.id == s.musicPresetID }) {
            customPresets[i].gains = s.bandGains
            persistCustomPresets()
        } else {
            s.musicPresetID = musicPresets.first { $0.gains == s.bandGains }?.id ?? Self.customPresetID
        }
        settings = s
    }

    func saveCustomPreset(named name: String) {
        let preset = MusicPreset(id: "user-\(UUID().uuidString)", name: uniqueName(name, existing: musicPresets.map(\.name)),
                                 gains: settings.bandGains, isBuiltIn: false)
        customPresets.append(preset)
        persistCustomPresets()
        settings.musicPresetID = preset.id
    }

    func renameCustomPreset(_ preset: MusicPreset, to name: String) {
        guard let i = customPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        customPresets[i].name = uniqueName(name, existing: musicPresets.filter { $0.id != preset.id }.map(\.name))
        persistCustomPresets()
    }

    func deleteCustomPreset(_ preset: MusicPreset) {
        customPresets.removeAll { $0.id == preset.id }
        persistCustomPresets()
        if settings.musicPresetID == preset.id { settings.musicPresetID = Self.customPresetID }
    }

    func resetBands() { selectMusicPreset(.flat) }

    // MARK: Describe → preset

    func generatePreset(from description: String) {
        let result = PresetGenerator.generate(from: description, headphones: headphoneProfiles, presets: MusicPreset.builtIn)
        let preset = MusicPreset(id: "user-\(UUID().uuidString)",
                                 name: uniqueName(result.name, existing: musicPresets.map(\.name)),
                                 gains: result.gains, isBuiltIn: false, origin: result.origin)
        customPresets.append(preset)
        persistCustomPresets()
        var s = settings
        s.musicPresetID = preset.id
        s.bandGains = preset.gains
        if let h = result.headphone {
            s.headphoneProfileID = h.id
            autoDetectedForUID = activeDevice?.uid   // don't let auto-detect undo this
        }
        settings = s
        lastGenerated = result
    }

    func dismissGenerated() { lastGenerated = nil }

    // MARK: Headphones

    func newHeadphoneDraft(basedOn base: HeadphoneProfile? = nil) -> HeadphoneProfile {
        let source = base ?? HeadphoneProfile.builtIn.first { $0.id == "generic-over" }!
        let name = base.map { "\($0.name) (Custom)" } ?? "My Headphones"
        return HeadphoneProfile(id: "user-hp-\(UUID().uuidString)",
                                name: uniqueName(name, existing: headphoneProfiles.map(\.name)),
                                kind: source.kind, matchKeywords: base == nil ? [] : source.matchKeywords,
                                filters: base == nil ? [] : source.filters,
                                note: base.map { "Based on \($0.name)." } ?? "", isBuiltIn: false,
                                source: base.map { b in
                                    var src = b.provenance
                                    src.kind = .modified
                                    src.basedOn = b.name
                                    return src
                                } ?? .userCreated)
    }

    func saveHeadphone(_ profile: HeadphoneProfile) {
        var p = profile
        p.isBuiltIn = false
        p.filters = Array(p.filters.prefix(HeadphoneProfile.maxFilters))
        // Editing a measured profile turns it into "your edits on top of …".
        if let old = customHeadphones.first(where: { $0.id == p.id }), old.filters != p.filters,
           p.provenance.kind == .measured || p.provenance.kind == .generic {
            var src = p.provenance
            src.kind = .modified
            src.basedOn = src.basedOn ?? "\(old.name) (\(old.provenance.title.lowercased()))"
            p.source = src
        }
        if let i = customHeadphones.firstIndex(where: { $0.id == p.id }) { customHeadphones[i] = p }
        else { customHeadphones.append(p) }
        persistCustomHeadphones()
        previewHeadphone = nil
        settings.headphoneProfileID = p.id
        autoDetectedForUID = activeDevice?.uid
    }

    func deleteHeadphone(_ profile: HeadphoneProfile) {
        customHeadphones.removeAll { $0.id == profile.id }
        persistCustomHeadphones()
        if settings.headphoneProfileID == profile.id { settings.headphoneProfileID = HeadphoneProfile.none.id }
    }

    // MARK: Output device

    var availableSampleRates: [Double] {
        activeDevice.map { backend.availableSampleRates(for: $0) } ?? []
    }

    var currentSampleRate: Double {
        activeDevice.flatMap { d in devices.first { $0.uid == d.uid }?.sampleRate } ?? backend.sampleRate
    }

    func setSampleRate(_ rate: Double) {
        guard let device = activeDevice else { return }
        do {
            try backend.setSampleRate(rate, for: device)
            refreshDevices(forceRestart: true)
        } catch {
            status = .failed("Could not change sample rate: \(error)")
        }
    }

    // MARK: Engine plumbing

    private func settingsChanged(from old: EQSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.settingsKey) }

        if settings.output != old.output { backend.update(output: settings.output) }
        if settings.hearing != old.hearing { pushHearing(force: true) }

        if settings.enabled != old.enabled || settings.outputDeviceUID != old.outputDeviceUID
            || (settings.autoDetectHeadphones && !old.autoDetectHeadphones) {
            if settings.autoDetectHeadphones && !old.autoDetectHeadphones { autoDetectedForUID = nil }
            refreshDevices(forceRestart: settings.outputDeviceUID != old.outputDeviceUID)
        } else {
            pushDSP()
        }
    }

    private func pushDSP() {
        backend.update(filters: filters, preampDB: effectivePreamp)
    }

    private var targetDevice: OutputDevice? {
        if let uid = settings.outputDeviceUID, let d = devices.first(where: { $0.uid == uid }) { return d }
        return backend.defaultOutputDevice()
    }

    func refreshDevices(forceRestart: Bool = false) {
        devices = backend.outputDevices()
        guard let target = targetDevice else {
            backend.stop(); activeDevice = nil
            status = .failed("No output device")
            return
        }

        if settings.autoDetectHeadphones, autoDetectedForUID != target.uid {
            autoDetectedForUID = target.uid
            if let profile = autoProfile(for: target), profile.id != settings.headphoneProfileID {
                settings.headphoneProfileID = profile.id     // re-enters settingsChanged → pushDSP
            }
        }

        guard settings.enabled else {
            backend.stop(); activeDevice = target; status = .stopped
            return
        }
        if !forceRestart, isRunning, activeDevice?.uid == target.uid { pushDSP(); return }

        activeDevice = target
        do {
            try backend.start(device: target)
            pushDSP()
            backend.update(output: settings.output)
            pushHearing(force: true)
            status = .running(deviceName: target.name, sampleRate: backend.sampleRate)
        } catch {
            status = .failed("Could not start: \(error)")
        }
    }

    private func autoProfile(for device: OutputDevice) -> HeadphoneProfile? {
        if let match = HeadphoneProfile.match(deviceName: device.name, in: headphoneProfiles) { return match }
        let name = device.name.lowercased()
        if device.transport == .builtIn {
            return headphoneProfiles.first { $0.id == (name.contains("speaker") ? "laptop-speakers" : "generic-over") }
        }
        return nil
    }

    // MARK: Hearing protection

    var doseLevel: DoseLevel {
        exposure.dose >= 1 ? .over : exposure.dose >= 0.8 ? .high : .ok
    }
    enum DoseLevel { case ok, high, over }

    func resetExposure() {
        exposure = ExposureMeter(day: Self.today())
        persistExposure()
        pushHearing(force: true)
    }

    private func tickHearing() {
        if exposure.day != Self.today() { exposure = ExposureMeter(day: Self.today()) }
        deviceVolumeDB = activeDevice.flatMap { backend.outputVolumeDB(for: $0) }
        protectionReductionDB = isRunning ? backend.protectionReductionDB : 0
        if isRunning {
            let level = Double(backend.outputLevelDBFS)
            if level > -80 {
                let spl = settings.hearing.estimatedSPL(levelDBFS: level, deviceVolumeDB: deviceVolumeDB ?? 0)
                estimatedSPL = spl
                exposure.add(spl: spl, seconds: 1)
            } else {
                estimatedSPL = nil
            }
        } else {
            estimatedSPL = nil
        }
        pushHearing(force: false)
        tickCount += 1
        if tickCount % 15 == 0 { persistExposure() }
    }

    /// Converts the SPL ceiling into a digital ceiling for the current device volume.
    private func pushHearing(force: Bool) {
        let cap = settings.hearing.capDBFS(deviceVolumeDB: deviceVolumeDB ?? 0, doseFraction: exposure.dose)
        guard force || lastCapDBFS.isNaN || abs(cap - lastCapDBFS) > 0.25 else { return }
        lastCapDBFS = cap
        backend.update(hearing: settings.hearing.realtime(sampleRate: backend.sampleRate, capDBFS: cap))
    }

    private func persistExposure() {
        if let data = try? JSONEncoder().encode(exposure) { defaults.set(data, forKey: Self.exposureKey) }
    }

    private static func today() -> Int {
        Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persistCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) { defaults.set(data, forKey: Self.customPresetsKey) }
    }

    private func persistCustomHeadphones() {
        if let data = try? JSONEncoder().encode(customHeadphones) { defaults.set(data, forKey: Self.customHeadphonesKey) }
    }

    private func uniqueName(_ raw: String, existing: [String]) -> String {
        let base = raw.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : raw.trimmingCharacters(in: .whitespaces)
        var name = base, n = 2
        while existing.contains(name) { name = "\(base) \(n)"; n += 1 }
        return name
    }

    func shutdown() {
        persistExposure()
        backend.stop()
    }
}
