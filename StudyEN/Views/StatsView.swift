import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(ChunkLibrary.self) private var library
    @Query private var progresses: [ChunkProgress]
    @Query(sort: \StudyDay.day) private var days: [StudyDay]
    @Query private var phaseExams: [PhaseExam]
    @Query private var drillProgress: [DrillProgress]

    var body: some View {
        let checked = days.filter(\.checkedIn)
        let mastered = progresses.filter(\.isMastered).count
        let avgScore = checked.isEmpty ? 0 : checked.map(\.examScore).reduce(0, +) / Double(checked.count)

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        StatTile(value: "\(progresses.count)", label: "已学", tint: .blue)
                        StatTile(value: "\(mastered)", label: "已掌握", tint: .green)
                        StatTile(value: "\(Int(avgScore * 100))%", label: "闯关均分", tint: .orange)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    grid(checkedCount: checked.count)
                } header: {
                    Text("180 天达标进度 · \(checked.count) / \(Plan.totalDays)")
                } footer: {
                    Text("每一格代表一个达标日。没达标的日子不占格子。")
                }

                if !weakest.isEmpty {
                    Section {
                        ForEach(weakest) { p in
                            HStack {
                                Text(library.chunk(id: p.chunkID)?.phrase ?? p.chunkID)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("忘了 \(p.lapseCount) 次")
                                    .foregroundStyle(.red)
                                if let latency = p.lastLatency {
                                    Text(String(format: "%.1f 秒", latency))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .font(.subheadline)
                        }
                    } header: {
                        Text("最薄弱的语块")
                    } footer: {
                        Text("秒数是最近一次答对的反应时间，越短越接近脱口而出。")
                    }
                }

                Section {
                    LabeledContent("已练", value: "\(drillProgress.count) / \(library.drills.count) 句")
                    LabeledContent("一次说对", value: "\(drillProgress.filter(\.firstTry).count) 句")
                } header: {
                    Text("语序造句")
                } footer: {
                    Text("一次说对的比例越高，说明语序越成为本能。")
                }

                Section("最近记录") {
                    ForEach(days.suffix(14).reversed()) { day in
                        HStack {
                            Text(day.day, format: .dateTime.month().day())
                            Spacer()
                            if day.checkedIn {
                                Text("达标 \(Int(day.examScore * 100))%").foregroundStyle(.green)
                            } else {
                                Text(day.examAttempts > 0 ? "未达标（挑战 \(day.examAttempts) 次）" : "未打卡")
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
            .navigationTitle("进度")
            .toolbar {
                ShareLink(item: exportJSON) {
                    Label("导出训练数据", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var weakest: [ChunkProgress] {
        Array(progresses.filter { $0.lapseCount > 0 }.sorted { $0.lapseCount > $1.lapseCount }.prefix(8))
    }

    /// 测试期把数据导出发给开发者，用来验证任务设计是否足够
    private var exportJSON: String {
        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "exportedAt": iso.string(from: .now),
            "days": days.map { [
                "day": iso.string(from: $0.day),
                "checkedIn": $0.checkedIn,
                "examScore": $0.examScore,
                "examAttempts": $0.examAttempts,
                "reviews": $0.reviews,
                "newLearned": $0.newLearned,
            ] as [String: Any] },
            "chunks": progresses.map { [
                "id": $0.chunkID,
                "box": $0.box,
                "reviewCount": $0.reviewCount,
                "lapseCount": $0.lapseCount,
                "lastLatency": $0.lastLatency ?? -1,
                "introduced": iso.string(from: $0.introducedDate),
            ] as [String: Any] },
            "drills": drillProgress.map { [
                "id": $0.drillID,
                "date": iso.string(from: $0.date),
                "firstTry": $0.firstTry,
            ] as [String: Any] },
            "phaseExams": phaseExams.map { [
                "phase": $0.phase,
                "passed": $0.passed,
                "bestScore": $0.bestScore,
                "attempts": $0.attempts,
            ] as [String: Any] },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func grid(checkedCount: Int) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 15)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<Plan.totalDays, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i < checkedCount ? phaseColor(day: i + 1) : Color.gray.opacity(0.15))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(.vertical, 6)
    }

    private func phaseColor(day: Int) -> Color {
        switch day {
        case 1...30: return .blue
        case 31...60: return .purple
        case 61...120: return .orange
        default: return .green
        }
    }
}
