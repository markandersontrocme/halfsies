import AppKit
import HalfsiesCore
import SwiftUI

/// Draws the menu bar item, the split ring and optionally the percentages, as one image.
/// A status item drops a SwiftUI label's text when the label also has an image, so the text is drawn here too.
@MainActor
enum MenuBarIcon {
    private static let ringSize: CGFloat = 16
    private static let lineWidth: CGFloat = 2.2

    /// A template image, so the system matches the menu bar's text color, unless a half is low.
    /// Template images lose their color, so a low battery uses a regular image that draws its own
    /// light or dark variant to match the menu bar's appearance at the moment it is drawn.
    static func image(for battery: SplitBattery, showsPercentages: Bool) -> NSImage {
        let image: NSImage
        if battery.isLow {
            let light = render(battery, showsPercentages, color: .black.opacity(0.85), colorScheme: .light)
            let dark = render(battery, showsPercentages, color: .white, colorScheme: .dark)
            image = NSImage(size: light.size, flipped: false) { rect in
                let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                (isDark ? dark : light).draw(in: rect)
                return true
            }
        } else {
            image = render(battery, showsPercentages, color: .black, colorScheme: .light)
            image.isTemplate = true
        }
        image.accessibilityDescription = battery.accessibilityDescription
        return image
    }

    /// Renders at 1x and 2x so the text stays sharp on both kinds of display.
    private static func render(
        _ battery: SplitBattery, _ showsPercentages: Bool, color: Color, colorScheme: ColorScheme
    ) -> NSImage {
        let content = HStack(spacing: 5) {
            SplitRing(battery, lineWidth: lineWidth, color: color)
                .frame(width: ringSize, height: ringSize)
            if showsPercentages {
                Text(battery.menuBarText)
                    .font(Font(NSFont.menuBarFont(ofSize: 0)))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .environment(\.colorScheme, colorScheme)

        let image = NSImage()
        for scale in [1.0, 2.0] {
            let renderer = ImageRenderer(content: content)
            renderer.scale = scale
            guard let cgImage = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
            image.addRepresentation(rep)
            image.size = rep.size
        }
        return image
    }
}
