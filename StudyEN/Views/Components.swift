import SwiftUI

struct StatTile: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title.bold()).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct KindTag: View {
    let kind: ChunkKind

    var body: some View {
        Text(kind == .phrasal ? "短语" : "支架")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((kind == .phrasal ? Color.blue : Color.purple).opacity(0.15), in: Capsule())
            .foregroundStyle(kind == .phrasal ? .blue : .purple)
    }
}

struct SpeakButton: View {
    let text: String
    var slow = false

    var body: some View {
        Button {
            Speaker.shared.speak(text, slow: slow)
        } label: {
            Image(systemName: slow ? "tortoise.fill" : "speaker.wave.2.fill")
                .font(.title3)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(slow ? "慢速朗读" : "朗读")
    }
}

struct RecordButton: View {
    let isRecording: Bool
    let idleTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isRecording ? "正在听…点我结束" : idleTitle,
                  systemImage: isRecording ? "waveform" : "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .symbolEffect(.variableColor.iterative, isActive: isRecording)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRecording ? .red : .accentColor)
        .controlSize(.large)
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

/// 题面：只给中文意思，逼用户自己说出英文
struct ChunkPromptView: View {
    let chunk: Chunk
    var showSentenceHint = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(chunk.meaning)
                .font(.largeTitle.bold())
            if let word = chunk.replaces {
                Label("别说 \(word)，用口语怎么说？", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            }
            if showSentenceHint {
                Text(chunk.exampleZh)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 答案：语块 + 例句 + 朗读
struct ChunkAnswerView: View {
    let chunk: Chunk

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(chunk.phrase).font(.largeTitle.bold())
                Spacer()
                SpeakButton(text: chunk.phrase)
            }
            HStack(spacing: 8) {
                Text(chunk.meaning)
                if let word = chunk.replaces {
                    Text("≈ \(word)").strikethrough().foregroundStyle(.secondary)
                }
            }
            .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(chunk.example).font(.title3.weight(.medium))
                    Spacer()
                    SpeakButton(text: chunk.example, slow: true)
                }
                Text(chunk.exampleZh).foregroundStyle(.secondary)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))

            if let tip = chunk.tip {
                Label(tip, systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
            Text("需要麦克风和语音识别权限").font(.title2.bold())
            Text("每日训练必须开口说，由语音识别判定是否达标。不开权限就无法训练和打卡。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            PrimaryButton("去设置里打开") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .padding(32)
    }
}

enum StepState {
    case locked, active, done
}

struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let state: StepState
    let action: () -> Void

    private var icon: String {
        switch state {
        case .locked: return "lock.fill"
        case .active: return "\(number).circle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .locked: return .gray
        case .active: return .blue
        case .done: return .green
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("第 \(number) 步 · \(title)")
                        .font(.headline)
                        .foregroundStyle(state == .locked ? .secondary : .primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if state == .active {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(state != .active)
    }
}
