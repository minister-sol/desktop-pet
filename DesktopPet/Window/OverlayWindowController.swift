// OverlayWindowController.swift
// Owns and manages one transparent overlay NSWindow.
// Coordinates between AppSettings, AnimationPlayer, VideoPlayer, and PetView.

import AppKit
import AVFoundation
import QuartzCore
import Combine

final class OverlayWindowController: NSWindowController {

    private enum LoadedAsset {
        case frameSequence(FrameSequence)
        case video(VideoPlayer)
    }

    // MARK: - Dependencies
    let settings: AppSettings
    private let resolveBookmark: (Data) -> URL?
    private let startAccess: (URL) -> Bool
    private let stopAccess: (URL) -> Void
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Playback
    private let animationPlayer = AnimationPlayer()
    private var videoPlayer: VideoPlayer?

    // MARK: - Views
    private var petView: PetView!
    private var greeting: NSTextField?
    private var greetingDismissal: DispatchWorkItem?
    private var reminderQueue: [PendingReminder] = []
    private var reminderView: NSView?
    private var dismissReminder: ((UUID) -> Bool)?
    var onVisibilityChanged: (() -> Void)?

    // MARK: - State
    private var currentAssetURL: URL?
    private var currentAssetIsSecurityScoped: Bool = false
    private var isVideoMode: Bool = false
    private var naturalSize: NSSize = NSSize(width: 200, height: 200)

    // MARK: - Init

    init(settings: AppSettings,
         resolveBookmark: @escaping (Data) -> URL? = { SecurityScopedAccess.resolve(bookmark: $0) },
         startAccess: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stopAccess: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.settings = settings
        self.resolveBookmark = resolveBookmark
        self.startAccess = startAccess
        self.stopAccess = stopAccess

        let size = NSSize(width: 300, height: 300)
        let origin = settings.savedPosition()
        let rect = NSRect(origin: origin, size: size)
        let window = OverlayWindow(contentRect: rect)

        super.init(window: window)

        setupPetView()
        setupAnimationPlayer()
        applySettings()
        observeSettings()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        stopCurrentSecurityScopedAccess()
    }

    // MARK: - Setup

    private func setupPetView() {
        guard let window else { return }
        let view = PetView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        view.delegate = self
        window.contentView?.addSubview(view)
        self.petView = view
    }

    private func setupAnimationPlayer() {
        animationPlayer.delegate = self
        animationPlayer.speed = settings.speed
    }

    private func applySettings() {
        guard let window = window as? OverlayWindow else { return }
        window.setClickThrough(settings.clickThrough)
        window.setAlwaysOnTop(settings.alwaysOnTop)
        window.alphaValue = settings.opacity
        petView.lockPosition = settings.lockPosition
        petView.clickThrough = settings.clickThrough
        animationPlayer.speed = settings.speed
        if settings.playing { animationPlayer.play() }
    }

    // MARK: - Settings Observation

    private func observeSettings() {
        settings.$opacity.sink { [weak self] v in
            self?.window?.alphaValue = v
        }.store(in: &cancellables)

        // dropFirst(1): skip the initial emit that fires during init.
        // At that point naturalSize is still (200,200) — the default before any
        // asset is loaded — so applyScale would recompute the origin from a wrong
        // center and silently move the window away from its saved position.
        settings.$scale.dropFirst(1).sink { [weak self] v in
            self?.applyScale(v)
        }.store(in: &cancellables)

        settings.$clickThrough.sink { [weak self] v in
            (self?.window as? OverlayWindow)?.setClickThrough(v)
            self?.petView.clickThrough = v
        }.store(in: &cancellables)

        settings.$lockPosition.sink { [weak self] v in
            self?.petView.lockPosition = v
        }.store(in: &cancellables)

        settings.$alwaysOnTop.sink { [weak self] v in
            (self?.window as? OverlayWindow)?.setAlwaysOnTop(v)
        }.store(in: &cancellables)

        settings.$speed.sink { [weak self] v in
            self?.animationPlayer.speed = v
            self?.videoPlayer?.speed = Float(v)
        }.store(in: &cancellables)

        settings.$playing.sink { [weak self] v in
            guard let self else { return }
            if v { self.animationPlayer.play(); self.videoPlayer?.play() }
            else { self.animationPlayer.pause(); self.videoPlayer?.pause() }
        }.store(in: &cancellables)

        settings.$flipHorizontal.sink { [weak self] v in
            self?.petView.flipHorizontal = v
        }.store(in: &cancellables)

        settings.$flipVertical.sink { [weak self] v in
            self?.petView.flipVertical = v
        }.store(in: &cancellables)
    }

    // MARK: - Visibility

    /// Show or hide the overlay window without closing it.
    /// The animation continues running in the background while hidden.
    func setVisible(_ visible: Bool) {
        if visible {
            window?.orderFront(nil)
        } else {
            window?.orderOut(nil)
        }
        onVisibilityChanged?()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    // MARK: - Asset Loading

    func loadAssetFromBookmark(_ bookmark: Data) -> Bool {
        guard let url = resolveBookmark(bookmark) else { return false }
        let didStartSecurityScope = startAccess(url)

        let didLoad = loadAsset(
            url: url,
            bookmarkData: bookmark,
            preservingSecurityScope: didStartSecurityScope
        )
        if !didLoad, didStartSecurityScope {
            stopAccess(url)
        }

        return didLoad
    }

    /// Stop accessing the current security-scoped resource if one is active.
    private func stopCurrentSecurityScopedAccess() {
        guard currentAssetIsSecurityScoped, let url = currentAssetURL else { return }
        stopAccess(url)
        currentAssetIsSecurityScoped = false
    }

    func loadAsset(url: URL) -> Bool {
        loadAsset(url: url, bookmarkData: SecurityScopedAccess.bookmark(for: url), preservingSecurityScope: false)
    }

    private func loadAsset(url: URL, bookmarkData: Data?, preservingSecurityScope: Bool) -> Bool {
        guard let loadedAsset = decodeAsset(url: url) else { return false }

        let previousAssetURL = currentAssetURL
        let previousAssetWasSecurityScoped = currentAssetIsSecurityScoped

        applyLoadedAsset(loadedAsset)

        let retainPreviousScope = previousAssetWasSecurityScoped && previousAssetURL == url && !preservingSecurityScope
        currentAssetURL = url
        currentAssetIsSecurityScoped = preservingSecurityScope || retainPreviousScope
        settings.assetBookmark = bookmarkData

        if previousAssetWasSecurityScoped,
           let previousAssetURL,
           !retainPreviousScope {
            stopAccess(previousAssetURL)
        }

        return true
    }

    private func decodeAsset(url: URL) -> LoadedAsset? {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "gif":
            return GIFDecoder.decode(url: url).map(LoadedAsset.frameSequence)
        case "png", "apng":
            return APNGDecoder.decode(url: url).map(LoadedAsset.frameSequence)
        case "mp4", "mov", "m4v", "avi", "mkv":
            return VideoPlayer(url: url).map(LoadedAsset.video)
        default:
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return PNGSequenceDecoder.decode(directory: url).map(LoadedAsset.frameSequence)
            }
            return APNGDecoder.decode(url: url).map(LoadedAsset.frameSequence)
        }
    }

    private func applyLoadedAsset(_ loadedAsset: LoadedAsset) {
        switch loadedAsset {
        case .frameSequence(let sequence):
            isVideoMode = false
            removeVideoLayer()
            resizeWindow(to: sizeForSequence(sequence))
            animationPlayer.load(sequence)
            if settings.playing { animationPlayer.play() }

        case .video(let player):
            isVideoMode = true
            animationPlayer.stop()
            removeVideoLayer()
            videoPlayer = player
            player.speed = Float(settings.speed)
            if let rootLayer = petView.layer {
                player.playerLayer.frame = rootLayer.bounds
                player.playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                rootLayer.addSublayer(player.playerLayer)
            }
            if settings.playing { player.play() }
        }
    }

    private func removeVideoLayer() {
        videoPlayer?.playerLayer.removeFromSuperlayer()
        videoPlayer = nil
    }

    // MARK: - Window Sizing

    private func sizeForSequence(_ seq: FrameSequence) -> NSSize {
        guard let first = seq.frames.first else { return NSSize(width: 200, height: 200) }
        naturalSize = NSSize(width: CGFloat(first.width), height: CGFloat(first.height))
        return NSSize(
            width: naturalSize.width * settings.scale,
            height: naturalSize.height * settings.scale
        )
    }

    private func resizeWindow(to size: NSSize) {
        guard let window else { return }
        // Preserve the saved origin exactly — do NOT recompute from center.
        // The origin is the bottom-left corner in macOS screen coordinates.
        // Re-reading savedPosition() (not window.frame.origin) ensures that
        // a freshly-restored window uses the persisted value, not whatever
        // temporary origin was set during the window init phase.
        let origin = settings.savedPosition()
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    private func applyScale(_ scale: Double) {
        guard let window else { return }
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let newW = naturalSize.width * scale
        let newH = naturalSize.height * scale
        let newOrigin = NSPoint(x: center.x - newW / 2, y: center.y - newH / 2)
        window.setFrame(NSRect(origin: newOrigin, size: NSSize(width: newW, height: newH)),
                        display: true, animate: false)
        if let vp = videoPlayer, let rootLayer = petView.layer {
            vp.playerLayer.frame = rootLayer.bounds
        }
    }
}

// MARK: - AnimationPlayerDelegate

extension OverlayWindowController: AnimationPlayerDelegate {
    func animationPlayer(_ player: AnimationPlayer, didAdvanceTo frame: CGImage) {
        petView.display(frame: frame)
    }
}

// MARK: - PetViewDelegate

extension OverlayWindowController: PetViewDelegate {
    func petViewDidClick(_ view: PetView) {
        showGreeting("你好呀！")
    }

    func showReminder(_ pending: PendingReminder, dismiss: @escaping (UUID) -> Bool) {
        guard !reminderQueue.contains(where: { $0.id == pending.id }) else { return }
        dismissReminder = dismiss
        reminderQueue.append(pending)
        if reminderQueue.count == 1 { displayCurrentReminder() }
    }

    func retainReminders(ids: Set<UUID>) {
        let currentID = reminderQueue.first?.id
        reminderQueue.removeAll { !ids.contains($0.id) }
        if currentID != reminderQueue.first?.id { displayCurrentReminder() }
    }

    private func displayCurrentReminder() {
        reminderView?.removeFromSuperview()
        reminderView = nil
        guard let pending = reminderQueue.first, let view = petView else { return }
        greetingDismissal?.cancel()
        greeting?.removeFromSuperview()
        greeting = nil
        let container = NSView(frame: NSRect(x: 10, y: max(0, view.bounds.height - 40), width: max(0, view.bounds.width - 20), height: 28))
        container.autoresizingMask = [.width, .minYMargin]
        let button = NSButton(title: "×", target: self, action: #selector(dismissCurrentReminder))
        button.frame = NSRect(x: max(0, container.bounds.width - 28), y: 0, width: 28, height: 28)
        button.autoresizingMask = [.minXMargin]
        let label = NSTextField(labelWithString: pending.reminder.text)
        label.alignment = .center
        label.drawsBackground = true
        label.backgroundColor = .controlBackgroundColor
        label.frame = NSRect(x: 0, y: 0, width: max(0, container.bounds.width - 28), height: 28)
        label.autoresizingMask = [.width]
        container.addSubview(label)
        container.addSubview(button)
        view.addSubview(container)
        reminderView = container
    }

    @objc private func dismissCurrentReminder() {
        guard let id = reminderQueue.first?.id else { return }
        if dismissReminder?(id) != true {
            let label = reminderView?.subviews.compactMap { $0 as? NSTextField }.first
            label?.stringValue = "Could not dismiss. Retry or open Reminders."
            label?.toolTip = reminderQueue.first?.reminder.text
        }
    }

    private func showGreeting(_ text: String) {
        guard reminderQueue.isEmpty else { return }
        guard let view = petView else { return }
        greetingDismissal?.cancel()
        greeting?.removeFromSuperview()
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.drawsBackground = true
        label.backgroundColor = .controlBackgroundColor
        label.isBezeled = false
        label.frame = NSRect(x: 10, y: max(0, view.bounds.height - 40), width: max(0, view.bounds.width - 20), height: 28)
        label.autoresizingMask = [.width, .minYMargin]
        view.addSubview(label)
        greeting = label
        let dismissal = DispatchWorkItem { [weak self, weak label] in
            label?.removeFromSuperview()
            self?.greeting = nil
        }
        greetingDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: dismissal)
    }

    func petView(_ view: PetView, didDropFileAt url: URL) {
        _ = loadAsset(url: url)
    }

    func petViewDidFinishDrag(_ view: PetView) {
        guard let window else { return }
        settings.savePosition(window.frame.origin)
    }
}
