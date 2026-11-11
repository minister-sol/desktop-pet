// main.swift
// App entry point. Uses NSApplicationMain to avoid @main conflicts with AppKit.

import AppKit

#if DEBUG
// The scheme sets this only for its Test action. Do not construct AppDelegate
// in the test host: its normal launch reads the user's stores and may open UI.
final class IsolatedTestHostDelegate: NSObject, NSApplicationDelegate {}
let delegate: NSObject & NSApplicationDelegate = MainActor.assumeIsolated {
    if ProcessInfo.processInfo.environment["DESKTOP_PET_TEST_HOST"] == "1" {
        return IsolatedTestHostDelegate()
    }
    return AppDelegate()
}
#else
let delegate = MainActor.assumeIsolated { AppDelegate() }
#endif
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
