import SwiftUI
import SwiftData

/// 训练标签：打开就是今天进行到的那一步（没有单独的首页）
struct TrainView: View {
    @Environment(ChunkLibrary.self) private var library
    @Query private var progresses: [ChunkProgress]
    @Query private var days: [StudyDay]
    @Query private var topicProgress: [TopicProgress]
    @Query private var enduranceSets: [EnduranceSet]

    @State private var cover: Cover?
    @State private var extra: ExtraBox?
    @State private var elapsed = StudyTimer.seconds
    @Environment(\.scenePhase) private var scenePhase

    enum Cover: Identifiable {
        case boss(Topic), endurance(Int), done
        var id: String {
            switch self {
            case .boss(let t): return "boss-\(t.id)"
            case .endurance: return "endurance"
            case .done: return "done"
            }
        }
    }

    enum Step { case warmup, unit(Topic, TopicUnit, Int), boss(Topic), endurance, exam, done }

    struct DayState {
        var trainingDay = 1
        var streak = 0
        var checkedIn = false
        var examTried = false
        var due: [QuizItem] = []
        var topic: Topic?
        var remaining: [TopicUnit] = []
        var bossDone = true
        var enduranceTarget: Double = 10
        var enduranceBest: Double = 0
        var learnedToday: [(topic: Topic, unit: TopicUnit)] = []
        var learnedOlder: [(topic: Topic, unit: TopicUnit)] = []

        var done: [Bool] {
            [due.isEmpty, remaining.isEmpty, bossDone, enduranceBest >= enduranceTarget, checkedIn]
        }

        var step: Step {
            if !due.isEmpty { return .warmup }
            if let topic, let u = remaining.first {
                return .unit(topic, u, topic.units.count - remaining.count + 1)
            }
            if let topic, !bossDone { return .boss(topic) }
            if enduranceBest < enduranceTarget { return .endurance }
            if !checkedIn { return .exam }
            return .done
        }
    }

    private var state: DayState {
        let cal = Calendar.current
        var s = DayState()
        let today = days.first { cal.isDateInToday($0.day) }
        s.checkedIn = today?.checkedIn ?? false
        s.examTried = (today?.examAttempts ?? 0) > 0
        let checkedDays = days.filter(\.checkedIn).count
        s.trainingDay = s.checkedIn ? checkedDays : checkedDays + 1

        let checkedSet = Set(days.filter(\.checkedIn).map(\.day))
        var cursor = cal.startOfDay(for: .now)
        if !checkedSet.contains(cursor) { cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        while checkedSet.contains(cursor) {
            s.streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        // 只看属于课题的进度（旧版语块的进度不参与）
        let unitProgress = progresses.filter { library.unit(id: $0.chunkID) != nil }
        let learned = Set(unitProgress.map(\.chunkID))
        let now = Date.now
        s.due = unitProgress.filter { $0.dueDate <= now }.compactMap { library.unit(id: $0.chunkID) }.map(QuizItem.random)
        s.learnedToday = unitProgress.filter { cal.isDateInToday($0.introducedDate) }.compactMap { library.unit(id: $0.chunkID) }
        s.learnedOlder = unitProgress.filter { !cal.isDateInToday($0.introducedDate) }.compactMap { library.unit(id: $0.chunkID) }

        // 每天一个新课题：今天已经通关了一个，就不再开新的
        let passed = Set(topicProgress.filter(\.bossPassed).map(\.topicID))
        let passedToday = topicProgress.first { $0.bossPassed && $0.bossDate.map(cal.isDateInToday) == true }
        if let id = passedToday?.topicID {
            s.topic = library.topics.first { $0.id == id }
        } else {
            s.topic = library.topics.first { !passed.contains($0.id) }
        }
        if let topic = s.topic {
            s.remaining = topic.units.filter { !learned.contains($0.id) }
            s.bossDone = passed.contains(topic.id)
        }

        s.enduranceTarget = Endurance.target(day: s.trainingDay)
        s.enduranceBest = enduranceSets.filter { cal.isDateInToday($0.date) }.map(\.speakingSeconds).max() ?? 0
        return s
    }

    private var examItems: [QuizItem] {
        let s = state
        var pairs = s.learnedToday + s.learnedOlder.shuffled().prefix(5)
        if pairs.isEmpty { pairs = Array((s.learnedOlder).shuffled().prefix(8)) }
        return pairs.map(QuizItem.random)
    }

    var body: some View {
        let s = state
        let step = s.step
        VStack(spacing: 0) {
            DayHeader(day: s.trainingDay, label: label(step, s), streak: s.streak, done: s.done, current: index(step), elapsed: StudyTimer.text(elapsed))
            switch step {
            case .warmup:
                VStack(spacing: 0) {
                    if s.examTried && !s.checkedIn {
                        Text("测试差一点，先把错题说对，再重考")
                            .font(.footnote.bold()).foregroundStyle(Theme.accentDark)
                            .padding(.top, 10)
                    }
                    FrameQuizView(mode: .review, items: s.due)
                }
            case .unit(let topic, let unit, _):
                UnitFlowView(topic: topic, unit: unit).id(unit.id)
            case .boss(let topic):
                startCard(icon: "bubble.left.and.bubble.right.fill", title: "对话演练", subtitle: topic.boss.role, button: "开始对话") {
                    cover = .boss(topic)
                }
            case .endurance:
                startCard(icon: "mic.fill", title: "连续开口",
                          subtitle: "\(Endurance.topic(day: s.trainingDay).zh) · 目标 \(Endurance.secondsText(s.enduranceTarget))",
                          button: "开始说") {
                    cover = .endurance(s.trainingDay)
                }
            case .exam:
                FrameQuizView(mode: .exam, items: examItems) { passed in
                    if passed { cover = .done }
                }
                .id("exam-\(days.first { Calendar.current.isDateInToday($0.day) }?.examAttempts ?? 0)")
            case .done:
                doneCard(s)
            }
        }
        .background(Theme.ground)
        .fullScreenCover(item: $cover) { c in
            switch c {
            case .boss(let topic): BossView(topic: topic)
            case .endurance(let day): EnduranceSessionView(trainingDay: day, suggestions: [])
            case .done: DoneView()
            }
        }
        .sheet(item: $extra) { box in
            FrameQuizView(mode: .extra, items: box.items) { _ in extra = nil }
                .background(Theme.ground)
                .presentationDetents([.large])
        }
        .task(id: s.checkedIn) { Reminder.refresh(checkedInToday: s.checkedIn) }
        // 今天的学习计时：只在前台、还没打卡时走
        .task(id: scenePhase == .active && !s.checkedIn) {
            guard scenePhase == .active, !s.checkedIn else { elapsed = StudyTimer.seconds; return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                StudyTimer.add(1)
                elapsed = StudyTimer.seconds
            }
        }
    }

    struct ExtraBox: Identifiable {
        let id = UUID()
        let items: [QuizItem]
    }

    private func index(_ step: Step) -> Int? {
        switch step {
        case .warmup: return 0
        case .unit: return 1
        case .boss: return 2
        case .endurance: return 3
        case .exam: return 4
        case .done: return nil
        }
    }

    private func label(_ step: Step, _ s: DayState) -> String {
        switch step {
        case .warmup: return "热身 · 还剩 \(s.due.count) 个"
        case .unit(let t, _, let n): return "新课题 · \(t.title) \(n)/\(t.units.count)"
        case .boss(let t): return "对话 · \(t.title)"
        case .endurance: return "连续开口"
        case .exam: return "达标测试"
        case .done: return "今日已达标"
        }
    }

    private func startCard(icon: String, title: String, subtitle: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28)).foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64).background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 20))
            Text(title).font(.system(size: 26, weight: .black))
            Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            InkButton(button, icon: "play.fill", action: action).padding(20)
        }
    }

    private func doneCard(_ s: DayState) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Theme.green)
            Text("今天的训练完成了").font(.system(size: 26, weight: .black))
            Text("已打卡，明天见").foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                let learned = s.learnedToday + s.learnedOlder
                if !learned.isEmpty {
                    Button("加练复习") { extra = ExtraBox(items: Array(learned.shuffled().prefix(10)).map(QuizItem.random)) }
                        .buttonStyle(.bordered).tint(Theme.ink)
                }
                Button("再练开口") { cover = .endurance(s.trainingDay) }
                    .buttonStyle(.bordered).tint(Theme.ink)
            }
            .padding(.top, 8)
            Spacer()
        }
    }
}

/// 今日达标：全黑的仪式感页面
struct DoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChunkLibrary.self) private var library
    @Query private var days: [StudyDay]
    @Query private var progresses: [ChunkProgress]
    @Query private var enduranceSets: [EnduranceSet]
    @Query private var topicProgress: [TopicProgress]

    var body: some View {
        let cal = Calendar.current
        let checked = days.filter(\.checkedIn).count
        let todaySets = enduranceSets.filter { cal.isDateInToday($0.date) }
        let total = todaySets.map(\.speakingSeconds).reduce(0, +)
        let best = todaySets.map(\.speakingSeconds).max() ?? 0
        let learnedToday = progresses.filter { cal.isDateInToday($0.introducedDate) }.compactMap { library.unit(id: $0.chunkID) }
        let passed = Set(topicProgress.filter(\.bossPassed).map(\.topicID))
        let next = library.topics.first { !passed.contains($0.id) }

        VStack(spacing: 0) {
            VStack(spacing: 16) {
                BlocksLogo(size: 96)
                Text("第 \(checked) 天").font(.footnote).foregroundStyle(Color(hex: 0xA5AAA0)).tracking(2)
                Text("今天达标了").font(.system(size: 34, weight: .black))
                Text("又叠上一块").foregroundStyle(Color(hex: 0xC9CDC4))
            }
            .padding(.top, 60)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                stat(Endurance.secondsText(total), "今天开口总时长")
                stat(Endurance.secondsText(best), "最长一次连续开口")
                stat("\(learnedToday.count)", "新学会的句子框架")
                stat("\(passed.count)", "通关的对话")
                stat(StudyTimer.text(StudyTimer.seconds), "今天学习用时")
            }
            .padding(.top, 34)

            if let pick = learnedToday.first {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今天学会的一句").font(.caption).foregroundStyle(Color(hex: 0xA5AAA0))
                        Text(pick.unit.example).font(Theme.en(17, .bold))
                    }
                    Spacer()
                    Button { Speaker.shared.speak(pick.unit.example) } label: {
                        Image(systemName: "play.fill").foregroundStyle(Theme.ink).frame(width: 44, height: 44).background(Color.white, in: Circle())
                    }
                    .accessibilityLabel("播放")
                }
                .padding(16)
                .background(Theme.inkSoft, in: RoundedRectangle(cornerRadius: 18))
                .padding(.top, 14)
            }

            Spacer()
            if let next {
                Text("明天：\(next.title)").font(.footnote).foregroundStyle(Color(hex: 0xA5AAA0)).padding(.bottom, 12)
            }
            Button { dismiss() } label: {
                Text("完成").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 22)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.en(24, .heavy))
            Text(label).font(.caption).foregroundStyle(Color(hex: 0xA5AAA0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.inkSoft, in: RoundedRectangle(cornerRadius: 18))
    }
}
