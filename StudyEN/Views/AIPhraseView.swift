import SwiftUI

/// AI 出一关：输入一个场景，DeepSeek 生成 10 张词组卡
struct AIPhraseLevelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreated: (PhraseLevel) -> Void

    @State private var theme = ""
    @State private var keyDraft = ""
    @State private var hasKey = AIKey.value != nil
    @State private var working = false
    @State private var error: String?

    private let ideas = ["健身房", "租房看房", "看病", "机场登机", "超市购物", "约朋友吃饭", "上班开会", "酒店前台"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hasKey {
                        Text("想练什么场景？").font(.system(size: 24, weight: .black))
                        Text("AI 会挑 10 个这个场景里最常用的词组，每张卡只练一个意思。")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        TextField("比如：健身房", text: $theme)
                            .font(.title3.bold())
                            .padding(14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        FlowLayout(spacing: 8) {
                            ForEach(ideas, id: \.self) { idea in
                                Button(idea) { theme = idea }
                                    .font(.subheadline)
                                    .foregroundStyle(theme == idea ? .white : Theme.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(theme == idea ? Theme.ink : Color.white, in: Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                        InkButton(working ? "生成中，大约 20 秒…" : "生成这一关", icon: "sparkles") { generate() }
                            .disabled(working || theme.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(working || theme.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                        if working { ProgressView().frame(maxWidth: .infinity) }
                        Button("更换密钥") {
                            AIKey.set(nil)
                            hasKey = false
                        }
                        .font(.footnote).foregroundStyle(Theme.faint)
                    } else {
                        Text("填入 DeepSeek 密钥").font(.system(size: 24, weight: .black))
                        Text("密钥只保存在这台手机的钥匙串里，不会上传到别处。")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                        SecureField("sk-…", text: $keyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        InkButton("保存") {
                            AIKey.set(keyDraft)
                            keyDraft = ""
                            hasKey = AIKey.value != nil
                        }
                    }
                    if let error {
                        Text(error).font(.subheadline.bold()).foregroundStyle(Theme.accentDark)
                    }
                }
                .padding(20)
            }
            .background(Theme.ground)
            .navigationTitle("AI 出一关")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private func generate() {
        let topic = theme.trimmingCharacters(in: .whitespaces)
        error = nil
        working = true
        Task {
            do {
                let level = try await PhraseAI.level(theme: topic, avoid: PhraseDeck.all.flatMap { $0.cards.map(\.en) })
                PhraseDeck.addCustom(level)
                working = false
                onCreated(level)
                dismiss()
            } catch {
                working = false
                self.error = error.localizedDescription
            }
        }
    }
}

/// 让 AI 按 PhraseLevel 的结构出题，并做基本校验
enum PhraseAI {
    private struct Draft: Decodable {
        let title: String?
        let cards: [PhraseCard]
    }

    static func level(theme: String, avoid: [String]) async throws -> PhraseLevel {
        let system = """
        你是给中国成年人做英语口语训练的教练。用户是“学了很多年英语但开不了口”的人。
        任务：为一个生活场景挑 10 个口语里最常用的英语短语动词或固定短语（2~4 个词），做成快速口说卡片。
        要求：
        1. 必须是母语者日常闲聊真的会说的，不要书面语、不要生僻。优先短语动词（如 check in, pick up, run out of）。
        2. 每张卡只取一个意思，就是这个场景里的意思。
        3. zh：中文意思，不超过 6 个字，口语化；有歧义时用括号补一点范围，如“打开（电器）”。
        4. ok：2~4 个学习者听到英文后可能脱口说出的中文说法，每个 1~4 个字，要包含 zh 的核心词；不要放会和别的意思混淆的字。
        5. ex：一句不超过 8 个词的自然口语例句，包含这个词组；exZh：例句的口语中文。
        6. 不要和这些已经学过的重复：\(avoid.joined(separator: ", "))
        只输出 json，格式：
        {"title": "不超过 6 个汉字的关卡名", "cards": [{"en": "...", "zh": "...", "ok": ["..."], "ex": "...", "exZh": "..."}]}
        """
        let text = try await DeepSeek.chat(system: system, user: "场景：\(theme)", json: true, temperature: 0.8)
        guard let data = text.data(using: .utf8), let draft = try? JSONDecoder().decode(Draft.self, from: data) else {
            throw DeepSeek.Failure.format
        }
        let known = Set(avoid.map { $0.lowercased() })
        var seen = Set<String>()
        let cards = draft.cards.compactMap { c -> PhraseCard? in
            let en = c.en.trimmingCharacters(in: .whitespaces).lowercased()
            guard !en.isEmpty, !c.zh.isEmpty, !c.ex.isEmpty, !known.contains(en), seen.insert(en).inserted else { return nil }
            let ok = c.ok.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return PhraseCard(en: en, zh: c.zh, ok: ok.isEmpty ? [c.zh] : ok, ex: c.ex, exZh: c.exZh)
        }
        guard cards.count >= 6 else { throw DeepSeek.Failure.format }
        let title = (draft.title?.isEmpty == false ? draft.title! : theme)
        return PhraseLevel(id: "AI-\(UUID().uuidString.prefix(8))", title: title, cards: Array(cards.prefix(10)))
    }
}
