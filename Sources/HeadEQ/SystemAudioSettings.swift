import AppKit
import AudioToolbox
import CoreAudio
import EQCore
import Foundation

/// macOS Headphone Accommodations (Accessibility ▸ Audio), backed by the
/// private PersonalAudio settings System Settings uses.
struct AccommodationsState: Equatable {
    var available = false
    var enabled = false
    var shape = 0          // 0 Balanced Tone, 1 Vocal Range, 2 Brightness
    var level = 0          // 0 Slight, 1 Moderate, 2 Strong
    // Transparency-mode customisation for the active AirPods (if any).
    var transparencyAddress: String?
    var transparencyCustomized = false
    var transparencyAmplification = 0.5
    var transparencyBalance = 0.5
    var transparencyTone = 0.5
    var conversationBoost = false
}

final class SystemAccommodations {
    private let pa = PrivateSettings(framework: "PersonalAudio", className: "PASettings")

    var isAvailable: Bool { pa.responds("setPersonalMediaEnabled:") }

    func read(device: OutputDevice?) -> AccommodationsState {
        var st = AccommodationsState()
        guard isAvailable else { return st }
        st.available = true
        st.enabled = pa.bool("personalMediaEnabled") ?? false
        if let config = pa.object("personalMediaConfiguration") {
            st.shape = Int(PrivateSettings.uint(config, "shape") ?? 0)
            st.level = Int(PrivateSettings.uint(config, "level") ?? 0)
        }
        if let address = Self.bluetoothAddress(device) {
            st.transparencyAddress = address
            st.transparencyCustomized = pa.bool("transparencyCustomizedForAddress:", address: address) ?? false
            st.transparencyAmplification = pa.double("transparencyAmplificationForAddress:", address: address) ?? 0.5
            st.transparencyBalance = pa.double("transparencyBalanceForAddress:", address: address) ?? 0.5
            st.transparencyTone = pa.double("transparencyToneForAddress:", address: address) ?? 0.5
            st.conversationBoost = pa.bool("transparencyBeamformingForAddress:", address: address) ?? false
        }
        return st
    }

    func setEnabled(_ on: Bool) { pa.set("setPersonalMediaEnabled:", bool: on) }

    func setTuning(shape: Int, level: Int) {
        guard let config = pa.object("personalMediaConfiguration") else { return }
        PrivateSettings.set(config, "setShape:", uint: UInt(max(0, min(2, shape))))
        PrivateSettings.set(config, "setLevel:", uint: UInt(max(0, min(2, level))))
        pa.set("setPersonalMediaConfiguration:", object: config)
    }

    func setTransparency(customized: Bool? = nil, amplification: Double? = nil, balance: Double? = nil,
                         tone: Double? = nil, conversationBoost: Bool? = nil, address: String) {
        if let customized { pa.set("setTransparencyCustomized:forAddress:", bool: customized, address: address) }
        if let amplification { pa.set("setTransparencyAmplification:forAddress:", double: amplification, address: address) }
        if let balance { pa.set("setTransparencyBalance:forAddress:", double: balance, address: address) }
        if let tone { pa.set("setTransparencyTone:forAddress:", double: tone, address: address) }
        if let conversationBoost { pa.set("setTransparencyBeamforming:forAddress:", bool: conversationBoost, address: address) }
    }

    /// Core Audio UIDs of Bluetooth devices start with the address ("38-C4-3A-4A-CA-8A:output").
    static func bluetoothAddress(_ device: OutputDevice?) -> String? {
        guard let device, device.transport == .bluetooth else { return nil }
        let head = device.uid.split(separator: ":").first.map(String.init) ?? device.uid
        let parts = head.split(separator: "-")
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 }) else { return nil }
        return parts.joined(separator: ":").uppercased()
    }
}

/// Everyday system sound settings: device volume/mute/balance (public Core
/// Audio), alert volume, UI sound effects, volume feedback, screen flash.
struct SystemSoundState: Equatable {
    var volume: Double?        // 0…1, nil if the device has no volume control
    var muted: Bool?
    var balance: Double?       // 0 left … 0.5 centre … 1 right
    var alertVolume: Double = 1
    var uiSounds = true
    var volumeFeedback = true
    var flashOnAlert = false
}

final class SystemSounds {
    func read(device: OutputDevice?) -> SystemSoundState {
        var st = SystemSoundState()
        if let id = device.flatMap({ CA.deviceID(forUID: $0.uid) }) {
            st.volume = Self.getFloat(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume).map(Double.init)
            st.balance = Self.getFloat(id, kAudioHardwareServiceDeviceProperty_VirtualMainBalance).map(Double.init)
            st.muted = Self.getUInt32(id, kAudioDevicePropertyMute).map { $0 != 0 }
        }
        st.alertVolume = Self.alertVolume() ?? 1
        st.uiSounds = Self.globalBool("com.apple.sound.uiaudio.enabled") ?? true
        st.volumeFeedback = Self.globalBool("com.apple.sound.beep.feedback") ?? true
        st.flashOnAlert = Self.globalBool("com.apple.sound.beep.flash") ?? false
        return st
    }

    func setVolume(_ v: Double, device: OutputDevice) {
        guard let id = CA.deviceID(forUID: device.uid) else { return }
        Self.setFloat(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(min(max(v, 0), 1)))
    }

    func setBalance(_ v: Double, device: OutputDevice) {
        guard let id = CA.deviceID(forUID: device.uid) else { return }
        Self.setFloat(id, kAudioHardwareServiceDeviceProperty_VirtualMainBalance, Float32(min(max(v, 0), 1)))
    }

    func setMuted(_ on: Bool, device: OutputDevice) {
        guard let id = CA.deviceID(forUID: device.uid) else { return }
        var value: UInt32 = on ? 1 : 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    func setAlertVolume(_ v: Double) {
        NSAppleScript(source: "set volume alert volume \(Int((min(max(v, 0), 1) * 100).rounded()))")?.executeAndReturnError(nil)
    }

    func setUISounds(_ on: Bool) { Self.setGlobal("com.apple.sound.uiaudio.enabled", on ? 1 : 0) }
    func setVolumeFeedback(_ on: Bool) { Self.setGlobal("com.apple.sound.beep.feedback", on ? 1 : 0) }
    func setFlashOnAlert(_ on: Bool) { Self.setGlobal("com.apple.sound.beep.flash", on ? 1 : 0) }

    static func openSoundSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(u) }
    }

    // MARK: helpers

    private static func alertVolume() -> Double? {
        guard let result = NSAppleScript(source: "alert volume of (get volume settings)")?.executeAndReturnError(nil) else { return nil }
        return Double(result.int32Value) / 100
    }

    private static func globalBool(_ key: String) -> Bool? {
        CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            .flatMap { ($0 as? NSNumber)?.boolValue }
    }

    private static func setGlobal(_ key: String, _ value: Int) {
        CFPreferencesSetValue(key as CFString, value as CFNumber, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.sound.settingsChangedNotification"), object: nil, userInfo: nil, deliverImmediately: true)
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private static func getFloat(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Float32? {
        var addr = outputAddress(selector)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func setFloat(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: Float32) {
        var addr = outputAddress(selector)
        var v = value
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    private static func getUInt32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = outputAddress(selector)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }
}

/// UI model for the System Audio page; polls while visible so changes made
/// with the keyboard volume keys or System Settings show up.
@MainActor
final class SystemAudioModel: ObservableObject {
    let accommodations = SystemAccommodations()
    let sounds = SystemSounds()
    @Published private(set) var acc = AccommodationsState()
    @Published private(set) var sys = SystemSoundState()
    private(set) var device: OutputDevice?
    private var timer: Timer?

    func refresh(device: OutputDevice?) {
        self.device = device
        let a = accommodations.read(device: device), s = sounds.read(device: device)
        if a != acc { acc = a }
        if s != sys { sys = s }
    }

    func startObserving(device: @escaping () -> OutputDevice?) {
        refresh(device: device())
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(device: device()) }
        }
    }

    func stopObserving() { timer?.invalidate(); timer = nil }

    func change(_ body: () -> Void) {
        body()
        refresh(device: device)
    }
}
