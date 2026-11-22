import AppKit
import SwiftUI

/// Petite bulle en haut de l'écran pendant qu'une action Forma tourne (le panneau est déjà fermé).
enum FormaHUD {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String, busy: Bool = false, duration: TimeInterval = 2.2) {
        hideWork?.cancel()
        let host = NSHostingView(rootView: HUDView(text: text, symbol: symbol, busy: busy))
        host.frame.size = host.fittingSize
        let p = panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            return p
        }()
        panel = p
        p.contentView = host
        if let screen = NSScreen.main {
            let size = host.fittingSize
            p.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 24,
                              width: size.width, height: size.height), display: true)
        }
        if !p.isVisible {
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.16; p.animator().alphaValue = 1 }
        }
        guard !busy else { return }
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 },
                                                 completionHandler: { p.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

private struct HUDView: View {
    let text: String
    let symbol: String
    let busy: Bool
    var body: some View {
        HStack(spacing: 10) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.tint)
            }
            Text(text).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(8)
    }
}
