# macOS XCTest 宿主隔离与运行方案

状态：仅依据源码和工程配置静态检查，尚未在 macOS、Xcode 或 CI 实际运行；以下是待验证的安全运行方案。

## 风险与边界

- `DesktopPetTests` 的 `TEST_HOST` 和 `BUNDLE_LOADER` 指向 `DesktopPet.app`；不能假定 XCTest 不会启动应用入口或应用代理。
- 正常启动会创建默认 `PetsStore` 和 `ReminderScheduler`，读取或写入应用支持目录及默认 UserDefaults。没有宠物记录时还可能打开素材选择器。测试方法内注入的临时 plist 和独立 UserDefaults 域不能隔离宿主在测试方法之前的动作。
- 不要在有真实桌宠数据的 macOS 用户账户上直接执行当前宿主测试。仅设置 `HOME` 或以为 CI 一定干净都不能证明 Foundation、偏好设置和宿主进程使用了预期目录。
- Debug 构建现已准备宿主隔离：共享 scheme 的 Test action 设置 `DESKTOP_PET_TEST_HOST=1`，`main.swift` 据此使用空代理而不创建正常 `AppDelegate`；Launch action 不设置该标记，Release 代码不包含该分支。测试会检查标记和代理。环境传递、宿主启动路径及实际隔离效果尚未验证，因此仍需使用专用测试账户或虚拟机。

## 首次运行准备

1. 使用独立的本地 macOS 测试账户或专用虚拟机；不登录个人 Apple 账户、不迁入真实宠物数据，并确认能够获得图形会话。记录设备或虚拟机架构、macOS、Xcode 和提交号。CI 也需确认 runner 为隔离环境及可用图形会话。
2. 在该账户中使用独立检出目录；执行前确认账户与数据目录确属测试环境。保留运行前的目录和文件清单，至少覆盖当前用户 Library/Application Support 下的 `desktop-pet`、`DesktopPet` 以及该应用偏好设置；记录不存在的路径，不创建或修改个人账户文件。
3. 在测试账户执行构建并单独检查可发现的测试；测试可能因工程、签名、宿主启动或图形环境失败，不能提前视为成功。

```sh
xcodebuild -version
uname -m
xcodebuild build-for-testing -project DesktopPet.xcodeproj -scheme DesktopPet \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project DesktopPet.xcodeproj -scheme DesktopPet \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

4. 观察宿主是否执行 `applicationDidFinishLaunching`、打开文件选择器、访问或创建默认应用数据；对比运行前后的目录和偏好设置，并记录测试数量、命令、结果和证据位置。若出现选择器或意外写入，停止测试，保留证据，在隔离账户内修正后复验。
5. 完整通过后仍需独立进行透明度、鼠标交互和全屏 Space 的图形验收；自动化结果不能替代这些检查。

## 后续工程改进

现有 Debug 启动模式仍须验证测试发现、标记是否传入宿主、默认存储是否保持不变、正常 Debug 启动以及 Release 启动行为。未经实际 macOS 测试，不应把环境变量或配置当作已验证的隔离机制。
