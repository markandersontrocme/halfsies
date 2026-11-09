import HalfsiesBattery
import HalfsiesCore
import SwiftUI

/// The menu bar label: "86% 39%", left then right.
public struct MenuBarLabel: View {
    let monitor: BatteryMonitor

    public init(monitor: BatteryMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        Text(monitor.menuBarText ?? "")
            .monospacedDigit()
    }
}

/// The panel shown when the menu bar item is clicked.
public struct BatteryPanel: View {
    let monitor: BatteryMonitor
    let openSettings: () -> Void
    let quit: () -> Void

    public init(monitor: BatteryMonitor, openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.monitor = monitor
        self.openSettings = openSettings
        self.quit = quit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let keyboard = monitor.selectedKeyboard, let split = monitor.split {
                Text(keyboard.name)
                    .font(.headline)
                BatteryRow(side: "Left", level: split.left)
                BatteryRow(side: "Right", level: split.right)
            } else {
                Text("No keyboard connected")
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Settings…", systemImage: "gearshape", action: openSettings)
                Spacer()
                Button("Quit", action: quit)
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(width: 260)
    }
}

struct BatteryRow: View {
    let side: String
    /// Nil when the keyboard does not report this side at all.
    let level: BatteryLevel?

    var body: some View {
        HStack(spacing: 8) {
            Text(side)
                .frame(width: 40, alignment: .leading)
            switch level {
            case .percent(let value):
                ProgressView(value: Double(value), total: 100)
                    .tint(value <= 20 ? .red : .accentColor)
                Text(level?.label ?? "")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            case .disconnected:
                Text("Not connected")
                    .foregroundStyle(.secondary)
                Spacer()
            case nil:
                Text("Not reported")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
