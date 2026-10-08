import AVFoundation
import Observation
import Speech

/// 实时语音识别：用来判定用户是否真的开口说对了
@Observable
final class SpeechChecker {
    private(set) var isRecording = false
    private(set) var transcript = ""

    /// 每次识别结果更新时回调（用于实时判定达标）
    @ObservationIgnored var onTranscript: ((String) -> Void)?
    /// 录音结束（超时 / 手动停止 / 识别结束）且未被判定达标时回调
    @ObservationIgnored var onStop: ((String) -> Void)?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var sessionID = 0

    static func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    @discardableResult
    func start(hints: [String] = [], timeout: TimeInterval = 8) -> Bool {
        stop(notify: false)
        transcript = ""
        guard let recognizer, recognizer.isAvailable, AudioSessionConfig.activate() else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = hints
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }

        sessionID += 1
        let id = sessionID
        self.request = request
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.isRecording, self.sessionID == id else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.onTranscript?(self.transcript)
                }
                if self.isRecording, error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.sessionID == id else { return }
            self.stop()
        }
        return true
    }

    func stop(notify: Bool = true) {
        guard isRecording else { return }
        isRecording = false
        sessionID += 1
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        if notify {
            onStop?(transcript)
        }
    }

    func clear() {
        transcript = ""
    }
}

/// 语序判定：主 → 谓 → 宾 → 方式 → 地点 → 时间
enum OrderChecker {
    static let rule = "中文状语往前挤，英文状语往后退"

    static let patternTips: [String: String] = [
        "question": "特殊疑问句：疑问词 + 助动词 + 主语 + 动词（不说 Where you are going）",
        "yesno": "一般疑问句：助动词或 be 动词放在句首",
        "frequency": "频率副词（always / usually / never…）放在实义动词前、be 动词后",
        "indirect": "间接疑问句用陈述语序：Do you know where he is，不说 where is he",
        "there": "“某处有某物”说 There is + 东西 + 地点",
        "extra": "伴随、方式、原因、目的都往句尾放：\(rule)",
    ]

    static func hint(for drill: WordOrderDrill) -> String {
        patternTips[drill.pattern ?? ""] ?? "主 → 谓 → 宾 → 方式 → 地点 → 时间"
    }

    struct Result {
        let ok: Bool
        let message: String?
    }

    /// 在识别结果里找某个成分的起始位置（允许中间夹 1 个多余的词）
    static func findSegment(_ heard: [String], _ segment: [String]) -> Int? {
        guard let first = segment.first else { return nil }
        for i in heard.indices where PhraseMatcher.wordMatches(first, heard[i]) {
            var j = i + 1, k = 1
            while k < segment.count && j < heard.count && j <= i + k + 1 {
                if PhraseMatcher.wordMatches(segment[k], heard[j]) { k += 1 }
                j += 1
            }
            if k == segment.count { return i }
        }
        return nil
    }

    static func check(_ drill: WordOrderDrill, transcript: String) -> Result {
        let heard = PhraseMatcher.words(transcript)
        var pos: [String: Int] = [:]
        for segment in drill.segments {
            guard let p = findSegment(heard, PhraseMatcher.words(segment.en)) else {
                return Result(ok: false, message: "缺少\(SentenceRole.name(segment.role))「\(segment.en)」")
            }
            pos[segment.role] = p
        }
        if !drill.isBasic {
            return checkPattern(drill, pos)
        }
        guard let s = pos["S"], let v = pos["V"] else { return Result(ok: false, message: nil) }
        if v < s {
            return Result(ok: false, message: "谓语要紧跟在主语后面")
        }
        for role in ["O", "P", "T"] {
            if let p = pos[role], p > s, p < v {
                return Result(ok: false, message: "\(SentenceRole.name(role))不能夹在主语和谓语中间：\(rule)")
            }
        }
        if let o = pos["O"], o < v {
            return Result(ok: false, message: "宾语要放在谓语后面")
        }
        // 时间可以放句首；放句尾时必须在地点后面
        if let p = pos["P"], let t = pos["T"], t > s, t < p {
            return Result(ok: false, message: "英文里地点在前、时间在后")
        }
        return Result(ok: true, message: nil)
    }

    /// 时间、地点、方式、伴随、原因目的：放在标准位置或整句句首都是正确英语
    private static let flexibleRoles: Set<String> = ["T", "P", "M", "W", "R"]

    /// 疑问句、间接疑问句等：主干成分按标准顺序逐个检查，状语允许放句首
    private static func checkPattern(_ drill: WordOrderDrill, _ pos: [String: Int]) -> Result {
        let tip = patternTips[drill.pattern ?? ""] ?? ""
        let core = drill.segments.filter { !flexibleRoles.contains($0.role) }
        for i in core.indices.dropFirst() {
            let before = core[i - 1], after = core[i]
            if let a = pos[after.role], let b = pos[before.role], a < b {
                return Result(ok: false, message: "「\(before.en)」要放在「\(after.en)」前面。\(tip)")
            }
        }
        let coreStart = core.compactMap { pos[$0.role] }.min() ?? 0
        for i in drill.segments.indices.dropFirst() {
            let segment = drill.segments[i], prev = drill.segments[i - 1]
            guard flexibleRoles.contains(segment.role), let p = pos[segment.role], p >= coreStart else { continue }
            if let q = pos[prev.role], p < q {
                return Result(ok: false, message: "\(SentenceRole.name(segment.role))「\(segment.en)」要放在「\(prev.en)」后面，或者放句首。\(tip)")
            }
        }
        return Result(ok: true, message: nil)
    }
}

/// 把识别文本和目标语块做比对
enum PhraseMatcher {
    private static let expansions: [String: [String]] = [
        "gonna": ["going", "to"], "wanna": ["want", "to"], "gotta": ["got", "to"],
        "kinda": ["kind", "of"], "sorta": ["sort", "of"], "ya": ["you"],
        "im": ["i", "am"], "ill": ["i", "will"], "ive": ["i", "have"], "theres": ["there", "is"],
    ]
    private static let numbers: [String: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five", "6": "six",
        "7": "seven", "8": "eight", "9": "nine", "10": "ten", "11": "eleven", "12": "twelve",
    ]
    /// 不规则动词：说过去式也算对
    private static let irregular: [String: Set<String>] = [
        "get": ["got", "gotten"], "run": ["ran"], "come": ["came"], "give": ["gave", "given"],
        "make": ["made"], "sell": ["sold"], "catch": ["caught"], "throw": ["threw", "thrown"],
        "take": ["took", "taken"], "go": ["went", "gone"], "have": ["had", "has"], "hang": ["hung"],
        "burn": ["burnt"], "wake": ["woke"], "be": ["am", "is", "are", "was", "were"],
    ]

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .flatMap { word -> [String] in
                if let expanded = expansions[word] { return expanded }
                if let number = numbers[word] { return [number] }
                return [word]
            }
    }

    static func wordMatches(_ target: String, _ heard: String) -> Bool {
        heard == target
            || (target.count >= 3 && heard.hasPrefix(target))
            || (irregular[target]?.contains(heard) ?? false)
    }

    /// 回想判定：语块任一写法（用 / 分隔）的词按顺序出现在识别结果中
    static func matchesPhrase(_ phrase: String, in transcript: String) -> Bool {
        let heard = words(transcript)
        return phrase.components(separatedBy: "/").contains { alternative in
            let target = words(alternative)
            guard !target.isEmpty else { return false }
            var i = 0
            for word in heard where i < target.count && wordMatches(target[i], word) {
                i += 1
            }
            return i == target.count
        }
    }

    /// 跟读判定：例句中按顺序读对的词占比（最长公共子序列）
    static func readingScore(_ sentence: String, transcript: String) -> Double {
        let target = words(sentence)
        let heard = words(transcript)
        guard !target.isEmpty, !heard.isEmpty else { return 0 }
        var dp = Array(repeating: Array(repeating: 0, count: heard.count + 1), count: target.count + 1)
        for i in 1...target.count {
            for j in 1...heard.count {
                dp[i][j] = wordMatches(target[i - 1], heard[j - 1])
                    ? dp[i - 1][j - 1] + 1
                    : max(dp[i - 1][j], dp[i][j - 1])
            }
        }
        return Double(dp[target.count][heard.count]) / Double(target.count)
    }
}
