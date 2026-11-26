import SwiftUI
import UIKit

/// App-wide colors. Change them here to restyle every screen.
extension Color {
    /// Main accent. Used for fills, bars, chips and buttons.
    static let appAccent = Color.blue //Color(red: 0.008, green: 0.243, blue: 0.541)
    /// Accent-colored text. Same as the accent; split out in case a lighter accent needs darker text.
    static let appAccentText = Color.indigo
    /// Text and icons placed on top of an `appAccent` fill.
    static let onAccent = Color.white

    /// A color that switches between two hex values for light and dark mode.
    init(light: UInt32, dark: UInt32) {
        func rgb(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
        self.init(UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }
}
