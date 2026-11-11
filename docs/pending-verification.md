# 待验证事项

本文件统一记录暂时无法执行的测试和验收。当前环境为 Windows，缺少 macOS 和 Xcode；以下均为待验证，不能视为通过。来源包括 [核心功能检查](changes/2026-11-12-core-review.md)、[实机验收准备](changes/2026-11-11-macos-release-readiness.md) 和 [实施顺序](superpowers/plans/2026-11-11-offline-implementation-order.md)。

## macOS 构建和自动化测试

- [ ] 复验 `AnimationPlayer.speed` 的并发访问：现已将速度放入 `stateLock` 保护的 `PlaybackState`；使用 Thread Sanitizer、播放中频繁调整速度和暂停恢复验证，并审查相关状态与性能。修改尚未在 macOS 编译或实测。
- [ ] 在 macOS 开启 Thread Sanitizer 运行 `testAnimationSpeedConcurrentReadsAndWritesRemainInRange`，并另用实际 CVDisplayLink 播放时切换速度；并发读写测试自身不能代替真实播放线程、性能和暂停恢复验证。当前无 Swift/Xcode，测试未运行。
- [ ] 复验 `OverlayWindowController.loadAssetFromBookmark` 的安全作用域配对：已调整同路径替换的保留与释放逻辑；以实际授权素材重复重载并检查访问生命周期，尤其确认视频播放结束前访问有效。修改尚未在 macOS 编译或实测。
- [ ] 检查关闭视频宠物时访问释放顺序：`OverlayWindowController.deinit` 在存储属性自动释放前停止安全作用域访问，视频播放器此时可能仍持有 AVPlayer/AVURLAsset。验证播放停止、播放器销毁及 stopAccess 的顺序，必要时先停止并释放视频资源；当前仅为静态生命周期风险，未证明发生实际读取失败。
- [ ] 按 `docs/changes/2026-11-12-playback-access-analysis.md` 覆盖同路径再次开始成功、未开始、普通导入、不同路径替换及失败回滚，核对每次成功 start 对应一次 stop，以及视频读取期间访问仍有效；Mac 上的真实授权验证与可注入计数测试均尚未执行。
- [ ] 在隔离 macOS Debug 环境编译运行 `testAnimationSpeedClampsToSupportedRange` 和 `testSecurityScopeSameURLReplacementBalancesAccess`；后者注入 start/stop 并检查同路径成功、未开始、普通导入、失败回滚、不同路径替换和释放。当前无 Swift/Xcode，测试与修改均未编译或运行；真实沙盒授权、视频寿命和 Thread Sanitizer 仍需验证。
- [ ] 检查素材导入的解码线程：`loadAsset` 同步调用 `decodeAsset`，而调用链来自 UI 事件；使用大 GIF、APNG 和 PNG 序列验证主线程响应并评估迁移到后台解码。此源码路径可能违反项目“不在主线程解码”的约束，尚未运行分析工具确认具体耗时。
- [ ] 记录提交号、设备或 CI runner 架构、macOS 与 Xcode 版本；执行 Debug 构建和共享 scheme 的 XCTest，记录命令、实际发现的测试数量及结果，确认数量大于零。
- [ ] 验证提醒模型、持久化及错误处理：输入校验、增删改、损坏文件保护和保存失败；补足尚缺的测试并运行。
- [ ] 构造损坏的 reminders.plist 启动，尝试无效输入、修正后保存及删除/关闭，检查错误是否始终可见、原文件未被覆盖且界面不误报成功；当前仅有源码层面的风险分析，详见 `docs/changes/2026-11-12-offline-followup-review.md`。
- [ ] 在 macOS 运行 `testCorruptStoreCannotBeOverwrittenByReplacement`，并确认加载失败时原始错误持续显示、编辑控件禁用；当前 Windows 环境没有 Swift/Xcode，新增测试尚未编译或运行。
- [ ] 运行 `Tests/PetInteractionTests.swift` 中新增的 `testReplacingRemindersPersistsDeletion` 和 `testFailedReplacementPreservesSchedulerData`：当前 Windows 环境无 Swift/Xcode，尚未编译或执行；记录测试发现数量及结果。
- [ ] 在 macOS 运行 `.github/workflows/build-check.yml` 中的 `OverlayWindowControllerTests`，验证新增的同刻提醒排队、逐条关闭及待查看列表同步测试；同时运行完整构建和 XCTest。当前无 Swift/Xcode，测试尚未编译或执行。
- [ ] 验证 `OverlayWindowControllerTests` 新增的关闭失败提示用例，并运行已编写的多宠物隐藏、显示、删除和队列重新分配集成测试；目前均未编译或执行。
- [ ] 在 macOS 运行 `testDisabledReminderHasNoNextOccurrence`、`testNextOccurrenceAfterExactTimeIsFollowingDay`、`testRepeatedDaylightSavingTimeUsesFirstOccurrence`，以及 `OverlayWindowControllerTests` 中的双窗口队列交接用例。当前环境无 Swift/Xcode，尚未编译或执行；双窗口测试手动交接队列，不覆盖 AppDelegate 的隐藏、显示和删除集成路径。
- [ ] 在 macOS 运行 `testDismissingOnePendingReminderPersistsRemainingQueue` 和 `testFailedPendingDismissalKeepsOriginalQueue`，确认关闭单项与写入失败时的调度器、存储状态；当前无 Swift/Xcode，尚未编译或运行。
- [ ] 在 macOS 运行 `testReminderAcceptsTextAtCharacterLimit`、`testReminderRejectsTextOverCharacterLimit`、`testReminderRejectsInvalidHoursAndMinutes`，检查 200 字符边界与非法时间；当前无 Swift/Xcode，尚未编译或运行。
- [ ] 在 macOS Debug 配置运行 `testAppDelegateRedistributesPendingWhenPetsHideShowAndAreRemoved`：该测试通过 Debug 专用入口注入临时存储、独立 UserDefaults 和两个窗口，覆盖隐藏、显示、删除、关闭提醒及全部隐藏后恢复。当前没有 Swift/Xcode，测试和入口尚未编译或运行；确认不访问真实应用数据，并记录测试数量及结果。
- [ ] 在隔离的 macOS 测试账户或虚拟机中先核实 XCTest host 的启动行为：当前测试 target 的 `TEST_HOST` 指向 DesktopPet.app，应用入口可能在测试方法之前使用默认存储或打开文件选择器；测试方法内的注入不保证宿主启动阶段隔离。确认后再运行，必要时调整测试宿主配置。
- [ ] 按 `docs/macos-xctest-isolation.md` 在专用 macOS 测试账户或虚拟机中确认宿主启动及默认存储、偏好设置变化，记录测试发现数量和结果；不要仅凭设置 HOME 宣称隔离。该方案尚未在 macOS 或 CI 试行。
- [ ] 在隔离 macOS 账户中验证共享 scheme Test action 的 `DESKTOP_PET_TEST_HOST=1` 确实传入测试宿主、`testHostedTestsUseIsolatedStartup` 被发现并通过，正常 AppDelegate 未启动、默认存储未读写且未打开选择器；同时检查普通 Debug 启动和 Release 启动不受影响。当前 Windows 无 Swift/Xcode，未编译或运行，标记和隔离效果均未证实。
- [ ] 验证 `testHostedTestsUseIsolatedStartup` 对实际安装的 `IsolatedTestHostDelegate` 的断言；若 XCTest 替换代理或宿主不执行 `main.swift`，应调查启动路径，不能把标记存在当作隔离证明。该断言尚未在 macOS 编译或运行。
- [ ] 验证 Debug 测试能发现依赖 Debug 专用入口的测试，并检查 Release 测试目标不引用这些 Debug 专用符号；目前仅作条件编译静态检查，尚未运行 Xcode 构建。
- [ ] 验证调度：同刻多条、午夜、夏令时不存在或重复时刻、时区和系统时钟变化、睡眠唤醒、当天去重和错过提醒不补发。
- [ ] 在 macOS 运行 `testDeletingReminderRemovesOnlyItsDeliveredMarker`，验证删除提醒后仅清理对应的已送达标记并持久化；当前无 Swift/Xcode，尚未编译或运行。
- [ ] 在隔离的 macOS Debug 测试环境运行 `testDueCallbacksDeliverTogetherDeduplicateAndResetNextDay` 和 `testDueCallbackDoesNotDeliverWhenPersistenceFails`；测试使用注入时钟、临时存储和 Debug 专用回调入口。当前没有 Swift/Xcode，测试未编译或运行，也未观察测试先失败再通过；睡眠唤醒竞态仍需实际验证。
- [ ] 运行 `testEarlyAndLateCallbacksRespectSixtySecondBoundary` 与 `testReschedulingAfterMissedOccurrenceSelectsNextDay`：前者记录当前实现对提前、59.9 秒和 60 秒延迟的行为，后者仅直接调用重排逻辑模拟错过后唤醒；测试尚未编译或运行，不能证明系统唤醒通知和计时器的实际顺序。
- [ ] 在隔离 macOS Debug 环境运行 `testReplacingEnabledReminderUpdatesScheduledTime`，验证禁用、重新启用及删除后计时器和保存状态；当前无 Swift/Xcode，测试尚未编译或执行。
- [ ] 在隔离 macOS Debug 环境运行 `testStaleCallbackAfterDisablingOrDeletingReminderDoesNotDeliver`，验证禁用或删除后旧回调不产生待查看提醒；该测试直接模拟回调，尚未编译或运行，也不能证明系统计时器竞态的实际顺序。
- [ ] 在 Mac 上特别验证睡眠跨越提醒时间但延迟小于 60 秒的情况：`fire` 接受此范围的延迟，唤醒通知与计时器回调的先后可能影响是否补发；需要对照“不补发”约定记录实际结果并处理不一致。当前仅为静态风险分析，未实测。
- [ ] 检查构建产物架构及许可证；记录 CI 的实际结果，不能以工作流配置代替运行证据。

## macOS 图形与系统验收

- [ ] 安装、启动、退出和重启，确认菜单栏模式、无 Dock 图标，以及已有宠物数据和位置保持。
- [ ] 使用已获许可且有透明区域的 GIF 或 APNG 检查透明、动画、缩放和素材导入；检查多个宠物及不同屏幕、显示缩放。普通 MP4 仅用于视频播放和循环测试，并检查视频下提示层级。
- [ ] 检查点击、拖动、位置锁定、鼠标穿透；切换 Space 并在 Safari 全屏时检查显示。
- [ ] 检查提醒新增、编辑、删除、启停、保存失败、重启及待查看列表；同刻多条逐条确认，检查隐藏宠物或无宠物时的入口。还需验证点击问候是否覆盖提醒、编辑中的提醒被删除后的状态。
- [ ] 在 Mac 图形会话中触发多条同刻提醒，确认按顺序显示、每次关闭只移除对应待查看项，列表关闭与桌面同步，点击问候不覆盖；检查视频、窄小宠物、隐藏/移除宠物、鼠标穿透和存储失败时的行为与可访问性。穿透时通过菜单栏待查看列表关闭。记录环境和结果。
- [ ] 验证关闭保存失败时桌面提示显示重试信息、原提醒仍在待查看列表；恢复写入后可重试关闭。多宠物下依次隐藏、显示和移除承载队列的宠物，确认队列转移、顺序和无重复；全部隐藏后恢复显示，检查待查看提醒可恢复展示。Windows 无法运行 macOS 构建或图形验收。
- [ ] 在重启时区分已触发但未关闭的待查看提醒和应用关闭期间错过的提醒：前者应仍可查看，后者不补发；核对 README 的使用说明与实际行为。
- [ ] 增加足够多的待查看提醒及长文本，检查固定高度设置窗口能否滚动、逐条阅读并关闭；测试关闭时存储失败是否有明确且可恢复的反馈。多宠物时隐藏或移除承载提示的宠物，核对菜单入口和其他可见宠物上的表现。
- [ ] 验证待查看区域新增滚动布局：多条 200 字提醒、长错误信息和较小屏幕下，确认列表可滚动、文本可读、每个关闭按钮可访问，且提醒编辑列表仍可使用；Windows 无法运行 SwiftUI 图形验收。
- [ ] 在 Mac 上编辑一条提醒后删除它，确认编辑取消且保存不会重新创建；模拟删除保存失败，确认编辑内容保留且错误可见；同时检查编辑期间目标消失时保存提示。当前无法运行 SwiftUI 或执行交互测试。
- [ ] 在实际系统中检查跨日、时区变化、休眠唤醒和应用关闭期间不补发；检查素材读取授权、登录启动、安装与卸载。

## 发行验证（暂缓）

- [ ] 正式发行准备就绪后验证 Developer ID 签名、公证、stapler 和 Gatekeeper，记录版本、产物来源和 SHA-256；检查下载地址与 Homebrew 配置。当前未声称已签名、公证或发布。

## 后续记录方式

遇到暂时无法测试的事项，在相应类别新增待办，写明范围、受阻原因、所需环境和可复现的验证步骤；必要时链接相关变更。执行后记录日期、提交号、环境、命令或操作、结果及证据位置；失败时记录复现步骤并保留待办，修复后复验。不要记录凭据或个人敏感数据。

- [ ] 在 GitHub 托管 macOS runner 首次运行 phase-one-tests.yml，检查 build-for-testing、完整 XCTest 数量、隔离启动断言、默认数据快照与上传证据；确认图形会话，并人工核实文件选择器和数据读取行为。Windows 上无法执行，CI 配置尚未实跑。

## 2026-11-12 GitHub Actions 运行记录

- 提交 9314b3ef39ab0a5d67b9206bf1fe79ded9165192 的 macOS XCTest 工作流运行 43071671789：build-for-testing 和 XCTest 成功，31 项测试、0 失败；隔离宿主断言通过，监控的默认数据快照未变化。证据：https://github.com/zhongjing0412/desktop-pet/actions/runs/43071671789 ，产物 macos-xctest-evidence（13877942262）。
- 此结果不证明没有读取默认数据或打开选择器，也未覆盖真实图形交互、透明度、全屏 Space、Thread Sanitizer 和实际安全作用域授权；上方对应待办仍保留。
