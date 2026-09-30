import SwiftUI

#if os(macOS)
import AppKit

struct MacWindowInitialSizeView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)

        DispatchQueue.main.async {
            guard let window = view.window,
                  let screen = window.screen else {
                return
            }

            let visible = screen.visibleFrame
            let targetWidth = visible.width * 0.94
            let targetHeight = visible.height * 0.92
            let targetFrame = NSRect(
                x: visible.midX - (targetWidth / 2),
                y: visible.midY - (targetHeight / 2),
                width: targetWidth,
                height: targetHeight
            )

            window.setFrame(targetFrame, display: true, animate: false)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#else

struct MacWindowInitialSizeView: View {
    var body: some View {
        EmptyView()
    }
}

#endif
