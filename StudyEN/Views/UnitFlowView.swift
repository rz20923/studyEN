import SwiftUI
import SwiftData

/// 一个框架单元：听（够 5 遍 + 答意思）→ 读（分块跟读 + 凭记忆换词说）→ 说
struct UnitFlowView: View {
    let topic: Topic
    let unit: TopicUnit

    @Environment(\.modelContext) private var context
    @Environment(ChunkLibrary.self) private var library
    @State private var speech = SpeechChecker()
    @State private var stage = 0

    // 听
    @State private var plays = 0
    @State private var choices: [String] = []
    @State private var picked: String?
    @State private var understood = false

    // 读
    @State private var readStep = 0
    @State private var fullFeedback: [Bool]?
    @State private var howTo: HowTo?

    // 说
    @State private var promptIndex = 0
    @State private var attempts = 0
    @State private var mustRead = false
    @State private var spoken: FrameMatcher.Result?
    @State private var promptDone = false

    @State private var feedback: String?

    static let requiredPlays = 5

    private struct HowTo: Identifiable {
        let id = UUID()
        let range: Range<Int>
        let text: String
    }

    private enum ReadStep: Hashable {
        case part(Range<Int>, String, Bool)
        case whole
        case swap(String)
    }

    private var tokens: [String] { unit.example.split(separator: " ").map(String.init) }

    private var readSteps: [ReadStep] {
        let r = unit.exampleRanges
        var steps: [ReadStep] = []
        func text(_ range: Range<Int>) -> String { tokens[range].joined(separator: " ") }
        if !r.before.isEmpty { steps.append(.part(r.before, text(r.before), false)) }
        if !r.slot.isEmpty { steps.append(.part(r.slot, text(r.slot), true)) }
        if r.after.count >= 2 { steps.append(.part(r.after, text(r.after), false)) }
        steps += [.whole, .whole]
        // 换词说：例句以外的每个选项都说一遍，而且凭记忆说
        let slotText = text(r.slot).lowercased()
        for option in unit.options where !slotText.contains(option.lowercased()) {
            steps.append(.swap(option))
        }
        return steps
    }

    var body: some View {
        VStack(spacing: 0) {
            StageSwitcher(current: stage)
                .padding(.horizontal, 20)
                .padding(.top, 14)
            switch stage {
            case 0: listenView
            case 1: readView
            default: speakView
            }
        }
        .onDisappear { speech.stop(notify: false) }
        .sheet(item: $howTo) { h in ChunkHowToSheet(key: unit.id, range: h.range, text: h.text) }
    }

    // MARK: - 听：必须听够 5 遍，再回答意思

    private var listenView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 10)
            Text("盲听 · 第 \(min(plays, Self.requiredPlays)) / \(Self.requiredPlays) 遍")
                .font(.footnote.bold()).foregroundStyle(Theme.accent)
            Text(plays < Self.requiredPlays ? "先只听，不看字" : (understood ? "对照着再听一遍" : "这句话是什么意思？"))
                .font(.system(size: 22, weight: .black)).padding(.top, 4)
            Text(plays < Self.requiredPlays ? "耳朵抓住加重的词就够了，小词会被吞掉" : "听够了，选出它的意思")
                .font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 2)

            waveform.padding(.vertical, 22)

            if understood {
                TokenLine(key: unit.id, range: 0..<tokens.count, size: 22)
                Text(unit.exampleZh).font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 8)
            } else if plays >= Self.requiredPlays {
                VStack(spacing: 10) {
                    ForEach(choices, id: \.self) { c in
                        let right = c == unit.exampleZh
                        Button {
                            picked = c
                            if right { understood = true } else { feedback = "不对，再听一遍想想" }
                        } label: {
                            Text(c).font(.body.weight(.medium))
                                .foregroundStyle(picked == c ? .white : Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(picked == c ? (right ? Theme.green : Color.red) : Color.white, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(stressFlags.enumerated()), id: \.offset) { i, stressed in
                        Capsule()
                            .fill(stressed ? Color(hex: 0xFFC7B0) : Color(hex: 0xDADDD5))
                            .frame(width: CGFloat(max(tokens[i].count, 2)) * 9, height: stressed ? 14 : 10)
                    }
                }
                Text("橙色 = 重读的位置").font(.caption).foregroundStyle(Theme.faint).padding(.top, 10)
            }
            if let feedback, !understood { Text(feedback).font(.subheadline.bold()).foregroundStyle(Theme.accentDark).padding(.top, 8) }
            Spacer()
            HStack(alignment: .center) {
                RoundIconButton(systemName: "tortoise.fill", label: "慢速") { play(slow: true) }
                Spacer()
                Button { play(slow: false) } label: {
                    Image(systemName: "play.fill").font(.system(size: 28)).foregroundStyle(.white)
                        .frame(width: 80, height: 80).background(Theme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("再听一遍")
                Spacer()
                RoundIconButton(systemName: "arrow.right", label: "下一步：读") {
                    feedback = nil
                    stage = 1
                    playTarget()
                }
                .opacity(understood ? 1 : 0.3)
                .disabled(!understood)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .task {
            if choices.isEmpty {
                let others = topic.units.filter { $0.id != unit.id }.map(\.exampleZh).shuffled().prefix(2)
                choices = ([unit.exampleZh] + others).shuffled()
            }
            if plays == 0 { play(slow: false) }
        }
    }

    private func play(slow: Bool) {
        plays += 1
        feedback = nil
        picked = nil
        Speaker.shared.speak(unit.example, slow: slow)
    }

    private var stressFlags: [Bool] {
        let toks = library.pron.sentences[unit.id]?.tokens ?? []
        return tokens.indices.map { $0 < toks.count ? toks[$0].stress : true }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(stressFlags.enumerated()), id: \.offset) { i, stressed in
                ForEach(0..<3, id: \.self) { k in
                    Capsule()
                        .fill(stressed ? Theme.accent : Theme.ink)
                        .frame(width: 5, height: CGFloat(stressed ? [44, 64, 36][k] : [14, 22, 12][k]) * (i % 2 == 0 ? 1 : 0.85))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .accessibilityHidden(true)
    }

    // MARK: - 读：分块跟读 → 整句 ×2 → 凭记忆换词说

    private var currentRead: ReadStep { readSteps[min(readStep, readSteps.count - 1)] }
    private var swapping: String? { if case .swap(let o) = currentRead { return o }; return nil }

    private var readView: some View {
        let r = unit.exampleRanges
        let activeRange: Range<Int>? = { if case .part(let range, _, _) = currentRead { return range }; return nil }()
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(unit.intent).font(.caption.bold()).foregroundStyle(Theme.muted)
                Spacer()
                PronToggle()
            }
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 10) {
                if let option = swapping {
                    // 凭记忆说：骨架藏起来，只给槽位的中文
                    VStack(alignment: .leading, spacing: 8) {
                        Text("凭记忆说整句，把槽位换成").font(.footnote).foregroundStyle(Theme.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(unit.optionZh(option)).font(.system(size: 26, weight: .black)).foregroundStyle(Theme.accent)
                            Text(option).font(Theme.en(16, .medium)).foregroundStyle(Theme.muted)
                        }
                        Text(unit.skeleton).font(Theme.en(18, .bold)).foregroundStyle(Theme.ink).blur(radius: 7)
                            .accessibilityHidden(true)
                    }
                } else {
                    if !r.before.isEmpty { block(r.before, slot: false, active: activeRange == r.before) }
                    block(r.slot, slot: true, active: activeRange == r.slot)
                    if !r.after.isEmpty { block(r.after, slot: false, active: activeRange == r.after) }
                    Text(unit.exampleZh).font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
            .padding(.top, 10)

            if swapping == nil {
                Text("点任意一块，看这一块怎么读").font(.caption).foregroundStyle(Theme.faint).padding(.top, 8)
            }

            Spacer(minLength: 8)
            readProgress
            if let feedback { Text(feedback).font(.subheadline.bold()).foregroundStyle(Theme.accentDark).padding(.top, 8) }
            if speech.isRecording {
                Text(speech.transcript.isEmpty ? "正在听…" : speech.transcript).font(Theme.en(15)).foregroundStyle(Theme.muted).padding(.top, 6)
            }
            HStack(spacing: 12) {
                RoundIconButton(systemName: "speaker.wave.2.fill", label: "播放", size: 56) { playTarget() }
                Button { toggleRead() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: speech.isRecording ? "waveform" : "mic.fill").foregroundStyle(speech.isRecording ? .white : Theme.accent)
                        Text(speech.isRecording ? "正在听…说完停一下" : readButtonTitle).font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(speech.isRecording ? Theme.accent : Theme.ink, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 20)
    }

    private func block(_ range: Range<Int>, slot: Bool, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if slot {
                Text(unit.slotHint).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accentSoft)
            }
            TokenLine(key: unit.id, range: range, size: 20,
                      color: slot ? .white : Theme.ink,
                      subColor: slot ? Theme.accentSoft : Theme.faint,
                      feedback: fullFeedback.map { Array($0[range.clamped(to: 0..<$0.count)]) },
                      tappable: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(slot ? Theme.accent : Theme.line, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? Theme.ink : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            howTo = HowTo(range: range, text: tokens[range].joined(separator: " "))
        }
    }

    private var readProgress: some View {
        let steps = readSteps
        let partCount = steps.filter { if case .part = $0 { return true }; return false }.count
        let swapCount = steps.count - partCount - 2
        let doneParts = min(readStep, partCount)
        let doneWhole = min(max(readStep - partCount, 0), 2)
        let doneSwap = max(readStep - partCount - 2, 0)
        return HStack(spacing: 6) {
            progressChip("分块 \(doneParts)/\(partCount)", done: doneParts == partCount, current: readStep < partCount)
            progressChip("整句 \(doneWhole)/2", done: doneWhole == 2, current: readStep >= partCount && readStep < partCount + 2)
            progressChip("换词 \(doneSwap)/\(swapCount)", done: false, current: readStep >= partCount + 2)
        }
    }

    private func progressChip(_ text: String, done: Bool, current: Bool) -> some View {
        Text(done ? "✓ \(text)" : text)
            .font(.caption.bold())
            .foregroundStyle(done || current ? Color.white : Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(done ? Theme.ink : (current ? Theme.accent : Theme.chip), in: Capsule())
    }

    private var readButtonTitle: String {
        switch currentRead {
        case .part: return "跟读这一块"
        case .whole: return "读整句"
        case .swap: return "说整句"
        }
    }

    private var readTargetText: String {
        switch currentRead {
        case .part(_, let text, _): return text
        case .whole: return unit.example
        case .swap(let o): return unit.sentence(with: o)
        }
    }

    private func playTarget() {
        if case .part = currentRead {
            Speaker.shared.speak(readTargetText, slow: true)
        } else {
            Speaker.shared.speak(readTargetText)
        }
    }

    private func toggleRead() {
        if speech.isRecording { speech.stop(); return }
        feedback = nil
        let step = currentRead
        let target = readTargetText
        speech.onTranscript = { text in
            if readPassed(step, text) {
                speech.stop(notify: false)
                advanceRead()
            }
        }
        speech.onStop = { text in
            switch step {
            case .part(let range, let part, _):
                var fb = Array(repeating: true, count: tokens.count)
                for (k, item) in PhraseMatcher.wordFeedback(part, transcript: text).enumerated() where range.lowerBound + k < fb.count {
                    fb[range.lowerBound + k] = item.ok
                }
                fullFeedback = fb
                feedback = "红色的词没读清，点那一块看怎么读"
            case .whole:
                fullFeedback = PhraseMatcher.wordFeedback(unit.example, transcript: text).map(\.ok)
                feedback = "红色的词没读清，点那一块看怎么读"
            case .swap(let o):
                let r = FrameMatcher.check(unit: unit, answer: unit.sentence(with: o), transcript: text)
                feedback = r.frameOK ? "槽位要换成 \(o)" : "骨架没说完整，点喇叭听一遍"
            }
        }
        if !speech.start(hints: [target]) { feedback = "语音识别暂不可用" }
    }

    private func readPassed(_ step: ReadStep, _ text: String) -> Bool {
        switch step {
        case .part(_, let target, _): return PhraseMatcher.readingScore(target, transcript: text) >= 0.65
        case .whole: return PhraseMatcher.readingScore(unit.example, transcript: text) >= 0.65
        case .swap(let o): return FrameMatcher.check(unit: unit, answer: unit.sentence(with: o), transcript: text).passed
        }
    }

    private func advanceRead() {
        fullFeedback = nil
        feedback = nil
        speech.clear()
        if readStep + 1 >= readSteps.count {
            stage = 2
        } else {
            readStep += 1
            // 换词说是凭记忆，不先播放答案
            if swapping == nil { playTarget() }
        }
    }

    // MARK: - 说

    private var prompt: TopicUnit.Prompt { unit.prompts[min(promptIndex, unit.prompts.count - 1)] }

    private var speakView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("你想说 · \(promptIndex + 1) / \(unit.prompts.count)").font(.caption).foregroundStyle(Color(hex: 0xA5AAA0))
                Text(prompt.zh).font(.title3.bold()).foregroundStyle(.white)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20))
            .padding(.top, 18)

            if promptDone || mustRead {
                TokenLine(key: "\(unit.id):a\(promptIndex)", range: 0..<prompt.answer.split(separator: " ").count, size: 22, fallback: prompt.answer)
                    .padding(.top, 4)
            } else {
                FlowLayout(spacing: 6) {
                    if !unit.before.isEmpty { Text(unit.before).foregroundStyle(Color(hex: 0x9A9E96)) }
                    Text(unit.slotHint)
                        .foregroundStyle(Theme.accentDark)
                        .padding(.horizontal, 12)
                        .background(Theme.accentTint, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4])).foregroundStyle(Theme.accent))
                    if !unit.after.isEmpty { Text(unit.after).foregroundStyle(Color(hex: 0x9A9E96)) }
                }
                .font(Theme.en(20, .bold))
                .padding(.top, 4)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("听到你说").font(.caption).foregroundStyle(Theme.faint)
                Text(speech.transcript.isEmpty ? (speech.isRecording ? "…" : " ") : speech.transcript)
                    .font(Theme.en(16, .medium))
                    .foregroundStyle(Color(hex: 0x3A3D38))
                if let spoken { CheckChips(frameOK: spoken.frameOK, slotOK: spoken.slotOK) }
                if let feedback { Text(feedback).font(.subheadline.bold()).foregroundStyle(Theme.accentDark) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))

            if promptDone {
                InkButton(promptIndex + 1 >= unit.prompts.count ? "完成这个框架" : "下一句") { nextPrompt() }
                    .padding(.bottom, 16)
            } else {
                HStack {
                    Button("看答案") {
                        speech.stop(notify: false)
                        mustRead = true
                        feedback = "照着读一遍"
                        Speaker.shared.speak(prompt.answer)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 72)
                    Spacer()
                    MicButton(isRecording: speech.isRecording) { toggleSpeak() }
                    Spacer()
                    Color.clear.frame(width: 72, height: 1)
                }
                .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 20)
    }

    private func toggleSpeak() {
        if speech.isRecording { speech.stop(); return }
        feedback = nil
        spoken = nil
        let p = prompt
        speech.onTranscript = { text in
            let ok: Bool
            if mustRead {
                ok = PhraseMatcher.readingScore(p.answer, transcript: text) >= 0.65
            } else {
                let r = FrameMatcher.check(unit: unit, answer: p.answer, transcript: text)
                ok = r.passed
                if ok { spoken = r }
            }
            if ok {
                speech.stop(notify: false)
                promptDone = true
                Speaker.shared.speak(p.answer)
            }
        }
        speech.onStop = { text in
            if mustRead {
                feedback = "没读清，照着再读一遍"
                return
            }
            let r = FrameMatcher.check(unit: unit, answer: p.answer, transcript: text)
            spoken = r
            attempts += 1
            if attempts >= 2 {
                mustRead = true
                feedback = "看正确说法，照着读一遍"
                Speaker.shared.speak(p.answer)
            } else {
                feedback = !r.frameOK ? "骨架没说完整：\(unit.skeleton)" : "槽位不对，再想想“\(p.zh)”"
            }
        }
        if !speech.start(hints: [p.answer]) { feedback = "语音识别暂不可用" }
    }

    private func nextPrompt() {
        speech.clear()
        spoken = nil
        feedback = nil
        attempts = 0
        mustRead = false
        promptDone = false
        if promptIndex + 1 >= unit.prompts.count {
            completeUnit()
        } else {
            promptIndex += 1
        }
    }

    /// 单元学完：进入间隔复习（明天开始复习）
    private func completeUnit() {
        let p = context.progress(for: unit.id) ?? {
            let created = ChunkProgress(chunkID: unit.id)
            context.insert(created)
            return created
        }()
        p.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        context.studyDay().newLearned += 1
        try? context.save()
    }
}
