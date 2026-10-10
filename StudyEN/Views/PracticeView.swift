import SwiftUI
import SwiftData

/// 随手练：像 Quizlet 一样的卡片，有空就刷，不影响每日打卡
struct PracticeView: View {
    @Environment(ChunkLibrary.self) private var library
    @Query private var progresses: [ChunkProgress]

    @State private var deck: Deck = .learned
    @State private var zhFront = true
    @State private var session: Session?

    enum Deck: Hashable {
        case learned, weak, all
        case scene(String)
    }

    enum Mode: String, CaseIterable, Identifiable {
        case cards = "翻卡片"
        case quiz = "选择题"
        case auto = "自动播放"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .cards: return "rectangle.on.rectangle.angled"
            case .quiz: return "checklist"
            case .auto: return "play.circle"
            }
        }

        var detail: String {
            switch self {
            case .cards: return "点卡片翻面，右滑认识、左滑不认识，不认识的会再出现"
            case .quiz: return "看中文选英文，四选一，无限连续"
            case .auto: return "自动翻面并朗读，适合走路、通勤时听"
            }
        }
    }

    struct Session: Identifiable {
        let id = UUID()
        let mode: Mode
        let cards: [Chunk]
    }

    private func cards(for deck: Deck) -> [Chunk] {
        switch deck {
        case .learned:
            return progresses.compactMap { library.chunk(id: $0.chunkID) }
        case .weak:
            return progresses.filter { $0.lapseCount > 0 || $0.box <= 1 }.compactMap { library.chunk(id: $0.chunkID) }
        case .all:
            return library.chunks
        case .scene(let scene):
            return library.chunks.filter { $0.scene == scene }
        }
    }

    var body: some View {
        let selected = cards(for: deck)
        NavigationStack {
            Form {
                Section("练哪些") {
                    Picker("范围", selection: $deck) {
                        Text("已学的（\(cards(for: .learned).count)）").tag(Deck.learned)
                        Text("薄弱的（\(cards(for: .weak).count)）").tag(Deck.weak)
                        Text("全部（\(library.chunks.count)）").tag(Deck.all)
                        ForEach(library.scenes(of: .phrasal) + library.scenes(of: .filler), id: \.self) { scene in
                            Text(scene).tag(Deck.scene(scene))
                        }
                    }
                    Picker("正面", selection: $zhFront) {
                        Text("中文 → 英文").tag(true)
                        Text("英文 → 中文").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(Mode.allCases) { mode in
                        Button {
                            session = Session(mode: mode, cards: selected)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: mode.icon).font(.title2).frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.rawValue).font(.headline)
                                    Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(selected.isEmpty)
                    }
                } footer: {
                    Text(selected.isEmpty ? "这个范围里还没有语块。先去「今天」学几个，或者选「全部」。" : "随手练不影响每日打卡，想练就练。")
                }
            }
            .navigationTitle("随手练")
            .fullScreenCover(item: $session) { s in
                switch s.mode {
                case .cards: FlashcardView(cards: s.cards, zhFront: zhFront)
                case .quiz: QuizView(cards: s.cards, pool: library.chunks)
                case .auto: AutoPlayView(cards: s.cards, zhFront: zhFront)
                }
            }
        }
    }
}

// MARK: - 卡片正反面

struct PracticeCardFace: View {
    let chunk: Chunk
    let zhFront: Bool
    let flipped: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.background.secondary)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            Group {
                if flipped {
                    back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                } else {
                    front
                }
            }
            .padding(24)
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
    }

    private var front: some View {
        VStack(spacing: 14) {
            KindTag(kind: chunk.kind)
            if zhFront {
                Text(chunk.meaning).font(.largeTitle.bold()).multilineTextAlignment(.center)
                if let word = chunk.replaces {
                    Text("别说 \(word)").foregroundStyle(.red)
                }
            } else {
                Text(chunk.phrase).font(.largeTitle.bold()).multilineTextAlignment(.center)
            }
            Text("点一下翻面").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var back: some View {
        VStack(spacing: 12) {
            Text(chunk.phrase).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(chunk.meaning).font(.title3)
            Divider()
            Text(chunk.example).font(.body.weight(.medium)).multilineTextAlignment(.center)
            Text(chunk.exampleZh).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 24) {
                SpeakButton(text: chunk.phrase)
                SpeakButton(text: chunk.example, slow: true)
            }
        }
    }
}

// MARK: - 翻卡片

struct FlashcardView: View {
    let all: [Chunk]
    let zhFront: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var deck: [Chunk]
    @State private var index = 0
    @State private var flipped = false
    @State private var known = 0
    @State private var unknown: [Chunk] = []
    @State private var drag: CGSize = .zero
    @State private var round = 1

    init(cards: [Chunk], zhFront: Bool) {
        all = cards
        self.zhFront = zhFront
        _deck = State(initialValue: cards.shuffled())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if index < deck.count {
                    let chunk = deck[index]
                    HStack {
                        Text("第 \(round) 轮 · \(index + 1)/\(deck.count)")
                        Spacer()
                        Text("认识 \(known)").foregroundStyle(.green)
                        Text("不认识 \(unknown.count)").foregroundStyle(.red)
                    }
                    .font(.subheadline.monospacedDigit())

                    PracticeCardFace(chunk: chunk, zhFront: zhFront, flipped: flipped)
                        .frame(maxHeight: 420)
                        .overlay(alignment: .top) { swipeHint }
                        .offset(drag)
                        .rotationEffect(.degrees(Double(drag.width / 25)))
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.4)) { flipped.toggle() }
                            if flipped { Speaker.shared.speak(chunk.phrase) }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation }
                                .onEnded { value in
                                    if value.translation.width > 100 { answer(true) }
                                    else if value.translation.width < -100 { answer(false) }
                                    else { withAnimation(.spring) { drag = .zero } }
                                }
                        )

                    HStack(spacing: 16) {
                        Button { answer(false) } label: {
                            Label("不认识", systemImage: "xmark").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered).tint(.red)
                        Button { answer(true) } label: {
                            Label("认识", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent).tint(.green)
                    }
                    .controlSize(.large)
                } else {
                    summary
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("结束") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var swipeHint: some View {
        if drag.width > 40 {
            Text("认识").font(.headline).padding(8).background(.green, in: Capsule()).foregroundStyle(.white).padding()
        } else if drag.width < -40 {
            Text("不认识").font(.headline).padding(8).background(.red, in: Capsule()).foregroundStyle(.white).padding()
        }
    }

    private func answer(_ ok: Bool) {
        guard index < deck.count else { return }
        if ok { known += 1 } else { unknown.append(deck[index]) }
        withAnimation(.easeOut(duration: 0.2)) {
            drag = .zero
            flipped = false
            index += 1
        }
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: unknown.isEmpty ? "star.fill" : "rectangle.stack.fill")
                .font(.system(size: 56))
                .foregroundStyle(unknown.isEmpty ? .yellow : .accentColor)
            Text(unknown.isEmpty ? "这一轮全认识！" : "这一轮练完了").font(.title.bold())
            Text("认识 \(known) · 不认识 \(unknown.count)").foregroundStyle(.secondary)
            Spacer()
            if !unknown.isEmpty {
                PrimaryButton("只练不认识的（\(unknown.count)）") { restart(with: unknown) }
            }
            Button("全部再来一轮") { restart(with: all) }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private func restart(with cards: [Chunk]) {
        deck = cards.shuffled()
        index = 0
        known = 0
        unknown = []
        flipped = false
        round += 1
    }
}

// MARK: - 选择题

struct QuizView: View {
    let cards: [Chunk]
    let pool: [Chunk]

    @Environment(\.dismiss) private var dismiss
    @State private var question: Chunk?
    @State private var options: [Chunk] = []
    @State private var picked: String?
    @State private var correct = 0
    @State private var total = 0
    @State private var streak = 0
    @State private var best = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Label("连对 \(streak)", systemImage: "flame.fill").foregroundStyle(.orange)
                    Spacer()
                    Text("最高 \(best) · 正确 \(correct)/\(total)").foregroundStyle(.secondary)
                }
                .font(.subheadline.monospacedDigit())

                if let q = question {
                    VStack(spacing: 8) {
                        Text(q.meaning).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        if let word = q.replaces {
                            Text("别说 \(word)").foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)

                    ForEach(options) { option in
                        Button { pick(option) } label: {
                            Text(option.phrase)
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(background(for: option), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(picked != nil && (option.id == q.id || option.id == picked) ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(picked != nil)
                    }

                    if picked != nil {
                        VStack(spacing: 4) {
                            Text(q.example).font(.subheadline.weight(.medium))
                            Text(q.exampleZh).font(.caption).foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                    }
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("结束") { dismiss() } }
            }
            .onAppear(perform: next)
        }
    }

    private func background(for option: Chunk) -> Color {
        guard let picked, let q = question else { return Color.gray.opacity(0.12) }
        if option.id == q.id { return .green }
        if option.id == picked { return .red }
        return Color.gray.opacity(0.12)
    }

    private func pick(_ option: Chunk) {
        guard picked == nil, let q = question else { return }
        picked = option.id
        total += 1
        let ok = option.id == q.id
        if ok {
            correct += 1
            streak += 1
            best = max(best, streak)
        } else {
            streak = 0
        }
        Speaker.shared.speak(q.phrase)
        Task {
            try? await Task.sleep(for: .seconds(ok ? 1.2 : 2.5))
            next()
        }
    }

    private func next() {
        let previous = question?.id
        guard let q = cards.filter({ $0.id != previous }).randomElement() ?? cards.first else { return }
        // 干扰项优先选同场景、同类型的，难度更接近真实
        let sameKind = pool.filter { $0.kind == q.kind && $0.id != q.id }
        let sameScene = sameKind.filter { $0.scene == q.scene }.shuffled()
        var distractors: [Chunk] = []
        for c in sameScene + sameKind.shuffled() where !distractors.contains(where: { $0.id == c.id }) {
            distractors.append(c)
            if distractors.count == 3 { break }
        }
        question = q
        options = (distractors + [q]).shuffled()
        picked = nil
    }
}

// MARK: - 自动播放

struct AutoPlayView: View {
    let zhFront: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var deck: [Chunk]
    @State private var index = 0
    @State private var flipped = false
    @State private var paused = false

    init(cards: [Chunk], zhFront: Bool) {
        self.zhFront = zhFront
        _deck = State(initialValue: cards.shuffled())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !deck.isEmpty {
                    Text("\(index + 1)/\(deck.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    PracticeCardFace(chunk: deck[index], zhFront: zhFront, flipped: flipped)
                        .frame(maxHeight: 420)
                    HStack(spacing: 16) {
                        Button { step(by: -1) } label: { Image(systemName: "backward.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }
                            .buttonStyle(.bordered)
                        Button { paused.toggle() } label: {
                            Image(systemName: paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        Button { step(by: 1) } label: { Image(systemName: "forward.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    Text("先想一想，3 秒后自动翻面并朗读").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("结束") {
                        Speaker.shared.stop()
                        dismiss()
                    }
                }
            }
            .task(id: "\(index)-\(paused)") { await play() }
        }
    }

    private func play() async {
        guard !paused, index < deck.count else { return }
        let chunk = deck[index]
        flipped = false
        if !zhFront { Speaker.shared.speak(chunk.phrase) }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(duration: 0.4)) { flipped = true }
        Speaker.shared.speak("\(chunk.phrase). \(chunk.example)")
        let words = chunk.example.split(separator: " ").count + chunk.phrase.split(separator: " ").count
        try? await Task.sleep(for: .seconds(2.5 + Double(words) * 0.45))
        guard !Task.isCancelled else { return }
        step(by: 1)
    }

    private func step(by delta: Int) {
        Speaker.shared.stop()
        let next = index + delta
        if next >= deck.count {
            deck.shuffle()
            index = 0
        } else {
            index = max(0, next)
        }
        flipped = false
    }
}
