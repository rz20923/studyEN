import Foundation
import SwiftData

/// 每个语块的复习状态（Leitner 盒子 + 到期日）
@Model
final class ChunkProgress {
    @Attribute(.unique) var chunkID: String
    var box: Int
    var dueDate: Date
    var introducedDate: Date
    var lastReviewed: Date?
    var reviewCount: Int
    var lapseCount: Int
    /// 最近一次答对用时（秒），衡量"脱口而出"的程度
    var lastLatency: Double?

    init(chunkID: String, now: Date = .now) {
        self.chunkID = chunkID
        self.box = 0
        self.dueDate = now
        self.introducedDate = now
        self.reviewCount = 0
        self.lapseCount = 0
    }

    var isMastered: Bool { box >= SRS.masteredBox }
}

/// 每天的训练记录。checkedIn 只有闯关达标后才会变成 true。
@Model
final class StudyDay {
    @Attribute(.unique) var day: Date
    var reviews: Int = 0
    var newLearned: Int = 0
    var checkedIn: Bool = false
    var examScore: Double = 0
    var examAttempts: Int = 0

    init(day: Date) {
        self.day = day
    }
}

/// 语序造句完成记录
@Model
final class DrillProgress {
    @Attribute(.unique) var drillID: String
    var date: Date
    /// 第一次就说对（没有看答案）
    var firstTry: Bool

    init(drillID: String, firstTry: Bool) {
        self.drillID = drillID
        self.date = .now
        self.firstTry = firstTry
    }
}

/// 阶段总考记录：没通过就不能进入下一阶段
@Model
final class PhaseExam {
    @Attribute(.unique) var phase: Int
    var passed: Bool = false
    var bestScore: Double = 0
    var attempts: Int = 0
    var lastAttemptDay: Date?
    var passedDate: Date?

    init(phase: Int) {
        self.phase = phase
    }

    var attemptedToday: Bool {
        lastAttemptDay.map { Calendar.current.isDateInToday($0) } ?? false
    }
}

enum Rating {
    case again, good
}

enum SRS {
    /// 每个盒子对应的间隔天数
    static let intervals = [0, 1, 2, 4, 7, 15, 30, 60]
    static let masteredBox = 5

    static func apply(_ rating: Rating, to p: ChunkProgress, now: Date = .now) {
        switch rating {
        case .again:
            p.box = 0
            p.lapseCount += 1
            p.dueDate = now
        case .good:
            p.box = min(p.box + 1, intervals.count - 1)
            let today = Calendar.current.startOfDay(for: now)
            p.dueDate = Calendar.current.date(byAdding: .day, value: intervals[p.box], to: today) ?? now
        }
        p.reviewCount += 1
        p.lastReviewed = now
    }
}

extension ModelContext {
    func progress(for id: String) -> ChunkProgress? {
        let descriptor = FetchDescriptor<ChunkProgress>(predicate: #Predicate { $0.chunkID == id })
        return try? fetch(descriptor).first
    }

    func phaseExam(_ phase: Int) -> PhaseExam {
        let descriptor = FetchDescriptor<PhaseExam>(predicate: #Predicate { $0.phase == phase })
        if let record = try? fetch(descriptor).first {
            return record
        }
        let record = PhaseExam(phase: phase)
        insert(record)
        return record
    }

    func studyDay(for date: Date = .now) -> StudyDay {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<StudyDay>(predicate: #Predicate { $0.day == day })
        if let record = try? fetch(descriptor).first {
            return record
        }
        let record = StudyDay(day: day)
        insert(record)
        return record
    }
}
