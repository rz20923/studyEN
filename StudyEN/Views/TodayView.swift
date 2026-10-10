import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(ChunkLibrary.self) private var library
    @Query private var progresses: [ChunkProgress]
    @Query(sort: \StudyDay.day, order: .reverse) private var days: [StudyDay]
    @Query private var phaseExams: [PhaseExam]
    @Query private var drillProgress: [DrillProgress]
    @Query private var enduranceSets: [EnduranceSet]

    @State private var session: ActiveSession?

    struct ActiveSession: Identifiable {
        let id = UUID()
        /// nil = 语序造句
        let mode: TrainingMode?
        let chunks: [Chunk]
        var drills: [WordOrderDrill] = []
        var endurance = false
    }

    /// 今天的任务状态，全部由已保存的数据推导，退出重进不会丢进度
    private struct DailyState {
        var trainingDay: Int
        var checkedInDays: Int
        var checkedIn: Bool
        var examScore: Double
        var examAttempts: Int
        var newChunks: [Chunk]
        var newDrills: [WordOrderDrill]
        var drillsDoneToday: Int
        var anyDrillDone: Bool
        var learnedToday: [Chunk]
        var due: [Chunk]
        var olderLearned: [Chunk]
        var streak: Int
        var phaseExam: PhaseExam?
        var enduranceBest: Double
        var enduranceBestEver: Double
        var recentChunks: [Chunk]

        var allLearned: [Chunk] { learnedToday + olderLearned }
        var phase1Passed: Bool { phaseExam?.passed ?? false }
        /// 第一阶段 30 个达标日已满、但总考没过：卡在第 30 天
        var phaseGate: Bool { checkedInDays >= Plan.phaseOneDays && !phase1Passed }

        var learnDone: Bool { newChunks.isEmpty }
        var drillDone: Bool { newDrills.isEmpty }
        var reviewDone: Bool { due.isEmpty }
        var enduranceTarget: Double { Endurance.target(day: trainingDay) }
        var enduranceDone: Bool { enduranceBest >= enduranceTarget }
        var strengthDone: Bool { reviewDone && learnDone && drillDone }
        var examReady: Bool { strengthDone && enduranceDone && !(learnedToday.isEmpty && olderLearned.isEmpty) }
    }

    private var state: DailyState {
        let cal = Calendar.current
        let today = days.first { cal.isDateInToday($0.day) }
        let checkedIn = today?.checkedIn ?? false
        let checkedInDays = days.filter(\.checkedIn).count

        let known = Set(progresses.map(\.chunkID))
        let introducedToday = progresses.filter { cal.isDateInToday($0.introducedDate) }
        // 今天开始时还没学的数量（含今天已学的），平摊到剩余达标日
        let quota = Plan.dailyQuota(
            unlearned: library.chunks.count - known.count + introducedToday.count,
            checkedInDaysBeforeToday: checkedInDays - (checkedIn ? 1 : 0)
        )
        let remaining = max(0, quota - introducedToday.count)

        // 语序造句同样按剩余量平摊到剩余达标日
        let doneDrillIDs = Set(drillProgress.map(\.drillID))
        let drillsDoneToday = drillProgress.filter { cal.isDateInToday($0.date) }.count
        let drillQuota = Plan.dailyQuota(
            unlearned: library.drills.count - doneDrillIDs.count + drillsDoneToday,
            checkedInDaysBeforeToday: checkedInDays - (checkedIn ? 1 : 0)
        )
        let newDrills = Array(library.drills.filter { !doneDrillIDs.contains($0.id) }.prefix(max(0, drillQuota - drillsDoneToday)))
        let newChunks = Array(library.learningOrder.filter { !known.contains($0.id) }.prefix(remaining))

        let now = Date.now
        let due = progresses
            .filter { $0.dueDate <= now }
            .sorted { $0.dueDate < $1.dueDate }
            .compactMap { library.chunk(id: $0.chunkID) }

        let olderLearned = progresses
            .filter { !cal.isDateInToday($0.introducedDate) }
            .compactMap { library.chunk(id: $0.chunkID) }

        var streak = 0
        let checkedSet = Set(days.filter(\.checkedIn).map(\.day))
        var cursor = cal.startOfDay(for: now)
        if !checkedSet.contains(cursor) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while checkedSet.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        let phaseExam = phaseExams.first { $0.phase == 1 }
        var trainingDay = checkedIn ? checkedInDays : checkedInDays + 1
        if !(phaseExam?.passed ?? false) {
            trainingDay = min(trainingDay, Plan.phaseOneDays)
        }

        let todaySets = enduranceSets.filter { cal.isDateInToday($0.date) }
        let recentChunks = progresses
            .sorted { $0.introducedDate > $1.introducedDate }
            .prefix(3)
            .compactMap { library.chunk(id: $0.chunkID) }

        return DailyState(
            trainingDay: trainingDay,
            checkedInDays: checkedInDays,
            checkedIn: checkedIn,
            examScore: today?.examScore ?? 0,
            examAttempts: today?.examAttempts ?? 0,
            newChunks: newChunks,
            newDrills: newDrills,
            drillsDoneToday: drillsDoneToday,
            anyDrillDone: !doneDrillIDs.isEmpty,
            learnedToday: introducedToday.compactMap { library.chunk(id: $0.chunkID) },
            due: due,
            olderLearned: olderLearned,
            streak: streak,
            phaseExam: phaseExam,
            enduranceBest: todaySets.map(\.speakingSeconds).max() ?? 0,
            enduranceBestEver: enduranceSets.map(\.speakingSeconds).max() ?? 0,
            recentChunks: Array(recentChunks)
        )
    }

    var body: some View {
        let s = state

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(s)

                    HStack(spacing: 12) {
                        StatTile(value: "\(s.checkedInDays)", label: "达标天数", tint: .green)
                        StatTile(value: "\(s.streak)", label: "连续达标", tint: .orange)
                        StatTile(value: Endurance.secondsText(s.enduranceBestEver), label: "最长开口", tint: .blue)
                    }

                    if needsEncouragement(s) {
                        encouragement(s)
                    }

                    VStack(spacing: 12) {
                        StepRow(
                            number: 1,
                            title: "热身 · 开口复习",
                            detail: !s.reviewDone ? "\(s.due.count) 个 · 看中文说出英文，错了本轮重来"
                                : (s.allLearned.isEmpty ? "第 1 天还没有要复习的内容，直接开始力量训练" : "今天的复习已完成 · 想多练可以点「加练」"),
                            state: !s.reviewDone ? .active : (s.allLearned.isEmpty ? .skip : .done),
                            tappableWhenDone: true
                        ) {
                            if s.reviewDone {
                                session = ActiveSession(mode: .extra, chunks: Array(s.allLearned.shuffled().prefix(10)))
                            } else {
                                session = ActiveSession(mode: .review, chunks: s.due)
                            }
                        }

                        StepRow(
                            number: 2,
                            title: "力量 · 学新语块",
                            detail: learnDetail(s),
                            state: s.learnDone ? .done : (s.reviewDone ? .active : .locked)
                        ) {
                            session = ActiveSession(mode: .learn, chunks: s.newChunks)
                        }

                        StepRow(
                            number: 3,
                            title: "力量 · 语序造句",
                            detail: drillDetail(s),
                            state: s.drillDone ? .done : (s.reviewDone && s.learnDone ? .active : .locked)
                        ) {
                            session = ActiveSession(mode: nil, chunks: [], drills: s.newDrills)
                        }

                        StepRow(
                            number: 4,
                            title: "耐力 · 连续开口",
                            detail: enduranceDetail(s),
                            state: s.enduranceDone ? .done : (s.strengthDone ? .active : .locked),
                            tappableWhenDone: true
                        ) {
                            session = ActiveSession(mode: nil, chunks: s.recentChunks, endurance: true)
                        }

                        if s.phase1Passed {
                            phaseDoneCard
                        } else if s.phaseGate {
                            StepRow(
                                number: 5,
                                title: "第一阶段总考",
                                detail: phaseExamDetail(s),
                                state: s.reviewDone && s.enduranceDone ? .active : .locked
                            ) {
                                session = ActiveSession(mode: .phaseExam, chunks: s.allLearned)
                            }
                        } else {
                            StepRow(
                                number: 5,
                                title: "达标测试 · 每日闯关",
                                detail: examDetail(s),
                                state: s.checkedIn ? .done : (s.examReady ? .active : .locked)
                            ) {
                                let extra = s.olderLearned.shuffled().prefix(Plan.examExtraOld)
                                session = ActiveSession(mode: .exam, chunks: s.learnedToday + extra)
                            }
                        }
                    }

                    roadmap(day: s.trainingDay)
                    rules
                }
                .padding()
            }
            .navigationTitle("今天")
            .task(id: s.checkedIn) { Reminder.refresh(checkedInToday: s.checkedIn) }
            .fullScreenCover(item: $session) { active in
                if active.endurance {
                    EnduranceSessionView(trainingDay: state.trainingDay, suggestions: active.chunks)
                } else if let mode = active.mode {
                    TrainingSessionView(mode: mode, chunks: active.chunks)
                } else {
                    WordOrderSessionView(drills: active.drills, showLesson: !state.anyDrillDone)
                }
            }
        }
    }

    private func header(_ s: DailyState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phaseTitle(for: s.trainingDay))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text("第 \(min(s.trainingDay, Plan.totalDays)) / \(Plan.totalDays) 天")
                    .font(.largeTitle.bold())
                Spacer()
                let ok = s.checkedIn || s.phase1Passed
                Text(s.phase1Passed ? "第一阶段通关" : (s.phaseGate ? "阶段总考" : (s.checkedIn ? "今日已达标" : "今日未打卡")))
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((ok ? Color.green : Color.red).opacity(0.15), in: Capsule())
                    .foregroundStyle(ok ? .green : .red)
            }
            ProgressView(value: Double(s.checkedInDays), total: Double(Plan.totalDays))
        }
    }

    private func learnDetail(_ s: DailyState) -> String {
        if s.learnDone {
            return s.learnedToday.isEmpty ? "今日无新语块" : "已完成 · 今天学了 \(s.learnedToday.count) 个"
        }
        return "\(s.newChunks.count) 个 · 跟读 \(Plan.readAloudTimes) 遍 + 用它说一句自己的话"
    }

    /// 今天挑战过但还没达标：鼓励当天练到达标
    private func needsEncouragement(_ s: DailyState) -> Bool {
        if s.checkedIn || s.phase1Passed { return false }
        if s.phaseGate { return s.phaseExam?.attemptedToday ?? false }
        return s.examAttempts > 0
    }

    private func encouragement(_ s: DailyState) -> some View {
        let rate = s.phaseGate ? Plan.phaseExamPassRate : Plan.examPassRate
        let best = s.phaseGate ? (s.phaseExam?.bestScore ?? 0) : s.examScore
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("今天还没达标，别放弃！").font(.headline)
                Text("最高 \(Int(best * 100))%，达标线 \(Int(rate * 100))%。先把错题复习完，再重新闯关，今天就把打卡拿下。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func enduranceDetail(_ s: DailyState) -> String {
        let goal = "围绕一个生活话题连续开口 \(Endurance.secondsText(s.enduranceTarget))"
        if s.enduranceDone { return "已达标 · 今天最长 \(Endurance.secondsText(s.enduranceBest))" }
        let flag = Endurance.isMilestone(day: s.trainingDay) ? " · 今天有里程碑录音" : ""
        return s.enduranceBest > 0 ? "\(goal) · 今天最长 \(Endurance.secondsText(s.enduranceBest))\(flag)" : goal + flag
    }

    private func drillDetail(_ s: DailyState) -> String {
        if s.drillDone {
            return s.drillsDoneToday > 0 ? "已完成 · 今天练了 \(s.drillsDoneToday) 句" : "今日无语序练习"
        }
        return "\(s.newDrills.count) 句 · 看中文，按「主谓宾方地时」说出英文"
    }

    private func examDetail(_ s: DailyState) -> String {
        if s.checkedIn {
            return "已打卡 · 正确率 \(Int(s.examScore * 100))%"
        }
        let line = "正确率 ≥ \(Int(Plan.examPassRate * 100))% 才能打卡"
        return s.examAttempts > 0 ? "\(line) · 已挑战 \(s.examAttempts) 次，最高 \(Int(s.examScore * 100))%" : line
    }

    private func phaseExamDetail(_ s: DailyState) -> String {
        let rule = "全部 \(s.allLearned.count) 个语块限时回想，≥ \(Int(Plan.phaseExamPassRate * 100))% 通关"
        guard let record = s.phaseExam, record.attempts > 0 else {
            return s.reviewDone ? rule : "先复习错题 · \(rule)"
        }
        let best = "已考 \(record.attempts) 次，最高 \(Int(record.bestScore * 100))%"
        return "\(rule) · \(best)"
    }

    private var phaseDoneCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("第一阶段通关", systemImage: "trophy.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("第二阶段「第一人称自言自语」开放前，每天完成复习，保持语块不生疏。这段时间不计入 180 天。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func phaseTitle(for day: Int) -> String {
        guard let index = Plan.phases.firstIndex(where: { $0.range.contains(day) }) else {
            return "180 天训练已完成"
        }
        return "第 \(index + 1) 阶段 · \(Plan.phases[index].title)"
    }

    private func roadmap(day: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("180 天路线").font(.headline)
            Text("只算达标打卡的天数。没达标的日子不算，计划不会往前走。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Plan.phases.indices, id: \.self) { i in
                let phase = Plan.phases[i]
                let active = phase.range.contains(day)
                let done = day > phase.range.upperBound
                HStack {
                    Image(systemName: done ? "checkmark.circle.fill" : (active ? "circle.inset.filled" : "circle"))
                        .foregroundStyle(done ? .green : (active ? .blue : .secondary))
                    Text("第 \(phase.range.lowerBound)–\(phase.range.upperBound) 天")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    Text(phase.title)
                        .fontWeight(active ? .semibold : .regular)
                        .foregroundStyle(active ? .primary : .secondary)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("达标规则").font(.headline)
            Label("像健身课一样按顺序练：热身 → 力量 → 耐力 → 达标测试，前一步没过，后一步锁定", systemImage: "lock")
            Label("耐力：连续开口时长从 10 秒逐步加到 5 分钟，说够才达标", systemImage: "timer")
            Label("语序造句：按「主 → 谓 → 宾 → 方式 → 地点 → 时间」说，\(OrderChecker.rule)", systemImage: "arrow.right")
            Label("全程开口说，由语音识别判定，不能自己点“会了”", systemImage: "mic")
            Label("闯关每题限时 \(Int(Plan.examAnswerSeconds)) 秒；正确率低于 \(Int(Plan.examPassRate * 100))%：错题打回复习，复习完重考", systemImage: "arrow.uturn.backward")
            Label("当天没达标就当天练到达标：错题复习完马上重考，不推到明天", systemImage: "flame")
            Label("第 30 天后必须通过阶段总考（≥ \(Int(Plan.phaseExamPassRate * 100))%，没过就复习错题后当天重考）才能进入下一阶段", systemImage: "flag.checkered")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}
