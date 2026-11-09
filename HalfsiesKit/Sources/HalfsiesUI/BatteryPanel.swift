import HalfsiesBattery
import HalfsiesCore
import SwiftUI

/// The panel shown when the menu bar item is clicked.
struct BatteryPanel: View {
    let monitor: BatteryMonitor
    let openSettings: () -> Void
    let quit: () -> Void

    init(monitor: BatteryMonitor, openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.monitor = monitor
        self.openSettings = openSettings
        self.quit = quit
    }

    var body: some View {
        VStack(spacing: 12) {
            if let keyboard = monitor.selectedKeyboard, let split = monitor.split {
                HStack(spacing: 0) {
                    SideReading(side: "Left", level: split.left)
                    SplitRing(split, lineWidth: 8)
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)
                    SideReading(side: "Right", level: split.right)
                }
                .padding(.top, 4)
                Text(keyboard.name)
                    .font(.headline)
            } else {
                Text("No keyboard connected")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Settings…", systemImage: "gearshape", action: openSettings)
                Spacer()
                Button("Quit", systemImage: "power", action: quit)
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 260)
    }
}

/// One side's percentage beside the ring, with a status line when there is no reading.
struct SideReading: View {
    let side: String
    /// Nil when the keyboard does not report this side at all.
    let level: BatteryLevel?

    var body: some View {
        VStack(spacing: 2) {
            Text(level?.label ?? "-")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueStyle)
            Text(side)
                .font(.caption)
                .foregroundStyle(.secondary)
            // Always present, so both sides keep the same height and stay level with the ring.
            Text(status ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(status == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side) \(status?.lowercased() ?? level?.label ?? "")")
    }

    private var status: String? {
        switch level {
        case .percent: nil
        case .disconnected: "Asleep"
        case nil: "Not reported"
        }
    }

    private var valueStyle: Color {
        switch level {
        case .percent: level?.isLow == true ? .red : .primary
        case .disconnected, nil: .secondary
        }
    }
}
