import SwiftUI
import SwiftData
import Charts

/// 课题标签：每个课题一张卡片
struct TopicsView: View {
    @Environment(ChunkLibrary.self) private var library
    @Query private var progresses: [ChunkProgress]
    @Query private var topicProgress: [TopicProgress]
    @State private var extra: TrainView.ExtraBox?

    var body: some View {
        let learned = Set(progresses.map(\.chunkID))
        let passed = Set(topicProgress.filter(\.bossPassed).map(\.topicID))
        let currentID = library.topics.first { !passed.contains($0.id) }?.id
        let learnedPairs = library.topics.flatMap { t in t.units.filter { learned.contains($0.id) }.map { (topic: t, unit: $0) } }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("一个课题 = 一件真实的事，学完能把这件事说下来")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    ForEach(library.topics) { topic in
                        let isPassed = passed.contains(topic.id)
                        let locked = !isPassed && topic.id != currentID
                        NavigationLink {
                            TopicDetailView(topic: topic)
                        } label: {
                            card(topic, learned: learned, passed: isPassed, locked: locked)
                        }
                        .buttonStyle(.plain)
                        .disabled(locked)
                    }
                    Button {
                        extra = TrainView.ExtraBox(items: learnedPairs.shuffled().prefix(10).map(QuizItem.random))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.on.rectangle.angled").foregroundStyle(Theme.accent).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("随手练").font(.headline).foregroundStyle(.white)
                                Text(learnedPairs.isEmpty ? "先学几个框架再来" : "学过的 \(learnedPairs.count) 个框架 · 不影响打卡")
                                    .font(.caption).foregroundStyle(Color(hex: 0xA5AAA0))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.white)
                        }
                        .padding(16)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(learnedPairs.isEmpty)
                }
                .padding(20)
            }
            .background(Theme.ground)
            .navigationTitle("课题")
        }
        .sheet(item: $extra) { box in
            FrameQuizView(mode: .extra, items: box.items) { _ in extra = nil }
                .background(Theme.ground)
        }
    }

    private func card(_ topic: Topic, learned: Set<String>, passed: Bool, locked: Bool) -> some View {
        let done = topic.units.filter { learned.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                if passed {
                    Tag(text: "已通关", fg: Theme.green, bg: Theme.greenTint)
                } else if locked {
                    Tag(text: "按顺序解锁", fg: Theme.muted)
                } else {
                    Tag(text: "进行中", fg: .white, bg: Theme.ink)
                }
                Spacer()
                Text("\(done) / \(topic.units.count) 框架").font(.caption).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title).font(.title3.weight(.black))
                Text(topic.units.first?.skeleton ?? "").font(Theme.en(14)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 4) {
                ForEach(topic.units) { u in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(learned.contains(u.id) ? (passed ? Color(hex: 0x1F9D55) : Theme.ink) : Theme.line)
                        .frame(height: 10)
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(passed ? Color(hex: 0x1F9D55) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(style: StrokeStyle(lineWidth: 1.5, dash: passed ? [] : [4, 3])).foregroundStyle(passed ? Color.clear : Color(hex: 0xC9CDC4)))
                    .frame(width: 44, height: 10)
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .opacity(locked ? 0.55 : 1)
    }
}

/// 课题详情：所有框架
struct TopicDetailView: View {
    let topic: Topic
    @Query private var progresses: [ChunkProgress]

    var body: some View {
        let learned = Set(progresses.map(\.chunkID))
        List {
            Section {
                Text(topic.scene).foregroundStyle(Theme.muted)
            }
            ForEach(topic.units) { u in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Tag(text: u.intent)
                        Spacer()
                        if learned.contains(u.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                        }
                    }
                    Text(u.skeleton).font(Theme.en(18, .bold))
                    HStack {
                        Text(u.example).font(Theme.en(15)).foregroundStyle(Theme.muted)
                        Spacer()
                        SpeakButton(text: u.example)
                    }
                    Text(u.exampleZh).font(.caption).foregroundStyle(Theme.faint)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 我的：累计开口、开口曲线、录音对比、180 天、设置
struct MeView: View {
    @Query private var days: [StudyDay]
    @Query(sort: \EnduranceSet.date) private var sets: [EnduranceSet]
    @Query private var notes: [StuckNote]
    @AppStorage("zhPron") private var zhPron = false
    @AppStorage(UserName.key) private var name = ""
    @State private var editName = false

    var body: some View {
        let total = sets.map(\.speakingSeconds).reduce(0, +)
        let checked = days.filter(\.checkedIn).count
        let best = Dictionary(grouping: sets, by: \.trainingDay)
            .map { (day: $0.key, seconds: $0.value.map(\.speakingSeconds).max() ?? 0) }
            .sorted { $0.day < $1.day }
            .suffix(12)
        let milestones = sets.filter(\.milestone)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("累计开口").font(.footnote).foregroundStyle(Theme.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(totalText(total)).font(Theme.en(52, .heavy))
                            Text("· 第 \(max(checked, 1)) 天").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("最长连续开口").font(.subheadline.bold())
                            Spacer()
                            Text("目标 \(Endurance.secondsText(Endurance.target(day: checked + 1)))").font(.caption).foregroundStyle(Theme.muted)
                        }
                        if best.isEmpty {
                            Text("完成第一次「连续开口」后，这里会画出你的进步。").font(.footnote).foregroundStyle(Theme.faint)
                        } else {
                            Chart {
                                ForEach(Array(best), id: \.day) { p in
                                    BarMark(x: .value("天", "\(p.day)"), y: .value("秒", p.seconds))
                                        .foregroundStyle(p.day == best.last?.day ? Theme.accent : Theme.ink)
                                        .cornerRadius(4)
                                }
                                RuleMark(y: .value("目标", Endurance.target(day: checked + 1)))
                                    .foregroundStyle(Theme.accent)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 110)
                        }
                    }
                    .padding(18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 24))

                    NavigationLink { RecordingsView() } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("同一个题目，听听自己的变化").font(.subheadline.bold())
                            HStack(spacing: 10) {
                                recBox("第 1 天", milestones.first.map { "\(Endurance.secondsText($0.speakingSeconds)) · 卡壳 \($0.pauses) 次" } ?? "还没录", dark: true)
                                recBox(milestones.count > 1 ? "第 \(milestones.last!.trainingDay) 天" : "第 30 天",
                                       milestones.count > 1 ? Endurance.secondsText(milestones.last!.speakingSeconds) : "还没录", dark: false)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("180 天").font(.subheadline.bold())
                            Spacer()
                            Text("每格一个达标日").font(.caption).foregroundStyle(Theme.muted)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 18), spacing: 4) {
                            ForEach(0..<180, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(i < checked ? Theme.ink : (i == checked ? Theme.accent : Theme.line))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                        .padding(.vertical, 12)
                        Divider()
                        NavigationLink { StuckNotesView() } label: { row("卡壳本", "\(notes.count) 条") }
                        Divider()
                        Button { editName = true } label: { row("英文名", name.isEmpty ? "未设置" : name) }
                            .buttonStyle(.plain)
                        Divider()
                        Toggle("读音显示汉字音译", isOn: $zhPron).padding(.vertical, 12).tint(Theme.accent)
                        Divider()
                        row("没达标提醒", "20:00 / 22:00")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
                }
                .padding(20)
                .sheet(isPresented: $editName) { NameOnboardingView() }
            }
            .background(Theme.ground)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func totalText(_ s: Double) -> String {
        let m = Int(s) / 60
        return m >= 60 ? String(format: "%d:%02d", m / 60, m % 60) : "\(m) 分"
    }

    private func recBox(_ title: String, _ value: String, dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(dark ? Color(hex: 0xA5AAA0) : Theme.accentSoft)
            Text(value).font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(dark ? Theme.inkSoft : Theme.accent, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).foregroundStyle(Theme.muted)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 12)
    }
}
