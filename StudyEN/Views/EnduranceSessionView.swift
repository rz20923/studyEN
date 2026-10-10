import SwiftUI
import SwiftData

/// 耐力训练：围绕一个生活话题连续开口，说够目标时长才达标
struct EnduranceSessionView: View {
    let trainingDay: Int
    /// 最近学的几个语块，提示用户试着用上
    let suggestions: [Chunk]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ChunkLibrary.self) private var library
    @Query(filter: #Predicate<EnduranceSet> { $0.milestone }, sort: \EnduranceSet.date) private var milestones: [EnduranceSet]

    @State private var recorder = EnduranceRecorder()
    @State private var player = RecordingPlayer()
    @State private var permission: Bool?
    @State private var result: EnduranceSet?
    @State private var stuckText = ""
    @State private var stuckNotes: [String] = []

    private var target: Double { Endurance.target(day: trainingDay) }
    private var topic: EnduranceTopic { Endurance.topic(day: trainingDay) }
    private var milestone: Bool { Endurance.isMilestone(day: trainingDay) }

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
            .navigationTitle("耐力训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出") {
                        recorder.stop()
                        player.stop()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onDisappear {
            recorder.stop()
            player.stop()
        }
    }

    @ViewBuilder
    private var main: some View {
        if recorder.isRecording {
            recordingView
        } else if let result {
            resultView(result)
        } else {
            introView
        }
    }

    // MARK: - 开始前

    private var introView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if milestone {
                        Label(trainingDay == 1 ? "里程碑录音：这是你的起点，之后每 30 天用同一个题目再录一次" : "里程碑录音：和第 1 天的自己对比一下",
                              systemImage: "flag.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                    Text("今天的话题").font(.caption).foregroundStyle(.secondary)
                    Text(topic.zh).font(.title2.bold())

                    HStack(spacing: 12) {
                        StatTile(value: Endurance.secondsText(target), label: "目标开口时长", tint: .blue)
                        StatTile(value: "第 \(trainingDay) 天", label: "训练进度", tint: .green)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("可以这样开头").font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(topic.starters, id: \.self) { s in
                                Text(s)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1), in: Capsule())
                            }
                        }
                    }

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("试着用上最近学的语块").font(.headline)
                            FlowLayout(spacing: 6) {
                                ForEach(suggestions) { c in
                                    Text(c.phrase)
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.purple.opacity(0.1), in: Capsule())
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("规则").font(.headline)
                        Label("只算你开口的时间，3 秒以内的换气停顿也算", systemImage: "waveform")
                        Label("停顿超过 \(Int(Endurance.pauseSeconds)) 秒记一次卡壳，超过 \(Int(Endurance.stopSilenceSeconds)) 秒自动结束", systemImage: "pause.circle")
                        Label("卡住了别停：用 Let me think… / How should I put it… 撑住，或者用最简单的英文绕过去", systemImage: "lightbulb")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            PrimaryButton("开始说") { start() }
                .padding()
        }
    }

    // MARK: - 录音中

    private var recordingView: some View {
        VStack(spacing: 20) {
            Text(topic.zh)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: min(1, recorder.speakingSeconds / target))
                    .stroke(recorder.speakingSeconds >= target ? Color.green : Color.blue,
                            style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: recorder.speakingSeconds)
                VStack(spacing: 4) {
                    Text("\(Int(recorder.speakingSeconds))")
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    Text("/ \(Int(target)) 秒").foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 220)

            // 音量条：说话时会跳动
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green.opacity(0.7))
                    .frame(width: geo.size.width * CGFloat(recorder.level))
                    .animation(.linear(duration: 0.1), value: recorder.level)
            }
            .frame(height: 8)
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 40)

            HStack(spacing: 24) {
                Label("卡壳 \(recorder.pauses)", systemImage: "pause.circle")
                Label("\(PhraseMatcher.words(recorder.transcript).count) 个词", systemImage: "text.word.spacing")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if recorder.hasSpoken && recorder.silence > Endurance.pauseSeconds {
                Text("卡住了？先说 Let me think… 撑住！")
                    .font(.headline)
                    .foregroundStyle(.orange)
            } else if !recorder.hasSpoken {
                Text("开始说吧，计时从你开口算起").foregroundStyle(.secondary)
            }

            ScrollView {
                Text(recorder.transcript.isEmpty ? " " : recorder.transcript)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding(.horizontal)

            Spacer()
            PrimaryButton("说完了") { finish() }
                .padding()
        }
        .padding(.top)
    }

    // MARK: - 结果

    private func resultView(_ set: EnduranceSet) -> some View {
        let firstMilestone = milestones.first { $0.persistentModelID != set.persistentModelID }
        let matches = Endurance.matches(for: stuckText, in: library.chunks)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 6) {
                    Image(systemName: set.passed ? "checkmark.seal.fill" : "flame.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(set.passed ? .green : .orange)
                    Text(set.passed ? "耐力达标！" : "还差 \(Int((set.targetSeconds - set.speakingSeconds).rounded(.up))) 秒，再来一组")
                        .font(.title2.bold())
                }
                .frame(maxWidth: .infinity)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(value: Endurance.secondsText(set.speakingSeconds), label: "开口时长 / 目标 \(Int(set.targetSeconds)) 秒", tint: .blue)
                    StatTile(value: "\(set.pauses)", label: "卡壳次数", tint: .orange)
                    StatTile(value: "\(set.words)", label: "说了多少个词", tint: .purple)
                    StatTile(value: "\(set.chunksUsed)", label: "用上的语块", tint: .green)
                }

                if let file = set.audioFile {
                    Button {
                        player.toggle(file)
                    } label: {
                        Label(player.playing == file ? "停止" : "听听刚才的自己", systemImage: player.playing == file ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if set.milestone, let first = firstMilestone, let firstFile = first.audioFile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("和第 \(first.trainingDay) 天对比").font(.headline)
                        Text("开口 \(Endurance.secondsText(first.speakingSeconds)) → \(Endurance.secondsText(set.speakingSeconds))，卡壳 \(first.pauses) → \(set.pauses) 次")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            player.toggle(firstFile)
                        } label: {
                            Label(player.playing == firstFile ? "停止" : "听第 \(first.trainingDay) 天的录音", systemImage: "play.circle")
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("卡壳本").font(.headline)
                    Text("刚才哪里想说却说不出？用中文记下来，先在语块库里帮你找现成说法。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("比如：我想说“推迟会议”", text: $stuckText)
                            .textFieldStyle(.roundedBorder)
                        Button("记下") { saveStuck() }
                            .disabled(stuckText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(matches) { c in
                        HStack {
                            Text(c.phrase).fontWeight(.semibold)
                            Text(c.meaning).foregroundStyle(.secondary)
                            Spacer()
                            SpeakButton(text: c.example)
                        }
                        .font(.subheadline)
                    }
                    if !stuckText.isEmpty && matches.isEmpty {
                        Text("语块库里暂时没有，记下来以后补充").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(stuckNotes, id: \.self) { note in
                        Label(note, systemImage: "bookmark.fill").font(.subheadline)
                    }
                }

                if !set.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("识别到你说的").font(.caption).foregroundStyle(.secondary)
                        Text(set.transcript).font(.body.italic())
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        result = nil
                    } label: {
                        Text("再来一组").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    if set.passed {
                        PrimaryButton("完成") { dismiss() }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - 动作

    private func start() {
        player.stop()
        Speaker.shared.stop()
        let name = "\(UUID().uuidString).m4a"
        recorder.onAutoStop = { finish() }
        if recorder.start(to: RecordingStore.url(name)) {
            pendingFile = name
        }
    }

    @State private var pendingFile: String?

    private func finish() {
        guard recorder.isRecording else { return }
        recorder.stop()
        let transcript = recorder.transcript
        // 用上的语块：至少两个词、并且在识别结果里基本连在一起出现才算
        let heard = PhraseMatcher.words(transcript)
        let used = library.chunks.filter { chunk in
            chunk.phrase.components(separatedBy: "/").contains { alt in
                let w = PhraseMatcher.words(alt)
                return w.count >= 2 && OrderChecker.findSegment(heard, w) != nil
            }
        }.count
        let set = EnduranceSet(
            trainingDay: trainingDay,
            topic: topic.zh,
            targetSeconds: target,
            speakingSeconds: recorder.speakingSeconds,
            pauses: recorder.pauses,
            words: PhraseMatcher.words(transcript).count,
            chunksUsed: used,
            passed: recorder.speakingSeconds >= target,
            audioFile: recorder.hasSpoken ? pendingFile : nil,
            milestone: milestone,
            transcript: transcript
        )
        context.insert(set)
        try? context.save()
        result = set
    }

    private func saveStuck() {
        let text = stuckText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        context.insert(StuckNote(text: text))
        try? context.save()
        stuckNotes.append(text)
        stuckText = ""
    }
}

/// 录音对比 + 耐力记录
struct RecordingsView: View {
    @Query(sort: \EnduranceSet.date, order: .reverse) private var sets: [EnduranceSet]
    @State private var player = RecordingPlayer()

    var body: some View {
        let milestones = sets.filter(\.milestone).reversed()
        List {
            Section {
                if milestones.isEmpty {
                    Text("第 1 天的耐力训练会录下你的第一段自我介绍，之后每 30 天用同一个题目再录一次。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(milestones)) { set in row(set) }
            } header: {
                Text("里程碑录音（同一个题目）")
            } footer: {
                Text("把第 1 天和最近一次放在一起听，进步一听就知道。")
            }
            Section("全部耐力记录") {
                ForEach(sets) { set in row(set) }
            }
        }
        .navigationTitle("录音对比")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }

    private func row(_ set: EnduranceSet) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(set.trainingDay) 天 · \(set.date.formatted(.dateTime.month().day()))").font(.subheadline.bold())
                Text("开口 \(Endurance.secondsText(set.speakingSeconds)) · 卡壳 \(set.pauses) · \(set.words) 词 · 语块 \(set.chunksUsed)")
                    .font(.caption)
                    .foregroundStyle(set.passed ? .green : .secondary)
            }
            Spacer()
            if let file = set.audioFile {
                Button {
                    player.toggle(file)
                } label: {
                    Image(systemName: player.playing == file ? "stop.circle.fill" : "play.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// 卡壳本：练习时想说却说不出的话
struct StuckNotesView: View {
    @Environment(\.modelContext) private var context
    @Environment(ChunkLibrary.self) private var library
    @Query(sort: \StuckNote.date, order: .reverse) private var notes: [StuckNote]

    var body: some View {
        List {
            if notes.isEmpty {
                Text("耐力训练结束后，把想说却说不出的话记在这里。").foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.text).font(.headline)
                    let matches = Endurance.matches(for: note.text, in: library.chunks)
                    if matches.isEmpty {
                        Text("语块库里暂时没有现成说法").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(matches) { c in
                        HStack {
                            Text(c.phrase).fontWeight(.semibold)
                            Text(c.meaning).foregroundStyle(.secondary)
                            Spacer()
                            SpeakButton(text: c.example)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { notes[$0] }.forEach(context.delete)
                try? context.save()
            }
        }
        .navigationTitle("卡壳本")
        .navigationBarTitleDisplayMode(.inline)
    }
}
