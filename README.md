# StudyEN · 语块（第一阶段：第 1–30 天）

180 天浸入式口语计划的 iOS App，当前只实现 **第一部分：生活情境语块**。

## 产品逻辑：强制达标训练（不是学习记录）

**180 天只按“达标打卡日”计算**：当天没达标，这一天不算，计划不往前走。

每天三步，按顺序解锁：

1. **学新语块**（数量自动计算 = 未学语块 ÷ 第一阶段剩余达标日，保证 30 个达标日学完全部清单）：听例句 → 大声跟读，语音识别读对 ≥75% 的词才算一遍，必须达标 3 遍
2. **语序造句**：看中文句子，按「主 → 谓 → 宾 → 方式 → 地点 → 时间」说出英文，语音判定语序；3 次没过就看答案，照读正确句子才算完成
3. **开口复习**：只给中文，必须用英文**说出**语块（语音判定，3 次机会）；没过的本轮末尾重来，直到说对
4. **每日闯关**：今天的新语块 + 随机 5 个旧语块，不给例句提示，每题 2 次机会；
   正确率 ≥80% 才打卡；不达标 → 当场复习错题 → 马上重考，**当天练到达标为止，不推到明天**

没有“我会了”自评按钮，全部由语音识别判定；不给麦克风权限无法训练。
规则参数集中在 `StudyEN/Services/PlanSettings.swift`。

内容：220 个短语动词 + 119 个谈话润滑剂，共 339 个（约每天 11–12 个）；语序造句 100 句，覆盖 7 类句型。学习顺序为润滑剂打头并均匀穿插。
扩充内容只需编辑 `StudyEN/Resources/chunks.json`。

## 构建：Windows 开发 + GitHub Actions 云端编译（无需 Mac）

- `.github/workflows/ci.yml`：每次 push 自动在云端 Mac 编译，相当于本地的“编译检查”
- `.github/workflows/testflight.yml`：手动触发或推送 `v*` 标签 → 签名 → 上传 TestFlight

### 一次性准备（全部在 Windows 浏览器里完成）

1. 注册 Apple Developer Program（99 美元/年）
2. developer.apple.com → Identifiers：注册 App ID `com.studyen.app`
3. App Store Connect → 我的 App → 新建 App，套装 ID 选上一步的 ID
4. App Store Connect → 用户和访问 → 集成 → 生成 API 密钥（角色 App 管理），下载 `.p8`
5. GitHub 新建一个**私有**空仓库（如 `studyen-certs`），给 fastlane match 存加密证书
6. 在本项目仓库 Settings → Secrets and variables → Actions 中添加：

| Secret | 内容 |
|---|---|
| `TEAM_ID` | 开发者账号 Team ID（Membership 页面） |
| `ASC_KEY_ID` | API 密钥 ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8_BASE64` | `.p8` 文件的 base64（PowerShell：`[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXX.p8"))`） |
| `MATCH_GIT_URL` | 证书仓库地址，如 `https://github.com/you/studyen-certs.git` |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `用户名:PAT` 的 base64（PAT 需 repo 权限） |
| `MATCH_PASSWORD` | 自定一个加密密码 |

7. 首次运行：在 Variables 中添加 `MATCH_READONLY=false`，到 Actions 页手动运行 TestFlight；
   成功后把它改成 `true`（之后只读取证书，不再新建）。
8. iPhone 安装 TestFlight，用自己的 Apple ID 加入内部测试即可装上。

上架前需要在 `StudyEN/Assets.xcassets/AppIcon.appiconset` 放入 1024×1024 图标（无透明通道）。

### 有 Mac 时

```bash
brew install xcodegen
xcodegen generate
open StudyEN.xcodeproj
```

## 结构

```
project.yml                 XcodeGen 工程定义
StudyEN/App                 入口 + Tab
StudyEN/Models              Chunk（内容）、ChunkProgress / StudyDay（SwiftData）、SRS
StudyEN/Services            TTS、计划天数
StudyEN/Views               今天 / 练习 / 语块库 / 进度
StudyEN/Resources/chunks.json  语块内容
```

## 后续（第二阶段，第 31–60 天）

“第一人称自言自语”：预计加入录音 + 语音识别（Speech 框架）、场景提示卡、“卡壳词”睡前清单。
