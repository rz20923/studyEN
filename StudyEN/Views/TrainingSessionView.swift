import SwiftUI
import SwiftData

enum TrainingMode {
    case learn, review, exam, phaseExam
    /// 加练：完成后的热身再练一组，不改复习计划、不影响打卡
    case extra

    var title: String {
        switch self {
        case .learn: return "学新语块"
        case .review: return "开口复习"
        case .exam: return "每日闯关"
        case .phaseExam: return "第一阶段总考"
        case .extra: return "加练 · 开口复习"
        }
    }

    var isExam: Bool { self == .exam || self == .phaseExam }
}

/// 强制训练：每一步都必须通过语音判定，不能靠"自评"糊弄过去
struct TrainingSessionView: View {
    /// 闯关没达标时会切到「复习错题」再切回闯关，所以模式是可变的
    @State private var mode: TrainingMode
    /// 闯关题目（重考时用同一组题重新打乱）
    private let examChunks: [Chunk]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var speech = SpeechChecker()
    @State private var permission: Bool?
    @State private var queue: [Chunk]
    @State private var index = 0

    // 当前卡片状态
    @State private var readPasses = 0
    @State private var ownSentenceDone = false
    @State private var failedAttempts = 0
    @State private var revealed = false
    @State private var correct = false
    @State private var feedback: String?
    @State private var cardShownAt = Date.now

    // 闯关
    @State private var wrong: [Chunk] = []
    @State private var examResult: ExamResult?
    /// 正在复习错题；复习完回到这个闯关模式重考
    @State private var retryExam: TrainingMode?
    /// 答题卡：题号 -> 是否答对
    @State private var answers: [Int: Bool] = [:]
    @State private var round = 0

    struct ExamResult {
        let score: Double
        let passed: Bool
        let wrong: [Chunk]
    }

    init(mode: TrainingMode, chunks: [Chunk]) {
        _mode = State(initialValue: mode)
        examChunks = chunks
        _queue = State(initialValue: mode.isExam ? chunks.shuffled() : chunks)
    }

    private var current: Chunk? { index < queue.count ? queue[index] : nil }
    private var maxAttempts: Int { mode.isExam ? 2 : 3 }
    private var passRate: Double { mode == .phaseExam ? Plan.phaseExamPassRate : Plan.examPassRate }

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
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出") {
                        speech.stop(notify: false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if current != nil {
                        Text("\(index + 1) / \(queue.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onDisappear { speech.stop(notify: false) }
    }

    // MARK: - Main

    @ViewBuilder
    private var main: some View {
        if let chunk = current {
            VStack(spacing: 0) {
                ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                    .padding(.horizontal)
                ScrollView {
                    card(chunk)
                        .padding()
                }
                controls(chunk)
                    .padding()
            }
            .task(id: "\(round)-\(index)") {
                cardShownAt = .now
                if mode == .phaseExam && index == 0 {
                    // 每次开考都记一次，用于统计挑战次数
                    let record = context.phaseExam(1)
                    record.attempts += 1
                    record.lastAttemptDay = .now
                    try? context.save()
                }
                switch mode {
                case .learn: Speaker.shared.speak(chunk.example)
                case .exam, .phaseExam: toggleRecording(chunk)  // 闯关自动收音并计时
                case .review, .extra: break
                }
            }
        } else if let result = examResult {
            examResultView(result)
        } else {
            finishedView
        }
    }

    private func card(_ chunk: Chunk) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if mode.isExam {
                AnswerSheetView(count: queue.count, answers: answers, current: index)
            }
            HStack {
                KindTag(kind: chunk.kind)
                Text(chunk.scene).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }

            if mode == .learn || revealed {
                ChunkAnswerView(chunk: chunk)
            } else {
                ChunkPromptView(chunk: chunk, showSentenceHint: !mode.isExam)
            }

            if revealed {
                Label(resultText, systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(correct ? .green : .red)
            }

            if mode == .learn {
                HStack(spacing: 8) {
                    Text("跟读例句达标").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(0..<Plan.readAloudTimes, id: \.self) { i in
                        Circle()
                            .fill(i < readPasses ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                    }
                }
                if readPasses >= Plan.readAloudTimes {
                    Label(ownSentenceDone ? "造句达标" : "用 \(chunk.phrase) 说一句你自己的话（≥\(Plan.ownSentenceMinWords) 个词，不能照读例句）",
                          systemImage: ownSentenceDone ? "checkmark.circle.fill" : "text.bubble")
                        .font(.subheadline.bold())
                        .foregroundStyle(ownSentenceDone ? .green : .blue)
                    if !ownSentenceDone {
                        Text("语序提示：主 → 谓 → 宾 → 方式 → 地点 → 时间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if mode.isExam && !revealed {
                Label("限时 \(Int(Plan.examAnswerSeconds)) 秒，脱口而出才算", systemImage: "timer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if mode == .learn && readPasses < Plan.readAloudTimes && !speech.isRecording && !speech.transcript.isEmpty {
                WordFeedbackView(sentence: chunk.example, transcript: speech.transcript)
            }

            if speech.isRecording || !speech.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("听到的：").font(.caption).foregroundStyle(.secondary)
                    Text(speech.transcript.isEmpty ? "…" : speech.transcript)
                        .font(.body.italic())
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

    private var resultText: String {
        if correct { return "说对了" }
        return mode.isExam ? "答错，计入错题" : "没过，本轮末尾再来一次"
    }

    @ViewBuilder
    private func controls(_ chunk: Chunk) -> some View {
        if mode == .learn {
            if ownSentenceDone {
                PrimaryButton("达标，下一个") { completeLearning(chunk) }
            } else if readPasses >= Plan.readAloudTimes {
                RecordButton(isRecording: speech.isRecording, idleTitle: "说一句自己的话") {
                    toggleRecording(chunk)
                }
            } else {
                RecordButton(isRecording: speech.isRecording,
                             idleTitle: "大声读例句（\(readPasses)/\(Plan.readAloudTimes)）") {
                    toggleRecording(chunk)
                }
            }
        } else if revealed {
            PrimaryButton(index + 1 >= queue.count ? "完成" : "下一个") { next() }
        } else {
            VStack(spacing: 10) {
                RecordButton(isRecording: speech.isRecording, idleTitle: "说出英文") {
                    toggleRecording(chunk)
                }
                Button("想不起来，看答案") {
                    speech.stop(notify: false)
                    markResult(chunk, correct: false)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Speech

    private func toggleRecording(_ chunk: Chunk) {
        if speech.isRecording {
            speech.stop()
            return
        }
        feedback = nil
        Speaker.shared.stop()
        speech.onTranscript = { text in heard(text, chunk) }
        speech.onStop = { _ in attemptFailed() }
        // 回想和闯关不给识别器提示词，避免"含糊说两句也被认成答案"
        let hints = mode == .learn && readPasses < Plan.readAloudTimes ? [chunk.example] : []
        let timeout = mode.isExam ? Plan.examAnswerSeconds : 8
        if !speech.start(hints: hints, timeout: timeout) {
            feedback = "语音识别暂不可用，请检查网络后再试"
        }
    }

    private func heard(_ text: String, _ chunk: Chunk) {
        let passed: Bool
        if mode == .learn && readPasses >= Plan.readAloudTimes {
            passed = isOwnSentence(text, for: chunk)
        } else if mode == .learn {
            passed = PhraseMatcher.readingScore(chunk.example, transcript: text) >= Plan.readingPassScore
        } else {
            passed = PhraseMatcher.matchesPhrase(chunk.phrase, in: text)
        }
        guard passed else { return }
        speech.stop(notify: false)
        if mode == .learn && readPasses >= Plan.readAloudTimes {
            ownSentenceDone = true
            feedback = "这句是你自己的了"
        } else if mode == .learn {
            readPasses += 1
            feedback = readPasses >= Plan.readAloudTimes ? "三遍全部达标！现在用它说一句你自己的话" : "很好，再读一遍"
        } else {
            markResult(chunk, correct: true)
        }
    }

    /// 造句判定：包含该语块、够长、且不是照读例句
    private func isOwnSentence(_ text: String, for chunk: Chunk) -> Bool {
        PhraseMatcher.matchesPhrase(chunk.phrase, in: text)
            && PhraseMatcher.words(text).count >= Plan.ownSentenceMinWords
            && PhraseMatcher.readingScore(chunk.example, transcript: text) < 0.7
    }

    private func attemptFailed() {
        guard let chunk = current else { return }
        if mode == .learn {
            feedback = readPasses >= Plan.readAloudTimes
                ? "没达标：句子里要有 \(chunk.phrase)，至少 \(Plan.ownSentenceMinWords) 个词，而且不能照读例句"
                : "没达标：要读对例句中 \(Int(Plan.readingPassScore * 100))% 的词，再来一遍"
            return
        }
        failedAttempts += 1
        if failedAttempts >= maxAttempts {
            markResult(chunk, correct: false)
        } else {
            feedback = mode.isExam
                ? "超时或不对，还有 \(maxAttempts - failedAttempts) 次机会"
                : "不对，还有 \(maxAttempts - failedAttempts) 次机会"
        }
    }

    // MARK: - Results

    private func markResult(_ chunk: Chunk, correct ok: Bool) {
        revealed = true
        correct = ok
        feedback = nil
        Speaker.shared.speak(chunk.phrase)

        if ok, mode != .learn, let p = context.progress(for: chunk.id) {
            p.lastLatency = Date.now.timeIntervalSince(cardShownAt)
        }

        switch mode {
        case .review:
            if let p = context.progress(for: chunk.id) {
                SRS.apply(ok ? .good : .again, to: p)
            }
            context.studyDay().reviews += 1
            if !ok { queue.append(chunk) }
        case .extra:
            if !ok { queue.append(chunk) }
        case .exam, .phaseExam:
            answers[index] = ok
            if !ok { wrong.append(chunk) }
        case .learn:
            break
        }
        try? context.save()
    }

    private func completeLearning(_ chunk: Chunk) {
        let p = context.progress(for: chunk.id) ?? {
            let created = ChunkProgress(chunkID: chunk.id)
            context.insert(created)
            return created
        }()
        // 今天学的新语块由今天的闯关来检验，明天进入复习
        let today = Calendar.current.startOfDay(for: .now)
        p.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? .now
        context.studyDay().newLearned += 1
        try? context.save()
        next()
    }

    private func next() {
        speech.stop(notify: false)
        speech.clear()
        if mode.isExam && index + 1 >= queue.count {
            finishExam()
        }
        resetCard()
        index += 1
    }

    private func resetCard() {
        readPasses = 0
        ownSentenceDone = false
        failedAttempts = 0
        revealed = false
        correct = false
        feedback = nil
    }

    /// 没达标：当场复习错题，复习完马上重考，不推到明天
    private func startRetryReview(_ result: ExamResult) {
        retryExam = mode
        mode = .review
        queue = result.wrong
        wrong = []
        examResult = nil
        resetCard()
        index = 0
        round += 1
    }

    private func retake(_ exam: TrainingMode) {
        mode = exam
        queue = examChunks.shuffled()
        answers = [:]
        wrong = []
        examResult = nil
        retryExam = nil
        resetCard()
        index = 0
        round += 1
    }

    private func finishExam() {
        let total = queue.count
        let score = total == 0 ? 0 : Double(total - wrong.count) / Double(total)
        let passed = score >= passRate

        // 错题一律打回复习队列：没通过就必须先复习再重考
        for chunk in wrong {
            if let p = context.progress(for: chunk.id) {
                SRS.apply(.again, to: p)
            }
        }
        if mode == .phaseExam {
            let record = context.phaseExam(1)
            record.bestScore = max(record.bestScore, score)
            if passed {
                record.passed = true
                record.passedDate = .now
            }
        } else {
            let day = context.studyDay()
            day.examAttempts += 1
            day.examScore = max(day.examScore, score)
            if passed { day.checkedIn = true }
        }
        try? context.save()

        examResult = ExamResult(score: score, passed: passed, wrong: wrong)
    }

    // MARK: - End screens

    private func examResultView(_ result: ExamResult) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: result.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(result.passed ? .green : .red)
            Text(mode == .phaseExam
                 ? (result.passed ? "第一阶段通关" : "总考还差一点")
                 : (result.passed ? "打卡成功" : "差一点！今天还没达标"))
                .font(.title.bold())
            Text("正确率 \(Int(result.score * 100))%（达标线 \(Int(passRate * 100))%）")
                .foregroundStyle(.secondary)
            if !result.passed {
                Text("只差 \(max(1, Int((((passRate - result.score) * 1000).rounded() / 10).rounded(.up))))%，复习完这 \(result.wrong.count) 个错题就能再冲一次")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            AnswerSheetView(count: queue.count, answers: answers)
                .padding(.horizontal)

            if !result.wrong.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("错题").font(.headline)
                    ForEach(result.wrong) { chunk in
                        HStack {
                            Text(chunk.phrase).fontWeight(.medium)
                            Spacer()
                            Text(chunk.meaning).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
            }

            Text(endMessage(passed: result.passed))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if result.passed {
                PrimaryButton("完成") { dismiss() }
                    .padding()
            } else {
                PrimaryButton("复习错题，马上重考") { startRetryReview(result) }
                    .padding()
            }
        }
    }

    private func endMessage(passed: Bool) -> String {
        switch (mode, passed) {
        case (.phaseExam, true): return "全部语块都能脱口而出了。"
        case (.phaseExam, false): return "错题复习完马上可以重考，今天就把它拿下。"
        case (_, true): return "今天的训练达标了，明天继续。"
        default: return "今天的打卡还在等你。复习错题后马上重考，练到达标为止。"
        }
    }

    @ViewBuilder
    private var finishedView: some View {
        if let exam = retryExam {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                Text("错题都说对了！").font(.title.bold())
                Text("趁热重新闯关，今天就把打卡拿下。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                PrimaryButton("重新闯关") { retake(exam) }
                    .padding()
            }
        } else {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("这一步完成了").font(.title.bold())
                Text(mode == .learn ? "下一步：语序造句" : (mode == .review ? "下一步：学新语块" : (mode == .extra ? "加练完成，不影响复习计划和打卡" : "下一步：达标测试")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                PrimaryButton("返回") { dismiss() }
                    .padding()
            }
        }
    }
}
