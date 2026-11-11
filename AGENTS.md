# AGENTS.md — AI Agent Guidelines for Desktop Pet

This file defines conventions and rules for AI agents (Kiro, Codex, Copilot, etc.)
working on this repository.

---

## 协作协议（每次项目对话适用）

- 开始工作时读取本文件，检查当前任务、相关计划和工作区状态；以用户最新明确指令为准，不假定其他工具知道本次对话内容。
- Codex 默认担任技术负责人，负责梳理接口、核心实现、集成、代码审查、构建和测试，以及记录未解决问题。用户可以针对具体任务调整分工。
- DSH 默认负责需求、用户体验、文案和验收建议；除非用户另有明确指示，不修改代码。区分已验证事实与建议。
- Copilot 默认承担接口清晰、范围独立的小型编码或测试任务。接口不明确时先提出问题，不擅自改变架构或并行重写核心模块。
- 三者不会自动互通。由项目负责人派发任务并转交成果；不得声称另一方已收到任务、完成工作或验证结果，除非有实际证据。
- 可并行开展互不依赖的体验梳理与构建基线工作。编码任务涉及共享接口时，先确定接口和文件边界；完成后由 Codex 审查、测试和整合，避免覆盖他人未提交的工作。
- 每次交接说明任务与范围、相关文件或补丁位置、接口和依赖、实际执行的验证及结果、未验证事项和待解决问题。无法运行 macOS 构建或手工验收时明确说明，不把建议当成已完成的验证。
- 将暂时无法执行的测试和验收统一记录在 `docs/pending-verification.md`，注明原因、环境、步骤及状态；实际验证后补充结果和证据，失败项保留至修复复验，不把静态检查视为运行通过。
- 每次回复都应包含“当前任务结果”和“下一位的提示词”：前者简述已完成的工作、成果位置及验证状态，未完成时说明进展和阻碍；后者给出一段可直接复制转发的命令提示，写明接收者、背景、已取得的结果、下一步任务和必要约束。不得编造结果或验证。
- 根据任务实际阶段选择下一位：通常 DSH 将体验清单交给 Codex，Copilot 将补丁交给 Codex，Codex 可将明确的小任务交给 Copilot 或将体验核对交给 DSH。若无需其他人接手，明确写“无需转交”，并提供用户可执行的下一步；若需要用户决定，提示词应列明待决定事项，不得假定已获批准。
- 遵守本文件的技术约束，审查外部贡献的许可与兼容性。不要在提示词或交接材料中粘贴令牌、密码或个人敏感数据。
- 本协议是项目默认协作方式，不意味着每个任务都必须调用全部三者；按任务需要使用。其他工具只有在读取或被提供本协议后才能遵循它。

---

## Project identity

- **Name:** Desktop Pet
- **Language:** Swift 5.9+
- **Platform:** macOS 14+, Apple Silicon primary
- **Architecture:** Native AppKit + SwiftUI, no cross-platform abstractions
- **Bundle ID:** `com.bssm-oss.desktop-pet`

---

## Core rules

### 1. Stay native macOS
Do NOT introduce cross-platform frameworks (Electron, Flutter, Tauri, Qt).
Do NOT add Rust unless there is a concrete, measurable performance reason.
AppKit + SwiftUI is the correct stack for this app.

### 2. No third-party dependencies
All functionality must use Apple frameworks only:
- ImageIO for GIF/APNG/PNG decode
- AVFoundation for video
- CoreAnimation / CALayer for rendering
- CVDisplayLink for frame scheduling
- PropertyListEncoder / PropertyListDecoder for the file-backed pet store in Application Support
- SMAppService for login items

Do NOT add Swift Package Manager dependencies without explicit approval.

### 3. Performance first
- Frame scheduling: always CVDisplayLink, never NSTimer for animation
- Rendering: always CALayer.contents = CGImage, never NSImageView.image per frame
- Decode: always at load time, never per-frame at runtime
- Guard against redundant CALayer updates (lastFrameIndex check)

### 4. Transparency is non-negotiable
The overlay window must always be:
```swift
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
```
Never set a background color on the window or content view.

### 5. Spaces behavior is non-negotiable
The window must always have:
```swift
window.collectionBehavior = [
    .canJoinAllSpaces,
    .fullScreenAuxiliary,
    .stationary
]
```
Never remove `.fullScreenAuxiliary` — it is what keeps the overlay visible when
another app goes fullscreen.

### 6. Menubar-only app
`LSUIElement = YES` in Info.plist must never be removed.
The app must never show a dock icon.
`NSApp.setActivationPolicy(.accessory)` must be called in `applicationDidFinishLaunching`.

---

## File structure

```
DesktopPet/
├── App/            # AppDelegate, Info.plist
├── Window/         # OverlayWindow, PetView, OverlayWindowController
├── Playback/       # AnimationPlayer, decoders, FrameSequence, VideoPlayer
├── MenuBar/        # MenuBarController
├── Settings/       # AppSettings, SettingsView
└── Utilities/      # PlaceholderAnimation, SecurityScopedAccess
```

When adding new files, place them in the correct group.
Update `DesktopPet.xcodeproj/project.pbxproj` to include new source files.

---

## Coding conventions

- Swift 5.9 concurrency where appropriate (`async/await` for decode operations)
- `final class` for all controllers and players (no subclassing intended)
- `// MARK: -` sections for readability
- Every file starts with a comment block explaining its role
- No force-unwraps (`!`) except where nil is genuinely impossible and documented
- `weak var delegate` for all delegate references (no retain cycles)
- `@MainActor` on any function that touches UIKit/AppKit

---

## What agents should NOT do

- Do not add `@NSApplicationMain` or `@main` to any file other than `AppDelegate.swift`
- Do not change `window.level` to `.screenSaver` or higher without documenting why
- Do not decode animation frames on the main thread (use background queue + main dispatch)
- Do not call `CVDisplayLinkStart` without a corresponding `CVDisplayLinkStop` in deinit
- Do not store strong references to `NSWindow` in delegates (use `weak`)
- Do not add `NSApp.activate(ignoringOtherApps: true)` in the main render loop

---

## Testing guidance

- `evernight.mp4` — use for video import/loop/positioning tests only, NOT transparency tests
- For transparency tests: use a GIF or APNG with known alpha regions
- For PNG sequence tests: create a folder with `frame_0001.png` through `frame_0010.png`
- Verify Spaces behavior by: opening the app, switching to a different Space, confirming overlay is still visible
- Verify fullscreen behavior by: making Safari fullscreen, confirming overlay appears in auxiliary space

---

## Commit message format

```
type(scope): short description

Types: feat, fix, perf, refactor, docs, chore
Scopes: window, playback, menubar, settings, decoder, build

Examples:
feat(playback): add HEVC with Alpha support
fix(window): restore fullScreenAuxiliary behavior after Space switch
perf(decoder): lazy-decode PNG sequences over 100 frames
docs: add transparent video format comparison
```
