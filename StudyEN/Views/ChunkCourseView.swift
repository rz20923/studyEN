import SwiftUI
import SwiftData
import UIKit

// MARK: - 数据：第 1 个月词块打底

/// 一个词块：只记一个意思
struct CourseChunk: Codable, Hashable, Identifiable {
    let en: String
    let zh: String
    /// 整块音译（按连读后的读法）
    let yi: String
    var id: String { en.lowercased() }
    /// 朗读和识别用：去掉省略号
    var spoken: String { en.replacingOccurrences(of: "...", with: "").trimmingCharacters(in: .whitespaces) }
}

enum ChunkCourse {
    static let totalDays = 30

    struct Day: Codable {
        let day: Int
        let title: String
        let items: [CourseChunk]
    }

    static let days: [Day] = {
        guard let url = Bundle.main.url(forResource: "chunk_course", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let days = try? JSONDecoder().decode([Day].self, from: data) else { return [] }
        return days
    }()

    static let byID: [String: CourseChunk] = Dictionary(days.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func content(_ day: Int) -> Day? { days.first { $0.day == day } }

    /// 某一天的学习记录：done 是已刷完的页
    struct Record: Codable, Equatable {
        var date: String
        var day: Int
        var done: [String] = []
        var checkedIn = false
        /// 这一天额外重学的顽固词块
        var relearn: [String] = []
    }

    struct State: Codable {
        var records: [Record] = []
        var wrongs: [String: Int] = [:]
        var pending: [String] = []
    }

    private static let key = "chunkCourse"

    static var state: State {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let s = try? JSONDecoder().decode(State.self, from: data) else { return State() }
            return s
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: key) }
        }
    }

    private static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    /// 今天是第几天：打了卡才进入下一天，没打卡第二天接着做同一天
    static func today() -> Record {
        var s = state
        let t = todayKey
        guard var last = s.records.last else {
            let r = Record(date: t, day: 1)
            s.records = [r]
            state = s
            return r
        }
        if last.date == t { return last }
        if last.checkedIn {
            let r = Record(date: t, day: last.day + 1, relearn: s.pending)
            s.pending = []
            s.records.append(r)
            state = s
            return r
        }
        last.date = t
        s.records[s.records.count - 1] = last
        state = s
        return last
    }

    static func save(_ r: Record) {
        var s = state
        if let i = s.records.lastIndex(where: { $0.day == r.day }) { s.records[i] = r } else { s.records.append(r) }
        state = s
    }

    static func newChunks(_ r: Record) -> [CourseChunk] {
        (content(r.day)?.items ?? []) + r.relearn.compactMap { byID[$0] }
    }

    struct ReviewSet {
        let label: String
        let key: String
        let chunks: [CourseChunk]
    }

    /// 复习：昨天的 + 大前天的
    static func reviewSets(_ r: Record) -> [ReviewSet] {
        let s = state
        return [(1, "昨天"), (3, "大前天")].compactMap { back, label in
            let d = r.day - back
            guard d >= 1 else { return nil }
            let relearn = s.records.first { $0.day == d }?.relearn ?? []
            let chunks = (content(d)?.items ?? []) + relearn.compactMap { byID[$0] }
            return chunks.isEmpty ? nil : ReviewSet(label: "\(label) · 第 \(d) 天", key: "r\(back)", chunks: chunks)
        }
    }

    /// 复习时说“不会”累计 3 次：第二天当新词块重学
    static func markWrong(_ id: String) {
        var s = state
        s.wrongs[id, default: 0] += 1
        if s.wrongs[id, default: 0] >= 3 {
            s.wrongs[id] = 0
            if !s.pending.contains(id) { s.pending.append(id) }
        }
        state = s
    }

    static func pages(_ chunks: [CourseChunk]) -> [[CourseChunk]] {
        stride(from: 0, to: chunks.count, by: 10).map { Array(chunks[$0..<min($0 + 10, chunks.count)]) }
    }

    /// 音译拐杖慢慢撤掉：2 = 显示，1 = 变淡，0 = 点一下才显示
    static func yiLevel(day: Int) -> Int { day <= 7 ? 2 : (day <= 14 ? 1 : 0) }

    static func cheer(day: Int) -> String {
        switch day {
        case 1...3: return "前 3 天最难熬，是正常的。熬过去就轻松了。"
        case 4...7: return "再坚持几天，第 7 天左右它会变成习惯。"
        case 8...14: return "到第 14 天，你会发现不刷反而难受。"
        default: return ""
        }
    }

    /// 打卡判定：词按顺序说出来即可；长句也接受整体相似度
    static func matches(_ chunk: CourseChunk, _ text: String) -> Bool {
        let target = PhraseMatcher.words(chunk.spoken)
        if PhraseJudge.ordered(target, in: text) { return true }
        return target.count > 3 && PhraseMatcher.readingScore(chunk.spoken, transcript: text) >= 0.6
    }
}

// MARK: - 今天：新词块 / 复习 / 打卡

struct ChunkDayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("chunkPhase") private var chunkPhase = true
    @State private var record = ChunkCourse.today()
    @State private var drill: DrillBox?
    @State private var testing = false
    @State private var elapsed = StudyTimer.seconds

    struct DrillBox: Identifiable {
        let id: String
        let title: String
        let chunks: [CourseChunk]
        let review: Bool
    }

    private var newPages: [[CourseChunk]] { ChunkCourse.pages(ChunkCourse.newChunks(record)) }
    private var reviews: [ChunkCourse.ReviewSet] { ChunkCourse.reviewSets(record) }

    private var pageIDs: [String] {
        newPages.indices.map { "n\($0)" } + reviews.flatMap { r in ChunkCourse.pages(r.chunks).indices.map { "\(r.key)-\($0)" } }
    }

    private var ready: Bool { !newPages.isEmpty && pageIDs.allSatisfy(record.done.contains) }

    var body: some View {
        let content = ChunkCourse.content(record.day)
        let newCount = ChunkCourse.newChunks(record).count
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(content)

                if record.day > ChunkCourse.totalDays {
                    graduate
                } else if newPages.isEmpty {
                    Text("第 \(record.day) 天的词块还在制作中。先把下面的复习刷完。")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }

                if !newPages.isEmpty {
                    sectionTitle("① 新词块 · \(newCount) 个", "每页刷到会：听读 → 听音猜意思 → 看中文说英文")
                    ForEach(newPages.indices, id: \.self) { p in
                        pageRow(id: "n\(p)", title: "第 \(p + 1) 页", chunks: newPages[p], review: false)
                    }
                }

                if !reviews.isEmpty {
                    sectionTitle("② 复习 · 昨天 + 大前天", "直接从听音猜意思开始，一页一两分钟")
                    ForEach(reviews, id: \.key) { r in
                        let pages = ChunkCourse.pages(r.chunks)
                        ForEach(pages.indices, id: \.self) { p in
                            pageRow(id: "\(r.key)-\(p)", title: "\(r.label)\(pages.count > 1 ? " · \(p + 1)" : "")", chunks: pages[p], review: true)
                        }
                    }
                }

                if !newPages.isEmpty {
                    sectionTitle("③ 打卡", "看中文说英文，答对 80% 就打卡")
                    checkIn
                }
            }
            .padding(20)
        }
        .background(Theme.ground)
        .fullScreenCover(item: $drill) { box in
            PageDrillView(title: box.title, chunks: box.chunks, review: box.review,
                          yiLevel: ChunkCourse.yiLevel(day: record.day)) {
                if !record.done.contains(box.id) { record.done.append(box.id) }
                ChunkCourse.save(record)
            }
        }
        .fullScreenCover(isPresented: $testing) {
            ChunkTestView(chunks: ChunkCourse.newChunks(record), yiLevel: ChunkCourse.yiLevel(day: record.day)) {
                record.checkedIn = true
                ChunkCourse.save(record)
                context.studyDay().checkedIn = true
                try? context.save()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { record = ChunkCourse.today() }
        }
        // 今天的学习计时：只在前台、还没打卡时走
        .task(id: scenePhase == .active && !record.checkedIn) {
            guard scenePhase == .active, !record.checkedIn else { elapsed = StudyTimer.seconds; return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                StudyTimer.add(1)
                elapsed = StudyTimer.seconds
            }
        }
    }

    private func header(_ content: ChunkCourse.Day?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("DAY \(record.day)").font(Theme.en(22, .heavy))
                Text("词块打底\(content.map { " · \($0.title)" } ?? "")")
                    .font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                Label(StudyTimer.text(elapsed), systemImage: "timer")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xDADDD5))
                    Capsule().fill(Theme.ink)
                        .frame(width: geo.size.width * min(1, Double(record.day - (record.checkedIn ? 0 : 1)) / Double(ChunkCourse.totalDays)))
                }
            }
            .frame(height: 5)
            Text("第 1 个月：先把最常用的词块听通、读通、记住，第 31 天起练句子")
                .font(.caption).foregroundStyle(Theme.faint)
            let cheer = ChunkCourse.cheer(day: record.day)
            if !cheer.isEmpty {
                Label(cheer, systemImage: "flame.fill")
                    .font(.footnote.bold())
                    .foregroundStyle(Theme.accentDark)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func sectionTitle(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(sub).font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.top, 6)
    }

    private func pageRow(id: String, title: String, chunks: [CourseChunk], review: Bool) -> some View {
        let done = record.done.contains(id)
        return Button {
            drill = DrillBox(id: id, title: title, chunks: chunks, review: review)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark" : "play.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(done ? Color.white : Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(done ? Theme.ink : Theme.accentTint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(chunks.prefix(3).map(\.en).joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Text(done ? "已刷完" : "\(chunks.count) 个").font(.caption).foregroundStyle(Theme.faint)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var checkIn: some View {
        if record.checkedIn {
            VStack(alignment: .leading, spacing: 6) {
                Label("今天打卡了", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.green)
                Text("明天是第 \(record.day + 1) 天。碎片时间可以把上面任何一页再刷一遍。")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.greenTint, in: RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                InkButton("打卡测试", icon: "mic.fill") { testing = true }
                    .disabled(!ready)
                    .opacity(ready ? 1 : 0.4)
                if !ready {
                    Text("还有 \(pageIDs.filter { !record.done.contains($0) }.count) 页没刷完，刷完就能打卡")
                        .font(.caption).foregroundStyle(Theme.faint)
                }
            }
        }
    }

    private var graduate: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("30 天词块打底完成").font(.title2.bold())
            Text("耳朵和嘴巴已经打通，接下来用这些词块练句子和对话。").foregroundStyle(Theme.muted)
            InkButton("进入句子训练", icon: "arrow.right") { chunkPhase = false }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - 一页 10 个，刷几轮

struct PageDrillView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let chunks: [CourseChunk]
    let review: Bool
    let yiLevel: Int
    let onFinish: () -> Void

    enum Round { case learn, guess, say }

    @State private var round: Round = .learn
    /// 本轮不会的，再刷第几遍
    @State private var again = 0
    @State private var queue: [Int] = []
    @State private var pos = 0
    @State private var flipped = false
    @State private var missed: [Int] = []
    @State private var marks: [Int: Bool] = [:]
    @State private var showYi = true
    @State private var finished = false
    @State private var totalMissed = 0
    @State private var flow = 0

    private var current: Int? { pos < queue.count ? queue[pos] : nil }

    private var roundNumber: Int {
        switch round {
        case .learn: return 1
        case .guess: return 2
        case .say: return 3
        }
    }

    private var roundTitle: String {
        let base: String
        switch round {
        case .learn: base = "听读：听一遍，跟着读一遍"
        case .guess: base = "听音猜意思：心里说出中文，再翻开"
        case .say: base = "看中文说英文：说出来，再翻开"
        }
        return again > 0 ? "不会的再刷一遍 · \(base)" : base
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { halt(); dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40).background(Color.white, in: Circle())
                }
                .accessibilityLabel("退出")
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.headline)
                    Text(finished ? "刷完了" : "第 \(roundNumber) 轮 / 3").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if finished {
                finishView
            } else {
                dots.padding(.top, 14)
                Text(roundTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accentDark)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 12)
                if let i = current {
                    card(chunks[i])
                        .id("\(round)-\(again)-\(pos)")
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        .padding(.horizontal, 20)
                }
                Spacer(minLength: 12)
                controls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .background(Theme.ground)
        .animation(.easeInOut(duration: 0.25), value: pos)
        .task { start(review ? .guess : .learn, Array(chunks.indices)) }
        .onDisappear { halt() }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(chunks.indices, id: \.self) { i in
                let inRound = queue.contains(i)
                let color: Color = current == i ? Theme.accent
                    : (marks[i] == true ? Theme.green : (marks[i] == false ? Color.red : (inRound ? Color(hex: 0xDADDD5) : Theme.ink.opacity(0.25))))
                Capsule().fill(color).frame(height: 6)
            }
        }
        .padding(.horizontal, 20)
    }

    private func card(_ c: CourseChunk) -> some View {
        let showEnglish = round == .learn || flipped
        let showChinese = flipped || (round == .say)
        return Button { if round != .learn && !flipped { flip() } } label: {
            VStack(spacing: 14) {
                if showEnglish {
                    Text(c.en)
                        .font(Theme.en(32, .heavy))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                    yiView(c)
                } else if round == .guess {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text("想想它的意思，点一下翻开").font(.subheadline).foregroundStyle(Theme.muted)
                }
                if showChinese {
                    Text(c.zh)
                        .font(.system(size: round == .say && !flipped ? 30 : 20, weight: .bold))
                        .foregroundStyle(round == .say && !flipped ? Theme.ink : Theme.muted)
                        .multilineTextAlignment(.center)
                    if round == .say && !flipped {
                        Text("说出英文，点一下翻开").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 280)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28))
            .rotation3DEffect(.degrees(flipped ? 360 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(.easeInOut(duration: 0.4), value: flipped)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func yiView(_ c: CourseChunk) -> some View {
        if showYi {
            Text(c.yi)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.accent)
                .opacity(yiLevel == 1 ? 0.45 : 1)
        } else {
            Button("显示音译") { showYi = true }
                .font(.caption).foregroundStyle(Theme.faint)
        }
    }

    @ViewBuilder private var controls: some View {
        if round == .learn {
            HStack(spacing: 12) {
                RoundIconButton(systemName: "arrow.counterclockwise", label: "再听") { replay(slow: false) }
                RoundIconButton(systemName: "tortoise.fill", label: "慢速") { replay(slow: true) }
                InkButton(flipped ? "下一个" : "跟读一遍…", icon: flipped ? "arrow.right" : "mouth") { advance() }
            }
        } else if !flipped {
            HStack(spacing: 12) {
                if round == .guess {
                    RoundIconButton(systemName: "arrow.counterclockwise", label: "再听") { replay(slow: false) }
                }
                InkButton("翻开", icon: "hand.tap") { flip() }
            }
        } else {
            HStack(spacing: 12) {
                Button { mark(false) } label: {
                    Text("不会").font(.headline).foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.red.opacity(0.4), lineWidth: 2))
                }
                .buttonStyle(.plain)
                InkButton("会", icon: "checkmark") { mark(true) }
            }
        }
    }

    private var finishView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Theme.green)
            Text("这一页刷完了").font(.system(size: 28, weight: .black))
            Text(totalMissed == 0 ? "一个都没卡住，厉害" : "卡住的 \(totalMissed) 次都多刷了几遍")
                .foregroundStyle(Theme.muted)
            Spacer()
            InkButton("完成", icon: "checkmark") {
                onFinish()
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: 流程

    private func start(_ r: Round, _ indices: [Int]) {
        round = r
        queue = indices
        pos = 0
        missed = []
        marks = [:]
        present()
    }

    private func present() {
        flow += 1
        flipped = false
        showYi = yiLevel > 0
        guard let i = current else { return }
        let c = chunks[i]
        let f = flow
        switch round {
        case .learn:
            // 读完留出跟读的时间，再翻出中文
            Speaker.shared.speak(c.spoken) {
                after(2.2, f) { flipped = true }
            }
        case .guess:
            Speaker.shared.speak(c.spoken)
        case .say:
            break
        }
    }

    private func replay(slow: Bool) {
        guard let i = current else { return }
        flow += 1
        let f = flow
        Speaker.shared.speak(chunks[i].spoken, slow: slow) {
            if round == .learn { after(2.2, f) { flipped = true } }
        }
    }

    private func flip() {
        guard let i = current else { return }
        flipped = true
        if round == .say { Speaker.shared.speak(chunks[i].spoken) }
    }

    private func mark(_ known: Bool) {
        guard let i = current else { return }
        marks[i] = known
        if !known {
            missed.append(i)
            totalMissed += 1
            if review { ChunkCourse.markWrong(chunks[i].id) }
        }
        advance()
    }

    private func advance() {
        Speaker.shared.stop()
        pos += 1
        if pos < queue.count { present() } else { endRound() }
    }

    private func endRound() {
        switch round {
        case .learn:
            again = 0
            start(.guess, Array(chunks.indices))
        case .guess, .say:
            if !missed.isEmpty && again < 2 {
                again += 1
                start(round, missed.shuffled())
            } else if round == .guess {
                again = 0
                start(.say, Array(chunks.indices).shuffled())
            } else {
                halt()
                finished = true
            }
        }
    }

    private func halt() {
        flow += 1
        Speaker.shared.stop()
    }

    private func after(_ seconds: Double, _ f: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard f == flow else { return }
            action()
        }
    }
}

// MARK: - 打卡测试：看中文说英文

struct ChunkTestView: View {
    @Environment(\.dismiss) private var dismiss
    let chunks: [CourseChunk]
    let yiLevel: Int
    let onPass: () -> Void

    @State private var speech = SpeechChecker()
    @State private var order: [Int] = []
    @State private var pos = 0
    @State private var tries = 0
    @State private var right: Set<Int> = []
    @State private var shown = false
    @State private var correct = false
    @State private var feedback: String?
    @State private var roundOver = false
    @State private var passed = false
    @State private var flow = 0

    private var current: Int? { pos < order.count ? order[pos] : nil }
    private var needed: Int { Int((Double(chunks.count) * 0.8).rounded(.up)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { stopAll(); dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40).background(Color.white, in: Circle())
                }
                .accessibilityLabel("退出")
                VStack(alignment: .leading, spacing: 0) {
                    Text("打卡测试").font(.headline)
                    Text("答对 \(right.count) / 需要 \(needed)").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("\(min(pos + 1, max(order.count, 1))) / \(order.count)")
                    .font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if passed {
                resultView(pass: true)
            } else if roundOver {
                resultView(pass: false)
            } else if let i = current {
                let c = chunks[i]
                Spacer()
                VStack(spacing: 14) {
                    Text(c.zh).font(.system(size: 32, weight: .black)).multilineTextAlignment(.center)
                    if shown || correct {
                        Text(c.en).font(Theme.en(28, .heavy)).foregroundStyle(correct ? Theme.green : Theme.ink)
                        if yiLevel > 0 || shown { Text(c.yi).font(.headline).foregroundStyle(Theme.accent) }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: 240)
                .background(correct ? Theme.greenTint : Color.white, in: RoundedRectangle(cornerRadius: 28))
                .padding(.horizontal, 20)

                Text(speech.transcript.isEmpty ? " " : speech.transcript)
                    .font(Theme.en(16)).foregroundStyle(Theme.muted).padding(.top, 14)
                if let feedback {
                    Text(feedback).font(.subheadline.bold()).foregroundStyle(Theme.accentDark).padding(.top, 4)
                }
                Spacer()
                if shown {
                    HStack(spacing: 12) {
                        RoundIconButton(systemName: "speaker.wave.2.fill", label: "再听") { Speaker.shared.speak(c.spoken) }
                        InkButton("跟读一遍，下一个", icon: "arrow.right") { next() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                } else {
                    MicButton(isRecording: speech.isRecording) {
                        if speech.isRecording { speech.stop() } else { listen() }
                    }
                    .padding(.bottom, 30)
                    .disabled(correct)
                }
            }
        }
        .background(Theme.ground)
        .task {
            _ = await SpeechChecker.requestPermissions()
            order = Array(chunks.indices).shuffled()
            present()
        }
        .onDisappear { stopAll() }
    }

    private func resultView(pass: Bool) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: pass ? "checkmark.seal.fill" : "arrow.clockwise.circle.fill")
                .font(.system(size: 64)).foregroundStyle(pass ? Theme.green : Theme.accent)
            Text(pass ? "打卡成功" : "还差一点").font(.system(size: 30, weight: .black))
            Text(pass ? "今天的 \(chunks.count) 个词块，你答对了 \(right.count) 个"
                      : "答对 \(right.count) 个，需要 \(needed) 个。把错的再测一遍就行")
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            if pass {
                InkButton("完成", icon: "checkmark") { dismiss() }
                    .padding(.horizontal, 20).padding(.bottom, 24)
            } else {
                InkButton("再测错的 \(chunks.count - right.count) 个", icon: "mic.fill") {
                    order = chunks.indices.filter { !right.contains($0) }.shuffled()
                    pos = 0
                    roundOver = false
                    present()
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
    }

    private func present() {
        flow += 1
        tries = 0
        shown = false
        correct = false
        feedback = nil
        speech.clear()
        let f = flow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard f == flow, current != nil else { return }
            listen()
        }
    }

    private func listen() {
        guard let i = current else { return }
        let c = chunks[i]
        let f = flow
        feedback = nil
        speech.settle = 0.6
        speech.stopAfterSilence = 2
        speech.onTranscript = { text in
            guard f == flow, !correct, ChunkCourse.matches(c, text) else { return }
            speech.stop(notify: false)
            correct = true
            right.insert(i)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard f == flow else { return }
                next()
            }
        }
        speech.onStop = { _ in
            guard f == flow, !correct else { return }
            tries += 1
            if tries >= 2 {
                shown = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                Speaker.shared.speak(c.spoken)
            } else {
                feedback = "没听出来，点麦克风再说一次"
            }
        }
        if !speech.start(hints: [c.spoken], timeout: 8) {
            feedback = "语音识别暂不可用，检查网络和麦克风权限"
        }
    }

    private func next() {
        stopAll()
        pos += 1
        if pos < order.count {
            present()
        } else if right.count >= needed {
            passed = true
            onPass()
        } else {
            roundOver = true
        }
    }

    private func stopAll() {
        flow += 1
        speech.stop(notify: false)
        Speaker.shared.stop()
    }
}

/// 训练标签：第 1 个月先做词块打底，之后是句子训练
struct TrainGate: View {
    @AppStorage("chunkPhase") private var chunkPhase = true

    var body: some View {
        if chunkPhase { ChunkDayView() } else { TrainView() }
    }
}
