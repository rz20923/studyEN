import SwiftUI

/// 今天练了多久（只算在训练页的时间）
enum StudyTimer {
    private static let dayKey = "timerDay"
    private static let secondsKey = "timerSeconds"

    private static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    static var seconds: Double {
        UserDefaults.standard.string(forKey: dayKey) == today ? UserDefaults.standard.double(forKey: secondsKey) : 0
    }

    static func add(_ s: Double) {
        let d = UserDefaults.standard
        if d.string(forKey: dayKey) != today {
            d.set(today, forKey: dayKey)
            d.set(0, forKey: secondsKey)
        }
        d.set(d.double(forKey: secondsKey) + s, forKey: secondsKey)
    }

    static func text(_ s: Double) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 点一个“块”：这一块怎么读（重读、弱读、连读）+ 每个词的意思
struct ChunkHowToSheet: View {
    @Environment(ChunkLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let key: String
    let range: Range<Int>
    let text: String

    @State private var selected: WordRef?

    private static let hardSounds: Set<String> = ["TH", "DH", "V", "R", "W", "AE", "LD", "NG", "Z", "ER"]

    var body: some View {
        let tokens = library.pron.sentences[key]?.tokens ?? []
        let links = library.pron.sentences[key]?.links ?? []
        let inRange = range.clamped(to: 0..<tokens.count).map { tokens[$0] }
        let stressed = inRange.filter { $0.stress && $0.weak != true }.map(\.t)
        let weak = inRange.filter { $0.weak == true }
        let localLinks = links.filter { range.contains($0.i) && range.contains($0.i + 1) && $0.i + 1 < tokens.count }

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        TokenLine(key: key, range: range, size: 24, tappable: false, fallback: text)
                        HStack(spacing: 12) {
                            Button { Speaker.shared.speak(text) } label: { Label("听", systemImage: "speaker.wave.2.fill") }
                            Button { Speaker.shared.speak(text, slow: true) } label: { Label("慢速", systemImage: "tortoise.fill") }
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.ink)
                    }
                    .padding(.vertical, 6)
                }

                Section("这一块怎么读") {
                    if !stressed.isEmpty {
                        tip("重读", stressed.map(clean).joined(separator: " · ") + "：读得重、清楚、稍长")
                    }
                    if !weak.isEmpty {
                        tip("弱读", weak.map { "\(clean($0.t)) /\($0.ipa ?? "")/" }.joined(separator: "、") + "：轻、快、短，一带而过")
                    }
                    ForEach(localLinks, id: \.self) { l in
                        tip("连读", "\(clean(tokens[l.i].t))‿\(clean(tokens[l.i + 1].t))：\(describe(l.type))")
                    }
                    if stressed.isEmpty && weak.isEmpty && localLinks.isEmpty {
                        Text("这一块没有连读，逐词读清楚就好").foregroundStyle(Theme.muted)
                    }
                }

                Section("每个词的意思") {
                    ForEach(Array(inRange.enumerated()), id: \.offset) { _, t in
                        let info = library.pron.words[PronunciationData.key(t.t)]
                        let hard = (info?.g ?? []).first { Self.hardSounds.contains($0) }.flatMap { library.pron.guide($0) }
                        Button { selected = WordRef(token: t.t) } label: {
                            HStack {
                                Text(clean(t.t)).font(Theme.en(17, .bold)).foregroundStyle(Theme.ink)
                                Text(library.gloss(t.t) ?? "").foregroundStyle(Theme.muted)
                                Spacer()
                                if let hard {
                                    Text(hard.name).font(.caption.bold()).foregroundStyle(Theme.accentDark)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Theme.accentTint, in: Capsule())
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.faint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("这一块怎么读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
            .sheet(item: $selected) { ref in WordGuideSheet(token: ref.token) }
        }
        .presentationDetents([.medium, .large])
    }

    private func clean(_ t: String) -> String {
        t.trimmingCharacters(in: CharacterSet(charactersIn: ",.?!"))
    }

    private func tip(_ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title).font(.caption.bold()).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.ink, in: Capsule())
            Text(body).font(.subheadline)
        }
    }

    private func describe(_ type: String) -> String {
        switch type {
        case "flap": return "t 夹在两个元音中间，读成很轻的 d"
        case "glide": return "两个元音之间自然带出一个轻轻的 y 或 w，不要断开"
        case "drop": return "前一个词结尾的辅音只做口型、不爆破，直接接后面"
        case "assim": return "两个音融在一起：t+y 读成 ch，d+y 读成 j"
        case "merge": return "相同的音只读一次，稍微拉长"
        case "hdrop": return "h 不发音，直接连起来读"
        default: return "前一个词的尾音直接接到后一个词开头，中间不停"
        }
    }
}

/// 第一次打开：给自己起个英文名
struct NameOnboardingView: View {
    @AppStorage(UserName.key) private var name = ""
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    private let suggestions = ["Leo", "Amy", "Jack", "Lily", "Max", "Emma", "Ryan", "Mia", "Kevin", "Grace"]

    private var valid: Bool {
        let t = draft.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.count <= 16 && t.allSatisfy { $0.isASCII && ($0.isLetter || $0 == " " || $0 == "-") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BlocksLogo(size: 44).padding(.top, 30)
            Text("先给自己起个英文名").font(.system(size: 28, weight: .black))
            Text("和外国人聊天，第一句就是介绍自己。后面的练习都会用这个名字。")
                .foregroundStyle(Theme.muted)
            TextField("输入英文名", text: $draft)
                .font(Theme.en(22, .bold))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            Text("或者选一个").font(.footnote).foregroundStyle(Theme.faint)
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button(s) { draft = s }
                        .font(Theme.en(16, .semibold))
                        .foregroundStyle(draft == s ? .white : Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(draft == s ? Theme.ink : Color.white, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            Spacer()
            InkButton(valid ? "就叫 \(draft.trimmingCharacters(in: .whitespaces))" : "先输入一个英文名") {
                guard valid else { return }
                name = draft.trimmingCharacters(in: .whitespaces)
                dismiss()
            }
            .opacity(valid ? 1 : 0.5)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .background(Theme.ground)
        .interactiveDismissDisabled()
        .onAppear { draft = name }
    }
}
