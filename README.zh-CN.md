# Claude Watch

[English](README.md) · [中文](README.zh-CN.md)

一款 macOS 菜单栏应用,实时监控 `claude.ai` 账号的 5 小时滚动窗口和 7 天周期额度使用情况。常驻屏幕右上角,每 90 秒拉取一次,用一眼能看懂的方式告诉你"还能用多久"。

<img width="336" alt="Claude Watch 弹窗界面,显示 5H 和 Week 两个仪表以及用量曲线图" src="https://github.com/user-attachments/assets/53973ae3-6775-41ba-a565-e56165cfe221" />

## 安装

1. 从 [最新 Release](https://github.com/metalbreeze/claudewatch/releases) 下载 `ClaudeWatch-X.Y.Z.dmg`。
2. 打开 DMG,把 **Claude Watch** 拖到「应用程序」文件夹。
3. **首次启动**:应用使用 ad-hoc 签名(尚未做 Apple 公证),macOS 会弹出 *"Apple 无法验证此 App ..."* 拒绝打开。绕开方式:
   - 在「应用程序」中**右键点击** Claude Watch → **打开** → 在弹出的对话框里再次点 **打开** 确认。
   - macOS 会记住这次授权,以后双击就能正常启动。
4. 菜单栏出现 `⌬ ⏳` 图标。右键点击它 → **Import from cURL…**。
5. 粘贴一段从浏览器 DevTools 复制的 cURL(见下文)。结束。

系统要求:Apple Silicon Mac,macOS 13 及以上。Intel Mac 支持和公证签名版本在路线图里。

## 为什么用 cURL 粘贴,而不是登录表单?

claude.ai 的网页端被 Cloudflare 的反爬和 Google OAuth 对嵌入式 WebView 的限制双重保护着。把登录窗口塞进 App 内部要同时和这两层斗,体验很差(Cloudflare 验证码循环、Google 拒绝"此浏览器可能不安全")。

务实的做法:你反正会在真实浏览器里登录 claude.ai,那就直接借用现成的会话。打开 DevTools → 切到 Network 选项卡 → 刷新 `https://claude.ai/settings/usage` 页面 → 找到对 `/api/organizations/{你的 org uuid}/usage` 的请求 → 右键 → **Copy as cURL** → 粘贴到 App。

App 会从 cURL 里抽出 `sessionKey`、`cf_clearance` 这两个 cookie 和 User-Agent 字符串,本地存起来,用来每 90 秒打一次同样的接口。

## 数据存在哪里

- **Cookies 和 device ID**: `~/Library/Application Support/ClaudeWatch/secrets/`,文件权限 `0600`。除了 `claude.ai` 本身,**不会**发送到任何其他地方。
- **用量历史**: `~/Library/Application Support/ClaudeWatch/usage.db`(SQLite),仅本地。
- **没有分析、没有遥测、没有第三方服务。** 唯一的网络出站目标就是 `claude.ai`。

Cookie 过期后(`cf_clearance` 约 24 小时,`sessionKey` 通常以周计),再花 30 秒做一次 cURL 粘贴即可刷新。

## 弹窗里有什么

点击菜单栏图标会打开一个 340pt 宽的弹窗:

- **顶部两张仪表卡**: `5H`(绿色色调)和 `Week`(青色色调)。中间的大百分比数字在 ≥75% 时变黄,≥90% 时变红。
- **时间范围选择**: 1h / 8h / 24h / 1w。每个对应不同的横轴跨度。
- **图表** 最多包含四种线:
  - **绿色实线** —— 5h 窗口实际用量(任意时间范围)。
  - **青色实线** —— 7 天周期实际用量(仅 1w 视图)。
  - **灰色虚线** —— 短期 5h 预测(1h / 8h / 24h)。虚线密度表示可信度:`[5,2]` 接近实线 = 预测高可信; `[2,6]` 稀疏点 = 持平 / 不会触顶。
  - **靛蓝色虚线竖线** —— 5h 窗口或周窗口的重置边界。
- **预测说明**: "likely full at HH:MM"、"won't hit limit this window" 或 "stable",根据斜率和预测时间动态显示。

## 从源码构建

```bash
git clone https://github.com/metalbreeze/claudewatch.git
cd claudewatch
brew install xcodegen
xcodegen generate          # 生成 ClaudeWatch.xcodeproj
open ClaudeWatch.xcodeproj
# 在 Xcode 里选中 ClaudeWatchMac scheme,按 ⌘R 运行
```

跑包级单元测试(41 个,覆盖模型、存储、抓取、预测、告警、同步):

```bash
cd Packages/UsageCore
swift test
```

Xcode 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成,`.xcodeproj` 本身在 gitignore 里。

## 架构

单一 Xcode 工程,两个 target 加一个本地 Swift Package:

- **`Packages/UsageCore/`** —— 纯逻辑 Swift Package。模型、GRDB 支持的 SQLite 存储、Anthropic API 抓取、预测器、轮询控制器、通知引擎、CloudKit 同步。38+ 单元测试。
- **`Apps/ClaudeWatchMac/`** —— SwiftUI 菜单栏 App。设置 `LSUIElement = YES`(没有 Dock 图标)。负责弹窗、设置窗口和 cURL 导入流程。
- **`Apps/ClaudeWatchiOS/`** —— iOS 配套 App 的占位目录(计划中)。

技术栈:Swift 5.10+、SwiftUI、用 [GRDB.swift](https://github.com/groue/GRDB.swift) 处理 SQLite、Swift Charts、WidgetKit(计划中)、WKWebView(仅用于登录回退)、CloudKit(计划中)、UserNotifications。

## 当前状态

**0.1.0 已支持:**

- Apple Silicon Mac 上的 macOS 菜单栏 App,macOS 13+
- 每 90 秒轮询 `claude.ai/api/organizations/{id}/usage`
- 两张仪表 + 时间范围切换的图表,带预测线
- 本地 SQLite 历史,7 天后自动按 5 分钟桶降采样
- 接近上限时发送系统通知
- 41 个 package 测试全部通过

**路线图:**

- iOS 配套 App + 主屏幕 / 锁屏小组件
- Mac 与 iPhone 间的 iCloud 同步
- 公证签名 DMG(免去右键 → 打开 的小麻烦)
- Universal Binary(Intel + Apple Silicon)
- 开机自启的后台代理

## 已知限制和风险

- **Anthropic 的 `/usage` API 没有公开文档。** 当前响应结构是 2026-04-30 通过抓包逆向出来的。一旦 Anthropic 改了格式,App 会在弹窗里抛出 `schemaDrift` 错误,直到新版本修复。
- **Cookies 会过期。** `cf_clearance` 通常 24 小时左右,`sessionKey` 一般以天或周计。任一过期时弹窗会显示提示,重新导入 cURL 即可。
- **服务条款灰色地带。** 程序化轮询 claude.ai 的消费级页面在技术上违反 Anthropic 的服务条款,即便每 90 秒一次。最坏的现实情况是账号被暂停(而非法律行动)。请自行评估风险使用;这是一个个人监控小工具,不是生产系统。

## 许可

尚未声明 —— 在 1.0 发布前确定。目前请按"保留所有权利,允许个人使用"理解。

## 致谢

绝大部分代码是 2026 年 4 月 30 日至 5 月 1 日在一个 Claude Code 会话里写出来的,使用了 Superpowers 技能链路(brainstorming → writing-plans → subagent-driven-development)。设计文档和实现计划存放在 `docs/superpowers/` 目录下。
