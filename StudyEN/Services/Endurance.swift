import AVFoundation
import Observation
import Speech

// MARK: - 规则

/// 耐力训练：每天一个生活话题，连续开口。目标时长从第 1 天 10 秒逐步加到第 180 天 5 分钟。
enum Endurance {
    /// 第 day 个达标日的目标开口秒数（取整到 5 秒）
    static func target(day: Int) -> Double {
        let d = Double(min(max(day, 1), Plan.totalDays))
        let t = 10 + 290 * pow((d - 1) / Double(Plan.totalDays - 1), 1.3)
        return (t / 5).rounded() * 5
    }

    /// 第 1 天和之后每 30 天：固定题目的里程碑录音，用来前后对比
    static func isMilestone(day: Int) -> Bool { day == 1 || day % 30 == 0 }

    /// 高于这个音量算在说话（dB）。测试期按实际情况调
    static let voiceThresholdDB: Float = -42
    /// 停顿超过这个秒数记一次卡壳
    static let pauseSeconds: Double = 3
    /// 停顿超过这个秒数自动结束这一组
    static let stopSilenceSeconds: Double = 8

    static func topic(day: Int) -> EnduranceTopic {
        isMilestone(day: day) ? milestoneTopic : topics[(max(day, 1) - 1) % topics.count]
    }

    static let milestoneTopic = EnduranceTopic(
        zh: "自我介绍：你叫什么、做什么工作、住在哪、平时喜欢做什么",
        starters: ["Hi, I'm…", "I work as… / I'm a…", "I live in…", "In my free time, I like to…"]
    )

    /// 生活话题：由近及远、由简单到复杂
    static let topics: [EnduranceTopic] = [
        .init(zh: "说说你今天早上从起床到出门都做了什么", starters: ["I woke up at…", "Then I…", "After that…"]),
        .init(zh: "介绍你住的地方：城市、房子、周围有什么", starters: ["I live in…", "There's a … near my place", "I like it because…"]),
        .init(zh: "你的工作或学习是做什么的？每天大概怎么过", starters: ["I work as…", "Every day I…", "The best part is…"]),
        .init(zh: "说说你昨天晚上吃了什么", starters: ["Last night I had…", "It was…", "I usually…"]),
        .init(zh: "你周末一般怎么过", starters: ["On weekends I usually…", "Sometimes I…", "Last weekend I…"]),
        .init(zh: "介绍一个你的好朋友", starters: ["My friend … is…", "We met…", "We usually…"]),
        .init(zh: "最近一件让你烦的事", starters: ["The thing is…", "It drives me crazy when…", "In the end…"]),
        .init(zh: "你怎么去上班或上学，路上做什么", starters: ["I go to work by…", "It takes about…", "On the way I…"]),
        .init(zh: "你最喜欢的一家餐厅或一种小吃", starters: ["My favorite place is…", "They have…", "You should try…"]),
        .init(zh: "你最近在看的剧或电影", starters: ["I've been watching…", "It's about…", "I like it because…"]),
        .init(zh: "描述你现在所在的房间，你看到了什么", starters: ["Right now I'm in…", "There's a…", "Next to it…"]),
        .init(zh: "说说你的爱好，是怎么开始的", starters: ["I'm really into…", "I started when…", "It helps me…"]),
        .init(zh: "最近一次出去玩或旅行的经历", starters: ["Last time I went to…", "We…", "The best part was…"]),
        .init(zh: "你今天接下来的计划", starters: ["Today I'm gonna…", "First…", "Later I might…"]),
        .init(zh: "讲一件你最近遇到的趣事", starters: ["So get this…", "All of a sudden…", "It turns out…"]),
        .init(zh: "介绍你的家人", starters: ["There are … people in my family", "My mom…", "We usually…"]),
        .init(zh: "你小时候最喜欢做什么", starters: ["When I was a kid, I used to…", "I remember…", "Now I…"]),
        .init(zh: "你平时怎么购物：网上还是线下", starters: ["I usually shop…", "Last time I bought…", "I always shop around…"]),
        .init(zh: "你怎么放松、怎么解压", starters: ["When I'm stressed out, I…", "It helps me chill out", "Sometimes I…"]),
        .init(zh: "介绍你的家乡", starters: ["I'm from…", "It's famous for…", "If you go there, you should…"]),
        .init(zh: "你最近学到的一样新东西", starters: ["I recently learned…", "At first…", "Now I can…"]),
        .init(zh: "描述你理想中的周末", starters: ["My perfect weekend would be…", "I'd sleep in…", "Then I'd…"]),
        .init(zh: "你最近买的一样东西，值不值", starters: ["I just bought…", "It was…", "To be honest…"]),
        .init(zh: "说说你的运动习惯", starters: ["I work out…", "I try to…", "I should…"]),
        .init(zh: "你遇到过最尴尬的一件事", starters: ["You won't believe this…", "I totally messed up…", "Now I laugh about it"]),
        .init(zh: "你手机里最常用的三个 App", starters: ["I use … every day", "I mostly use it to…", "I can't live without…"]),
        .init(zh: "你最近一次生病或特别累是什么情况", starters: ["I came down with…", "I felt…", "It took me a while to get over it"]),
        .init(zh: "你未来一年想做的三件事", starters: ["This year I want to…", "I'm planning to…", "I'm also thinking about…"]),
        .init(zh: "给外国朋友推荐你所在城市值得去的地方", starters: ["You should definitely check out…", "It's great for…", "Don't miss…"]),
        .init(zh: "说说你和同事或同学之间的一件事", starters: ["One of my coworkers…", "We get along…", "The other day…"]),
        .init(zh: "你喜欢什么样的天气，为什么", starters: ["I prefer…", "When it's…, I…", "I can't stand…"]),
        .init(zh: "你做过最好的一个决定", starters: ["The best decision I made was…", "At first I…", "It turned out…"]),
        .init(zh: "描述一顿难忘的饭", starters: ["I'll never forget…", "We had…", "It was so good that…"]),
        .init(zh: "如果有一个月的假期，你会做什么", starters: ["If I had a month off, I'd…", "First I'd…", "I'd also…"]),
        .init(zh: "说说你最近的心情和原因", starters: ["I've been feeling…", "Mostly because…", "I guess…"]),
        .init(zh: "你怎么看在家工作", starters: ["Personally, I think…", "The good thing is…", "The bad thing is…"]),
        .init(zh: "你最近一次和朋友聚会做了什么", starters: ["Last time we got together, we…", "We ended up…", "It was…"]),
        .init(zh: "你学英语的原因和最大的困难", starters: ["I'm learning English because…", "The hardest part is…", "I'm trying to…"]),
        .init(zh: "描述一个你常去的地方", starters: ["I often go to…", "It's a … place", "I like to … there"]),
        .init(zh: "说一个你想改掉的习惯", starters: ["I'm trying to cut down on…", "I used to…", "Now I…"]),
    ]

    /// 卡壳本：用中文关键词在语块库里找现成说法（不需要大模型）
    static func matches(for text: String, in chunks: [Chunk]) -> [Chunk] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: "；;，,、（）()…/ ")
        return Array(chunks.filter { chunk in
            let keys = chunk.meaning.components(separatedBy: separators).filter { $0.count >= 2 }
            return keys.contains { q.contains($0) } || chunk.phrase.lowercased().contains(q.lowercased())
        }.prefix(5))
    }

    static func secondsText(_ s: Double) -> String {
        let total = Int(s.rounded())
        return total < 60 ? "\(total) 秒" : "\(total / 60) 分 \(total % 60) 秒"
    }
}

struct EnduranceTopic: Hashable {
    let zh: String
    let starters: [String]
}

// MARK: - 录音存放

enum RecordingStore {
    static var directory: URL {
        let dir = URL.documentsDirectory.appending(path: "recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(_ name: String) -> URL { directory.appending(path: name) }
}

// MARK: - 连续开口录音：统计有效开口时长、卡壳次数，同时转写

@Observable
final class EnduranceRecorder {
    private(set) var isRecording = false
    /// 有效开口时长：说话 + 3 秒以内的正常换气停顿
    private(set) var speakingSeconds: Double = 0
    private(set) var pauses = 0
    private(set) var silence: Double = 0
    private(set) var level: Float = 0
    private(set) var transcript = ""
    private(set) var hasSpoken = false

    /// 停顿太久自动结束时回调
    @ObservationIgnored var onAutoStop: (() -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func start(to url: URL) -> Bool {
        stop()
        speakingSeconds = 0
        pauses = 0
        silence = 0
        level = 0
        transcript = ""
        hasSpoken = false
        guard AudioSessionConfig.activate() else { return false }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let file = try? AVAudioFile(forWriting: url, settings: settings) else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if let recognizer, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        if let recognizer, recognizer.isAvailable {
            task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
                guard let text = result?.bestTranscription.formattedString else { return }
                DispatchQueue.main.async { self?.transcript = text }
            }
        }

        let sampleRate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            try? file.write(from: buffer)
            request.append(buffer)
            let db = Self.decibels(buffer)
            let duration = Double(buffer.frameLength) / sampleRate
            DispatchQueue.main.async { self?.process(db: db, duration: duration) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        isRecording = true
        return true
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
    }

    private func process(db: Float, duration: Double) {
        guard isRecording else { return }
        level = max(0, min(1, (db + 60) / 50))
        if db > Endurance.voiceThresholdDB {
            hasSpoken = true
            silence = 0
            speakingSeconds += duration
        } else if hasSpoken {
            let before = silence
            silence += duration
            if silence <= Endurance.pauseSeconds {
                speakingSeconds += duration
            } else if before <= Endurance.pauseSeconds {
                // 刚越过卡壳线：这段停顿不算开口，记一次卡壳
                speakingSeconds = max(0, speakingSeconds - Endurance.pauseSeconds)
                pauses += 1
            }
            if silence > Endurance.stopSilenceSeconds {
                onAutoStop?()
            }
        }
    }

    private static func decibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -160 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return 20 * log10(max(sqrt(sum / Float(n)), 1e-7))
    }
}

// MARK: - 回放

@Observable
final class RecordingPlayer {
    private(set) var playing: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private let delegate = Delegate()

    init() {
        delegate.onFinish = { [weak self] in self?.playing = nil }
    }

    func toggle(_ name: String) {
        if playing == name {
            stop()
            return
        }
        stop()
        Speaker.shared.stop()
        AudioSessionConfig.activate()
        guard let p = try? AVAudioPlayer(contentsOf: RecordingStore.url(name)) else { return }
        p.delegate = delegate
        p.play()
        player = p
        playing = name
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    private final class Delegate: NSObject, AVAudioPlayerDelegate {
        var onFinish: (() -> Void)?
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            DispatchQueue.main.async { self.onFinish?() }
        }
    }
}
