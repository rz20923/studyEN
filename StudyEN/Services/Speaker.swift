import AVFoundation

/// 系统 TTS 朗读，用于听原声、跟读
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    /// 每次朗读用新的合成器：被录音打断过的合成器偶尔会卡住不出声
    private var synth = AVSpeechSynthesizer()
    private var onDone: (() -> Void)?

    /// onDone：完整读完时回调（被打断不回调）
    func speak(_ text: String, slow: Bool = false, onDone: (() -> Void)? = nil) {
        AudioSessionConfig.activate()
        self.onDone = nil
        synth.stopSpeaking(at: .immediate)
        synth = AVSpeechSynthesizer()
        synth.delegate = self
        self.onDone = onDone
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = slow ? 0.38 : AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    func stop() {
        onDone = nil
        synth.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, synthesizer === self.synth, let done = self.onDone else { return }
            self.onDone = nil
            done()
        }
    }
}

/// 朗读和录音共用同一个音频会话配置，避免来回切换导致的卡顿
enum AudioSessionConfig {
    @discardableResult
    static func activate() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            // allowBluetoothA2DP：连着蓝牙耳机时朗读走耳机；defaultToSpeaker 只在没接耳机时生效
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers])
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }
}
