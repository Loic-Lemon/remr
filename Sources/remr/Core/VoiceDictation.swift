import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import Speech
import SwiftUI

struct VoiceInputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let deviceID: AudioDeviceID
}

enum VoiceInputDevices {
    static func available() -> [VoiceInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasInput(id),
                  let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, selector: kAudioObjectPropertyName) else { return nil }
            return VoiceInputDevice(id: uid, name: name, deviceID: id)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        let pointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return false }
        return pointer.pointee.mNumberBuffers > 0 && pointer.pointee.mBuffers.mNumberChannels > 0
    }

    private static func stringProperty(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeUnretainedValue() as String
    }
}

@MainActor
protocol VoiceTranscriber: AnyObject {
    var name: String { get }
    var transcript: String { get }
    var activeDeviceName: String? { get }
    var fellBackToDefaultInput: Bool { get }
    var onTranscriptChange: ((String) -> Void)? { get set }

    func start() async throws
    func stop() async throws -> String
    func cancel()
}

@MainActor
final class AppleSpeechTranscriber: NSObject, VoiceTranscriber, SFSpeechRecognizerDelegate {
    enum Error: LocalizedError {
        case microphoneDenied
        case speechDenied
        case unavailable
        case onDeviceUnavailable
        case inputDeviceUnavailable
        case noTranscript

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: return "Microphone access is required for voice dictation."
            case .speechDenied: return "Speech recognition access is required for voice dictation."
            case .unavailable: return "Apple Speech recognition is unavailable."
            case .onDeviceUnavailable: return "On-device speech recognition is unavailable for this language or Mac."
            case .inputDeviceUnavailable: return "The selected microphone is unavailable. Choose another microphone in Settings."
            case .noTranscript: return "No speech was detected. Check the selected microphone and try again."
            }
        }
    }

    let name = "Apple Speech (on-device)"
    var transcript = ""
    private(set) var activeDeviceName: String?
    private(set) var fellBackToDefaultInput = false
    var onTranscriptChange: ((String) -> Void)?

    private let recognizer: SFSpeechRecognizer
    var inputDeviceID: String?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var receivedFinalResult = false
    private var lastNonEmptyTranscript = ""

    init(locale: Locale = .current, inputDeviceID: String? = nil) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))!
        self.inputDeviceID = inputDeviceID
        super.init()
        recognizer.delegate = self
    }

    func start() async throws {
        guard recognizer.isAvailable else { throw Error.unavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw Error.onDeviceUnavailable }

        let microphone = await requestMicrophoneAccess()
        guard microphone else { throw Error.microphoneDenied }
        let speech = await requestSpeechAccess()
        guard speech == .authorized else { throw Error.speechDenied }

        cancel()
        transcript = ""
        receivedFinalResult = false
        lastNonEmptyTranscript = ""
        onTranscriptChange?("")

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let engine = AVAudioEngine()
        let input = engine.inputNode
        activeDeviceName = nil
        fellBackToDefaultInput = false
        if let inputDeviceID {
            // A saved microphone can vanish (unplugged device). Fall back to
            // the system default instead of failing the session; the UI
            // reports the fallback so the user can update Settings.
            if let device = VoiceInputDevices.available().first(where: { $0.id == inputDeviceID }),
               let audioUnit = input.audioUnit {
                var deviceID = device.deviceID
                let status = AudioUnitSetProperty(audioUnit,
                                                  kAudioOutputUnitProperty_CurrentDevice,
                                                  kAudioUnitScope_Global,
                                                  0,
                                                  &deviceID,
                                                  UInt32(MemoryLayout<AudioDeviceID>.size))
                if status == noErr {
                    activeDeviceName = device.name
                } else {
                    fellBackToDefaultInput = true
                }
            } else {
                fellBackToDefaultInput = true
            }
        }
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine = engine

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    // Apple can deliver a final callback whose best
                    // transcription is temporarily empty even though a
                    // partial result was already shown. Never discard the
                    // last usable text at the stop boundary.
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        self.transcript = text
                        self.lastNonEmptyTranscript = text
                        self.onTranscriptChange?(text)
                    }
                    self.receivedFinalResult = result.isFinal
                }
                if error != nil { self.stopAudioCapture() }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cancel()
            throw error
        }
    }

    func stop() async throws -> String {
        stopAudioCapture()
        request?.endAudio()
        recognitionTask?.finish()

        // finish() only signals the task; its final callback arrives later.
        // Reading transcript immediately races that callback and made short
        // dictation appear empty. Wait briefly for the final result, with a
        // bound so a failed recognizer cannot hang the recording flow.
        for _ in 0..<30 where !receivedFinalResult {
            try? await Task.sleep(for: .milliseconds(100))
        }

        recognitionTask = nil
        request = nil
        let result = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = lastNonEmptyTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty || !fallback.isEmpty else { throw Error.noTranscript }
        return result.isEmpty ? fallback : result
    }

    func cancel() {
        stopAudioCapture()
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        receivedFinalResult = false
        lastNonEmptyTranscript = ""
        transcript = ""
    }

    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func requestMicrophoneAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return true
            case .denied: return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default: return false
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default: return false
        }
    }

    private func requestSpeechAccess() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

enum VoiceDictationMode: String, Codable {
    case verify
    case log

    var title: String {
        switch self {
        case .verify: return "Voice Verify"
        case .log: return "Voice Log"
        }
    }
}

enum VoiceDictationState: Equatable {
    case idle
    case recording
    case processing
    case failed(String)
}

@MainActor
final class VoiceDictationCoordinator: ObservableObject {
    @Published private(set) var state: VoiceDictationState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var mode: VoiceDictationMode = .verify
    @Published private(set) var activeMicrophoneName: String?
    @Published private(set) var usedFallbackMicrophone = false

    private let transcriber: VoiceTranscriber
    private var processingTask: Task<Void, Never>?
    var onCompleted: ((VoiceDictationMode, String, String) -> Void)?

    init(transcriber: VoiceTranscriber? = nil) {
        let selected = transcriber ?? AppleSpeechTranscriber()
        self.transcriber = selected
        selected.onTranscriptChange = { [weak self] transcript in
            self?.transcript = transcript
        }
    }

    func configure(inputDeviceID: String?) {
        (transcriber as? AppleSpeechTranscriber)?.inputDeviceID = inputDeviceID
    }

    func start(mode: VoiceDictationMode) {
        guard state == .idle || isFailure else { return }
        processingTask?.cancel()
        self.mode = mode
        transcript = ""
        activeMicrophoneName = nil
        usedFallbackMicrophone = false
        state = .recording
        Task { @MainActor in
            do {
                try await transcriber.start()
                activeMicrophoneName = transcriber.activeDeviceName ?? "System default"
                usedFallbackMicrophone = transcriber.fellBackToDefaultInput
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard state == .recording else { return }
        state = .processing
        processingTask?.cancel()
        processingTask = Task { @MainActor in
            do {
                let transcript = try await transcriber.stop()
                self.transcript = transcript
                let cleaned = try await OllamaReminderParser(model: SettingsStore.shared.ollamaModel).cleanVoice(transcript)
                guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw OllamaReminderParser.ParserError.invalidResponse
                }
                state = .idle
                onCompleted?(mode, transcript, cleaned)
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        transcriber.cancel()
        transcript = ""
        state = .idle
    }

    func retry() {
        guard isFailure else { return }
        start(mode: mode)
    }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }
}

struct VoiceDictationView: View {
    @ObservedObject var coordinator: VoiceDictationCoordinator
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: coordinator.state == .recording ? "waveform.circle.fill" : "waveform.circle")
                    .font(.title2)
                    .rotationEffect(.degrees(coordinator.state == .recording ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false),
                               value: coordinator.state == .recording)
                    .foregroundStyle(coordinator.state == .recording ? .red : .accentColor)
                Text(coordinator.mode.title)
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }

            switch coordinator.state {
            case .recording:
                Text("Listening…")
                    .foregroundStyle(.secondary)
                if let mic = coordinator.activeMicrophoneName {
                    Text("Mic: \(mic)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if coordinator.usedFallbackMicrophone {
                    Text("Saved microphone unavailable — using System default. Update it in Settings.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Text(coordinator.transcript.isEmpty ? "Speak your reminders" : coordinator.transcript)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                Button("Stop Recording") { coordinator.stop() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .processing:
                ProgressView("Preparing reminders…")
                Text(coordinator.transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("Retry") { coordinator.retry() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                }
            case .idle:
                EmptyView()
            }
        }
        .padding(16)
        .frame(width: 340)
        .liquidGlassPopup()
        .onExitCommand(perform: onCancel)
    }
}
