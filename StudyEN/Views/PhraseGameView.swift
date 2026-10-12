import SwiftUI
import UIKit

// MARK: - 数据

/// 一张词组卡：只练一个意思
struct PhraseCard: Codable, Hashable {
    let en: String
    let zh: String
    /// 听音说意思时，说出其中任何一个就算对
    let ok: [String]
    let ex: String
    let exZh: String
}

/// 一关 = 10 张卡
struct PhraseLevel: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let cards: [PhraseCard]
}

enum PhraseDeck {
    static let builtin: [PhraseLevel] = {
        guard let url = Bundle.main.url(forResource: "phrasals", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let levels = try? JSONDecoder().decode([PhraseLevel].self, from: data) else { return [] }
        return levels
    }()

    /// AI 生成的关卡，存在本机
    private static let customKey = "aiPhraseLevels"

    static var custom: [PhraseLevel] {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let levels = try? JSONDecoder().decode([PhraseLevel].self, from: data) else { return [] }
        return levels
    }

    static var all: [PhraseLevel] { builtin + custom }

    static func addCustom(_ level: PhraseLevel) { saveCustom(custom + [level]) }

    static func removeCustom(id: String) { saveCustom(custom.filter { $0.id != id }) }

    private static func saveCustom(_ levels: [PhraseLevel]) {
        if let data = try? JSONEncoder().encode(levels) { UserDefaults.standard.set(data, forKey: customKey) }
    }
}

enum PhraseMode: String, CaseIterable, Identifiable {
    case listen, say
    var id: String { rawValue }
    var title: String { self == .listen ? "听音说意思" : "看中文说英文" }
    var hint: String { self == .listen ? "听到英文，马上说出中文意思" : "看到中文，马上说出英文词组" }
    var icon: String { self == .listen ? "ear" : "mouth" }
    /// 每张卡的作答时间
    var seconds: Double { self == .listen ? 5 : 6 }
}

struct PhraseRecord: Codable {
    var stars = 0
    var best = 0
}

/// 每关每种玩法的星级和最高分
enum PhraseRecords {
    private static let key = "phraseRecords"

    static func all() -> [String: PhraseRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: PhraseRecord].self, from: data) else { return [:] }
        return dict
    }

    static func id(_ level: String, _ mode: PhraseMode) -> String { "\(level):\(mode.rawValue)" }

    /// 返回是否破了最高分
    @discardableResult
    static func save(level: String, mode: PhraseMode, stars: Int, score: Int) -> Bool {
        var dict = all()
        var r = dict[id(level, mode)] ?? PhraseRecord()
        let record = score > r.best
        r.stars = max(r.stars, stars)
        r.best = max(r.best, score)
        dict[id(level, mode)] = r
        if let data = try? JSONEncoder().encode(dict) { UserDefaults.standard.set(data, forKey: key) }
        return record
    }
}

enum PhraseJudge {
    /// 中文：说出任何一个可接受的说法就算对
    static func zh(_ card: PhraseCard, _ text: String) -> Bool {
        let heard = text.filter { !$0.isPunctuation && !$0.isWhitespace }
        guard !heard.isEmpty else { return false }
        let main = card.zh.components(separatedBy: "；").map { String($0.prefix { $0 != "（" }) }.filter { !$0.isEmpty }
        return (card.ok + main).contains { heard.contains($0) }
    }

    /// 英文：词组的词按顺序出现，中间最多夹 2 个词（pick it up 也算）；gave up 这种变形也算
    static func en(_ card: PhraseCard, _ text: String) -> Bool {
        let target = PhraseMatcher.words(card.en)
        let heard = PhraseMatcher.words(text)
        guard let head = target.first else { return false }
        for s in heard.indices where PhraseMatcher.wordMatches(head, heard[s]) {
            var k = 1, i = s + 1, gap = 0
            while k < target.count, i < heard.count, gap <= 2 {
                if PhraseMatcher.wordMatches(target[k], heard[i]) { k += 1; gap = 0 } else { gap += 1 }
                i += 1
            }
            if k == target.count { return true }
        }
        return false
    }
}

// MARK: - 选关

struct PhraseHubView: View {
    @State private var mode: PhraseMode = .listen
    @State private var records = PhraseRecords.all()
    @State private var playing: GameBox?
    @State private var levels = PhraseDeck.all
    @State private var showAI = false

    struct GameBox: Identifiable {
        let id = UUID()
        let index: Int
        let mode: PhraseMode
    }

    private func record(_ i: Int) -> PhraseRecord {
        records[PhraseRecords.id(levels[i].id, mode)] ?? PhraseRecord()
    }

    /// AI 生成的关卡不用解锁
    private func unlocked(_ i: Int) -> Bool { i == 0 || i >= PhraseDeck.builtin.count || record(i - 1).stars > 0 }

    var body: some View {
        let stars = records.values.map(\.stars).reduce(0, +)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("词组闯关").font(.system(size: 30, weight: .black))
                    Spacer()
                    Label("\(stars) / \(levels.count * 6)", systemImage: "star.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.ink)
                }
                Text("10 张卡一关，听到就说，越快越连击分越高")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Button { showAI = true } label: {
                    Label("AI 出一关：输入场景，生成 10 张卡", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.accentDark)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    ForEach(PhraseMode.allCases) { m in
                        Button { mode = m } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Image(systemName: m.icon).font(.title3)
                                Text(m.title).font(.headline)
                                Text(m.hint).font(.caption).opacity(0.7).lineLimit(2)
                            }
                            .foregroundStyle(mode == m ? Color.white : Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(mode == m ? Theme.ink : Color.white, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ForEach(levels.indices, id: \.self) { i in
                        let r = record(i)
                        let open = unlocked(i)
                        Button {
                            if open { playing = GameBox(index: i, mode: mode) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(i >= PhraseDeck.builtin.count ? "AI 关卡" : "第 \(i + 1) 关").font(.caption.bold())
                                        .foregroundStyle(i >= PhraseDeck.builtin.count ? Theme.accentDark : Theme.muted)
                                    Spacer()
                                    if !open { Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.faint) }
                                }
                                Text(levels[i].title).font(.headline).foregroundStyle(open ? Theme.ink : Theme.faint)
                                HStack(spacing: 2) {
                                    ForEach(0..<3, id: \.self) { k in
                                        Image(systemName: k < r.stars ? "star.fill" : "star")
                                            .font(.caption)
                                            .foregroundStyle(k < r.stars ? Theme.accent : Theme.line)
                                    }
                                    Spacer()
                                    if r.best > 0 { Text("\(r.best)").font(.caption.monospacedDigit()).foregroundStyle(Theme.faint) }
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(open ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .disabled(!open)
                        .contextMenu {
                            if i >= PhraseDeck.builtin.count {
                                Button("删除这一关", role: .destructive) {
                                    PhraseDeck.removeCustom(id: levels[i].id)
                                    levels = PhraseDeck.all
                                }
                            }
                        }
                    }
                }
                Text("过一关（至少 1 星）解锁下一关。两种玩法分开算星。")
                    .font(.caption).foregroundStyle(Theme.faint)
            }
            .padding(20)
        }
        .background(Theme.ground)
        .fullScreenCover(item: $playing, onDismiss: { records = PhraseRecords.all() }) { box in
            PhraseGameView(levelIndex: box.index, mode: box.mode, levels: levels)
        }
        // 生成完等弹窗收起再进游戏，否则全屏页弹不出来
        .sheet(isPresented: $showAI, onDismiss: {
            if levels.count != PhraseDeck.all.count {
                levels = PhraseDeck.all
                playing = GameBox(index: levels.count - 1, mode: mode)
            }
        }) {
            AIPhraseLevelSheet { _ in }
        }
    }
}

// MARK: - 卡片墙

struct PhraseGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State var levelIndex: Int
    let mode: PhraseMode
    let levels: [PhraseLevel]

    enum CardState { case idle, right, wrong, retry, fixed }

    struct Outcome {
        let stars: Int
        let score: Int
        let maxCombo: Int
        let firstTry: Int
        let seconds: Int
        let record: Bool
    }

    @State private var speech = SpeechChecker()
    @State private var status: [CardState] = []
    @State private var queue: [Int] = []
    @State private var current: Int?
    @State private var listenStart: Date?
    @State private var running = false
    @State private var round = 1
    @State private var combo = 0
    @State private var maxCombo = 0
    @State private var score = 0
    @State private var gain: Int?
    @State private var firstWrong = 0
    @State private var startedAt: Date?
    @State private var shakes: [Int: Int] = [:]
    @State private var banner: String?
    @State private var message: String?
    @State private var outcome: Outcome?
    @State private var pulse = false
    /// 每次暂停 / 重开都换一个号，旧的回调自动作废
    @State private var flow = 0

    private var level: PhraseLevel { levels[levelIndex] }
    private var cards: [PhraseCard] { level.cards }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            comboBar
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(cards.indices, id: \.self) { i in cardView(i) }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 8)
            bottomPanel
        }
        .background(Theme.ground)
        .overlay {
            if let banner {
                Text(banner)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 18)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 22))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay { if let outcome { resultView(outcome) } }
        .animation(.spring(duration: 0.35), value: banner)
        .animation(.easeInOut(duration: 0.25), value: outcome == nil)
        .task {
            reset()
            _ = await SpeechChecker.requestPermissions()
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { pulse = true } }
        .onDisappear { halt() }
    }

    // MARK: 顶部

    private var topBar: some View {
        HStack {
            Button { halt(); dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40).background(Color.white, in: Circle())
            }
            .accessibilityLabel("退出")
            VStack(alignment: .leading, spacing: 0) {
                Text("第 \(levelIndex + 1) 关 · \(level.title)").font(.headline)
                Text(round == 1 ? mode.title : "第二轮 · 补错").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("\(score)")
                .font(Theme.en(26, .heavy))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: score)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var comboBar: some View {
        HStack(spacing: 8) {
            if combo >= 2 {
                Label("连击 ×\(combo)", systemImage: "flame.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(combo >= 5 ? Theme.accent : Theme.ink, in: Capsule())
                    .scaleEffect(combo >= 5 ? 1.08 : 1)
                    .transition(.scale)
            }
            if let gain {
                Text("+\(gain)").font(.subheadline.bold()).foregroundStyle(Theme.green)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer()
            Text("\(status.filter { $0 == .right || $0 == .fixed }.count) / \(cards.count)")
                .font(.caption.bold().monospacedDigit()).foregroundStyle(Theme.muted)
        }
        .frame(height: 34)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .animation(.spring(duration: 0.3), value: combo)
        .animation(.easeOut(duration: 0.3), value: gain)
    }

    // MARK: 卡片

    private func cardView(_ i: Int) -> some View {
        let card = cards[i]
        let s = i < status.count ? status[i] : .idle
        let active = current == i && running
        let revealed = s == .right || s == .fixed || s == .wrong
        let border: Color = active ? Theme.accent : (s == .right || s == .fixed ? Theme.green : (s == .wrong || s == .retry ? Color.red : Color.clear))
        let fill: Color = s == .right || s == .fixed ? Theme.greenTint : (s == .wrong ? Color.red.opacity(0.08) : Color.white)

        return Button { tap(i) } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3) {
                    if revealed {
                        Text(card.en).font(Theme.en(17, .bold)).foregroundStyle(Theme.ink)
                        Text(card.zh).font(.caption).foregroundStyle(Theme.muted)
                    } else if mode == .say {
                        Text(card.zh).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                    } else {
                        Image(systemName: active ? "waveform" : "speaker.wave.2")
                            .font(.title3).foregroundStyle(active ? Theme.accent : Theme.faint)
                            .symbolEffect(.variableColor.iterative, isActive: active && listenStart == nil)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 66)

                if !revealed && mode == .listen {
                    Text("\(i + 1)").font(.caption2.bold()).foregroundStyle(Theme.faint).padding(8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if active, let start = listenStart {
                    TimelineView(.periodic(from: start, by: 0.05)) { ctx in
                        let left = max(0, 1 - ctx.date.timeIntervalSince(start) / mode.seconds)
                        Circle().trim(from: 0, to: left)
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 18, height: 18)
                            .padding(8)
                    }
                }
            }
            .background(fill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(border, style: StrokeStyle(lineWidth: active ? 3 : 2, dash: s == .retry && !active ? [5, 4] : []))
                    .opacity(active ? (pulse ? 1 : 0.35) : 1)
            )
            .rotation3DEffect(.degrees(revealed ? 360 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(.easeInOut(duration: 0.45), value: revealed)
            .modifier(Shake(animatableData: CGFloat(shakes[i] ?? 0)))
            .animation(.linear(duration: 0.4), value: shakes[i] ?? 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(revealed ? "\(card.en)，\(card.zh)" : (mode == .say ? card.zh : "第 \(i + 1) 张"))
    }

    // MARK: 底部

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if let message {
                Text(message).font(.subheadline.bold()).foregroundStyle(Theme.accentDark)
            }
            if running, let i = current {
                let s = status[i]
                if s == .wrong || s == .right || s == .fixed {
                    VStack(spacing: 2) {
                        Text(cards[i].ex).font(Theme.en(16, .semibold))
                        Text(cards[i].exZh).font(.caption).foregroundStyle(Theme.muted)
                    }
                    .multilineTextAlignment(.center)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: listenStart == nil ? "speaker.wave.2.fill" : "mic.fill")
                            .foregroundStyle(listenStart == nil ? Theme.ink : Theme.accent)
                            .symbolEffect(.pulse, isActive: listenStart != nil)
                        Text(listenStart == nil ? "听…" : (mode == .listen ? "说出中文意思" : "说出英文"))
                            .font(.headline)
                    }
                    Text(speech.transcript.isEmpty ? " " : speech.transcript)
                        .font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Button("暂停") { pause() }
                    .font(.subheadline).foregroundStyle(Theme.muted)
            } else if outcome == nil {
                Text(startedAt == nil ? mode.hint : "已暂停，点卡片或继续").font(.subheadline).foregroundStyle(Theme.muted)
                InkButton(startedAt == nil ? "开始" : "继续", icon: "play.fill") { resume() }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 120)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: 结算

    private func resultView(_ o: Outcome) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { k in
                        Image(systemName: k < o.stars ? "star.fill" : "star")
                            .font(.system(size: 38))
                            .foregroundStyle(k < o.stars ? Theme.accent : Color(hex: 0x4A4E48))
                    }
                }
                Text(o.stars == 3 ? "全部一次答对！" : (o.stars == 2 ? "很稳" : "过关了")).font(.system(size: 26, weight: .black))
                if o.record { Tag(text: "新纪录", fg: .white, bg: Theme.accent) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    stat("\(o.score)", "得分")
                    stat("×\(o.maxCombo)", "最高连击")
                    stat("\(o.firstTry) / \(cards.count)", "一次答对")
                    stat(String(format: "%d:%02d", o.seconds / 60, o.seconds % 60), "用时")
                }
                VStack(spacing: 10) {
                    if levelIndex + 1 < levels.count {
                        InkButton("下一关", icon: "arrow.right") {
                            levelIndex += 1
                            reset()
                        }
                    }
                    HStack(spacing: 10) {
                        Button("再来一次") { reset() }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        Button("返回") { dismiss() }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                }
            }
            .foregroundStyle(.white)
            .padding(22)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 28))
            .padding(20)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.en(22, .heavy)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Color(hex: 0xA5AAA0))
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Theme.inkSoft, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: 流程

    private func reset() {
        halt()
        status = Array(repeating: .idle, count: cards.count)
        queue = Array(cards.indices)
        current = nil
        round = 1
        combo = 0
        maxCombo = 0
        score = 0
        gain = nil
        firstWrong = 0
        startedAt = nil
        shakes = [:]
        banner = nil
        message = nil
        outcome = nil
    }

    /// 停掉播音、录音和所有待执行的回调
    private func halt() {
        flow += 1
        running = false
        listenStart = nil
        speech.stop(notify: false)
        Speaker.shared.stop()
    }

    private func pause() {
        if let i = current, status[i] == .idle || status[i] == .retry { queue.insert(i, at: 0) }
        halt()
        current = nil
    }

    private func resume() {
        if startedAt == nil { startedAt = .now }
        running = true
        message = nil
        next()
    }

    /// 没开始或暂停时，点哪张就从哪张开始
    private func tap(_ i: Int) {
        guard !running, outcome == nil, queue.contains(i) else { return }
        queue.removeAll { $0 == i }
        queue.insert(i, at: 0)
        resume()
    }

    private func next() {
        guard running else { return }
        if queue.isEmpty { endRound(); return }
        play(queue.removeFirst())
    }

    private func play(_ i: Int) {
        current = i
        speech.clear()
        let f = flow
        switch mode {
        case .listen:
            Speaker.shared.speak(cards[i].en) {
                guard f == flow else { return }
                listen(i)
            }
        case .say:
            after(0.3, f) { listen(i) }
        }
    }

    private func listen(_ i: Int) {
        let card = cards[i]
        let f = flow
        speech.settle = 0
        speech.stopAfterSilence = 2
        speech.onTranscript = { text in
            guard f == flow, current == i else { return }
            if mode == .listen ? PhraseJudge.zh(card, text) : PhraseJudge.en(card, text) {
                speech.stop(notify: false)
                hit(i)
            }
        }
        speech.onStop = { _ in
            guard f == flow, current == i else { return }
            miss(i)
        }
        listenStart = .now
        let ok = speech.start(hints: mode == .listen ? card.ok : [card.en],
                              timeout: mode.seconds,
                              locale: mode == .listen ? "zh-CN" : "en-US")
        if !ok {
            pause()
            message = "语音识别暂不可用，检查网络和麦克风权限"
        }
    }

    private func hit(_ i: Int) {
        let fast = listenStart.map { Date.now.timeIntervalSince($0) < 2 } ?? false
        listenStart = nil
        status[i] = round == 1 ? .right : .fixed
        combo += 1
        maxCombo = max(maxCombo, combo)
        var g = 100 + min(combo - 1, 10) * 20 + (fast ? 50 : 0)
        if round == 2 { g /= 2 }
        score += g
        gain = g
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        if combo == 5 || combo == 10 { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
        let f = flow
        if mode == .say {
            Speaker.shared.speak(cards[i].en) { after(0.3, f) { gain = nil; next() } }
        } else {
            after(0.9, f) { gain = nil; next() }
        }
    }

    private func miss(_ i: Int) {
        listenStart = nil
        if round == 1 { firstWrong += 1 }
        status[i] = .wrong
        combo = 0
        gain = nil
        shakes[i, default: 0] += 1
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        let f = flow
        // 答错：原声再读一遍，看清楚再往下
        Speaker.shared.speak(cards[i].en, slow: true) {
            after(1.0, f) { next() }
        }
    }

    private func endRound() {
        let wrong = status.indices.filter { status[$0] == .wrong }
        if round == 1 && !wrong.isEmpty {
            round = 2
            for i in wrong { status[i] = .retry }
            queue = wrong
            current = nil
            banner = "第二轮 · 补 \(wrong.count) 张"
            let f = flow
            after(1.4, f) {
                banner = nil
                next()
            }
        } else {
            finish()
        }
    }

    private func finish() {
        let seconds = Int(Date.now.timeIntervalSince(startedAt ?? .now))
        let stars = firstWrong == 0 ? 3 : (firstWrong <= 2 ? 2 : 1)
        let record = PhraseRecords.save(level: level.id, mode: mode, stars: stars, score: score)
        halt()
        current = nil
        outcome = Outcome(stars: stars, score: score, maxCombo: maxCombo,
                          firstTry: cards.count - firstWrong, seconds: seconds, record: record)
    }

    private func after(_ seconds: Double, _ f: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard f == flow else { return }
            action()
        }
    }
}

/// 答错时卡片左右抖动
private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
