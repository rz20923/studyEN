import Foundation

/// 180 天强制训练的规则常量。
/// "第 N 天" 只按**达标打卡**的天数计算，不按日历天数：没达标的日子不算数。
enum Plan {
    static let totalDays = 180
    static let phaseOneDays = 30

    /// 每天的新语块数不是固定值：由“还没学的语块 ÷ 第一阶段剩余达标日”算出，
    /// 保证 30 个达标日内把清单全部学完。内容清单增减时自动适配。
    static func dailyQuota(unlearned: Int, checkedInDaysBeforeToday: Int) -> Int {
        let daysLeft = max(1, phaseOneDays - checkedInDaysBeforeToday)
        return Int((Double(unlearned) / Double(daysLeft)).rounded(.up))
    }
    /// 新语块必须用语音跟读例句达标的次数
    static let readAloudTimes = 3
    /// 跟读判定：读对例句中多少比例的词算一次达标
    static let readingPassScore = 0.75
    /// 闯关正确率达到多少才能打卡
    static let examPassRate = 0.8
    /// 造句判定：自己说的句子至少多少个词
    static let ownSentenceMinWords = 5
    /// 闯关每题回答时限（秒）：衡量是否"脱口而出"
    static let examAnswerSeconds: Double = 6
    /// 阶段总考：全部语块限时回想，正确率达到多少才能进入下一阶段；没过就当天复习错题后重考
    static let phaseExamPassRate = 0.9
    /// 闯关时额外抽查的旧语块数
    static let examExtraOld = 5

    static let phases: [(range: ClosedRange<Int>, title: String)] = [
        (1...30, "生活情境语块"),
        (31...60, "第一人称自言自语"),
        (61...120, "单句影子跟读"),
        (121...180, "提问与接茬"),
    ]
}
