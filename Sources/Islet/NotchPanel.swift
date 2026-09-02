import AppKit
import SwiftUI

/// Borderless, always-on-top panel pinned to the top centre of the built-in display.
/// Transparent areas are click-through; only the black island reacts to the mouse.
final class NotchPanel: NSPanel {
    static let maxSize = NSSize(width: 560, height: 260)

    init(geometry: NotchGeometry, store: UsageStore) {
        super.init(contentRect: NSRect(origin: .zero, size: Self.maxSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false

        let root = NotchView(geometry: geometry).environmentObject(store)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: Self.maxSize)
        contentView = host
        place(on: geometry)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func place(on geometry: NotchGeometry) {
        let f = geometry.screenFrame
        let origin = NSPoint(x: f.midX - Self.maxSize.width / 2, y: f.maxY - Self.maxSize.height)
        setFrameOrigin(origin)
    }
}
