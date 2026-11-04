import AudioToolbox
import CoreAudio
import EQCore
import Foundation
import os

/// macOS backend: a global Core Audio process tap (macOS 14.2+) captures all
/// system audio (except our own process) and mutes the original. A private
/// aggregate device combines that tap with the chosen output device; our IO
/// proc runs the EQ and writes the result to the output.
final class TapBackend: AudioBackend {
    var onDevicesChanged: (() -> Void)?
    private(set) var sampleRate: Double = 48_000

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var tapChannels = 2
    private var lastFilters: [FilterSpec] = []
    private var lastPreamp: Double = 0
    private var lastOutput = OutputSettings()

    var visualizerRing: SampleRing { renderer.ring }
    var limiterReductionDB: Float { renderer.processor.limiterReductionDB }
    var protectionReductionDB: Float { renderer.processor.protectionReductionDB }
    var outputLevelDBFS: Float { renderer.processor.outputLevelDBFS }
    var levelerGainDB: Float { renderer.processor.levelerGainDB }
    var loudnessLUFS: Float { renderer.processor.loudnessLUFS }
    private var lastHearing = RealtimeHearing()
    private var lastProcessing = ProcessingConfig()
    private var installedSignature = StageSignature()

    func update(processing: ProcessingConfig) {
        lastProcessing = processing
        // Build stage objects only when the set of enabled features changes.
        if processing.signature != installedSignature || !renderer.hasStageSet(for: processing.signature) {
            installedSignature = processing.signature
            renderer.post(stages: processing.signature.isEmpty ? nil : StageSet(processing.signature))
        }
        renderer.post(stageParams: processing.realtime(sampleRate: sampleRate))
    }

    func update(hearing: RealtimeHearing) {
        lastHearing = hearing
        renderer.post(hearing: hearing)
    }

    func outputVolumeDB(for device: OutputDevice) -> Double? {
        guard let id = CA.deviceID(forUID: device.uid) else { return nil }
        for element in [kAudioObjectPropertyElementMain, 1] {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeDecibels,
                                                  mScope: kAudioObjectPropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr { return Double(min(0, value)) }
        }
        return nil
    }

    private let renderer = Renderer()
    private let ioQueue = DispatchQueue(label: "HeadEQ.io", qos: .userInteractive)

    init() {
        installListeners()
    }

    // MARK: Devices

    func outputDevices() -> [OutputDevice] {
        CA.objectIDs(CA.system, kAudioHardwarePropertyDevices).compactMap(CA.outputDevice)
    }

    func defaultOutputDevice() -> OutputDevice? {
        guard let id = try? CA.get(CA.system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0)) else { return nil }
        return CA.outputDevice(id)
    }

    private func installListeners() {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = address(selector)
            AudioObjectAddPropertyListenerBlock(CA.system, &addr, .main) { [weak self] _, _ in
                self?.onDevicesChanged?()
            }
        }
    }

    // MARK: Lifecycle

    func start(device: OutputDevice) throws {
        stop()
        do {
            try createTap()
            try createAggregate(outputUID: device.uid)
            sampleRate = (try? CA.get(aggregateID, kAudioDevicePropertyNominalSampleRate, initial: Float64(0))) ?? 0
            if sampleRate <= 0 { sampleRate = device.sampleRate > 0 ? device.sampleRate : 48_000 }
            renderer.tapChannels = tapChannels
            renderer.processor.reset()
            update(filters: lastFilters, preampDB: lastPreamp)
            update(output: lastOutput)
            update(hearing: lastHearing)
            renderer.post(stageParams: lastProcessing.realtime(sampleRate: sampleRate))

            let renderer = self.renderer
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { _, input, _, output, _ in
                renderer.render(input: input, output: output)
            }, "Create IO proc")
            try check(AudioDeviceStart(aggregateID, ioProcID), "Start device")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let proc = ioProcID {
                AudioDeviceStop(aggregateID, proc)
                AudioDeviceDestroyIOProcID(aggregateID, proc)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
    }

    func update(filters: [FilterSpec], preampDB: Double) {
        lastFilters = filters
        lastPreamp = preampDB
        let coeffs = filters.prefix(EQProcessor.maxFilters).map { BiquadCoefficients($0, sampleRate: sampleRate) }
        renderer.post(coeffs, preampDB: Float(preampDB))
    }

    func update(output: OutputSettings) {
        lastOutput = output
        renderer.post(output: output.realtime(sampleRate: sampleRate))
    }

    func availableSampleRates(for device: OutputDevice) -> [Double] {
        guard let id = CA.deviceID(forUID: device.uid) else { return [] }
        var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ranges) == noErr else { return [] }
        let common: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000, 352_800, 384_000]
        var rates = Set<Double>()
        for r in ranges {
            if r.mMinimum == r.mMaximum { rates.insert(r.mMinimum) }
            else { common.filter { $0 >= r.mMinimum && $0 <= r.mMaximum }.forEach { rates.insert($0) } }
        }
        return rates.sorted()
    }

    func setSampleRate(_ rate: Double, for device: OutputDevice) throws {
        guard let id = CA.deviceID(forUID: device.uid) else { throw CoreAudioError(status: -1, what: "Find device") }
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var value = Float64(rate)
        try check(AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value),
                  "Set sample rate")
    }

    // MARK: Setup

    private var tapUUID = UUID()

    private func createTap() throws {
        // Exclude ourselves so our processed output is never re-captured.
        var pid = getpid()
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var selfObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(CA.system, &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &selfObject),
                  "Find own audio process")
        guard selfObject != kAudioObjectUnknown else {
            throw CoreAudioError(status: -1, what: "Find own audio process")
        }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [selfObject])
        tapUUID = UUID()
        description.uuid = tapUUID
        description.name = "HeadEQ Tap"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Create process tap (check Audio Capture permission)")

        let format = try CA.get(tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
        tapChannels = max(1, Int(format.mChannelsPerFrame))
    }

    private func createAggregate(outputUID: String) throws {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "HeadEQ Output",
            kAudioAggregateDeviceUIDKey: "HeadEQ-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "Create aggregate device")
    }
}

/// Everything touched on the real-time IO thread. No allocations in `render`.
private final class Renderer {
    static let maxFrames = 16_384
    static let maxChannels = 8

    let processor = EQProcessor(maxChannels: Renderer.maxChannels)
    let ring = SampleRing(capacity: 8192)
    var tapChannels = 2

    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames * maxChannels)

    // Parameter mailbox (main thread → IO thread), guarded by a try-lock so
    // the IO thread never blocks.
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()
    private let pending = UnsafeMutablePointer<BiquadCoefficients>.allocate(capacity: EQProcessor.maxFilters)
    private var pendingCount = 0
    private var pendingPreamp: Float = 0
    private var dirty = false
    private var pendingOutput = RealtimeOutput()
    private var outputDirty = false
    private var pendingHearing = RealtimeHearing()
    private var hearingDirty = false

    // Stage set mailbox. The audio thread swaps sets and parks the old one in
    // `retired`; it's released here on the main thread, never on the audio thread.
    private var pendingStages: StageSet?
    private var stagesDirty = false
    private var retired: StageSet?
    private var postedStages: StageSet?
    private var pendingStageParams = StageParams()
    private var stageParamsDirty = false

    func hasStageSet(for sig: StageSignature) -> Bool { sig.isEmpty ? postedStages == nil : postedStages?.signature == sig }

    func post(stages: StageSet?) {
        os_unfair_lock_lock(lock)
        let toFree = retired
        retired = nil
        pendingStages = stages
        postedStages = stages
        stagesDirty = true
        os_unfair_lock_unlock(lock)
        _ = toFree   // released here, on the caller's (main) thread
    }

    func post(stageParams: StageParams) {
        os_unfair_lock_lock(lock)
        pendingStageParams = stageParams
        stageParamsDirty = true
        os_unfair_lock_unlock(lock)
    }

    func post(hearing: RealtimeHearing) {
        os_unfair_lock_lock(lock)
        pendingHearing = hearing
        hearingDirty = true
        os_unfair_lock_unlock(lock)
    }

    func post(output: RealtimeOutput) {
        os_unfair_lock_lock(lock)
        pendingOutput = output
        outputDirty = true
        os_unfair_lock_unlock(lock)
    }

    func post(_ coeffs: [BiquadCoefficients], preampDB: Float) {
        os_unfair_lock_lock(lock)
        pendingCount = min(coeffs.count, EQProcessor.maxFilters)
        for i in 0..<pendingCount { pending[i] = coeffs[i] }
        pendingPreamp = preampDB
        dirty = true
        os_unfair_lock_unlock(lock)
    }

    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        if os_unfair_lock_trylock(lock) {
            if dirty {
                processor.apply(UnsafeBufferPointer(start: pending, count: pendingCount), preampDB: pendingPreamp)
                dirty = false
            }
            if stagesDirty {
                let old = processor.installStages(pendingStages)
                if old != nil { retired = old }
                pendingStages = nil
                stagesDirty = false
                stageParamsDirty = true
            }
            if stageParamsDirty {
                processor.applyStageParams(pendingStageParams)
                stageParamsDirty = false
            }
            if hearingDirty {
                processor.applyHearing(pendingHearing)
                hearingDirty = false
            }
            if outputDirty {
                processor.applyOutput(pendingOutput)
                outputDirty = false
            }
            os_unfair_lock_unlock(lock)
        }

        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)

        // The tap's streams are the last input streams of the aggregate (any
        // input streams of the output sub-device come first). Walk backwards.
        let channels = min(tapChannels, Self.maxChannels)
        var frames = 0
        var remaining = channels
        var bufferIndex = inList.count - 1
        while remaining > 0, bufferIndex >= 0 {
            let buf = inList[bufferIndex]
            let n = Int(buf.mNumberChannels)
            if n > 0, let data = buf.mData?.assumingMemoryBound(to: Float.self) {
                let f = min(Int(buf.mDataByteSize) / (4 * n), Self.maxFrames)
                frames = max(frames, f)
                let firstChannel = remaining - n
                for c in 0..<n where firstChannel + c >= 0 {
                    let dst = scratch + (firstChannel + c) * Self.maxFrames
                    for t in 0..<f { dst[t] = data[t * n + c] }
                }
                remaining -= n
            }
            bufferIndex -= 1
        }

        if frames > 0 {
            let left = scratch
            let right: UnsafeMutablePointer<Float>? = channels > 1 ? scratch + Self.maxFrames : nil
            processor.processStereo(left: left, right: right, frames: frames)
            for c in 2..<max(2, channels) {   // rare: >2 tap channels get EQ only
                processor.process(channel: c, samples: scratch + c * Self.maxFrames, frames: frames)
            }
            ring.writeMix(left, right, frames: frames)
        }

        // Write to output; extra device channels (e.g. multichannel DACs) get
        // silence, mono tap is duplicated.
        var outChannel = 0
        for buf in outList {
            let n = Int(buf.mNumberChannels)
            guard n > 0, let data = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let f = Int(buf.mDataByteSize) / (4 * n)
            for c in 0..<n {
                let ch = outChannel + c
                if ch < 2, frames > 0 {
                    let src = scratch + min(ch, channels - 1) * Self.maxFrames
                    let m = min(f, frames)
                    for t in 0..<m { data[t * n + c] = src[t] }
                    for t in m..<f { data[t * n + c] = 0 }
                } else {
                    for t in 0..<f { data[t * n + c] = 0 }
                }
            }
            outChannel += n
        }
    }
}
