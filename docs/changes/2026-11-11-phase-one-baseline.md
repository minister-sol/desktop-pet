# 第一阶段基线记录

- 基线提交：`e8b53d0`（`chore(build): import desktop pet project`）。
- 工作区已有 `AGENTS.md` 修改，实施时应保留。
- 当前共享 scheme 的 Testables 为空；`Tests/` 中已有两个独立 Swift 可执行回归测试，但它们不是 XCTest target。
- `build-check.yml` 编译并运行这两个回归测试，`build-mac.yml` 编译和打包；两者均只针对 `master` 的推送和 PR，当前本地分支为 `main`。
- 用户提供的 Actions 截图显示一次 macOS 构建处于排队状态，不代表构建通过；截图不足以确认该任务对应本工作区的代码。
- 当前执行环境为 Windows，尚未运行 Xcode 构建、XCTest 或 macOS 图形交互验收。

后续需建立真正的 XCTest target、确认可用的 Apple Silicon runner，再实施点击交互和每日提醒，并按计划完成集成验证。
