import SwiftUI

// MARK: - 数据

/// 一个音的发音方法：嘴张多大、唇形、舌位、常见错误
struct PhonemeGuide: Codable, Identifiable, Hashable {
    let id: String
    let ipa: String
    let name: String
    /// 张口程度 1(几乎闭) – 4(最大)
    let open: Int
    let lips: String
    let tongue: String
    let how: String
    let mistake: String
    let words: [String]
    let pairs: [[String]]
}

struct PronToken: Codable, Hashable {
    let t: String
    let ipa: String?
    let stress: Bool
    let weak: Bool?
    let focus: Bool?
    let g: [String]?
}

struct PronLink: Codable, Hashable {
    let i: Int
    /// link 连读 / flap 闪音 / glide 元音连读 / drop 不完全爆破 / assim 同化 / merge 同音合并 / hdrop h 脱落
    let type: String

    var label: String {
        ["link": "连", "flap": "闪", "glide": "滑", "drop": "吞", "assim": "化", "merge": "并", "hdrop": "连"][type] ?? ""
    }

    var color: Color {
        switch type {
        case "flap", "assim": return .purple
        case "drop": return .gray
        default: return .blue
        }
    }
}

struct PronSentence: Codable, Hashable {
    let tokens: [PronToken]
    let links: [PronLink]
    let notes: [String]
}

struct PronWord: Codable, Hashable {
    let ipa: String
    let g: [String]
}

struct PronunciationData: Codable {
    let guides: [PhonemeGuide]
    let sentences: [String: PronSentence]
    let words: [String: PronWord]

    static let empty = PronunciationData(guides: [], sentences: [:], words: [:])

    func guide(_ id: String) -> PhonemeGuide? { guides.first { $0.id == id } }

    /// 和生成脚本一致的查词方式：小写、去掉两端标点
    static func key(_ token: String) -> String {
        var t = token.replacingOccurrences(of: "’", with: "'").lowercased()
        while let first = t.unicodeScalars.first, !CharacterSet.alphanumerics.contains(first) { t.removeFirst() }
        if t.hasSuffix("...") { t.removeLast(3) }
        if t.hasSuffix("…") { t.removeLast() }
        if t != "p.m." {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'."))
            while let last = t.unicodeScalars.last, !allowed.contains(last) { t.removeLast() }
            while t.hasSuffix(".") { t.removeLast() }
        }
        return t
    }
}

// MARK: - 怎么读：重音 · 弱读 · 连读

struct WordRef: Identifiable {
    let id = UUID()
    let token: String
}

/// 一句话的读法：粗体重读、灰色弱读、‿ 连读；点单词看嘴型
struct PronLineView: View {
    @Environment(ChunkLibrary.self) private var library
    let key: String
    var showNotes = true

    @State private var selected: WordRef?

    var body: some View {
        if let sentence = library.pron.sentences[key] {
            let linkAt = Dictionary(sentence.links.map { ($0.i, $0) }, uniquingKeysWith: { a, _ in a })
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 2) {
                    ForEach(Array(sentence.tokens.enumerated()), id: \.offset) { i, token in
                        HStack(spacing: 2) {
                            Button {
                                selected = WordRef(token: token.t)
                            } label: {
                                VStack(spacing: 1) {
                                    Text(token.t)
                                        .font(token.stress ? .body.bold() : .callout)
                                        .foregroundStyle(token.stress ? Color.primary : Color.secondary)
                                        .underline(token.focus == true, color: .blue)
                                    Text(token.ipa.map { "/\($0)/" } ?? " ")
                                        .font(.caption2)
                                        .foregroundStyle(token.weak == true ? Color.orange : Color.secondary)
                                }
                                .padding(.horizontal, 2)
                            }
                            .buttonStyle(.plain)
                            if let link = linkAt[i] {
                                VStack(spacing: 0) {
                                    Text("‿").font(.headline)
                                    Text(link.label).font(.system(size: 9, weight: .bold))
                                }
                                .foregroundStyle(link.color)
                            }
                        }
                    }
                }
                if showNotes {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sentence.notes, id: \.self) { note in
                            Text("· \(note)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(item: $selected) { ref in
                WordGuideSheet(token: ref.token)
            }
        }
    }
}

/// 点一个词：音标 + 这个词里难发的音该怎么摆嘴型
struct WordGuideSheet: View {
    @Environment(ChunkLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let token: String

    var body: some View {
        let key = PronunciationData.key(token)
        let info = library.pron.words[key]
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key).font(.title.bold())
                            if let info {
                                Text("/\(info.ipa)/").font(.title3).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        SpeakButton(text: key)
                        SpeakButton(text: key, slow: true)
                    }
                }
                let guides = (info?.g ?? []).compactMap { library.pron.guide($0) }
                if guides.isEmpty {
                    Text("这个词没有特别难的音，听朗读跟着模仿就行。").foregroundStyle(.secondary)
                } else {
                    ForEach(guides) { guide in
                        Section("\(guide.name) /\(guide.ipa)/") {
                            GuideCardView(guide: guide, showTitle: false)
                        }
                    }
                }
            }
            .navigationTitle("怎么发音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 一个音的发音卡片
struct GuideCardView: View {
    let guide: PhonemeGuide
    var showTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showTitle {
                Text("\(guide.name)  /\(guide.ipa)/").font(.title3.bold())
            }
            HStack(spacing: 16) {
                OpenMeter(level: guide.open)
                Label(guide.lips, systemImage: "mouth").font(.subheadline)
            }
            Label(guide.tongue, systemImage: "arrow.up.and.down").font(.subheadline)
            Text(guide.how).font(.body)
            Label(guide.mistake, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            if !guide.words.isEmpty {
                Text("练习词（点击朗读）").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(guide.words, id: \.self) { word in
                        Button(word) { Speaker.shared.speak(word, slow: true) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            if !guide.pairs.isEmpty {
                Text("对比着听，别读混").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(guide.pairs, id: \.self) { pair in
                        Button(pair.joined(separator: " / ")) {
                            Speaker.shared.speak(pair.joined(separator: ", "), slow: true)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 张口程度：4 格
struct OpenMeter: View {
    let level: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("张口").font(.subheadline)
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i <= level ? Color.accentColor : Color.gray.opacity(0.25))
                    .frame(width: 8, height: CGFloat(6 + i * 4))
            }
            Text(["", "小", "半开", "较大", "最大"][min(max(level, 1), 4)]).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 语块库里的「发音指南」：所有难发的音
struct PronGuideListView: View {
    @Environment(ChunkLibrary.self) private var library

    var body: some View {
        List(library.pron.guides) { guide in
            NavigationLink {
                ScrollView {
                    GuideCardView(guide: guide).padding()
                }
                .navigationTitle(guide.name)
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack {
                    Text("/\(guide.ipa)/").font(.headline).frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guide.name)
                        Text(guide.words.prefix(3).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("发音指南")
        .navigationBarTitleDisplayMode(.inline)
    }
}
