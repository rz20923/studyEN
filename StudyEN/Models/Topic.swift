import Foundation
import SwiftData

/// 课题：一个真实事件，含 4~6 个框架单元和一段多轮对话
struct Topic: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let scene: String
    let units: [TopicUnit]
    let boss: Boss

    struct Boss: Codable, Hashable {
        let role: String
        let npcName: String
        let turns: [Turn]
    }

    struct Turn: Codable, Hashable {
        let npc: String
        /// 这一轮要用的单元（units 下标）
        let unit: Int
        let zh: String
        let answer: String
    }
}

/// 单元：一个框架 = 固定骨架 + 一个槽位
struct TopicUnit: Codable, Identifiable, Hashable {
    let id: String
    /// 含 [slot] 的框架，如 "I'd like to have [slot], please."
    let frame: String
    let intent: String
    let slotHint: String
    let options: [String]
    /// 每个可替换词的中文，不认识的词不会卡住
    let optionsZh: [String]?
    let example: String
    let exampleZh: String
    let prompts: [Prompt]

    struct Prompt: Codable, Hashable {
        let zh: String
        let answer: String
    }

    var before: String { frame.components(separatedBy: "[slot]").first ?? "" }
    var after: String { frame.components(separatedBy: "[slot]").dropFirst().first ?? "" }

    /// 骨架显示：槽位用下划线
    var skeleton: String { frame.replacingOccurrences(of: "[slot]", with: "___") }

    func optionZh(_ option: String) -> String {
        guard let zh = optionsZh, let i = options.firstIndex(of: option), i < zh.count else { return "" }
        return zh[i]
    }

    /// 自我介绍单元换成用户自己的英文名
    func personalized() -> TopicUnit {
        guard id == "T01U1", let name = UserName.current else { return self }
        let others = options.filter { $0 != name }
        return TopicUnit(
            id: id, frame: frame, intent: intent, slotHint: slotHint,
            options: [name] + others.prefix(3), optionsZh: [name] + others.prefix(3),
            example: example, exampleZh: exampleZh,
            prompts: [Prompt(zh: "用你的英文名 \(name) 介绍自己", answer: sentence(with: name))] + prompts.prefix(1)
        )
    }

    /// 把槽位换成某个词，得到整句
    func sentence(with slot: String) -> String {
        frame.replacingOccurrences(of: "[slot]", with: slot)
    }

    /// 例句按“骨架前段 / 槽位 / 骨架后段”切开，返回每段在例句词序列里的范围
    var exampleRanges: (before: Range<Int>, slot: Range<Int>, after: Range<Int>) {
        let total = example.split(separator: " ").count
        let b = before.split(separator: " ").count
        let a = after.split(separator: " ").filter { !$0.allSatisfy { ",.?!".contains($0) } }.count
        let slotEnd = max(b, total - a)
        return (0..<b, b..<slotEnd, slotEnd..<total)
    }
}

/// 用户的英文名（第一次打开时起）
enum UserName {
    static let key = "englishName"
    static var current: String? {
        let name = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? nil : name
    }

    /// 例句里的 Leo 换成用户的名字
    static func apply(_ text: String) -> String {
        guard let name = current else { return text }
        return text.replacingOccurrences(of: "Leo", with: name)
    }
}

/// 课题完成记录：对话演练是否通过
@Model
final class TopicProgress {
    @Attribute(.unique) var topicID: String
    var bossPassed: Bool = false
    var bossDate: Date?

    init(topicID: String) {
        self.topicID = topicID
    }
}

/// 框架判定：骨架是否完整、槽位是否填对
enum FrameMatcher {
    struct Result {
        let frameOK: Bool
        let slotOK: Bool
        var passed: Bool { frameOK && slotOK }
    }

    /// 在 heard 里从 start 开始按顺序找 target 的词（允许中间夹别的词），返回最后一个匹配词之后的位置
    private static func match(_ target: [String], in heard: [String], from start: Int) -> (first: Int, end: Int)? {
        guard !target.isEmpty else { return (start, start) }
        var k = 0, first = -1, i = start
        while i < heard.count && k < target.count {
            if PhraseMatcher.wordMatches(target[k], heard[i]) {
                if first < 0 { first = i }
                k += 1
            }
            i += 1
        }
        return k == target.count ? (first, i) : nil
    }

    /// 取出一句话里槽位部分的词
    static func slotWords(unit: TopicUnit, in text: String) -> [String]? {
        let heard = PhraseMatcher.words(text)
        let b = PhraseMatcher.words(unit.before)
        let a = PhraseMatcher.words(unit.after)
        guard let pre = match(b, in: heard, from: 0) else { return nil }
        if a.isEmpty { return Array(heard[pre.end...]) }
        // 后段从槽位之后找：至少留 1 个词给槽位
        guard pre.end + 1 <= heard.count, let post = match(a, in: heard, from: pre.end + 1) else { return nil }
        return Array(heard[pre.end..<post.first])
    }

    static func check(unit: TopicUnit, answer: String?, transcript: String) -> Result {
        let heard = PhraseMatcher.words(transcript)
        // 自我介绍里的名字识别器常听不准，名字随便说都算填对
        let expected = unit.id == "T01U1" ? nil : answer.flatMap { slotWords(unit: unit, in: $0) }
        var best = Result(frameOK: false, slotOK: false)
        // 说错了接着重说：从后面任意位置重新开始匹配也算
        for k in 0..<min(max(heard.count, 1), 40) {
            let text = heard[min(k, heard.count)...].joined(separator: " ")
            guard let spoken = slotWords(unit: unit, in: text), !spoken.isEmpty else { continue }
            guard let expected, !expected.isEmpty else { return Result(frameOK: true, slotOK: true) }
            let score = PhraseMatcher.readingScore(expected.joined(separator: " "), transcript: spoken.joined(separator: " "))
            if score >= 0.5 { return Result(frameOK: true, slotOK: true) }
            best = Result(frameOK: true, slotOK: false)
        }
        return best
    }
}
