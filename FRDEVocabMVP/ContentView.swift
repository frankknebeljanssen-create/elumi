import SwiftUI
import AVFoundation
import Speech
import Vision
import UIKit
import ImageIO
import NaturalLanguage

struct FlashCard: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
    let answer: String
    let promptLanguageCode: String
    let answerLanguageCode: String
    let category: String
}

enum AppScreen: Hashable {
    case train
    case flashcards
    case lists
    case scan
}

enum Direction: String, CaseIterable, Identifiable, Codable {
    case frenchToGerman = "Französisch → Deutsch"
    case germanToFrench = "Deutsch → Französisch"

    var id: String { rawValue }
}

enum CardType: String, CaseIterable, Identifiable, Codable {
    case words = "Wörter"
    case phrases = "Phrasen"

    var id: String { rawValue }

    var categoryName: String {
        switch self {
        case .words:
            return "Wort"
        case .phrases:
            return "Phrase"
        }
    }
}

enum VocabularyLevel: String, CaseIterable, Identifiable, Codable {
    case beginner = "Anfänger"
    case intermediate = "Mittel"
    case advanced = "Fortgeschritten"

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .beginner:
            return 1
        case .intermediate:
            return 2
        case .advanced:
            return 3
        }
    }
}

enum TrainingSource: String, CaseIterable, Identifiable {
    case curriculum = "Standard"
    case customList = "Eigene Liste"

    var id: String { rawValue }
}

enum ImportColumnOrder: String, CaseIterable, Identifiable {
    case autoDetect = "Auto"
    case frenchFirst = "FR | DE"
    case germanFirst = "DE | FR"

    var id: String { rawValue }
}

struct VocabularyItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var french: String
    var german: String
    var cardType: CardType
    var level: VocabularyLevel? = nil

    func card(for direction: Direction) -> FlashCard {
        switch direction {
        case .frenchToGerman:
            return FlashCard(
                prompt: french,
                answer: german,
                promptLanguageCode: "fr-FR",
                answerLanguageCode: "de-DE",
                category: cardType.categoryName
            )
        case .germanToFrench:
            return FlashCard(
                prompt: german,
                answer: french,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "fr-FR",
                category: cardType.categoryName
            )
        }
    }
}

struct VocabularyList: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var items: [VocabularyItem]
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, items: [VocabularyItem], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.items = items
        self.isBuiltIn = isBuiltIn
    }
}

struct FlashcardDeckCard: Identifiable, Codable, Equatable {
    let id: String
    let french: String
    let german: String

    func card(for direction: Direction) -> FlashCard {
        switch direction {
        case .frenchToGerman:
            return FlashCard(
                prompt: french,
                answer: german,
                promptLanguageCode: "fr-FR",
                answerLanguageCode: "de-DE",
                category: "Karteikarte"
            )
        case .germanToFrench:
            return FlashCard(
                prompt: german,
                answer: french,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "fr-FR",
                category: "Karteikarte"
            )
        }
    }
}

struct FlashcardDeck: Identifiable, Equatable {
    let id: String
    let name: String
    let cards: [FlashcardDeckCard]
}

private struct OCRLineBox: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect

    var midX: CGFloat { boundingBox.midX }
    var midY: CGFloat { boundingBox.midY }
    var height: CGFloat { boundingBox.height }
    var minX: CGFloat { boundingBox.minX }
    var width: CGFloat { boundingBox.width }
}

private struct ImportPreviewPair: Identifiable, Equatable {
    var id = UUID()
    var french: String
    var german: String
}

struct FlashcardSessionState: Codable, Equatable {
    var deckID: String
    var direction: Direction
    var remainingCardIDs: [String]
    var currentCardID: String?
    var correctCount: Int
    var wrongCount: Int
    var isCompleted: Bool
}

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
        requestAuthorization()
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
            }
        }
    }

    func startRecording(localeIdentifier: String) {
        stopRecording()
        transcript = ""
        recordError = nil
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
                        self?.scheduleSilenceStopIfNeeded(for: result.bestTranscription.formattedString, isFinal: result.isFinal)
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

    func stopRecording() {
        silenceStopWorkItem?.cancel()
        silenceStopWorkItem = nil
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
}

@MainActor
final class Speaker: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false

    private let synth = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(text: String, languageCode: String) {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false

        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            // If session setup fails, continue with speech synthesis anyway.
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.82
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
        deactivatePlaybackSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        deactivatePlaybackSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        deactivatePlaybackSession()
    }

    private func deactivatePlaybackSession() {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class FeedbackPlayer: ObservableObject {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let audioSession = AVAudioSession.sharedInstance()
    private let sampleRate: Double = 44_100
    private let successBuffer: AVAudioPCMBuffer?
    private let errorBuffer: AVAudioPCMBuffer?
    private var isConfigured = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        successBuffer = FeedbackPlayer.makeBuffer(
            format: format,
            sampleRate: sampleRate,
            segments: [
                (frequency: 988, duration: 0.05, amplitude: 0.23),
                (frequency: 1318, duration: 0.07, amplitude: 0.24),
                (frequency: 1568, duration: 0.11, amplitude: 0.22)
            ]
        )
        errorBuffer = FeedbackPlayer.makeBuffer(
            format: format,
            sampleRate: sampleRate,
            segments: [
                (frequency: 320, duration: 0.05, amplitude: 0.2),
                (frequency: 240, duration: 0.08, amplitude: 0.22),
                (frequency: 180, duration: 0.12, amplitude: 0.18)
            ]
        )
    }

    func playSuccess() {
        play(successBuffer)
    }

    func playError() {
        play(errorBuffer)
    }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }

        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            // If audio session setup fails, skip reconfiguration and still attempt playback.
        }

        configureEngineIfNeeded(for: buffer.format)
        guard let playerNode else { return }
        startEngineIfNeeded()
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        playerNode.play()
    }

    private func configureEngineIfNeeded(for format: AVAudioFormat) {
        guard !isConfigured else { return }
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        self.engine = engine
        self.playerNode = playerNode
        isConfigured = true
    }

    private func startEngineIfNeeded() {
        guard let engine else { return }
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            // If the engine fails to start, the app should still function without feedback tones.
        }
    }

    private static func makeBuffer(
        format: AVAudioFormat?,
        sampleRate: Double,
        segments: [(frequency: Double, duration: Double, amplitude: Double)]
    ) -> AVAudioPCMBuffer? {
        guard let format else { return nil }

        let totalFrames = segments.reduce(0) { partialResult, segment in
            partialResult + Int(segment.duration * sampleRate)
        }

        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(totalFrames)
              ),
              let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        var frameIndex = 0
        for segment in segments {
            let segmentFrames = Int(segment.duration * sampleRate)
            guard segmentFrames > 0 else { continue }

            for sampleIndex in 0..<segmentFrames {
                let progress = Double(sampleIndex) / Double(segmentFrames)
                let envelope = min(progress * 6, 1) * min((1 - progress) * 6, 1)
                let time = Double(sampleIndex) / sampleRate
                let sample = sin(2 * Double.pi * segment.frequency * time) * segment.amplitude * envelope
                channelData[frameIndex] = Float(sample)
                frameIndex += 1
            }
        }

        buffer.frameLength = AVAudioFrameCount(frameIndex)
        return buffer
    }
}

final class VocabularyListStore: ObservableObject {
    static let builtInListID = UUID(uuidString: "5A30AE93-0F08-4A96-B55A-A77E3F4D2A9B")!

    @Published private(set) var customLists: [VocabularyList] = [] {
        didSet { saveCustomLists() }
    }
    @Published var selectedListID: UUID = builtInListID {
        didSet { saveSelectedListID() }
    }

    private let customListsKey = "FRDEVocabMVP.customLists.v2"
    private let selectedListKey = "FRDEVocabMVP.selectedListID.v2"

    init() {
        loadState()
    }

    var builtInList: VocabularyList {
        VocabularyList(
            id: Self.builtInListID,
            name: "Standardpaket",
            items: DataStore.defaultItems,
            isBuiltIn: true
        )
    }

    var builtInWordsCount: Int {
        builtInList.items.filter { $0.cardType == .words }.count
    }

    var builtInPhrasesCount: Int {
        builtInList.items.filter { $0.cardType == .phrases }.count
    }

    var allLists: [VocabularyList] {
        [builtInList] + customLists
    }

    var selectedList: VocabularyList {
        allLists.first(where: { $0.id == selectedListID }) ?? builtInList
    }

    var selectedCustomList: VocabularyList? {
        customLists.first(where: { $0.id == selectedListID })
    }

    func builtInItems(for level: VocabularyLevel) -> [VocabularyItem] {
        builtInList.items.filter { ($0.level?.rank ?? Int.max) <= level.rank }
    }

    func customList(with id: UUID?) -> VocabularyList? {
        guard let id else { return customLists.first }
        return customLists.first(where: { $0.id == id }) ?? customLists.first
    }

    func suggestedListName(from baseName: String) -> String {
        uniqueListName(from: baseName)
    }

    @discardableResult
    func ensureCustomList(named proposedName: String) -> UUID {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "Liste" : trimmed

        if let existingList = customLists.first(where: {
            $0.name.localizedCaseInsensitiveCompare(baseName) == .orderedSame
        }) {
            selectedListID = existingList.id
            return existingList.id
        }

        return createList(named: baseName)
    }

    func cards(for direction: Direction, type: CardType) -> [FlashCard] {
        selectedList.items
            .filter { $0.cardType == type }
            .map { $0.card(for: direction) }
    }

    @discardableResult
    func createList(named proposedName: String = "") -> UUID {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "Liste" : trimmed
        let uniqueName = uniqueListName(from: baseName)
        let list = VocabularyList(name: uniqueName, items: [])
        customLists.append(list)
        selectedListID = list.id
        return list.id
    }

    func deleteSelectedCustomList() {
        guard let index = customLists.firstIndex(where: { $0.id == selectedListID }) else { return }
        customLists.remove(at: index)
        selectedListID = Self.builtInListID
    }

    func renameList(id: UUID, to proposedName: String) {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = customLists.firstIndex(where: { $0.id == id }) else { return }

        let currentName = customLists[index].name
        if currentName.localizedCaseInsensitiveCompare(trimmed) == .orderedSame {
            customLists[index].name = trimmed
            return
        }

        let takenNames = allLists
            .filter { $0.id != id }
            .map(\.name)

        let uniqueName: String
        if !takenNames.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            uniqueName = trimmed
        } else {
            var candidateIndex = 2
            var candidate = "\(trimmed) \(candidateIndex)"
            while takenNames.contains(where: { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
                candidateIndex += 1
                candidate = "\(trimmed) \(candidateIndex)"
            }
            uniqueName = candidate
        }

        customLists[index].name = uniqueName
        selectedListID = customLists[index].id
    }

    func addItem(french: String, german: String, type: CardType, to listID: UUID? = nil) {
        let frenchValue = french.trimmingCharacters(in: .whitespacesAndNewlines)
        let germanValue = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !frenchValue.isEmpty, !germanValue.isEmpty else { return }

        let targetID = listID ?? selectedListID
        guard let index = customLists.firstIndex(where: { $0.id == targetID }) else { return }

        customLists[index].items.append(
            VocabularyItem(
                french: frenchValue,
                german: germanValue,
                cardType: type
            )
        )
    }

    func removeItem(itemID: UUID, from listID: UUID) {
        guard let listIndex = customLists.firstIndex(where: { $0.id == listID }) else { return }
        customLists[listIndex].items.removeAll { $0.id == itemID }
    }

    @discardableResult
    func importItems(
        _ items: [VocabularyItem],
        preferredListID: UUID?,
        suggestedListName: String
    ) -> Int {
        guard !items.isEmpty else { return 0 }

        let targetID: UUID
        if let preferredListID, customLists.contains(where: { $0.id == preferredListID }) {
            targetID = preferredListID
        } else if let selectedCustomList {
            targetID = selectedCustomList.id
        } else {
            targetID = createList(named: suggestedListName)
        }

        guard let index = customLists.firstIndex(where: { $0.id == targetID }) else { return 0 }
        customLists[index].items.append(contentsOf: items)
        selectedListID = targetID
        return items.count
    }

    private func loadState() {
        if let data = UserDefaults.standard.data(forKey: customListsKey),
           let decoded = try? JSONDecoder().decode([VocabularyList].self, from: data) {
            customLists = decoded
        }

        if let rawID = UserDefaults.standard.string(forKey: selectedListKey),
           let decodedID = UUID(uuidString: rawID),
           allLists.contains(where: { $0.id == decodedID }) {
            selectedListID = decodedID
        } else {
            selectedListID = Self.builtInListID
        }
    }

    private func saveCustomLists() {
        if let data = try? JSONEncoder().encode(customLists) {
            UserDefaults.standard.set(data, forKey: customListsKey)
        }
    }

    private func saveSelectedListID() {
        UserDefaults.standard.set(selectedListID.uuidString, forKey: selectedListKey)
    }

    private func uniqueListName(from baseName: String) -> String {
        if !allLists.map(\.name).contains(where: { $0.localizedCaseInsensitiveCompare(baseName) == .orderedSame }) {
            return baseName
        }

        for index in 2...999 {
            let candidate = "\(baseName) \(index)"
            if !allLists.map(\.name).contains(where: { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
                return candidate
            }
        }

        return "\(baseName) \(UUID().uuidString.prefix(4))"
    }
}

final class FlashcardSessionStore: ObservableObject {
    @Published var selectedDeckID: String {
        didSet {
            UserDefaults.standard.set(selectedDeckID, forKey: selectedDeckKey)
            ensureValidSession()
        }
    }
    @Published var selectedDirection: Direction {
        didSet {
            UserDefaults.standard.set(selectedDirection.rawValue, forKey: selectedDirectionKey)
            ensureValidSession()
        }
    }
    @Published private(set) var session: FlashcardSessionState? {
        didSet { saveSession() }
    }

    private let sessionKey = "FRDEVocabMVP.flashcardSession.v1"
    private let selectedDeckKey = "FRDEVocabMVP.flashcardDeck.v1"
    private let selectedDirectionKey = "FRDEVocabMVP.flashcardDirection.v1"

    init() {
        let defaultDeckID = DataStore.flashcardDecks.first?.id ?? "flashcards-1"
        self.selectedDeckID = UserDefaults.standard.string(forKey: selectedDeckKey) ?? defaultDeckID

        if let rawDirection = UserDefaults.standard.string(forKey: selectedDirectionKey),
           let decodedDirection = Direction(rawValue: rawDirection) {
            self.selectedDirection = decodedDirection
        } else {
            self.selectedDirection = .frenchToGerman
        }

        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let decoded = try? JSONDecoder().decode(FlashcardSessionState.self, from: data) {
            self.session = decoded
        } else {
            self.session = nil
        }

        ensureValidSession()
    }

    var decks: [FlashcardDeck] {
        DataStore.flashcardDecks
    }

    var selectedDeck: FlashcardDeck {
        decks.first(where: { $0.id == selectedDeckID }) ?? decks[0]
    }

    var totalCount: Int {
        selectedDeck.cards.count
    }

    var masteredCount: Int {
        totalCount - (session?.remainingCardIDs.count ?? totalCount)
    }

    var remainingCount: Int {
        session?.remainingCardIDs.count ?? totalCount
    }

    var wrongCount: Int {
        session?.wrongCount ?? 0
    }

    var hasActiveSession: Bool {
        guard let session else { return false }
        return session.deckID == selectedDeck.id
            && session.direction == selectedDirection
            && !session.isCompleted
            && !session.remainingCardIDs.isEmpty
    }

    var currentCard: FlashcardDeckCard? {
        guard let session, let currentCardID = session.currentCardID else { return nil }
        return selectedDeck.cards.first(where: { $0.id == currentCardID })
    }

    func startOrResumeSession() {
        if hasActiveSession {
            if currentCard == nil {
                chooseNextCard(avoiding: nil)
            }
            return
        }

        let ids = selectedDeck.cards.map(\.id)
        let firstID = ids.randomElement()
        session = FlashcardSessionState(
            deckID: selectedDeck.id,
            direction: selectedDirection,
            remainingCardIDs: ids,
            currentCardID: firstID,
            correctCount: 0,
            wrongCount: 0,
            isCompleted: ids.isEmpty
        )
    }

    func restartSession() {
        let ids = selectedDeck.cards.map(\.id)
        session = FlashcardSessionState(
            deckID: selectedDeck.id,
            direction: selectedDirection,
            remainingCardIDs: ids,
            currentCardID: ids.randomElement(),
            correctCount: 0,
            wrongCount: 0,
            isCompleted: ids.isEmpty
        )
    }

    func markCorrect() {
        guard var session, let currentCardID = session.currentCardID else { return }
        session.remainingCardIDs.removeAll { $0 == currentCardID }
        session.correctCount += 1

        if session.remainingCardIDs.isEmpty {
            session.currentCardID = nil
            session.isCompleted = true
            self.session = session
            return
        }

        self.session = session
        chooseNextCard(avoiding: currentCardID)
    }

    func markWrong() {
        guard var session else { return }
        session.wrongCount += 1
        self.session = session
        chooseNextCard(avoiding: session.currentCardID)
    }

    private func chooseNextCard(avoiding currentID: String?) {
        guard var session else { return }
        let candidates: [String]
        if let currentID, session.remainingCardIDs.count > 1 {
            let filtered = session.remainingCardIDs.filter { $0 != currentID }
            candidates = filtered.isEmpty ? session.remainingCardIDs : filtered
        } else {
            candidates = session.remainingCardIDs
        }

        session.currentCardID = candidates.randomElement()
        self.session = session
    }

    private func ensureValidSession() {
        guard let firstDeck = decks.first else { return }
        if !decks.contains(where: { $0.id == selectedDeckID }) {
            selectedDeckID = firstDeck.id
        }

        guard let session else { return }
        guard session.deckID == selectedDeckID, session.direction == selectedDirection else {
            self.session = nil
            return
        }

        let validIDs = Set(selectedDeck.cards.map(\.id))
        let remaining = session.remainingCardIDs.filter { validIDs.contains($0) }
        let currentIsValid = session.currentCardID.map { validIDs.contains($0) } ?? false

        var updated = session
        updated.remainingCardIDs = remaining
        updated.currentCardID = currentIsValid ? session.currentCardID : remaining.randomElement()
        updated.isCompleted = remaining.isEmpty
        self.session = updated
    }

    private func saveSession() {
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }
    }
}

struct ScoreResult {
    let label: String
    let detail: String
}

struct ContentView: View {
    @StateObject private var speechController = SpeechController()
    @StateObject private var speaker = Speaker()
    @StateObject private var feedbackPlayer = FeedbackPlayer()
    @StateObject private var listStore = VocabularyListStore()
    @StateObject private var flashcardSessionStore = FlashcardSessionStore()

    var body: some View {
        NavigationStack {
            HomeView(listStore: listStore)
                .navigationDestination(for: AppScreen.self) { screen in
                    switch screen {
                    case .train:
                        TrainingView(
                            listStore: listStore,
                            speechController: speechController,
                            speaker: speaker,
                            feedbackPlayer: feedbackPlayer
                        )
                    case .flashcards:
                        FlashcardsView(
                            sessionStore: flashcardSessionStore,
                            speechController: speechController,
                            speaker: speaker,
                            feedbackPlayer: feedbackPlayer
                        )
                    case .lists:
                        ListsView(listStore: listStore)
                    case .scan:
                        ScanImportView(listStore: listStore)
                    }
                }
        }
    }
}

struct HomeView: View {
    @ObservedObject var listStore: VocabularyListStore

    private var wordsCount: Int {
        listStore.builtInWordsCount
    }

    private var phrasesCount: Int {
        listStore.builtInPhrasesCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Vokabeltrainer")
                    .font(.largeTitle.bold())
                Text("Standardtraining mit festen Inhalten")
                    .foregroundStyle(.secondary)
                Text("\(wordsCount) Wörter · \(phrasesCount) Phrasen · \(listStore.customLists.count) eigene Listen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            NavigationLink(value: AppScreen.train) {
                HomeActionButton(title: "Train", subtitle: "Sprechen, prüfen, weiter", systemImage: "mic.circle.fill")
            }
            .buttonStyle(.plain)

            NavigationLink(value: AppScreen.flashcards) {
                HomeActionButton(title: "Karteikarten", subtitle: "Stapel klassisch abarbeiten", systemImage: "square.stack.3d.up.fill")
            }
            .buttonStyle(.plain)

            NavigationLink(value: AppScreen.lists) {
                HomeActionButton(title: "Lists", subtitle: "Listen anlegen und pflegen", systemImage: "list.bullet.rectangle.fill")
            }
            .buttonStyle(.plain)

            NavigationLink(value: AppScreen.scan) {
                HomeActionButton(title: "Scan", subtitle: "OCR Text schnell importieren", systemImage: "text.viewfinder")
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Home")
    }
}

struct TrainingView: View {
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var speechController: SpeechController
    @ObservedObject var speaker: Speaker
    @ObservedObject var feedbackPlayer: FeedbackPlayer

    @State private var trainingSource: TrainingSource = .curriculum
    @State private var selectedLevel: VocabularyLevel = .beginner
    @State private var selectedTrainingListID: UUID?
    @State private var direction: Direction = .frenchToGerman
    @State private var cardType: CardType = .words
    @State private var currentCard: FlashCard?
    @State private var lastResult: ScoreResult?
    @State private var shouldEvaluateAfterStop = false
    @State private var pendingFeedbackTask: DispatchWorkItem?
    @State private var hasStartedTraining = false
    @State private var failedAttemptsOnCurrentCard = 0

    private var activeDeck: [FlashCard] {
        activeItems
            .filter { $0.cardType == cardType }
            .map { $0.card(for: direction) }
    }

    private var activeItems: [VocabularyItem] {
        switch trainingSource {
        case .curriculum:
            return listStore.builtInItems(for: selectedLevel)
        case .customList:
            return selectedTrainingList?.items ?? []
        }
    }

    private var availableCustomLists: [VocabularyList] {
        listStore.customLists
    }

    private var selectedTrainingList: VocabularyList? {
        listStore.customList(with: selectedTrainingListID)
    }

    private var localeIdentifierForRecognition: String {
        switch direction {
        case .frenchToGerman:
            return "de-DE"
        case .germanToFrench:
            return "fr-FR"
        }
    }

    private var recordButtonTitle: String {
        if speechController.isRecording {
            return "Aufnahme stoppen"
        }
        return speechController.transcript.isEmpty ? "Antwort aufnehmen" : "Erneut aufnehmen"
    }

    private var actionButtonHeight: CGFloat {
        82
    }

    private var actionButtonFont: Font {
        .system(size: 22, weight: .semibold, design: .rounded)
    }

    private var recordingSymbolName: String {
        speechController.isRecording ? "stop.fill" : "mic.fill"
    }

    private var showsRetryOnlyMessage: Bool {
        lastResult?.label == "Falsch"
    }

    private var showsNotRecognizedMessage: Bool {
        lastResult?.label == "Nicht erkannt"
    }

    private var showsSuccessOnlyMessage: Bool {
        lastResult?.label == "Korrekt! 🙂"
    }

    private var showsSolutionMessage: Bool {
        lastResult?.label == "Lösung"
    }

    private var solutionUnlockThreshold: Int {
        5
    }

    private var canRevealSolution: Bool {
        hasStartedTraining && currentCard != nil && failedAttemptsOnCurrentCard >= solutionUnlockThreshold
    }

    private var recordingButtonColor: Color {
        showsSuccessOnlyMessage ? .green : .accentColor
    }

    private var solutionButtonTitle: String {
        if canRevealSolution {
            return "Lösung"
        }
        return "Lösung \(failedAttemptsOnCurrentCard)/\(solutionUnlockThreshold)"
    }

    private var canStartTraining: Bool {
        !activeDeck.isEmpty
    }

    private var trainingSummaryTitle: String {
        switch trainingSource {
        case .curriculum:
            return "Los geht's"
        case .customList:
            return selectedTrainingList?.name ?? "Eigene Liste"
        }
    }

    private var trainingSummaryDetail: String {
        switch trainingSource {
        case .curriculum:
            return "\(selectedLevel.rawValue) · \(activeDeck.count) \(cardType.rawValue.lowercased()) bereit"
        case .customList:
            let listName = selectedTrainingList?.name ?? "Keine Liste"
            return "\(listName) · \(activeDeck.count) \(cardType.rawValue.lowercased()) bereit"
        }
    }

    private var startHintText: String {
        if trainingSource == .customList {
            return "Für diesen Typ gibt es in der gewählten Liste noch keine Einträge."
        }
        return "Für dieses Niveau sind für den gewählten Typ gerade keine Karten verfügbar."
    }

    var body: some View {
        VStack(spacing: 14) {
            configurationCard
            sessionCard
            actionButtons
            responseCard

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Train")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureTrainingSelectionValidity()
            resetTrainingSession()
        }
        .onChange(of: direction) { _, _ in
            resetTrainingSession()
        }
        .onChange(of: cardType) { _, _ in
            resetTrainingSession()
        }
        .onChange(of: trainingSource) { _, _ in
            ensureTrainingSelectionValidity()
            resetTrainingSession()
        }
        .onChange(of: selectedLevel) { _, _ in
            resetTrainingSession()
        }
        .onChange(of: selectedTrainingListID) { _, _ in
            resetTrainingSession()
        }
        .onChange(of: listStore.customLists) { _, _ in
            ensureTrainingSelectionValidity()
            resetTrainingSession()
        }
        .onChange(of: speechController.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording, shouldEvaluateAfterStop else { return }
            shouldEvaluateAfterStop = false
            evaluateTranscript()
        }
        .onDisappear {
            cancelPendingFeedback()
            shouldEvaluateAfterStop = false
            speechController.stopRecording()
            speechController.deactivateAudioSession()
        }
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if !availableCustomLists.isEmpty {
                    Menu {
                        ForEach(TrainingSource.allCases) { source in
                            Button(source.rawValue) {
                                trainingSource = source
                            }
                        }
                    } label: {
                        selectionChip(trainingSource.rawValue)
                    }
                } else {
                    selectionChip("Standard")
                }

                Spacer(minLength: 0)

                if trainingSource == .curriculum {
                    Menu {
                        ForEach(VocabularyLevel.allCases) { level in
                            Button(level.rawValue) {
                                selectedLevel = level
                            }
                        }
                    } label: {
                        selectionChip(selectedLevel.rawValue)
                    }
                } else {
                    Menu {
                        ForEach(availableCustomLists) { list in
                            Button(list.name) {
                                selectedTrainingListID = list.id
                            }
                        }
                    } label: {
                        selectionChip(selectedTrainingList?.name ?? "Liste wählen")
                    }
                }
            }

            Picker("Richtung", selection: $direction) {
                ForEach(Direction.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("Typ", selection: $cardType) {
                ForEach(CardType.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var sessionCard: some View {
        Group {
            if !hasStartedTraining {
                VStack(alignment: .leading, spacing: 14) {
                    Text(trainingSummaryTitle)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(trainingSummaryDetail)
                        .foregroundStyle(.secondary)

                    Button {
                        startTraining()
                    } label: {
                        Text("Los geht's")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 72)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .background(canStartTraining ? Color.accentColor : Color.gray.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStartTraining)

                    if !canStartTraining {
                        Text(startHintText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else if let currentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentCard.category.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(currentCard.prompt)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keine Karten")
                        .font(.headline)
                    Text(startHintText)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsNotRecognizedMessage {
                Text("Nicht erkannt, bitte nochmal sprechen.")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if showsRetryOnlyMessage {
                Text("Falsch, bitte nochmal. 🙃")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if showsSolutionMessage, let currentCard {
                Text("Lösung")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(currentCard.answer)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else if !hasStartedTraining {
                Text("Bereit?")
                    .font(.headline)
                Text("Tippe oben auf Los geht's, dann startet die erste Karte direkt.")
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Antwort")
                    .font(.headline)
                Text(speechController.transcript.isEmpty ? "Noch nichts erkannt" : speechController.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(speechController.transcript.isEmpty ? .secondary : .primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }

            if let error = speechController.recordError {
                Text("Hinweis: \(error)")
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var actionButtons: some View {
        VStack(spacing: 14) {
            Button {
                toggleRecording()
            } label: {
                Group {
                    if showsSuccessOnlyMessage {
                        Text("Korrekt! 🙂")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: recordingSymbolName)
                            .font(.system(size: 34, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: actionButtonHeight)
                .foregroundStyle(.white)
                .background(recordingButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .disabled(!hasStartedTraining || currentCard == nil || speechController.authorizationStatus == .denied || speechController.authorizationStatus == .restricted)
            .opacity(!hasStartedTraining || currentCard == nil || speechController.authorizationStatus == .denied || speechController.authorizationStatus == .restricted ? 0.5 : 1)

            Button {
                speakCurrentPrompt()
            } label: {
                Label("Vorsprechen", systemImage: "speaker.wave.2.fill")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .font(actionButtonFont)
                    .foregroundStyle(.primary)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .disabled(!hasStartedTraining || currentCard == nil)
            .opacity(!hasStartedTraining || currentCard == nil ? 0.5 : 1)

            Button {
                revealSolution()
            } label: {
                Label(solutionButtonTitle, systemImage: "lightbulb")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canRevealSolution)
            .opacity(canRevealSolution ? 1 : 0.6)

            Button {
                cancelPendingFeedback()
                loadRandomCard(avoidingCurrentCard: true)
                speakCurrentPrompt()
            } label: {
                Label("Nächste Karte", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!hasStartedTraining || activeDeck.isEmpty)
        }
    }

    private func selectionChip(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func ensureTrainingSelectionValidity() {
        if availableCustomLists.isEmpty {
            trainingSource = .curriculum
            selectedTrainingListID = nil
            return
        }

        let preferredListID = listStore.selectedCustomList?.id ?? availableCustomLists.first?.id

        if trainingSource == .customList, selectedTrainingList == nil {
            selectedTrainingListID = preferredListID
        }

        if selectedTrainingListID == nil {
            selectedTrainingListID = preferredListID
        }
    }

    private func resetTrainingSession() {
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        hasStartedTraining = false
        failedAttemptsOnCurrentCard = 0
        currentCard = nil
        lastResult = nil
        speaker.stop()
        speechController.stopRecording()
        speechController.transcript = ""
        speechController.recordError = nil
    }

    private func startTraining() {
        ensureTrainingSelectionValidity()
        guard canStartTraining else {
            resetTrainingSession()
            return
        }

        hasStartedTraining = true
        loadRandomCard()
        speakCurrentPrompt()
    }

    private func speakCurrentPrompt() {
        guard let currentCard else { return }
        speaker.speak(text: currentCard.prompt, languageCode: currentCard.promptLanguageCode)
    }

    private func toggleRecording() {
        guard hasStartedTraining, currentCard != nil else { return }
        cancelPendingFeedback()

        if speechController.isRecording {
            shouldEvaluateAfterStop = true
            speechController.stopRecording()
        } else {
            speaker.stop()
            lastResult = nil
            shouldEvaluateAfterStop = true
            speechController.startRecording(localeIdentifier: localeIdentifierForRecognition)
        }
    }

    private func loadRandomCard(avoidingCurrentCard: Bool = false) {
        let previousCard = currentCard
        failedAttemptsOnCurrentCard = 0
        speechController.transcript = ""
        speechController.recordError = nil
        lastResult = nil

        let availableCards: [FlashCard]
        if avoidingCurrentCard, let previousCard, activeDeck.count > 1 {
            let filteredCards = activeDeck.filter { card in
                card.prompt != previousCard.prompt || card.answer != previousCard.answer
            }
            availableCards = filteredCards.isEmpty ? activeDeck : filteredCards
        } else {
            availableCards = activeDeck
        }

        guard let newCard = availableCards.randomElement() else {
            hasStartedTraining = false
            currentCard = nil
            return
        }

        currentCard = newCard
    }

    private func evaluateTranscript() {
        guard hasStartedTraining, let currentCard else { return }

        let expected = normalized(currentCard.answer)
        let got = normalized(speechController.transcript)

        guard !got.isEmpty else {
            lastResult = ScoreResult(
                label: "Nicht erkannt",
                detail: "Bitte nochmal sprechen."
            )
            return
        }

        if got == expected {
            handleCorrectAnswer()
            return
        }

        let distance = levenshtein(got, expected)
        let maxLength = max(got.count, expected.count)
        let ratio = maxLength == 0 ? 0 : Double(distance) / Double(maxLength)

        if ratio <= 0.25 || got.contains(expected) || expected.contains(got) {
            handleCorrectAnswer()
        } else {
            feedbackPlayer.playError()
            failedAttemptsOnCurrentCard += 1
            lastResult = ScoreResult(
                label: "Falsch",
                detail: "Bitte nochmal."
            )
            repeatCurrentPrompt()
        }
    }

    private func handleCorrectAnswer() {
        feedbackPlayer.playSuccess()
        lastResult = ScoreResult(label: "Korrekt! 🙂", detail: "")
        scheduleNextCard()
    }

    private func revealSolution() {
        guard let currentCard, canRevealSolution else { return }
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController.stopRecording()
        speechController.transcript = ""
        speechController.recordError = nil
        lastResult = ScoreResult(label: "Lösung", detail: currentCard.answer)
    }

    private func repeatCurrentPrompt() {
        guard let currentCard else { return }
        scheduleFeedbackTask(after: 0.65) {
            guard isShowing(currentCard) else { return }
            speaker.speak(text: currentCard.prompt, languageCode: currentCard.promptLanguageCode)
        }
    }

    private func scheduleNextCard() {
        guard let currentCard else { return }
        scheduleFeedbackTask(after: 0.9) {
            guard isShowing(currentCard) else { return }
            loadRandomCard(avoidingCurrentCard: true)
            if hasStartedTraining {
                speakCurrentPrompt()
            }
        }
    }

    private func scheduleFeedbackTask(after delay: TimeInterval, action: @escaping () -> Void) {
        cancelPendingFeedback()
        let workItem = DispatchWorkItem(block: action)
        pendingFeedbackTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingFeedback() {
        pendingFeedbackTask?.cancel()
        pendingFeedbackTask = nil
    }

    private func isShowing(_ card: FlashCard) -> Bool {
        guard let currentCard else { return false }
        return currentCard.prompt == card.prompt
            && currentCard.answer == card.answer
            && currentCard.category == card.category
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "’", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(
                        dist[i - 1][j] + 1,
                        dist[i][j - 1] + 1,
                        dist[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return dist[a.count][b.count]
    }
}

struct FlashcardsView: View {
    @ObservedObject var sessionStore: FlashcardSessionStore
    @ObservedObject var speechController: SpeechController
    @ObservedObject var speaker: Speaker
    @ObservedObject var feedbackPlayer: FeedbackPlayer

    @State private var lastResult: ScoreResult?
    @State private var shouldEvaluateAfterStop = false
    @State private var pendingFeedbackTask: DispatchWorkItem?
    @State private var showingSolution = false
    @State private var cardFlyOutOffset: CGFloat = 0
    @State private var cardFlyOutRotation: Double = 0
    @State private var cardFlyOutOpacity: Double = 1

    private var currentCard: FlashcardDeckCard? {
        sessionStore.currentCard
    }

    private var currentFlashCard: FlashCard? {
        currentCard?.card(for: sessionStore.selectedDirection)
    }

    private var isSessionReady: Bool {
        sessionStore.hasActiveSession && currentCard != nil
    }

    private var actionButtonHeight: CGFloat {
        82
    }

    private var actionButtonFont: Font {
        .system(size: 22, weight: .semibold, design: .rounded)
    }

    private var recordingSymbolName: String {
        speechController.isRecording ? "stop.fill" : "mic.fill"
    }

    private var headerTitle: String {
        sessionStore.hasActiveSession ? "Session fortsetzen" : sessionStore.selectedDeck.name
    }

    private var progressText: String {
        "\(sessionStore.masteredCount)/\(sessionStore.totalCount) richtig · \(sessionStore.wrongCount) falsch · \(sessionStore.remainingCount) im Stapel"
    }

    private var stackCaption: String {
        if sessionStore.session?.isCompleted == true {
            return "Stapel leer"
        }
        return "\(sessionStore.remainingCount) Karten im Stapel"
    }

    private var showsSuccessOnlyMessage: Bool {
        lastResult?.label == "Korrekt! 🙂"
    }

    private var flashcardRecordingButtonColor: Color {
        showsSuccessOnlyMessage ? .green : .accentColor
    }

    var body: some View {
        VStack(spacing: 14) {
            flashcardConfigCard
            flashcardSummaryCard
            flashcardPromptCard
            flashcardActionButtons
            flashcardResponseCard

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Karteikarten")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if sessionStore.hasActiveSession == false {
                speechController.stopRecording()
                speechController.deactivateAudioSession()
            }
        }
        .onChange(of: sessionStore.selectedDeckID) { _, _ in
            resetTransientState()
        }
        .onChange(of: sessionStore.selectedDirection) { _, _ in
            resetTransientState()
        }
        .onChange(of: speechController.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording, shouldEvaluateAfterStop else { return }
            shouldEvaluateAfterStop = false
            evaluateTranscript()
        }
        .onDisappear {
            resetTransientState()
            speechController.stopRecording()
            speechController.deactivateAudioSession()
        }
    }

    private var flashcardConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(sessionStore.decks) { deck in
                        Button(deck.name) {
                            sessionStore.selectedDeckID = deck.id
                        }
                    }
                } label: {
                    selectionChip(title: sessionStore.selectedDeck.name)
                }

                Spacer(minLength: 0)

                Menu {
                    ForEach(Direction.allCases) { direction in
                        Button(direction.rawValue) {
                            sessionStore.selectedDirection = direction
                        }
                    }
                } label: {
                    selectionChip(title: sessionStore.selectedDirection.rawValue)
                }
            }

            Text("Klassischer Stapel: richtig gesagte Karten verschwinden, falsche bleiben im Deck und tauchen wieder auf, bis alle geschafft sind.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var flashcardSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headerTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(progressText)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(sessionStore.hasActiveSession ? "Weiterlernen" : "Session starten") {
                    startOrResumeSession()
                }
                .buttonStyle(.borderedProminent)
                .disabled(sessionStore.totalCount == 0)

                Button("Neu mischen") {
                    resetTransientState()
                    sessionStore.restartSession()
                }
                .buttonStyle(.bordered)
                .disabled(sessionStore.totalCount == 0)
            }

            if sessionStore.session?.isCompleted == true {
                Text("Stapel geschafft! 🎉")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var flashcardPromptCard: some View {
        Group {
            if let currentFlashCard, sessionStore.hasActiveSession {
                VStack(alignment: .leading, spacing: 8) {
                    FlashcardStackVisual(
                        remainingCount: sessionStore.remainingCount,
                        totalCount: sessionStore.totalCount,
                        caption: stackCaption
                    )
                    .padding(.bottom, 6)

                    Text(currentFlashCard.category.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(currentFlashCard.prompt)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .offset(x: cardFlyOutOffset)
                .rotationEffect(.degrees(cardFlyOutRotation))
                .opacity(cardFlyOutOpacity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Karteikarten 1")
                        .font(.headline)
                    Text("Tippe oben auf `Session starten`, dann beginnt der Stapel und merkt sich deinen Stand.")
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var flashcardResponseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sessionStore.session?.isCompleted == true {
                Text("Alle Karten aus dem Stapel sind raus. 🙂")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if showingSolution, let currentFlashCard {
                Text("Lösung")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(currentFlashCard.answer)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else if lastResult?.label == "Noch im Stapel 🙃" {
                Text("Noch im Stapel 🙃")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if lastResult?.label == "Nicht erkannt" {
                Text("Nicht erkannt, bitte nochmal sprechen.")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if sessionStore.hasActiveSession {
                Text("Antwort")
                    .font(.headline)
                Text(speechController.transcript.isEmpty ? "Noch nichts erkannt" : speechController.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(speechController.transcript.isEmpty ? .secondary : .primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            } else {
                Text("Fortschritt")
                    .font(.headline)
                Text("Richtige Karten werden aus dem Stapel entfernt. Falsche Karten bleiben drin, bis du am Ende alle geschafft hast.")
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }

            if let error = speechController.recordError {
                Text("Hinweis: \(error)")
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var flashcardActionButtons: some View {
        VStack(spacing: 14) {
            Button {
                toggleRecording()
            } label: {
                Group {
                    if showsSuccessOnlyMessage {
                        Text("Korrekt! 🙂")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: recordingSymbolName)
                            .font(.system(size: 34, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: actionButtonHeight)
                .foregroundStyle(.white)
                .background(flashcardRecordingButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .disabled(!isSessionReady || speechController.authorizationStatus == .denied || speechController.authorizationStatus == .restricted)
            .opacity(!isSessionReady || speechController.authorizationStatus == .denied || speechController.authorizationStatus == .restricted ? 0.5 : 1)

            Button {
                speakCurrentPrompt()
            } label: {
                Label("Vorsprechen", systemImage: "speaker.wave.2.fill")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .font(actionButtonFont)
                    .foregroundStyle(.primary)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .disabled(!isSessionReady)
            .opacity(isSessionReady ? 1 : 0.5)

            HStack(spacing: 10) {
                Button("Lösung") {
                    revealSolution()
                }
                .buttonStyle(.bordered)
                .disabled(!isSessionReady)

                Button("Überspringen") {
                    skipCard()
                }
                .buttonStyle(.bordered)
                .disabled(!isSessionReady)
            }
        }
    }

    private func selectionChip(title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func startOrResumeSession() {
        resetTransientState()
        sessionStore.startOrResumeSession()
        speakCurrentPrompt()
    }

    private func toggleRecording() {
        guard isSessionReady else { return }
        cancelPendingFeedback()

        if speechController.isRecording {
            shouldEvaluateAfterStop = true
            speechController.stopRecording()
        } else {
            speaker.stop()
            lastResult = nil
            showingSolution = false
            shouldEvaluateAfterStop = true
            speechController.startRecording(localeIdentifier: recognitionLocale)
        }
    }

    private var recognitionLocale: String {
        switch sessionStore.selectedDirection {
        case .frenchToGerman:
            return "de-DE"
        case .germanToFrench:
            return "fr-FR"
        }
    }

    private func speakCurrentPrompt() {
        guard let currentFlashCard else { return }
        speaker.speak(text: currentFlashCard.prompt, languageCode: currentFlashCard.promptLanguageCode)
    }

    private func evaluateTranscript() {
        guard let currentFlashCard else { return }

        let expected = normalized(currentFlashCard.answer)
        let got = normalized(speechController.transcript)

        guard !got.isEmpty else {
            lastResult = ScoreResult(label: "Nicht erkannt", detail: "Bitte nochmal sprechen.")
            showingSolution = false
            return
        }

        if isCorrect(got: got, expected: expected) {
            feedbackPlayer.playSuccess()
            lastResult = ScoreResult(label: "Korrekt! 🙂", detail: "")
            showingSolution = false
            animateCorrectCardRemoval()
        } else {
            feedbackPlayer.playError()
            lastResult = ScoreResult(label: "Noch im Stapel 🙃", detail: "")
            showingSolution = false
            sessionStore.markWrong()
            scheduleNextPrompt(after: 0.9)
        }
    }

    private func revealSolution() {
        guard let currentFlashCard else { return }
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController.stopRecording()
        speechController.transcript = ""
        lastResult = ScoreResult(label: "Lösung", detail: currentFlashCard.answer)
        showingSolution = true
    }

    private func skipCard() {
        guard isSessionReady else { return }
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController.stopRecording()
        speechController.transcript = ""
        lastResult = nil
        showingSolution = false
        sessionStore.markWrong()
        speakCurrentPrompt()
    }

    private func scheduleNextPrompt(after delay: TimeInterval) {
        cancelPendingFeedback()
        let workItem = DispatchWorkItem {
            lastResult = nil
            showingSolution = false
            if sessionStore.session?.isCompleted == true {
                speechController.transcript = ""
                return
            }
            speechController.transcript = ""
            speakCurrentPrompt()
        }
        pendingFeedbackTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingFeedback() {
        pendingFeedbackTask?.cancel()
        pendingFeedbackTask = nil
    }

    private func resetTransientState() {
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        lastResult = nil
        showingSolution = false
        resetCardFlyOut()
        speaker.stop()
        speechController.stopRecording()
        speechController.transcript = ""
        speechController.recordError = nil
    }

    private func animateCorrectCardRemoval() {
        cancelPendingFeedback()
        resetCardFlyOut()

        withAnimation(.easeIn(duration: 0.28)) {
            cardFlyOutOffset = 340
            cardFlyOutRotation = 12
            cardFlyOutOpacity = 0.15
        }

        let workItem = DispatchWorkItem {
            sessionStore.markCorrect()
            resetCardFlyOut()
            scheduleNextPrompt(after: 0.45)
        }
        pendingFeedbackTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func resetCardFlyOut() {
        cardFlyOutOffset = 0
        cardFlyOutRotation = 0
        cardFlyOutOpacity = 1
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "’", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isCorrect(got: String, expected: String) -> Bool {
        if got == expected {
            return true
        }

        let distance = levenshtein(got, expected)
        let maxLength = max(got.count, expected.count)
        let ratio = maxLength == 0 ? 0 : Double(distance) / Double(maxLength)
        return ratio <= 0.25 || got.contains(expected) || expected.contains(got)
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(
                        dist[i - 1][j] + 1,
                        dist[i][j - 1] + 1,
                        dist[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return dist[a.count][b.count]
    }
}

struct ListsView: View {
    @ObservedObject var listStore: VocabularyListStore

    @State private var newListName = ""
    @State private var editableListName = ""
    @State private var frenchText = ""
    @State private var germanText = ""
    @State private var cardType: CardType = .words

    private var selectedList: VocabularyList {
        listStore.selectedList
    }

    private var allItems: [VocabularyItem] {
        selectedList.items
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Liste", selection: $listStore.selectedListID) {
                    ForEach(listStore.allLists) { list in
                        Text(list.name).tag(list.id)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 10) {
                    TextField("Neue Liste", text: $newListName)
                        .textFieldStyle(.roundedBorder)

                    Button("Anlegen") {
                        let createdID = listStore.createList(named: newListName)
                        if createdID != VocabularyListStore.builtInListID {
                            newListName = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack {
                    Text(selectedList.isBuiltIn ? "Standardpaket" : "Eigene Liste")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(selectedList.items.count) Einträge")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !selectedList.isBuiltIn {
                    HStack(spacing: 10) {
                        TextField("Listenname", text: $editableListName)
                            .textFieldStyle(.roundedBorder)

                        Button("Umbenennen") {
                            listStore.renameList(id: selectedList.id, to: editableListName)
                            editableListName = listStore.selectedList.name
                        }
                        .buttonStyle(.bordered)
                        .disabled(editableListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 12) {
                TextField("Französisch", text: $frenchText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedList.isBuiltIn)

                TextField("Deutsch", text: $germanText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedList.isBuiltIn)

                Picker("Typ", selection: $cardType) {
                    ForEach(CardType.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(selectedList.isBuiltIn)

                HStack(spacing: 10) {
                    Button("Eintrag hinzufügen") {
                        addEntry()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedList.isBuiltIn || frenchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || germanText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Liste löschen") {
                        listStore.deleteSelectedCustomList()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedList.isBuiltIn)
                }

                if selectedList.isBuiltIn {
                    Text("Das Standardpaket bleibt unverändert. Lege für eigene Inhalte eine neue Liste an.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 10) {
                Text("Alle Einträge")
                    .font(.headline)

                if allItems.isEmpty {
                    Text("Noch keine Einträge in dieser Liste.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(allItems) { item in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.french)
                                            .lineLimit(2)
                                        Text(item.german)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Text(item.cardType == .words ? "Wort" : "Phrase")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if !selectedList.isBuiltIn {
                                        Button {
                                            listStore.removeItem(itemID: item.id, from: selectedList.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editableListName = selectedList.name
        }
        .onChange(of: listStore.selectedListID) { _, _ in
            editableListName = listStore.selectedList.name
        }
    }

    private func addEntry() {
        listStore.addItem(
            french: frenchText,
            german: germanText,
            type: cardType,
            to: selectedList.id
        )
        frenchText = ""
        germanText = ""
    }
}

struct ScanImportView: View {
    @ObservedObject var listStore: VocabularyListStore

    @State private var importText = ""
    @State private var importType: CardType = .words
    @State private var columnOrder: ImportColumnOrder = .autoDetect
    @State private var listName = ""
    @State private var importMessage = "Füge OCR Text ein. Eine Zeile entspricht einem Paar."
    @State private var previewPairs: [ImportPreviewPair] = []
    @State private var selectedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var isRecognizingImage = false
    @State private var isSyncingPreviewToText = false
    @State private var hideIncompletePreviewPairs = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Foto machen", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRecognizingImage || !UIImagePickerController.isSourceTypeAvailable(.camera))
                    .opacity(UIImagePickerController.isSourceTypeAvailable(.camera) ? 1 : 0.5)

                    Button {
                        showingPhotoLibrary = true
                    } label: {
                        Label("Bild wählen", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRecognizingImage)
                }

                Picker("Reihenfolge", selection: $columnOrder) {
                    ForEach(ImportColumnOrder.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Button("FR/DE tauschen") {
                        switch columnOrder {
                        case .autoDetect:
                            columnOrder = .germanFirst
                        case .frenchFirst:
                            columnOrder = .germanFirst
                        case .germanFirst:
                            columnOrder = .frenchFirst
                        }
                    }
                    .buttonStyle(.bordered)

                    Text(columnOrder == .autoDetect ? "Auto erkennt die Sprache" : "Falls OCR vertauscht hat, hier wechseln")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Picker("Typ", selection: $importType) {
                    ForEach(CardType.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Listenname", text: $listName)
                    .textFieldStyle(.roundedBorder)

                Text("Format: `bonjour = guten tag` oder `bonjour → guten tag`")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            TextEditor(text: $importText)
                .padding(12)
                .frame(height: 210)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            if !previewPairs.isEmpty {
                previewCard
            }

            Button("Importieren") {
                importScannedText()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text(importMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureSuggestedListName()
            refreshPreviewPairsFromImportText()
        }
        .onChange(of: importText) { _, newValue in
            if isSyncingPreviewToText {
                isSyncingPreviewToText = false
                return
            }

            previewPairs = parsePreviewPairs(from: newValue)
        }
        .onChange(of: columnOrder) { _, _ in
            refreshPreviewPairsFromImportText()
        }
        .sheet(isPresented: $showingCamera) {
            ImagePicker(sourceType: .camera) { image in
                handleSelectedImage(image)
            }
        }
        .sheet(isPresented: $showingPhotoLibrary) {
            ImagePicker(sourceType: .photoLibrary) { image in
                handleSelectedImage(image)
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vorschau")
                    .font(.headline)
                Spacer()
                Text("\(previewPairs.count) Paare")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Toggle("Fehlerhafte ausblenden", isOn: $hideIncompletePreviewPairs)
                    .font(.subheadline)

                Spacer()

                Button("Zeile hinzufügen") {
                    previewPairs.append(ImportPreviewPair(french: "", german: ""))
                    syncImportTextFromPreview()
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(visiblePreviewPairs) { pair in
                        HStack(spacing: 8) {
                            TextField("Französisch", text: Binding(
                                get: { bindingValue(for: pair.id)?.french ?? "" },
                                set: { newValue in
                                    updatePreviewPair(pair.id) { $0.french = newValue }
                                    syncImportTextFromPreview()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField("Deutsch", text: Binding(
                                get: { bindingValue(for: pair.id)?.german ?? "" },
                                set: { newValue in
                                    updatePreviewPair(pair.id) { $0.german = newValue }
                                    syncImportTextFromPreview()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Button {
                                previewPairs.removeAll { $0.id == pair.id }
                                syncImportTextFromPreview()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func importScannedText() {
        let items = previewPairs.compactMap { pair in
            makeVocabularyItem(french: pair.french, german: pair.german)
        }
        let trimmedListName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetListID = listStore.ensureCustomList(
            named: trimmedListName.isEmpty ? listStore.suggestedListName(from: "Scan") : trimmedListName
        )
        let importedCount = listStore.importItems(
            items,
            preferredListID: targetListID,
            suggestedListName: trimmedListName.isEmpty ? "Scan" : trimmedListName
        )

        if importedCount == 0 {
            importMessage = "Keine Paare erkannt. Nutze pro Zeile ein Trennzeichen wie `=` oder `→`."
            return
        }

        importMessage = "\(importedCount) Einträge in „\(listStore.selectedList.name)“ importiert."
        importText = ""
        listName = listStore.selectedList.name
    }

    private var visiblePreviewPairs: [ImportPreviewPair] {
        if hideIncompletePreviewPairs {
            return previewPairs.filter { pair in
                !sanitizedLine(pair.french).isEmpty && !sanitizedLine(pair.german).isEmpty
            }
        }

        return previewPairs
    }

    private func parsePreviewPairs(from rawText: String) -> [ImportPreviewPair] {
        let rawLines = rawText
            .components(separatedBy: .newlines)
            .map { sanitizedLine($0) }
            .filter { !$0.isEmpty }

        var explicitPairs: [ImportPreviewPair] = []
        var unmatchedLines: [String] = []

        for line in rawLines {
            if let pair = splitLine(line), let previewPair = makePreviewPair(first: pair.0, second: pair.1) {
                explicitPairs.append(previewPair)
            } else {
                unmatchedLines.append(line)
            }
        }

        if !explicitPairs.isEmpty {
            return explicitPairs + unmatchedLines.map { makeIncompletePreviewPair(from: $0) }
        }

        var fallbackPairs: [ImportPreviewPair] = []
        var index = 0
        while index + 1 < rawLines.count {
            if let pair = makePreviewPair(first: rawLines[index], second: rawLines[index + 1]) {
                fallbackPairs.append(pair)
            }
            index += 2
        }

        if index < rawLines.count {
            fallbackPairs.append(makeIncompletePreviewPair(from: rawLines[index]))
        }

        return fallbackPairs
    }

    private func splitLine(_ line: String) -> (String, String)? {
        let separators = ["→", "=", ";", "\t", " - ", ":"]

        for separator in separators {
            guard let range = line.range(of: separator) else { continue }
            let left = String(line[..<range.lowerBound])
            let right = String(line[range.upperBound...])
            return (left, right)
        }

        if let range = line.range(of: #" {2,}"#, options: .regularExpression) {
            let left = String(line[..<range.lowerBound])
            let right = String(line[range.upperBound...])
            return (left, right)
        }

        return nil
    }

    private func handleSelectedImage(_ image: UIImage?) {
        guard let image else { return }
        selectedImage = image
        ensureSuggestedListName()
        recognizeText(from: image)
    }

    private func recognizeText(from image: UIImage) {
        guard let cgImage = image.cgImage else {
            importMessage = "Das Bild konnte nicht gelesen werden."
            return
        }

        isRecognizingImage = true
        importMessage = "Text wird erkannt..."

        let request = VNRecognizeTextRequest { request, error in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let lineBoxes = observations.compactMap { observation -> OCRLineBox? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = sanitizedLine(candidate.string)
                guard !text.isEmpty else { return nil }
                return OCRLineBox(text: text, boundingBox: observation.boundingBox)
            }

            DispatchQueue.main.async {
                isRecognizingImage = false

                if error != nil {
                    importMessage = "Der Text konnte aus dem Foto nicht erkannt werden."
                    return
                }

                let filteredBoxes = filteredVocabularyBoxes(from: lineBoxes)
                let boxesForImport = filteredBoxes.count >= 2 ? filteredBoxes : lineBoxes
                let pairedLines = makeColumnPairs(from: boxesForImport)
                let cleanedText: String

                if !pairedLines.isEmpty {
                    cleanedText = pairedLines
                        .map { "\($0.0) = \($0.1)" }
                        .joined(separator: "\n")
                } else {
                    cleanedText = boxesForImport
                        .sorted { lhs, rhs in
                            if abs(lhs.midY - rhs.midY) > 0.018 {
                                return lhs.midY > rhs.midY
                            }
                            return lhs.minX < rhs.minX
                        }
                        .map(\.text)
                        .joined(separator: "\n")
                }

                importText = cleanedText
                let detectedCount = parsePreviewPairs(from: cleanedText).count

                if detectedCount > 0 {
                    if !pairedLines.isEmpty {
                        importMessage = "\(detectedCount) Paare aus linker und rechter Spalte erkannt. Prüfe kurz und tippe dann auf „Importieren“."
                    } else {
                        importMessage = "\(detectedCount) Paare erkannt. Prüfe kurz und tippe dann auf „Importieren“."
                    }
                } else if cleanedText.isEmpty {
                    importMessage = "Kein lesbarer Text im Foto gefunden."
                } else {
                    importMessage = "Text erkannt. Falls nötig, kurz im Feld anpassen und dann importieren."
                }
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["fr-FR", "de-DE", "en-US"]

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    isRecognizingImage = false
                    importMessage = "Der Text konnte aus dem Foto nicht erkannt werden."
                }
            }
        }
    }

    private func sanitizedLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*[\d\.\-\)\(]+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[•·]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filteredVocabularyBoxes(from boxes: [OCRLineBox]) -> [OCRLineBox] {
        boxes.filter { box in
            let text = box.text.lowercased()
            let hasLetters = text.rangeOfCharacter(from: .letters) != nil
            guard hasLetters else { return false }

            if text.contains("www.") || text.contains("http") || text.contains(".de") || text.contains(".fr") || text.contains(".com") {
                return false
            }

            if text.range(of: #"^(seite|page)\s*\d+$"#, options: .regularExpression) != nil {
                return false
            }

            if text.range(of: #"^\d+([\/\-]\d+)?$"#, options: .regularExpression) != nil {
                return false
            }

            let wordCount = normalizedWords(in: text).count
            if box.width > 0.62 && (box.midY > 0.9 || box.midY < 0.1) {
                return false
            }

            if box.width > 0.55 && wordCount >= 4 && (box.midY > 0.84 || box.midY < 0.14) {
                return false
            }

            return true
        }
    }

    private func makeColumnPairs(from boxes: [OCRLineBox]) -> [(String, String)] {
        guard boxes.count >= 2 else { return [] }

        let columns = columnGroups(for: boxes)
        guard columns.count >= 2 else { return [] }

        var pairs: [(String, String, CGFloat)] = []
        var columnIndex = 0

        while columnIndex + 1 < columns.count {
            let leftRows = mergeBoxesIntoRows(columns[columnIndex])
            let rightRows = mergeBoxesIntoRows(columns[columnIndex + 1])
            pairs.append(contentsOf: matchedPairs(leftRows: leftRows, rightRows: rightRows))
            columnIndex += 2
        }

        return pairs
            .sorted { $0.2 > $1.2 }
            .map { ($0.0, $0.1) }
    }

    private func columnGroups(for boxes: [OCRLineBox]) -> [[OCRLineBox]] {
        let sortedBoxes = boxes.sorted { $0.midX < $1.midX }
        let averageWidth = sortedBoxes.map(\.width).reduce(0, +) / CGFloat(sortedBoxes.count)
        let threshold = max(averageWidth * 1.35, 0.14)

        var groups: [[OCRLineBox]] = []

        for box in sortedBoxes {
            if let lastIndex = groups.indices.last {
                let currentGroup = groups[lastIndex]
                let currentCenter = currentGroup.map(\.midX).reduce(0, +) / CGFloat(currentGroup.count)
                if abs(box.midX - currentCenter) <= threshold {
                    groups[lastIndex].append(box)
                } else {
                    groups.append([box])
                }
            } else {
                groups.append([box])
            }
        }

        return groups
            .filter { !$0.isEmpty }
            .sorted {
                ($0.map(\.midX).reduce(0, +) / CGFloat($0.count)) < ($1.map(\.midX).reduce(0, +) / CGFloat($1.count))
            }
    }

    private func matchedPairs(leftRows: [OCRLineBox], rightRows: [OCRLineBox]) -> [(String, String, CGFloat)] {
        guard !leftRows.isEmpty, !rightRows.isEmpty else { return [] }

        let averageHeight = (leftRows + rightRows).map(\.height).reduce(0, +) / CGFloat(leftRows.count + rightRows.count)
        let verticalTolerance = max(averageHeight * 1.6, 0.03)
        var unmatchedRights = rightRows
        var pairs: [(String, String, CGFloat)] = []

        for leftRow in leftRows.sorted(by: { $0.midY > $1.midY }) {
            guard let bestIndex = unmatchedRights.indices.min(by: {
                abs(unmatchedRights[$0].midY - leftRow.midY) < abs(unmatchedRights[$1].midY - leftRow.midY)
            }) else { continue }

            let rightRow = unmatchedRights[bestIndex]
            let distance = abs(rightRow.midY - leftRow.midY)
            guard distance <= verticalTolerance else { continue }

            pairs.append((leftRow.text, rightRow.text, max(leftRow.midY, rightRow.midY)))
            unmatchedRights.remove(at: bestIndex)
        }

        return pairs
    }

    private func mergeBoxesIntoRows(_ boxes: [OCRLineBox]) -> [OCRLineBox] {
        let sortedBoxes = boxes.sorted {
            if abs($0.midY - $1.midY) > 0.018 {
                return $0.midY > $1.midY
            }
            return $0.minX < $1.minX
        }

        var rows: [OCRLineBox] = []

        for box in sortedBoxes {
            if let last = rows.last {
                let tolerance = max(last.height, box.height) * 0.7
                if abs(last.midY - box.midY) <= tolerance {
                    let combinedText = [last.text, box.text]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    let combinedRect = last.boundingBox.union(box.boundingBox)
                    rows[rows.count - 1] = OCRLineBox(text: combinedText, boundingBox: combinedRect)
                    continue
                }
            }

            rows.append(box)
        }

        return rows
    }

    private func makePreviewPair(first: String, second: String) -> ImportPreviewPair? {
        let left = sanitizedLine(first)
        let right = sanitizedLine(second)
        guard !left.isEmpty, !right.isEmpty else { return nil }

        switch columnOrder {
        case .autoDetect:
            switch detectColumnOrder(first: left, second: right) {
            case .frenchFirst:
                return ImportPreviewPair(french: left, german: right)
            case .germanFirst:
                return ImportPreviewPair(french: right, german: left)
            case .autoDetect:
                return ImportPreviewPair(french: left, german: right)
            }
        case .frenchFirst:
            return ImportPreviewPair(french: left, german: right)
        case .germanFirst:
            return ImportPreviewPair(french: right, german: left)
        }
    }

    private func makeIncompletePreviewPair(from line: String) -> ImportPreviewPair {
        let cleanedLine = sanitizedLine(line)

        switch columnOrder {
        case .germanFirst:
            return ImportPreviewPair(french: "", german: cleanedLine)
        case .autoDetect, .frenchFirst:
            return ImportPreviewPair(french: cleanedLine, german: "")
        }
    }

    private func makeVocabularyItem(french: String, german: String) -> VocabularyItem? {
        let normalizedFrench = sanitizedLine(french)
        let normalizedGerman = sanitizedLine(german)
        guard !normalizedFrench.isEmpty, !normalizedGerman.isEmpty else { return nil }

        return VocabularyItem(
            french: normalizedFrench,
            german: normalizedGerman,
            cardType: importType
        )
    }

    private func detectColumnOrder(first: String, second: String) -> ImportColumnOrder {
        let firstFrenchScore = frenchScore(for: first)
        let firstGermanScore = germanScore(for: first)
        let secondFrenchScore = frenchScore(for: second)
        let secondGermanScore = germanScore(for: second)

        let frenchFirstScore = firstFrenchScore + secondGermanScore
        let germanFirstScore = firstGermanScore + secondFrenchScore

        if frenchFirstScore == germanFirstScore {
            return .frenchFirst
        }

        return frenchFirstScore > germanFirstScore ? .frenchFirst : .germanFirst
    }

    private func frenchScore(for text: String) -> Double {
        languageScore(for: text, language: .french) + heuristicFrenchScore(for: text)
    }

    private func germanScore(for text: String) -> Double {
        languageScore(for: text, language: .german) + heuristicGermanScore(for: text)
    }

    private func languageScore(for text: String, language: NLLanguage) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text.lowercased())
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        return hypotheses[language] ?? 0
    }

    private func heuristicFrenchScore(for text: String) -> Double {
        let normalizedWords = normalizedWords(in: text)
        let joined = normalizedWords.joined(separator: " ")

        var score = 0.0

        let frenchMarkers = [
            "je", "tu", "il", "elle", "nous", "vous", "ils", "elles",
            "bonjour", "merci", "oui", "non", "avec", "pour", "dans",
            "est", "suis", "avoir", "etre", "être", "une", "des", "les",
            "un", "du", "de", "la", "le", "au", "aux", "pas", "que"
        ]

        for marker in frenchMarkers where normalizedWords.contains(marker) {
            score += 0.55
        }

        if joined.contains("j ") || joined.contains("qu ") || joined.contains("c ") {
            score += 0.35
        }

        if text.range(of: "[àâçéèêëîïôùûüÿœæ]", options: .regularExpression) != nil {
            score += 1.1
        }

        return score
    }

    private func heuristicGermanScore(for text: String) -> Double {
        let normalizedWords = normalizedWords(in: text)
        let joined = normalizedWords.joined(separator: " ")

        var score = 0.0

        let germanMarkers = [
            "ich", "du", "er", "sie", "wir", "ihr", "danke", "bitte",
            "und", "mit", "für", "nicht", "ein", "eine", "der", "die",
            "das", "dem", "den", "ist", "bin", "habe", "haben", "gut",
            "heute", "morgen", "wo", "was", "wie"
        ]

        for marker in germanMarkers where normalizedWords.contains(marker) {
            score += 0.55
        }

        if text.range(of: "[äöüß]", options: .regularExpression) != nil {
            score += 1.1
        }

        if joined.contains("sch") || joined.contains("ein ") || joined.contains("ich") {
            score += 0.3
        }

        return score
    }

    private func normalizedWords(in text: String) -> [String] {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func ensureSuggestedListName() {
        if listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            listName = listStore.suggestedListName(from: "Scan")
        }
    }

    private func refreshPreviewPairsFromImportText() {
        previewPairs = parsePreviewPairs(from: importText)
    }

    private func bindingValue(for id: UUID) -> ImportPreviewPair? {
        previewPairs.first(where: { $0.id == id })
    }

    private func updatePreviewPair(_ id: UUID, update: (inout ImportPreviewPair) -> Void) {
        guard let index = previewPairs.firstIndex(where: { $0.id == id }) else { return }
        update(&previewPairs[index])
    }

    private func syncImportTextFromPreview() {
        isSyncingPreviewToText = true
        importText = previewPairs
            .map { pair in
                let french = sanitizedLine(pair.french)
                let german = sanitizedLine(pair.german)

                if !french.isEmpty && !german.isEmpty {
                    return "\(french) = \(german)"
                }

                return !french.isEmpty ? french : german
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImagePicked: (UIImage?) -> Void

        init(onImagePicked: @escaping (UIImage?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
            onImagePicked(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onImagePicked(nil)
        }
    }
}

struct HomeActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct FlashcardStackVisual: View {
    let remainingCount: Int
    let totalCount: Int
    let caption: String

    private var remainingRatio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(remainingCount) / Double(totalCount)
    }

    private var visibleLayers: Int {
        if remainingCount <= 0 {
            return 1
        }
        return max(1, Int(ceil(remainingRatio * 6)))
    }

    private var frontColor: Color {
        if remainingCount <= 0 {
            return Color.green.opacity(0.18)
        }
        return Color.accentColor.opacity(0.16)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ForEach(0..<visibleLayers, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(index == 0 ? frontColor : Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(index == 0 ? 0.08 : 0.04), lineWidth: 1)
                        )
                        .frame(width: 134 - CGFloat(index * 7), height: 58 - CGFloat(index * 2))
                        .offset(y: CGFloat(index * 5))
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                }

                VStack(spacing: 2) {
                    Text("\(remainingCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(remainingCount == 1 ? "Karte" : "Karten")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .offset(y: 4)
            }
            .frame(height: 82)

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DataStore {
    static let flashcardDecks: [FlashcardDeck] = [
        FlashcardDeck(
            id: "flashcards-1",
            name: "Karteikarten 1",
            cards: flashcardsOne
        )
    ]

    static let defaultItems: [VocabularyItem] =
        beginnerWords
        + beginnerPhrases
        + intermediateWords
        + intermediatePhrases
        + advancedWords
        + advancedPhrases

    private static let beginnerWords = makeItems([
        "bonjour|guten tag",
        "merci|danke",
        "s il vous plaît|bitte",
        "oui|ja",
        "non|nein",
        "eau|wasser",
        "pain|brot",
        "lait|milch",
        "café|kaffee",
        "thé|tee",
        "pomme|apfel",
        "banane|banane",
        "fromage|käse",
        "maison|haus",
        "école|schule",
        "livre|buch",
        "ami|freund",
        "famille|familie",
        "ville|stadt",
        "gare|bahnhof",
        "voiture|auto",
        "rue|straße",
        "porte|tür",
        "fenêtre|fenster",
        "soleil|sonne",
        "lune|mond",
        "jour|tag",
        "nuit|nacht",
        "table|tisch",
        "chaise|stuhl",
        "chien|hund",
        "chat|katze",
        "argent|geld",
        "travail|arbeit",
        "musique|musik"
    ], type: .words, level: .beginner)

    private static let beginnerPhrases = makeItems([
        "Comment ça va ?|wie geht es dir",
        "Je m appelle Marie.|ich heiße marie",
        "Où est la gare ?|wo ist der bahnhof",
        "Je voudrais un café.|ich möchte einen kaffee",
        "Je ne comprends pas.|ich verstehe nicht",
        "Parlez plus lentement, s il vous plaît.|sprechen sie bitte langsamer",
        "Où sont les toilettes ?|wo ist die toilette",
        "J ai une réservation.|ich habe eine reservierung",
        "Je cherche mon hôtel.|ich suche mein hotel",
        "Pouvez vous m aider ?|können sie mir helfen",
        "J aime la musique.|ich mag musik",
        "À demain matin.|bis morgen früh",
        "Bon appétit !|guten appetit",
        "Excusez moi.|entschuldigen sie",
        "Quelle heure est il ?|wie spät ist es",
        "Je suis fatigué.|ich bin müde",
        "J ai faim.|ich habe hunger",
        "J ai soif.|ich habe durst",
        "C est très bien.|das ist sehr gut",
        "À bientôt.|bis bald",
        "Bienvenue chez nous.|willkommen bei uns",
        "Où habites tu ?|wo wohnst du",
        "Voici mon billet.|hier ist mein ticket",
        "Je suis prêt.|ich bin bereit",
        "Cela va bien.|es geht gut",
        "Je suis en retard.|ich bin zu spät",
        "Je suis perdu.|ich habe mich verlaufen",
        "C est parfait.|das ist perfekt",
        "Ouvrez la porte, s il vous plaît.|öffnen sie bitte die tür",
        "Fermez la fenêtre, s il vous plaît.|schließen sie bitte das fenster"
    ], type: .phrases, level: .beginner)

    private static let intermediateWords = makeItems([
        "marché|markt",
        "pharmacie|apotheke",
        "hôpital|krankenhaus",
        "aéroport|flughafen",
        "train|zug",
        "métro|u bahn",
        "billet|ticket",
        "valise|koffer",
        "plage|strand",
        "montagne|berg",
        "forêt|wald",
        "rivière|fluss",
        "journal|zeitung",
        "histoire|geschichte",
        "question|frage",
        "réponse|antwort",
        "voyage|reise",
        "vacances|urlaub",
        "bureau|büro",
        "ordinateur|computer",
        "téléphone|telefon",
        "réunion|meeting",
        "voisin|nachbar",
        "cuisine|küche",
        "déjeuner|mittagessen",
        "dîner|abendessen",
        "petit déjeuner|frühstück",
        "magasin|geschäft",
        "vitesse|geschwindigkeit",
        "météo|wetter",
        "printemps|frühling",
        "été|sommer",
        "automne|herbst",
        "hiver|winter",
        "problème|problem"
    ], type: .words, level: .intermediate)

    private static let intermediatePhrases = makeItems([
        "Je vais au marché.|ich gehe zum markt",
        "Puis je payer par carte ?|kann ich mit karte bezahlen",
        "Mon téléphone ne fonctionne plus.|mein telefon funktioniert nicht mehr",
        "Nous partons ce soir.|wir fahren heute abend los",
        "Il pleut depuis ce matin.|es regnet seit heute morgen",
        "Pouvez vous répéter la question ?|können sie die frage wiederholen",
        "Je prends le train à huit heures.|ich nehme den zug um acht uhr",
        "Nous visitons la ville demain.|wir besuchen morgen die stadt",
        "Je travaille au bureau aujourd hui.|ich arbeite heute im büro",
        "Il y a trop de bruit ici.|hier ist es zu laut",
        "Combien de temps faut il ?|wie lange dauert es",
        "J ai oublié mon billet.|ich habe mein ticket vergessen",
        "La pharmacie est elle ouverte ?|ist die apotheke geöffnet",
        "Je voudrais réserver une table.|ich möchte einen tisch reservieren",
        "Cette rue est très calme.|diese straße ist sehr ruhig",
        "Nous avons besoin d aide.|wir brauchen hilfe",
        "Le magasin ferme à six heures.|das geschäft schließt um sechs uhr",
        "Je cherche une pharmacie de garde.|ich suche eine notapotheke",
        "Le musée ouvre à dix heures.|das museum öffnet um zehn uhr",
        "Je dois appeler ma famille.|ich muss meine familie anrufen",
        "Nous restons trois nuits.|wir bleiben drei nächte",
        "Il fait meilleur qu hier.|das wetter ist besser als gestern",
        "Je voudrais changer de chambre.|ich möchte das zimmer wechseln",
        "Où puis je acheter un billet ?|wo kann ich ein ticket kaufen",
        "Mon ordinateur est trop lent.|mein computer ist zu langsam",
        "Je préfère voyager en train.|ich reise lieber mit dem zug",
        "Le voisin parle très fort.|der nachbar spricht sehr laut",
        "Je prépare le dîner ce soir.|ich bereite heute abend das abendessen vor",
        "Nous faisons une promenade en forêt.|wir machen einen spaziergang im wald",
        "La météo annonce du vent demain.|der wetterbericht meldet morgen wind"
    ], type: .phrases, level: .intermediate)

    private static let advancedWords = makeItems([
        "confiance|vertrauen",
        "réussite|erfolg",
        "connaissance|wissen",
        "décision|entscheidung",
        "développement|entwicklung",
        "entreprise|unternehmen",
        "environnement|umgebung",
        "habitude|gewohnheit",
        "expérience|erfahrung",
        "responsabilité|verantwortung",
        "liberté|freiheit",
        "avenir|zukunft",
        "mémoire|erinnerung",
        "sentiment|gefühl",
        "courage|mut",
        "richesse|reichtum",
        "pauvreté|armut",
        "discours|rede",
        "amélioration|verbesserung",
        "recherche|forschung",
        "résultat|ergebnis",
        "solution|lösung",
        "proposition|vorschlag",
        "contrat|vertrag",
        "entretien|gespräch",
        "candidature|bewerbung",
        "occasion|gelegenheit",
        "comportement|verhalten",
        "soutien|unterstützung",
        "défi|herausforderung",
        "qualité|qualität",
        "efficacité|effizienz",
        "précision|genauigkeit",
        "perspective|perspektive",
        "équilibre|balance"
    ], type: .words, level: .advanced)

    private static let advancedPhrases = makeItems([
        "Malgré le retard, nous sommes restés calmes.|trotz der verspätung sind wir ruhig geblieben",
        "J aimerais améliorer ma prononciation chaque jour.|ich möchte meine aussprache jeden tag verbessern",
        "Cette décision aura des conséquences importantes.|diese entscheidung wird wichtige folgen haben",
        "Il faut trouver une solution durable.|wir müssen eine dauerhafte lösung finden",
        "Je préfère réfléchir avant de répondre.|ich denke lieber nach bevor ich antworte",
        "Nous avons discuté du projet pendant une heure.|wir haben eine stunde über das projekt gesprochen",
        "Il manque encore quelques détails essentiels.|es fehlen noch einige wichtige details",
        "Je n étais pas d accord au début.|ich war am anfang nicht einverstanden",
        "Cette expérience m a beaucoup appris.|diese erfahrung hat mir viel beigebracht",
        "Pouvez vous résumer les points principaux ?|können sie die wichtigsten punkte zusammenfassen",
        "Je me sens plus à l aise en français.|ich fühle mich auf französisch sicherer",
        "Il serait utile de pratiquer plus souvent.|es wäre sinnvoll öfter zu üben",
        "Cette proposition semble intéressante.|dieser vorschlag wirkt interessant",
        "Nous devons respecter la date limite.|wir müssen die frist einhalten",
        "Je n ai pas encore pris ma décision.|ich habe meine entscheidung noch nicht getroffen",
        "Son discours était clair et convaincant.|seine rede war klar und überzeugend",
        "J essaie de garder un bon équilibre.|ich versuche eine gute balance zu halten",
        "Il vaut mieux prévenir que guérir.|vorsicht ist besser als nachsicht",
        "Cette tâche demande beaucoup de précision.|diese aufgabe verlangt viel genauigkeit",
        "Nous avons besoin d une réponse rapide.|wir brauchen eine schnelle antwort",
        "Je voudrais approfondir ce sujet.|ich möchte dieses thema vertiefen",
        "Les résultats sont meilleurs que prévu.|die ergebnisse sind besser als erwartet",
        "Il faut tenir compte du contexte.|man muss den kontext berücksichtigen",
        "Cette habitude m aide à progresser.|diese gewohnheit hilft mir beim fortschritt",
        "Je cherche un environnement plus calme.|ich suche eine ruhigere umgebung",
        "Nous avons finalement trouvé un compromis.|wir haben am ende einen kompromiss gefunden",
        "La qualité de ce travail est remarquable.|die qualität dieser arbeit ist bemerkenswert",
        "Je manque parfois de confiance en moi.|mir fehlt manchmal das selbstvertrauen",
        "Son comportement a changé récemment.|sein verhalten hat sich kürzlich verändert",
        "Cette candidature mérite une réponse rapide.|diese bewerbung verdient eine schnelle antwort",
        "Il faut analyser la situation avec précision.|wir müssen die situation genau analysieren",
        "Ce défi demande beaucoup d énergie.|diese herausforderung braucht viel energie",
        "Le soutien de l équipe était précieux.|die unterstützung des teams war wertvoll",
        "J ai besoin de prendre un peu de recul.|ich muss etwas abstand gewinnen",
        "Cette perspective me semble plus réaliste.|diese perspektive erscheint mir realistischer"
    ], type: .phrases, level: .advanced)

    private static let flashcardsOne = makeFlashcardDeckCards(idPrefix: "fc1", pairs: [
        "bonjour|guten tag",
        "merci|danke",
        "s il vous plaît|bitte",
        "au revoir|auf wiedersehen",
        "eau|wasser",
        "pain|brot",
        "fromage|käse",
        "gare|bahnhof",
        "voiture|auto",
        "hôtel|hotel",
        "famille|familie",
        "ami|freund",
        "jour|tag",
        "nuit|nacht",
        "soleil|sonne",
        "lune|mond",
        "école|schule",
        "travail|arbeit",
        "argent|geld",
        "musique|musik",
        "maison|haus",
        "livre|buch",
        "ville|stadt",
        "rue|straße",
        "porte|tür",
        "fenêtre|fenster",
        "chien|hund",
        "chat|katze",
        "café|kaffee",
        "thé|tee",
        "Comment ça va ?|wie geht es dir",
        "Je m appelle Marie.|ich heiße marie",
        "Où est la gare ?|wo ist der bahnhof",
        "Je voudrais un café.|ich möchte einen kaffee",
        "Combien ça coûte ?|wie viel kostet das",
        "Je ne comprends pas.|ich verstehe nicht",
        "Parlez plus lentement, s il vous plaît.|sprechen sie bitte langsamer",
        "Où sont les toilettes ?|wo ist die toilette",
        "J ai une réservation.|ich habe eine reservierung",
        "Je cherche mon hôtel.|ich suche mein hotel",
        "Pouvez vous m aider ?|können sie mir helfen",
        "Je suis allemand.|ich bin deutscher",
        "J aime la musique.|ich mag musik",
        "Nous partons demain.|wir fahren morgen los",
        "Il fait très chaud aujourd hui.|heute ist es sehr heiß",
        "Je prends le métro.|ich nehme die u bahn",
        "Nous avons faim.|wir haben hunger",
        "La table est prête.|der tisch ist fertig",
        "Je voudrais payer.|ich möchte bezahlen",
        "À demain matin.|bis morgen früh"
    ])

    private static func makeItems(_ pairs: [String], type: CardType, level: VocabularyLevel) -> [VocabularyItem] {
        pairs.compactMap { line in
            let values = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard values.count == 2 else { return nil }
            return VocabularyItem(
                french: values[0],
                german: values[1],
                cardType: type,
                level: level
            )
        }
    }

    private static func makeFlashcardDeckCards(idPrefix: String, pairs: [String]) -> [FlashcardDeckCard] {
        pairs.enumerated().compactMap { index, line in
            let values = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard values.count == 2 else { return nil }
            return FlashcardDeckCard(
                id: "\(idPrefix)-\(String(format: "%03d", index + 1))",
                french: values[0],
                german: values[1]
            )
        }
    }
}
