import SwiftUI
import SwiftData

/// 语序造句：看中文，按「主 → 谓 → 宾 → 方式 → 地点 → 时间」说出英文，由语音识别判定语序
struct WordOrderSessionView: View {
    let drills: [WordOrderDrill]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var speech = SpeechChecker()
    @State private var permission: Bool?
    @State private var lessonVisible: Bool
    @State private var index = 0
    @State private var failed = 0
    @State private var revealed = false
    @State private var correct = false
    @State private var done = false
    @State private var feedback: String?
    @State private var lastCheck: OrderChecker.Result?

    private let maxAttempts = 3

    init(drills: [WordOrderDrill], showLesson: Bool) {
        self.drills = drills
        _lessonVisible = State(initialValue: showLesson)
    }

    private var current: WordOrderDrill? { index < drills.count ? drills[index] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if let permission {
                    if permission { main } else { PermissionDeniedView() }
                } else {
                    ProgressView("正在请求麦克风权限…")
                        .task { permission = await SpeechChecker.requestPermissions() }
                }
            }
            .navigationTitle("语序造句")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出") {
                        speech.stop(notify: false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if current != nil && !lessonVisible {
                        Text("\(index + 1) / \(drills.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onDisappear { speech.stop(notify: false) }
    }

    @ViewBuilder
    private var main: some View {
        if lessonVisible {
            VStack(spacing: 0) {
                ScrollView {
                    WordOrderLessonView(example: drills.first)
                        .padding()
                }
                PrimaryButton("懂了，开始练") { lessonVisible = false }
                    .padding()
            }
        } else if let drill = current {
            VStack(spacing: 0) {
                ProgressView(value: Double(index), total: Double(max(drills.count, 1)))
                    .padding(.horizontal)
                ScrollView {
                    card(drill).padding()
                }
                controls(drill).padding()
            }
        } else {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("这一步完成了").font(.title.bold())
                Text("下一步：开口复习").foregroundStyle(.secondary)
                Spacer()
                PrimaryButton("返回") { dismiss() }.padding()
            }
        }
    }

    private func card(_ drill: WordOrderDrill) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(OrderChecker.hint(for: drill))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(drill.zh)
                .font(.title2.bold())

            if revealed {
                Label(correct ? "语序正确" : "语序没过", systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(correct ? .green : .red)
                SegmentsView(drill: drill)
                HStack {
                    Text(drill.sentence).font(.headline)
                    Spacer()
                    SpeakButton(text: drill.sentence)
                }
            }

            if speech.isRecording || !speech.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("听到的：").font(.caption).foregroundStyle(.secondary)
                    Text(speech.transcript.isEmpty ? "…" : speech.transcript).font(.body.italic())
                }
            }
            if let feedback {
                Text(feedback)
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func controls(_ drill: WordOrderDrill) -> some View {
        if done {
            PrimaryButton(index + 1 >= drills.count ? "完成" : "下一句") { next() }
        } else {
            RecordButton(isRecording: speech.isRecording,
                         idleTitle: revealed ? "照着正确语序读一遍" : "用英文说出这句话") {
                toggleRecording(drill)
            }
        }
    }

    private func toggleRecording(_ drill: WordOrderDrill) {
        if speech.isRecording {
            speech.stop()
            return
        }
        feedback = nil
        Speaker.shared.stop()
        speech.onTranscript = { text in heard(text, drill) }
        speech.onStop = { _ in attemptFailed(drill) }
        if !speech.start() {
            feedback = "语音识别暂不可用，请检查网络后再试"
        }
    }

    private func heard(_ text: String, _ drill: WordOrderDrill) {
        let passed: Bool
        if revealed {
            passed = PhraseMatcher.readingScore(drill.sentence, transcript: text) >= 0.8
        } else {
            let result = OrderChecker.check(drill, transcript: text)
            lastCheck = result
            passed = result.ok
        }
        guard passed else { return }
        speech.stop(notify: false)
        complete(drill)
    }

    private func attemptFailed(_ drill: WordOrderDrill) {
        if revealed {
            feedback = "没读对，照着正确语序再读一遍"
            return
        }
        failed += 1
        let why = lastCheck?.message ?? "没听清，再说一遍"
        if failed >= maxAttempts {
            revealed = true
            correct = false
            feedback = "\(why)。看正确语序，大声读一遍才能过"
            Speaker.shared.speak(drill.sentence)
        } else {
            feedback = "\(why)（还有 \(maxAttempts - failed) 次机会）"
        }
    }

    private func complete(_ drill: WordOrderDrill) {
        context.insert(DrillProgress(drillID: drill.id, firstTry: !revealed && failed == 0))
        try? context.save()
        done = true
        feedback = nil
        if !revealed {
            revealed = true
            correct = true
        }
    }

    private func next() {
        speech.stop(notify: false)
        speech.clear()
        failed = 0
        revealed = false
        correct = false
        done = false
        feedback = nil
        lastCheck = nil
        index += 1
    }
}

/// 语序规则讲解（第一次进入语序造句时展示，语块库里也能随时查看）
struct WordOrderLessonView: View {
    let example: WordOrderDrill?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("单词都会却说不对？问题在语序").font(.title3.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text("主 → 谓 → 宾 → 方式 → 地点 → 时间").font(.headline)
                Text("谁 → 做 → 什么 → 怎么做 → 在哪 → 何时")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("中文语序：我 / 上周日 / 在图书馆 / 安静地 / 看 / 书\n（主 / 时间 / 地点 / 方式 / 谓 / 宾）")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("英文语序：").font(.subheadline).foregroundStyle(.secondary)
            if let example {
                SegmentsView(drill: example)
            }
            Text("口诀：\(OrderChecker.rule)。").font(.headline)
            Text("时间也可以放在句首（Last Sunday, I read…），但时间、地点绝不能夹在主语和谓语中间。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 把英文句子按成分上色显示
struct SegmentsView: View {
    let drill: WordOrderDrill

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(drill.segments.enumerated()), id: \.offset) { _, segment in
                let color = roleColor(segment.role)
                VStack(spacing: 2) {
                    Text(segment.en).font(.subheadline.bold())
                    Text(SentenceRole.name(segment.role)).font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .foregroundStyle(color)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "S": return .blue
        case "V": return .red
        case "O": return .orange
        case "M": return .purple
        case "P": return .green
        case "T": return .teal
        case "Q", "A", "L", "E": return .pink
        default: return .indigo
        }
    }
}

/// 自动换行排列
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 语块库里的「语序规则」页
struct WordOrderRulesView: View {
    @Environment(ChunkLibrary.self) private var library
    @Query private var done: [DrillProgress]

    var body: some View {
        let doneIDs = Set(done.map(\.drillID))
        List {
            Section {
                WordOrderLessonView(example: library.drills.first)
            }
            Section("语序造句库 · 已练 \(doneIDs.count) / \(library.drills.count)") {
                ForEach(library.drills) { drill in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drill.zh).font(.subheadline)
                        if doneIDs.contains(drill.id) {
                            HStack {
                                Text(drill.sentence).font(.subheadline.bold())
                                Spacer()
                                SpeakButton(text: drill.sentence)
                            }
                        } else {
                            Text("（练过后显示答案）").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("语序规则")
        .navigationBarTitleDisplayMode(.inline)
    }
}
