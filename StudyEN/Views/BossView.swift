import SwiftUI
import SwiftData

/// 综合对话：同一情境多轮剧情，用本课题的框架接住每一轮
struct BossView: View {
    let topic: Topic

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var speech = SpeechChecker()
    @State private var permission: Bool?
    @State private var turn = 0
    @State private var said: [String] = []
    @State private var attempts = 0
    @State private var showHint = false
    @State private var mustRead = false
    @State private var feedback: String?
    @State private var finished = false

    private var turns: [Topic.Turn] { topic.boss.turns }
    private var currentTurn: Topic.Turn? { turn < turns.count ? turns[turn] : nil }
    private func unit(_ t: Topic.Turn) -> TopicUnit { topic.units[min(t.unit, topic.units.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            header
            if permission == false {
                PermissionDeniedView()
            } else if finished {
                finishView
            } else {
                chat
                dock
            }
        }
        .background(Theme.ground)
        .task {
            if permission == nil { permission = await SpeechChecker.requestPermissions() }
        }
        .task(id: turn) { await startTurn() }
        .onDisappear { speech.stop(notify: false) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40).background(Color.white, in: Circle())
            }
            .accessibilityLabel("退出")
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title).font(.headline.weight(.black))
                Text("\(topic.boss.role) · 第 \(min(turn + 1, turns.count)) / \(turns.count) 轮").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<min(turn + 1, turns.count), id: \.self) { i in
                        npcBubble(turns[i].npc)
                        if i < said.count { userBubble(said[i]) }
                    }
                    if let t = currentTurn {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("轮到你 · 你想说").font(.caption).foregroundStyle(Theme.faint)
                            Text(t.zh).font(.headline)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1.5))

                        if showHint || mustRead {
                            Label(mustRead ? UserName.apply(t.answer) : unit(t).skeleton, systemImage: "lightbulb")
                                .font(Theme.en(15, .semibold))
                                .foregroundStyle(Theme.accentDark)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Theme.accentTint, in: Capsule())
                                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(Theme.accent))
                        }
                        if speech.isRecording || !speech.transcript.isEmpty {
                            Text(speech.transcript.isEmpty ? "…" : speech.transcript)
                                .font(Theme.en(15)).foregroundStyle(Theme.muted)
                        }
                        if let feedback { Text(feedback).font(.subheadline.bold()).foregroundStyle(Theme.accentDark) }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: turn) { withAnimation { proxy.scrollTo("bottom") } }
            .onChange(of: showHint) { withAnimation { proxy.scrollTo("bottom") } }
        }
    }

    private func npcBubble(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(String(topic.boss.npcName.prefix(2)))
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Theme.ink, in: Circle())
            Text(text)
                .font(Theme.en(16, .medium))
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18))
            Spacer(minLength: 30)
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 50)
            Text(text)
                .font(Theme.en(16, .medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Theme.ink, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18))
        }
    }

    private var dock: some View {
        HStack(spacing: 28) {
            RoundIconButton(systemName: "arrow.counterclockwise", label: "重听对方") {
                if let t = currentTurn { Speaker.shared.speak(t.npc) }
            }
            MicButton(isRecording: speech.isRecording) { toggle() }
            RoundIconButton(systemName: "lightbulb", label: "看框架") { showHint = true }
        }
        .padding(.vertical, 18)
    }

    private var finishView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text("对话通关").font(.largeTitle.bold())
            Text("\(turns.count) 轮全部接住了").foregroundStyle(Theme.muted)
            Spacer()
            InkButton("完成") { dismiss() }.padding(20)
        }
    }

    // MARK: - 流程

    private func startTurn() async {
        guard let t = currentTurn else { return }
        showHint = false
        mustRead = false
        attempts = 0
        feedback = nil
        speech.clear()
        Speaker.shared.speak(t.npc)
        // 卡住 5 秒还没开口：浮出框架提示
        try? await Task.sleep(for: .seconds(Double(t.npc.split(separator: " ").count) * 0.4 + 5))
        if !Task.isCancelled && !speech.isRecording && speech.transcript.isEmpty { showHint = true }
    }

    private func toggle() {
        if speech.isRecording { speech.stop(); return }
        guard let t = currentTurn else { return }
        feedback = nil
        Speaker.shared.stop()
        let u = unit(t)
        speech.onTranscript = { text in
            let ok = mustRead
                ? PhraseMatcher.readingScore(UserName.apply(t.answer), transcript: text) >= 0.6
                : FrameMatcher.check(unit: u, answer: nil, transcript: text).frameOK
            if ok {
                speech.stop(notify: false)
                said.append(text)
                if turn + 1 >= turns.count { complete() }
                turn += 1
            }
        }
        speech.onStop = { _ in
            attempts += 1
            showHint = true
            if attempts >= 2 {
                mustRead = true
                feedback = "照着提示读一遍就能继续"
            } else {
                feedback = "试试用这个框架：\(u.skeleton)"
            }
        }
        if !speech.start(hints: [UserName.apply(t.answer)], timeout: 12) { feedback = "语音识别暂不可用" }
    }

    private func complete() {
        let id = topic.id
        let record = (try? context.fetch(FetchDescriptor<TopicProgress>(predicate: #Predicate { $0.topicID == id })))?.first
            ?? {
                let created = TopicProgress(topicID: topic.id)
                context.insert(created)
                return created
            }()
        record.bossPassed = true
        record.bossDate = .now
        try? context.save()
        finished = true
    }
}
