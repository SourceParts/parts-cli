import Foundation
import Speech
import AVFoundation

/// Voice recognition service for Parts Studio.
/// Supports two modes:
///   1. Direct command mode — spoken words map 1:1 to console commands
///   2. Natural language mode — activated by "hey parts" wake word
@MainActor
class VoiceService: ObservableObject {
    @Published var isListening = false
    @Published var isAvailable = false
    @Published var lastTranscription = ""
    @Published var mode: VoiceMode = .direct

    enum VoiceMode: String, CaseIterable {
        case direct = "Direct"
        case natural = "Natural"
    }

    var onCommand: ((String) -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var wakeWordDetected = false
    private var silenceTimer: Timer?

    init() {
        checkAvailability()
    }

    // MARK: - Availability

    private func checkAvailability() {
        guard let recognizer = speechRecognizer else {
            isAvailable = false
            return
        }
        isAvailable = recognizer.isAvailable
    }

    // MARK: - Permission

    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self.requestMicrophoneAccess(completion: completion)
                default:
                    completion(false)
                }
            }
        }
    }

    private func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    // MARK: - Start / Stop

    func startListening() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            return
        }

        requestPermission { [weak self] granted in
            guard granted else { return }
            self?.beginRecognition()
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        isListening = false
        wakeWordDetected = false
    }

    // MARK: - Recognition

    private func beginRecognition() {
        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false

        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            stopListening()
            return
        }

        guard let recognizer = speechRecognizer else { return }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                self.lastTranscription = text
                self.resetSilenceTimer()

                if result.isFinal {
                    self.processTranscription(text)
                }
            }

            if error != nil {
                // Restart recognition on error (timeout, etc.)
                self.stopListening()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.isListening { self.startListening() }
                }
            }
        }
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let text = self.lastTranscription
            if !text.isEmpty {
                self.processTranscription(text)
                self.lastTranscription = ""
                // Restart recognition for next utterance
                self.restartRecognition()
            }
        }
    }

    private func restartRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        wakeWordDetected = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.beginRecognition()
        }
    }

    // MARK: - Command Processing

    private func processTranscription(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch mode {
        case .direct:
            // Direct mode: map spoken text to console command
            let command = mapToCommand(trimmed)
            if let command = command {
                onCommand?(command)
            }

        case .natural:
            // Natural mode: wait for "hey parts" wake word
            if trimmed.contains("hey parts") || trimmed.contains("a parts") || trimmed.contains("hey park") {
                if let range = trimmed.range(of: "hey parts") ?? trimmed.range(of: "a parts") ?? trimmed.range(of: "hey park") {
                    let afterWake = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !afterWake.isEmpty {
                        interpretNaturalLanguage(afterWake)
                    } else {
                        wakeWordDetected = true
                    }
                }
            } else if wakeWordDetected {
                interpretNaturalLanguage(trimmed)
                wakeWordDetected = false
            }
        }
    }

    // MARK: - Direct Command Mapping

    /// Map spoken words to console commands. Handles common voice quirks.
    private func mapToCommand(_ spoken: String) -> String? {
        let words = spoken.lowercased()

        // Exact matches for simple commands
        let directCommands = [
            "help", "status", "info", "stop", "clear",
            "gps", "gps raw", "gps stop",
            "rack", "rack reset", "lora",
        ]

        for cmd in directCommands {
            if words == cmd || words == cmd.replacingOccurrences(of: "rack", with: "rak") {
                return cmd.replacingOccurrences(of: "rack", with: "rak")
            }
        }

        // Pattern matches
        if words.hasPrefix("read ") { return words }
        if words.hasPrefix("gpio ") { return words }
        if words.hasPrefix("rack ") || words.hasPrefix("rak ") {
            return words.replacingOccurrences(of: "rack", with: "rak")
        }
        if words.hasPrefix("backlight ") { return words }
        if words == "boot" { return "boot" }
        if words == "scratch" { return "scratch" }
        if words.contains("gps") && words.contains("stop") { return "gps stop" }
        if words.contains("gps") && words.contains("raw") { return "gps raw" }
        if words.contains("gps") || words.contains("location") { return "gps" }

        return words // pass through as-is
    }

    // MARK: - Natural Language via ML Service

    /// Ollama URL for local LLM inference (llama3.1:8b).
    /// Falls back to the ml-service NLP endpoint if Ollama isn't running.
    var ollamaURL = "http://127.0.0.1:11434"
    var mlServiceURL = "http://127.0.0.1:8000"

    /// Send natural language to Ollama (llama3.1:8b) or ml-service for command interpretation.
    private func interpretNaturalLanguage(_ spoken: String) {
        let systemPrompt = """
        You are Parts Studio, a hardware control console. Convert the user's voice command \
        into exactly one console command. Available commands:
        help, status, info, gps, gps raw, gps stop, rak, rak reset, rak join, rak send <hex>, \
        swd scan, swd stop, swd status, boot, stop, read <addr> [len], gpio <port>, \
        backlight <0-255>, dump brom, voice stop, clear.
        Respond with ONLY the command, nothing else.
        """

        // Try Ollama first (local, fast)
        let ollamaBody: [String: Any] = [
            "model": "llama3.1:8b",
            "prompt": "User said: \"\(spoken)\"\nCommand:",
            "system": systemPrompt,
            "stream": false,
            "options": ["temperature": 0.1, "num_predict": 50],
        ]

        guard let url = URL(string: "\(ollamaURL)/api/generate"),
              let jsonData = try? JSONSerialization.data(withJSONObject: ollamaBody) else {
            onCommand?(interpretLocal(spoken))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["response"] as? String {
                    let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: "\n").first ?? spoken
                    self?.onCommand?(command)
                    return
                }
                // Ollama unavailable — try ml-service NLP endpoint
                self?.tryMLService(spoken)
            }
        }.resume()
    }

    /// Fallback: try the ml-service NLP query endpoint.
    private func tryMLService(_ spoken: String) {
        let body: [String: Any] = [
            "query": "Convert to Parts Studio command: \(spoken)",
        ]

        guard let url = URL(string: "\(mlServiceURL)/api/nlp/query"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            onCommand?(interpretLocal(spoken))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 3

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let resp = json["response"] as? [String: Any],
                   let analysis = resp["analysis"] as? String {
                    self?.onCommand?(analysis)
                    return
                }
                // All services unavailable — local fallback
                self?.onCommand?(self?.interpretLocal(spoken) ?? spoken)
            }
        }.resume()
    }

    /// Local fallback when ML service is unavailable.
    private func interpretLocal(_ spoken: String) -> String {
        let text = spoken.lowercased()
        if text.contains("gps") && text.contains("stop") { return "gps stop" }
        if text.contains("gps") && text.contains("raw") { return "gps raw" }
        if text.contains("gps") || text.contains("location") || text.contains("satellite") { return "gps" }
        if text.contains("reset") && (text.contains("lora") || text.contains("rak")) { return "rak reset" }
        if text.contains("lora") || text.contains("rak") { return "rak" }
        if text.contains("stop") { return "stop" }
        if text.contains("status") { return "status" }
        if text.contains("help") { return "help" }
        if text.contains("boot") { return "boot" }
        return text
    }
}
