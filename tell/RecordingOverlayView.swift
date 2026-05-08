import AppKit
import SwiftUI

@Observable
final class OverlayState {
    var isProcessing = false
}

final class RecordingOverlayPanel: NSPanel {
    let state = OverlayState()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: RecordingOverlayView(state: state))
    }

    func show() {
        state.isProcessing = false
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFrontRegardless()
    }

    func showProcessing() {
        state.isProcessing = true
    }

    func hide() {
        orderOut(nil)
    }
}

private struct RecordingOverlayView: View {
    var state: OverlayState
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .shadow(radius: 12)

            if state.isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .transition(.opacity.combined(with: .scale))
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
                    .scaleEffect(scale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            scale = 1.2
                        }
                    }
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.isProcessing)
        .frame(width: 120, height: 120)
    }
}
