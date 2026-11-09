import AppKit
import HalfsiesBattery
import Observation
import SwiftUI

/// Owns the menu bar item and the panel it opens.
///
/// The item is an AppKit status item rather than a SwiftUI `MenuBarExtra`:
/// `MenuBarExtra` drops the text of a label that also has an image, and squeezes a wide image to a fixed width,
/// so it cannot show the split ring next to the percentages.
@MainActor
public final class MenuBarController: NSObject {
    private let monitor: BatteryMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: StatusPanel

    public init(monitor: BatteryMonitor, openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.monitor = monitor
        let panel = StatusPanel()
        self.panel = panel
        panel.setContent(
            BatteryPanel(
                monitor: monitor,
                openSettings: { [weak panel] in
                    panel?.dismiss()
                    openSettings()
                },
                quit: quit))
        super.init()

        statusItem.autosaveName = "Halfsies"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        panel.onDismiss = { [weak self] in self?.statusItem.button?.highlight(false) }
        update()
    }

    /// Redraws the item now and again whenever anything it shows changes.
    private func update() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
    }

    private func render() {
        guard let split = monitor.split else {
            // Nothing to show while no keyboard is connected. Opening the app again shows Settings.
            panel.dismiss()
            statusItem.isVisible = false
            return
        }
        statusItem.button?.image = MenuBarIcon.image(for: split, showsPercentages: !monitor.settings.compactMenuBar)
        statusItem.isVisible = true
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.dismiss()
            return
        }
        guard let button = statusItem.button, let window = button.window else { return }
        panel.show(below: window.convertToScreen(button.convert(button.bounds, to: nil)), in: window)
        // The button clears its highlight when the click ends, so set it after that.
        Task { @MainActor in button.highlight(true) }
    }
}

/// A borderless panel that drops down from a menu bar item and closes when the user clicks anywhere else.
private final class StatusPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private var outsideClickMonitor: Any?
    private var isDismissing = false
    /// The menu bar item's window, whose clicks toggle the panel.
    private weak var anchorWindow: NSWindow?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        animationBehavior = .utilityWindow
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    func setContent(_ content: some View) {
        let hosting = NSHostingController(
            rootView: content
                .background(PanelMaterial())
                .clipShape(.rect(cornerRadius: 16)))
        hosting.sizingOptions = .preferredContentSize
        contentViewController = hosting
    }

    override var canBecomeKey: Bool { true }

    /// Shows the panel under `anchor`, a rectangle in screen coordinates inside `anchorWindow`, kept inside the screen.
    func show(below anchor: NSRect, in anchorWindow: NSWindow) {
        self.anchorWindow = anchorWindow
        if let view = contentViewController?.view {
            setContentSize(view.fittingSize)
        }
        let margin: CGFloat = 8
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - frame.height - 6)
        if let visible = anchorWindow.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - frame.width - margin)
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        invalidateShadow()

        // Clicks in other apps do not always take key status from a non-activating panel.
        // Clicks on the menu bar item arrive here too, and are left to the item's action, which toggles the panel.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isClickOnAnchor else { return }
                self.dismiss()
            }
        }
    }

    func dismiss() {
        guard isVisible, !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        orderOut(nil)
        onDismiss?()
    }

    override func resignKey() {
        super.resignKey()
        guard !isClickOnAnchor else { return }
        dismiss()
    }

    /// Whether a mouse button is down over the menu bar item.
    /// The item's action toggles the panel on mouse-up, so closing on that mouse-down would make the action reopen it.
    private var isClickOnAnchor: Bool {
        guard NSEvent.pressedMouseButtons != 0, let anchorWindow else { return false }
        return anchorWindow.frame.contains(NSEvent.mouseLocation)
    }

    /// Escape closes the panel.
    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }
}

/// The blurred background of the panel.
private struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
