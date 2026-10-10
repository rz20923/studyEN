import SwiftUI
import SwiftData

/// 一道题：某个框架 + 一个“你想说”
struct QuizItem: Identifiable, Hashable {
    let id = UUID()
    let topic: Topic
    let unit: TopicUnit
    let prompt: TopicUnit.Prompt

    static func random(_ pair: (topic: Topic, unit: TopicUnit)) -> QuizItem {
        QuizItem(topic: pair.topic, unit: pair.unit, prompt: pair.unit.prompts.randomElement() ?? .init(zh: pair.unit.exampleZh, answer: pair.unit.example))
    }
}

/// 看中文意图 → 用英文说出整句。热身复习、达标测试、加练共用
struct FrameQuizView: View {
    enum Mode { case review, exam, extra }

    let mode: Mode
    /// 测试结束（passed）或加练结束时回调
    var onFinish: ((Bool) -> Void)?

    @Environment(\.modelContext) private var context
    @State private var speech = SpeechChecker()
    @State private var queue: [QuizItem]
    @State private var index = 0
    @State private var attempts = 0
    @State private var revealed = false
    @State private var result: FrameMatcher.Result?
    @State private var feedback: String?
    @State private var wrong: [QuizItem] = []
    @State private var examResult: (score: Double, passed: Bool)?
    @State private var permission: Bool?

    init(mode: Mode, items: [QuizItem], onFinish: ((Bool) -> Void)? = nil) {
        self.mode = mode
        self.onFinish = onFinish
        _queue = State(initialValue: mode == .exam ? items.shuffled() : items)
    }

    private var current: QuizItem? { index < queue.count ? queue[index] : nil }
    private var maxAttempts: Int { mode == .exam ? 2 : 3 }

    var body: some View {
        Group {
            if permission == false {
                PermissionDeniedView()
            } else if let r = examResult {
                examResultView(r)
            } else if let item = current {
                question(item)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Theme.green)
                    Text(mode == .extra ? "这一组练完了" : "完成").font(.title2.bold())
                    Spacer()
                    if mode == .extra { InkButton("结束") { onFinish?(true) }.padding(20) }
                }
            }
        }
        .task {
            if permission == nil { permission = await SpeechChecker.requestPermissions() }
        }
        .onDisappear { speech.stop(notify: false) }
    }

    // MARK: - 题目

    private func question(_ item: QuizItem) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Tag(text: item.unit.intent)
                    Spacer()
                    Text(mode == .exam ? "测试 \(index + 1) / \(queue.count)" : "来自 · \(item.topic.title)")
                        .font(.caption)
                        .foregroundStyle(Theme.faint)
                }
                Text("你想说").font(.footnote).foregroundStyle(Theme.faint).padding(.top, 28)
                Text(item.prompt.zh)
                    .font(.system(size: 28, weight: .black))
                    .padding(.top, 6)
                Spacer(minLength: 16)

                if revealed {
                    VStack(alignment: .leading, spacing: 10) {
                        TokenLine(key: answerKey(item), range: 0..<item.prompt.answer.split(separator: " ").count, size: 20)
                        HStack {
                            if let result { CheckChips(frameOK: result.frameOK, slotOK: result.slotOK) }
                            Spacer()
                            RoundIconButton(systemName: "speaker.wave.2.fill", label: "播放", size: 40) {
                                Speaker.shared.speak(item.prompt.answer)
                            }
                        }
                    }
                } else {
                    Text(speech.isRecording ? (speech.transcript.isEmpty ? "正在听…" : speech.transcript) : "用英文说出整句")
                        .font(Theme.en(16, .medium))
                        .foregroundStyle(speech.isRecording ? Theme.ink : Color(hex: 0x9A9E96))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 5])).foregroundStyle(Color(hex: 0xDADDD5)))
                }
                if let feedback {
                    Text(feedback).font(.subheadline.bold()).foregroundStyle(Theme.accentDark).padding(.top, 10)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 20)
            .padding(.top, 16)

            HStack(spacing: 28) {
                if revealed {
                    InkButton(index + 1 >= queue.count ? "完成" : "下一题") { next() }
                } else {
                    Button("看答案") {
                        speech.stop(notify: false)
                        mark(item, ok: false, result: nil)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 72)
                    .opacity(mode == .exam ? 0 : 1)
                    .disabled(mode == .exam)
                    MicButton(isRecording: speech.isRecording) { toggle(item) }
                    Color.clear.frame(width: 72, height: 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .task(id: index) {
            if mode == .exam, let item = current, permission == true { toggle(item) }
        }
    }

    private func answerKey(_ item: QuizItem) -> String {
        let i = item.unit.prompts.firstIndex(of: item.prompt) ?? 0
        return "\(item.unit.id):a\(i)"
    }

    // MARK: - 判定

    private func toggle(_ item: QuizItem) {
        if speech.isRecording {
            speech.stop()
            return
        }
        feedback = nil
        Speaker.shared.stop()
        speech.onTranscript = { text in
            let r = FrameMatcher.check(unit: item.unit, answer: item.prompt.answer, transcript: text)
            if r.passed {
                speech.stop(notify: false)
                mark(item, ok: true, result: r)
            }
        }
        speech.onStop = { text in failed(item, transcript: text) }
        if !speech.start(timeout: mode == .exam ? 10 : 12) {
            feedback = "语音识别暂不可用，请稍后再试"
        }
    }

    private func failed(_ item: QuizItem, transcript: String) {
        attempts += 1
        let r = FrameMatcher.check(unit: item.unit, answer: item.prompt.answer, transcript: transcript)
        if attempts >= maxAttempts {
            mark(item, ok: false, result: r)
        } else {
            feedback = !r.frameOK ? "骨架没说完整：\(item.unit.skeleton)" : "槽位不对，再想想“\(item.prompt.zh)”"
        }
    }

    private func mark(_ item: QuizItem, ok: Bool, result r: FrameMatcher.Result?) {
        revealed = true
        result = r ?? FrameMatcher.Result(frameOK: false, slotOK: false)
        feedback = ok ? nil : "听一遍正确说法，跟着读一下"
        Speaker.shared.speak(item.prompt.answer)
        switch mode {
        case .review:
            if let p = context.progress(for: item.unit.id) { SRS.apply(ok ? .good : .again, to: p) }
            context.studyDay().reviews += 1
            if !ok { queue.append(QuizItem.random((topic: item.topic, unit: item.unit))) }
            try? context.save()
        case .extra:
            if !ok { queue.append(item) }
        case .exam:
            if !ok { wrong.append(item) }
        }
    }

    private func next() {
        speech.stop(notify: false)
        speech.clear()
        if mode == .exam && index + 1 >= queue.count {
            let score = queue.isEmpty ? 0 : Double(queue.count - wrong.count) / Double(queue.count)
            examResult = (score, score >= Plan.examPassRate)
        }
        attempts = 0
        revealed = false
        result = nil
        feedback = nil
        index += 1
        if mode != .exam && index >= queue.count { onFinish?(true) }
    }

    // MARK: - 测试结果（点按钮时才写入，避免页面立刻跳走）

    private func examResultView(_ r: (score: Double, passed: Bool)) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: r.passed ? "checkmark.seal.fill" : "flame.fill")
                .font(.system(size: 60))
                .foregroundStyle(r.passed ? Theme.green : Theme.accent)
            Text(r.passed ? "测试通过" : "差一点！").font(.largeTitle.bold())
            Text("正确率 \(Int(r.score * 100))% · 达标线 \(Int(Plan.examPassRate * 100))%")
                .foregroundStyle(Theme.muted)
            if !wrong.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(wrong) { item in
                        HStack {
                            Text(item.prompt.zh).font(.subheadline)
                            Spacer()
                            Text(item.unit.skeleton).font(Theme.en(13)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 20)
            }
            Spacer()
            InkButton(r.passed ? "打卡" : "复习错题，马上重考") { commitExam(r) }
                .padding(20)
        }
    }

    private func commitExam(_ r: (score: Double, passed: Bool)) {
        for item in wrong {
            if let p = context.progress(for: item.unit.id) { SRS.apply(.again, to: p) }
        }
        let day = context.studyDay()
        day.examAttempts += 1
        day.examScore = max(day.examScore, r.score)
        if r.passed { day.checkedIn = true }
        try? context.save()
        onFinish?(r.passed)
    }
}
