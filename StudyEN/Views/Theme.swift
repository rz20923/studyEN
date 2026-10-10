import SwiftUI

/// 设计稿「语块 App 设计方案」的颜色和字体
enum Theme {
    static let ground = Color(hex: 0xF1F2EE)
    static let ink = Color(hex: 0x111311)
    static let inkSoft = Color(hex: 0x1C1F1C)
    static let muted = Color(hex: 0x6B6F68)
    static let faint = Color(hex: 0x8A8E86)
    static let line = Color(hex: 0xE1E4DC)
    static let chip = Color(hex: 0xE4E6E0)
    static let accent = Color(hex: 0xFF5A1F)
    static let accentDark = Color(hex: 0xB53A0E)
    static let accentTint = Color(hex: 0xFFF4EF)
    static let accentSoft = Color(hex: 0xFFE1D4)
    static let green = Color(hex: 0x1F7A47)
    static let greenTint = Color(hex: 0xE3F3E8)

    /// 英文句子用圆体
    static func en(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// 三块积木的标志
struct BlocksLogo: View {
    var size: CGFloat = 26

    var body: some View {
        VStack(spacing: size * 0.06) {
            RoundedRectangle(cornerRadius: size * 0.08).fill(Theme.ink).frame(width: size * 0.38, height: size * 0.19)
            RoundedRectangle(cornerRadius: size * 0.1).fill(Theme.accent).frame(width: size * 0.62, height: size * 0.23)
            RoundedRectangle(cornerRadius: size * 0.12).fill(Theme.ink).frame(width: size * 0.85, height: size * 0.3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 顶部一行：DAY N + 当前在做什么 + 连续天数 + 5 段进度
struct DayHeader: View {
    let day: Int
    let label: String
    let streak: Int
    /// 5 步是否完成
    let done: [Bool]
    let current: Int?

    private let names = ["热身", "新课题", "对话", "开口", "测试"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("DAY \(day)").font(Theme.en(22, .heavy))
                Text(label).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                Label("\(streak)", systemImage: "flame.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.ink)
                    .labelStyle(FlameLabelStyle())
            }
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(done[i] ? Theme.ink : (i == current ? Theme.accent : Color(hex: 0xDADDD5)))
                        .frame(height: 5)
                }
            }
            HStack {
                ForEach(0..<5, id: \.self) { i in
                    Text(names[i])
                        .font(.system(size: 11, weight: i == current ? .bold : .regular))
                        .foregroundStyle(i == current ? Theme.accentDark : Theme.faint)
                    if i < 4 { Spacer() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

private struct FlameLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

/// 大圆形麦克风按钮
struct MicButton: View {
    let isRecording: Bool
    var size: CGFloat = 80
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(isRecording ? Color.white : Theme.accent)
                .frame(width: size, height: size)
                .background(isRecording ? Theme.accent : Theme.ink, in: Circle())
                .overlay(Circle().stroke(isRecording ? Theme.accentSoft : Theme.line, lineWidth: 8).padding(-8))
                .symbolEffect(.pulse, isActive: isRecording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "正在听，点击结束" : "开始说")
    }
}

/// 黑色主按钮
struct InkButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).foregroundStyle(Theme.accent) }
                Text(title).font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

/// 小圆角标签
struct Tag: View {
    let text: String
    var fg: Color = Color(hex: 0x4B4F48)
    var bg: Color = Theme.chip

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bg, in: Capsule())
    }
}

/// 白色圆形小按钮（播放、慢速等）
struct RoundIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(Color.white, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 听 / 读 / 说 分段指示
struct StageSwitcher: View {
    let current: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(["听", "读", "说"].enumerated()), id: \.offset) { i, name in
                Text(name)
                    .font(.subheadline.weight(i == current ? .bold : .regular))
                    .foregroundStyle(i == current ? Color.white : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(i == current ? Theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(4)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 一句话的词：重读加粗、弱读变浅，下面是音标或汉字；读错的词标红；点词看嘴型
struct TokenLine: View {
    @Environment(ChunkLibrary.self) private var library
    @AppStorage("zhPron") private var zhPron = false
    let key: String
    let range: Range<Int>
    var size: CGFloat = 21
    var color: Color = Theme.ink
    var subColor: Color = Theme.faint
    /// 和 range 等长：false 的词标红
    var feedback: [Bool]?

    @State private var selected: WordRef?

    var body: some View {
        if let s = library.pron.sentences[key] {
            let links = Set(s.links.map(\.i))
            FlowLayout(spacing: 4) {
                ForEach(Array(range.clamped(to: 0..<s.tokens.count)), id: \.self) { i in
                    let t = s.tokens[i]
                    let bad = feedback.map { i - range.lowerBound < $0.count && !$0[i - range.lowerBound] } ?? false
                    HStack(alignment: .top, spacing: 1) {
                        Button {
                            selected = WordRef(token: t.t)
                        } label: {
                            VStack(spacing: 1) {
                                Text(t.t)
                                    .font(Theme.en(t.weak == true ? size * 0.82 : size, t.stress ? .bold : .medium))
                                    .foregroundStyle(bad ? Color.red : (t.stress ? color : color.opacity(0.6)))
                                    .underline(bad, color: .red)
                                Text(zhPron ? (t.zh ?? " ") : (t.ipa.map { "/\($0)/" } ?? " "))
                                    .font(.system(size: zhPron ? 12 : 11, weight: zhPron ? .bold : .regular))
                                    .foregroundStyle(zhPron ? Theme.accent : (t.weak == true ? Color.orange : subColor))
                            }
                        }
                        .buttonStyle(.plain)
                        if links.contains(i) && i + 1 < range.upperBound {
                            Text("‿").font(.headline).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .sheet(item: $selected) { ref in WordGuideSheet(token: ref.token) }
        }
    }
}

/// 音标 / 汉字 小切换
struct PronToggle: View {
    @AppStorage("zhPron") private var zhPron = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { zh in
                Button {
                    zhPron = zh
                } label: {
                    Text(zh ? "汉字" : "音标")
                        .font(.caption.weight(zhPron == zh ? .bold : .regular))
                        .foregroundStyle(zhPron == zh ? Theme.ink : Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(zhPron == zh ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 判定结果小标签：骨架完整 / 槽位填对
struct CheckChips: View {
    let frameOK: Bool
    let slotOK: Bool

    var body: some View {
        HStack(spacing: 8) {
            chip("骨架完整", ok: frameOK)
            chip("槽位填对", ok: slotOK)
        }
    }

    private func chip(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark" : "xmark")
            .font(.footnote.bold())
            .foregroundStyle(ok ? Theme.green : Color.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(ok ? Theme.greenTint : Color.red.opacity(0.1), in: Capsule())
    }
}
