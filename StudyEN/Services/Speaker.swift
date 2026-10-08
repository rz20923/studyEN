import AVFoundation

/// 系统 TTS 朗读，用于听原声、跟读
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String, slow: Bool = false) {
        AudioSessionConfig.activate()
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = slow ? 0.38 : AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}

/// 朗读和录音共用同一个音频会话配置，避免来回切换导致的卡顿
enum AudioSessionConfig {
    @discardableResult
    static func activate() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }
}
