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
            // Natural mode: wait for wake word (with common misrecognition variants)
            let wakeVariants = [
                "hey parts studio",
                "hey parts",
                "hey parks",
                "hey park",
                "pay parts",
                "a parts",
                "parts",
            ]
            let lower = trimmed.lowercased()
            var matchedRange: Range<String.Index>? = nil
            for variant in wakeVariants {
                if let range = lower.range(of: variant) {
                    matchedRange = range
                    break
                }
            }

            if let range = matchedRange {
                let afterWake = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !afterWake.isEmpty {
                    interpretNaturalLanguage(afterWake)
                } else {
                    wakeWordDetected = true
                }
            } else if wakeWordDetected {
                interpretNaturalLanguage(trimmed)
                wakeWordDetected = false
            }
        }
    }

    // MARK: - Direct Command Mapping

    /// Map spoken words to console commands. Handles common voice quirks and numeric arguments.
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

        // Pattern matches with numeric argument extraction
        // "read address 0x1000" or "read address 1000" -> "read 0x1000"
        if words.hasPrefix("read ") {
            return extractCommandWithArgs("read", from: words, stripWords: ["address", "at", "from", "offset", "memory"])
        }
        if words.hasPrefix("gpio ") {
            return extractCommandWithArgs("gpio", from: words, stripWords: ["port", "pin", "number"])
        }
        if words.hasPrefix("rack ") || words.hasPrefix("rak ") {
            return extractCommandWithArgs("rak", from: words.replacingOccurrences(of: "rack", with: "rak"), stripWords: [])
        }
        // "backlight 128" or "backlight level 128" or "backlight to 200" -> "backlight 128"
        if words.hasPrefix("backlight ") {
            return extractCommandWithArgs("backlight", from: words, stripWords: ["level", "to", "set", "value", "brightness"])
        }
        // "dump brom" / "dump b rom" (voice quirk)
        if words.contains("dump") && (words.contains("brom") || words.contains("b rom")) {
            return "dump brom"
        }
        if words == "boot" { return "boot" }
        if words == "scratch" { return "scratch" }
        if words.contains("gps") && words.contains("stop") { return "gps stop" }
        if words.contains("gps") && words.contains("raw") { return "gps raw" }
        if words.contains("gps") || words.contains("location") { return "gps" }

        return words // pass through as-is
    }

    /// Extract a command and its arguments, stripping filler words that speech recognition may insert.
    /// E.g. "read address 0x1000 64" with stripWords=["address","at"] -> "read 0x1000 64"
    private func extractCommandWithArgs(_ command: String, from spoken: String, stripWords: [String]) -> String {
        let tokens = spoken.split(separator: " ").map(String.init)
        guard tokens.count > 1 else { return command }

        var args: [String] = []
        for token in tokens.dropFirst() {
            let lower = token.lowercased()
            // Skip filler words
            if stripWords.contains(lower) { continue }
            // Convert spoken numbers: "one thousand" won't appear (speech-to-text gives digits)
            // but handle "hex" prefix: "hex 1000" -> "0x1000"
            if lower == "hex" || lower == "0x" { continue }  // next token gets 0x prefix below
            // If previous arg was "hex", prefix this with 0x
            if let prev = args.last, (prev == "hex" || prev == "0x") {
                args.removeLast()
                args.append("0x\(token)")
            } else {
                args.append(token)
            }
        }

        return ([command] + args).joined(separator: " ")
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
