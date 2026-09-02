import AppKit

/// Where the notch is (or where a virtual one should hang on notch-less Macs).
struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    static func detect() -> NotchGeometry {
        let screens = NSScreen.screens
        let screen = screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? screens[0]
        let inset = screen.safeAreaInsets.top
        if inset > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let w = screen.frame.width - l.width - r.width
            return NotchGeometry(screenFrame: screen.frame, hasNotch: true, notchWidth: w, notchHeight: inset)
        }
        let menuBar = NSApplication.shared.mainMenu.map { _ in NSStatusBar.system.thickness } ?? 24
        return NotchGeometry(screenFrame: screen.frame, hasNotch: false, notchWidth: 160, notchHeight: max(menuBar, 24))
    }
}
