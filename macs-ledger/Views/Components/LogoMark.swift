import SwiftUI

/// The app's logo drawn as shapes: a rounded square split into six tiles. Used for the loading animation, and
/// rendered once to produce the app icon (see scripts/render-app-icon.swift), so both always match.
struct LogoMark: View {
    var color: Color = .appAccent
    /// How many tiles are showing, in `revealOrder`. 6 shows the whole logo. Changes animate per tile.
    var revealed: Int = Tile.all.count

    /// One tile, in a 1144 × 1160 design space measured from the original logo artwork.
    struct Tile {
        let x, y, width, height: CGFloat
        /// Only the tile on each outer corner of the logo is rounded, on that corner.
        let corners: UnevenRoundedRectangle.Corners

        static let designWidth: CGFloat = 1144
        static let designHeight: CGFloat = 1160
        static let cornerRadius: CGFloat = 195

        static let all: [Tile] = [
            Tile(x: 0,   y: 0,   width: 274, height: 284, corners: .topLeading),     // 0 top-left
            Tile(x: 436, y: 0,   width: 708, height: 737, corners: .topTrailing),    // 1 big
            Tile(x: 886, y: 904, width: 258, height: 256, corners: .bottomTrailing), // 2 bottom-right
            Tile(x: 436, y: 904, width: 288, height: 256, corners: []),              // 3 bottom-middle
            Tile(x: 0,   y: 904, width: 274, height: 256, corners: .bottomLeading),  // 4 bottom-left
            Tile(x: 0,   y: 451, width: 274, height: 286, corners: []),              // 5 middle-left
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Tile.designWidth, geometry.size.height / Tile.designHeight)
            let originX = (geometry.size.width - Tile.designWidth * scale) / 2
            let originY = (geometry.size.height - Tile.designHeight * scale) / 2

            ForEach(Tile.all.indices, id: \.self) { index in
                let tile = Tile.all[index]
                let isShown = index < revealed
                tileShape(tile, scale: scale)
                    .fill(color)
                    .frame(width: tile.width * scale, height: tile.height * scale)
                    .scaleEffect(isShown ? 1 : 0.3)
                    .opacity(isShown ? 1 : 0)
                    .animation(.spring(response: 0.38, dampingFraction: 0.62), value: isShown)
                    .position(
                        x: originX + (tile.x + tile.width / 2) * scale,
                        y: originY + (tile.y + tile.height / 2) * scale
                    )
            }
        }
        .aspectRatio(Tile.designWidth / Tile.designHeight, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func tileShape(_ tile: Tile, scale: CGFloat) -> UnevenRoundedRectangle {
        let r = Tile.cornerRadius * scale
        return UnevenRoundedRectangle(
            topLeadingRadius: tile.corners.contains(.topLeading) ? r : 0,
            bottomLeadingRadius: tile.corners.contains(.bottomLeading) ? r : 0,
            bottomTrailingRadius: tile.corners.contains(.bottomTrailing) ? r : 0,
            topTrailingRadius: tile.corners.contains(.topTrailing) ? r : 0,
            style: .circular
        )
    }
}

extension UnevenRoundedRectangle {
    /// Which corners of a tile are rounded.
    struct Corners: OptionSet {
        let rawValue: Int
        static let topLeading = Corners(rawValue: 1 << 0)
        static let topTrailing = Corners(rawValue: 1 << 1)
        static let bottomLeading = Corners(rawValue: 1 << 2)
        static let bottomTrailing = Corners(rawValue: 1 << 3)
    }
}
