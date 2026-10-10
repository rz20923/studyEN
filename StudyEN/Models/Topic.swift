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
        guard let spoken = slotWords(unit: unit, in: transcript), !spoken.isEmpty else {
            return Result(frameOK: false, slotOK: false)
        }
        guard let answer, let expected = slotWords(unit: unit, in: answer), !expected.isEmpty else {
            return Result(frameOK: true, slotOK: true)
        }
        let score = PhraseMatcher.readingScore(expected.joined(separator: " "), transcript: spoken.joined(separator: " "))
        return Result(frameOK: true, slotOK: score >= 0.5)
    }
}
