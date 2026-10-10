import Foundation
import Observation

enum ChunkKind: String, Codable, CaseIterable, Identifiable {
    case phrasal
    case filler

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phrasal: return "短语动词"
        case .filler: return "谈话润滑剂"
        }
    }
}

/// 一个"生活情境语块"：不是孤立单词，而是带场景、带例句的整块表达。
struct Chunk: Codable, Identifiable, Hashable {
    let id: String
    let kind: ChunkKind
    let scene: String
    let phrase: String
    let meaning: String
    /// 被替代的书面大词，例如 put up with 替代 tolerate
    let replaces: String?
    let example: String
    let exampleZh: String
    let tip: String?
    /// 例句按意群拆分并标好成分，用于分段跟读
    let parts: [WordOrderDrill.Segment]?
}

/// 语序造句题：中文句子 + 按英文语序拆好的成分
struct WordOrderDrill: Codable, Identifiable, Hashable {
    struct Segment: Codable, Hashable {
        /// S 主语 / V 谓语 / O 宾语 / M 方式 / P 地点 / T 时间
        /// Q 疑问词 / A 助动词 / F 频率副词 / L 引导句 / E 存在句 / W 伴随 / R 原因目的
        let role: String
        let en: String
    }

    let id: String
    let zh: String
    let segments: [Segment]
    /// basic 陈述句 / question 特殊疑问句 / yesno 一般疑问句 / frequency 频率副词 /
    /// indirect 间接疑问句 / there 存在句 / extra 伴随原因目的
    let pattern: String?

    var isBasic: Bool { (pattern ?? "basic") == "basic" }

    var sentence: String {
        let text = segments.map(\.en).joined(separator: " ")
        let asks = pattern == "question" || pattern == "yesno"
            || (pattern == "indirect" && ["do ", "can ", "could ", "would "].contains { text.hasPrefix($0) })
        return text.prefix(1).uppercased() + text.dropFirst() + (asks ? "?" : ".")
    }
}

enum SentenceRole {
    static func name(_ role: String) -> String {
        [
            "S": "主语", "V": "谓语", "O": "宾语", "M": "方式", "P": "地点", "T": "时间",
            "Q": "疑问词", "A": "助动词", "F": "频率副词", "L": "引导句", "E": "存在句", "W": "伴随", "R": "原因/目的",
            "C": "表语", "J": "连接", "X": "插入语",
        ][role] ?? role
    }
}

@Observable
final class ChunkLibrary {
    let chunks: [Chunk]
    let drills: [WordOrderDrill]
    /// 发音数据：每句的重音/弱读/连读、每个词的音标和难点音、发音指南
    let pron: PronunciationData
    /// 课题（MVP 的主线内容）
    let topics: [Topic]
    private let unitByID: [String: (topic: Topic, unit: TopicUnit)]
    /// 学习顺序：润滑剂打头，并均匀穿插在短语动词之间
    let learningOrder: [Chunk]
    private let byID: [String: Chunk]

    init(chunks: [Chunk], drills: [WordOrderDrill], pron: PronunciationData, topics: [Topic]) {
        self.chunks = chunks
        self.drills = drills
        self.pron = pron
        self.topics = topics
        var map: [String: (topic: Topic, unit: TopicUnit)] = [:]
        for t in topics { for u in t.units { map[u.id] = (t, u) } }
        self.unitByID = map
        self.byID = Dictionary(chunks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.learningOrder = Self.interleave(
            fillers: chunks.filter { $0.kind == .filler },
            phrasals: chunks.filter { $0.kind == .phrasal }
        )
    }

    static func load() -> ChunkLibrary {
        ChunkLibrary(chunks: decode("chunks"), drills: decode("word_order"), pron: decodeObject("pronunciation") ?? .empty, topics: decode("topics"))
    }

    private static func decodeObject<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func decode<T: Decodable>(_ name: String) -> [T] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([T].self, from: data) else {
            assertionFailure("\(name).json 加载失败")
            return []
        }
        return items
    }

    func chunk(id: String) -> Chunk? { byID[id] }

    func unit(id: String) -> (topic: Topic, unit: TopicUnit)? { unitByID[id] }

    func scenes(of kind: ChunkKind) -> [String] {
        var seen = Set<String>()
        return chunks.filter { $0.kind == kind }.compactMap { seen.insert($0.scene).inserted ? $0.scene : nil }
    }

    private static func interleave(fillers: [Chunk], phrasals: [Chunk]) -> [Chunk] {
        var result: [Chunk] = []
        var fi = 0, pi = 0
        while fi < fillers.count || pi < phrasals.count {
            let fRatio = Double(fi) / Double(max(fillers.count, 1))
            let pRatio = Double(pi) / Double(max(phrasals.count, 1))
            if fi < fillers.count && (pi >= phrasals.count || fRatio <= pRatio) {
                result.append(fillers[fi]); fi += 1
            } else {
                result.append(phrasals[pi]); pi += 1
            }
        }
        return result
    }
}
