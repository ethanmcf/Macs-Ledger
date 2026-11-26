// Renders the app icon from LogoMark so it always matches the in-app logo.
// Usage (from the repo root):
//   swiftc -parse-as-library -o /tmp/render-icon scripts/render-app-icon.swift \
//     macs-ledger/Views/Components/LogoMark.swift macs-ledger/Views/Components/Theme.swift && /tmp/render-icon
import SwiftUI
import AppKit

@main
struct RenderAppIcon {
    @MainActor
    static func main() throws {
        let size: CGFloat = 1024
        // iOS's light-mode system blue (#007AFF), which is what Color.blue shows in the app.
        let blue = Color(red: 0, green: 122 / 255, blue: 1)
        let icon = ZStack {
            Color.white
            LogoMark(color: blue)
                .padding(size * 0.2) // same margin as the original artwork
        }
        .frame(width: size, height: size)

        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        guard let rendered = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }

        // App icons must be fully opaque: redraw without an alpha channel.
        let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(rendered, in: CGRect(x: 0, y: 0, width: size, height: size))
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        let png = bitmap.representation(using: .png, properties: [:])!
        let output = URL(fileURLWithPath: "macs-ledger/Assets.xcassets/AppIcon.appiconset/logo.png")
        try png.write(to: output)
        print("Wrote \(output.path)")
    }
}
