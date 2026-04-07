import SwiftUI
import AVFoundation
import Speech

final class SpeechController: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var recordError: String?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var silenceStopWorkItem: DispatchWorkItem?
    private let silenceTimeout: TimeInterval = 1.0
    private let audioSession = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestAuthorizationIfNeeded(completion: ((SFSpeechRecognizerAuthorizationStatus) -> Void)? = nil) {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        authorizationStatus = currentStatus

        guard currentStatus == .notDetermined else {
            completion?(currentStatus)
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                completion?(status)
            }
        }
    }

    func startRecording(localeIdentifier: String) {
        stopRecording()
        transcript = ""
        recordError = nil
        requestAuthorizationIfNeeded { [weak self] status in
            guard let self else { return }
            guard status == .authorized else {
                self.recordError = self.authorizationErrorMessage(for: status)
                return
            }
            self.beginRecording(localeIdentifier: localeIdentifier)
        }
    }

    func stopRecording() {
        silenceStopWorkItem?.cancel()
        silenceStopWorkItem = nil
        guard isRecording || audioEngine.isRunning || request != nil || task != nil else {
            return
        }
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
    }

    func deactivateAudioSession() {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecording(localeIdentifier: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))

        guard let recognizer = recognizer, recognizer.isAvailable else {
            recordError = "Spracherkennung ist gerade nicht verfügbar."
            return
        }

        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try audioSession.setPreferredIOBufferDuration(0.005)
            try audioSession.setActive(true)

            request = SFSpeechAudioBufferRecognitionRequest()
            guard let request = request else {
                recordError = "Audio Anfrage konnte nicht erstellt werden."
                return
            }
            request.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result = result {
                        self?.transcript = result.bestTranscription.formattedString
                        self?.scheduleSilenceStopIfNeeded(
                            for: result.bestTranscription.formattedString,
                            isFinal: result.isFinal
                        )
                    }
                    if let error = error {
                        guard self?.shouldSurfaceRecognitionError(error) == true else { return }
                        self?.recordError = error.localizedDescription
                        self?.stopRecording()
                        return
                    }
                    if result?.isFinal == true {
                        self?.stopRecording()
                    }
                }
            }
        } catch {
            recordError = error.localizedDescription
            stopRecording()
        }
    }

    private func scheduleSilenceStopIfNeeded(for transcript: String, isFinal: Bool) {
        silenceStopWorkItem?.cancel()
        silenceStopWorkItem = nil

        guard isRecording, !isFinal, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            self.stopRecording()
        }

        silenceStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceTimeout, execute: workItem)
    }

    private func shouldSurfaceRecognitionError(_ error: Error) -> Bool {
        if !isRecording {
            return false
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return false
        }

        let message = nsError.localizedDescription.lowercased()
        if message.contains("cancel") || message.contains("abgebrochen") {
            return false
        }

        return true
    }

    private func authorizationErrorMessage(for status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .denied:
            return "Bitte erlaube den Mikrofon- und Speech-Zugriff in den Einstellungen."
        case .restricted:
            return "Spracherkennung ist auf diesem Gerät eingeschränkt."
        case .notDetermined:
            return "Spracherkennung ist noch nicht freigegeben."
        case .authorized:
            return "Spracherkennung ist gerade nicht verfügbar."
        @unknown default:
            return "Spracherkennung ist gerade nicht verfügbar."
        }
    }
}
