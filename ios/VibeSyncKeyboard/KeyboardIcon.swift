import UIKit

/// The keyboard's glyphs: the Tabler Icons (MIT, tabler.io/icons) outline
/// icons the app already shows for the same things. The app dropped iOS emoji
/// for these on 2026-08-17 (lib/core/theme/app_icons.dart); emoji left in the
/// keyboard made the two read as different products.
///
/// The extension cannot reach the app's Flutter icon font, so each glyph is
/// kept here as geometry on Tabler's 24 × 24 grid and stroked the way Tabler
/// draws it: 2-unit stroke, round caps and joins, no fill. The paths come from
/// Tabler v3.19.0, the release behind the app's flutter_tabler_icons 1.43.0;
/// each glyph quotes its upstream path data, with the arcs pre-converted to
/// cubic Béziers so the keyboard needs no SVG parser.
enum KeyboardIcon: CaseIterable {
    case refresh
    case messageCircle
    case moodWink
    case masksTheater
    case crystalBall
    case heart
    case bulb
    case alertTriangle

    /// Room between a glyph and the text after it.
    static let textGap: CGFloat = 5

    /// About the size of the emoji each glyph replaces, so rows keep their
    /// height: 1.2 × the point size of the text beside it.
    static func side(for font: UIFont) -> CGFloat {
        (font.pointSize * 1.2).rounded()
    }

    /// The glyph `side` points square in `color`. `trailingSpace` adds
    /// transparent room on the right, which keeps the gap before the text the
    /// same in buttons and in labels.
    func image(
        side: CGFloat,
        color: UIColor,
        trailingSpace: CGFloat = 0
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side + trailingSpace, height: side)
        )
        return renderer.image { context in
            let canvas = context.cgContext
            canvas.scaleBy(x: side / 24, y: side / 24)
            canvas.addPath(path)
            canvas.setStrokeColor(color.cgColor)
            canvas.setLineWidth(2)
            canvas.setLineCap(.round)
            canvas.setLineJoin(.round)
            canvas.strokePath()
        }
    }

    /// For buttons: UIKit tints a template image with the button's tint, and
    /// greys it out with the title when the button is disabled.
    func templateImage(side: CGFloat, trailingSpace: CGFloat = 0) -> UIImage {
        image(side: side, color: .black, trailingSpace: trailingSpace)
            .withRenderingMode(.alwaysTemplate)
    }

    /// `text` led by this glyph, for a label set in `font`. The glyph is
    /// centred on the cap height so it sits level with the text beside it.
    func leading(
        _ text: String,
        font: UIFont,
        textColor: UIColor,
        iconColor: UIColor
    ) -> NSAttributedString {
        let side = Self.side(for: font)
        let attachment = NSTextAttachment()
        attachment.image = image(
            side: side,
            color: iconColor,
            trailingSpace: Self.textGap
        )
        attachment.bounds = CGRect(
            x: 0,
            y: ((font.capHeight - side) / 2).rounded(),
            width: side + Self.textGap,
            height: side
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let result = NSMutableAttributedString(
            attributedString: NSAttributedString(attachment: attachment)
        )
        result.addAttributes(
            attributes,
            range: NSRange(location: 0, length: result.length)
        )
        result.append(NSAttributedString(string: text, attributes: attributes))
        return result
    }

    private var path: CGPath {
        let path = CGMutablePath()
        for segment in segments {
            switch segment {
            case let .move(x, y):
                path.move(to: CGPoint(x: x, y: y))
            case let .line(x, y):
                path.addLine(to: CGPoint(x: x, y: y))
            case let .curve(x1, y1, x2, y2, x, y):
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: x1, y: y1),
                    control2: CGPoint(x: x2, y: y2)
                )
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

/// Absolute coordinates on the 24 × 24 grid.
private enum KeyboardIconSegment {
    case move(CGFloat, CGFloat)
    case line(CGFloat, CGFloat)
    case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    case close
}

private extension KeyboardIcon {
    var segments: [KeyboardIconSegment] {
        switch self {
        case .refresh:
            // tabler-icons v3.19.0 outline/refresh.svg
            //   M20 11a8.1 8.1 0 0 0 -15.5 -2m-.5 -4v4h4
            //   M4 13a8.1 8.1 0 0 0 15.5 2m.5 4v-4h-4
            return [
                .move(20, 11),
                .curve(19.497, 7.383, 16.636, 4.549, 13.014, 4.082),
                .curve(9.391, 3.614, 5.905, 5.629, 4.5, 9),
                .move(4, 5),
                .line(4, 9),
                .line(8, 9),
                .move(4, 13),
                .curve(4.503, 16.617, 7.364, 19.451, 10.986, 19.918),
                .curve(14.609, 20.386, 18.095, 18.371, 19.5, 15),
                .move(20, 19),
                .line(20, 15),
                .line(16, 15),
            ]
        case .messageCircle:
            // tabler-icons v3.19.0 outline/message-circle.svg
            //   M3 20l1.3 -3.9c-2.324 -3.437 -1.426 -7.872 2.1 -10.374c3.526 -2.501 8.59 -2.296 11.845 .48c3.255 2.777 3.695 7.266 1.029 10.501c-2.666 3.235 -7.615 4.215 -11.574 2.293l-4.7 1
            return [
                .move(3, 20),
                .line(4.3, 16.1),
                .curve(1.976, 12.663, 2.874, 8.228, 6.4, 5.726),
                .curve(9.926, 3.225, 14.99, 3.43, 18.245, 6.206),
                .curve(21.5, 8.983, 21.94, 13.472, 19.274, 16.707),
                .curve(16.608, 19.942, 11.659, 20.922, 7.7, 19),
                .line(3, 20),
            ]
        case .moodWink:
            // tabler-icons v3.19.0 outline/mood-wink.svg
            //   M12 12m-9 0a9 9 0 1 0 18 0a9 9 0 1 0 -18 0
            //   M15 10h.01
            //   M9.5 15a3.5 3.5 0 0 0 5 0
            //   M8.5 8.5l1.5 1.5l-1.5 1.5
            return [
                .move(3, 12),
                .curve(3, 16.971, 7.029, 21, 12, 21),
                .curve(16.971, 21, 21, 16.971, 21, 12),
                .curve(21, 7.029, 16.971, 3, 12, 3),
                .curve(7.029, 3, 3, 7.029, 3, 12),
                .move(15, 10),
                .line(15.01, 10),
                .move(9.5, 15),
                .curve(10.158, 15.672, 11.059, 16.051, 12, 16.051),
                .curve(12.941, 16.051, 13.842, 15.672, 14.5, 15),
                .move(8.5, 8.5),
                .line(10, 10),
                .line(8.5, 11.5),
            ]
        case .masksTheater:
            // tabler-icons v3.19.0 outline/masks-theater.svg
            //   M13.192 9h6.616a2 2 0 0 1 1.992 2.183l-.567 6.182a4 4 0 0 1 -3.983 3.635h-1.5a4 4 0 0 1 -3.983 -3.635l-.567 -6.182a2 2 0 0 1 1.992 -2.183z
            //   M15 13h.01
            //   M18 13h.01
            //   M15 16.5c1 .667 2 .667 3 0
            //   M8.632 15.982a4.037 4.037 0 0 1 -.382 .018h-1.5a4 4 0 0 1 -3.983 -3.635l-.567 -6.182a2 2 0 0 1 1.992 -2.183h6.616a2 2 0 0 1 2 2
            //   M6 8h.01
            //   M9 8h.01
            //   M6 12c.764 -.51 1.528 -.63 2.291 -.36
            return [
                .move(13.192, 9),
                .line(19.808, 9),
                .curve(20.37, 9, 20.907, 9.237, 21.286, 9.652),
                .curve(21.665, 10.067, 21.851, 10.623, 21.8, 11.183),
                .line(21.233, 17.365),
                .curve(21.044, 19.424, 19.318, 21, 17.25, 21),
                .line(15.75, 21),
                .curve(13.682, 21, 11.956, 19.424, 11.767, 17.365),
                .line(11.2, 11.183),
                .curve(11.149, 10.623, 11.335, 10.067, 11.714, 9.652),
                .curve(12.093, 9.237, 12.63, 9, 13.192, 9),
                .close,
                .move(15, 13),
                .line(15.01, 13),
                .move(18, 13),
                .line(18.01, 13),
                .move(15, 16.5),
                .curve(16, 17.167, 17, 17.167, 18, 16.5),
                .move(8.632, 15.982),
                .curve(8.505, 15.994, 8.378, 16, 8.25, 16),
                .line(6.75, 16),
                .curve(4.682, 16, 2.956, 14.424, 2.767, 12.365),
                .line(2.2, 6.183),
                .curve(2.149, 5.623, 2.335, 5.067, 2.714, 4.652),
                .curve(3.093, 4.237, 3.63, 4, 4.192, 4),
                .line(10.808, 4),
                .curve(11.913, 4, 12.808, 4.895, 12.808, 6),
                .move(6, 8),
                .line(6.01, 8),
                .move(9, 8),
                .line(9.01, 8),
                .move(6, 12),
                .curve(6.764, 11.49, 7.528, 11.37, 8.291, 11.64),
            ]
        case .crystalBall:
            // tabler-icons v3.19.0 outline/crystal-ball.svg
            //   M6.73 17.018a8 8 0 1 1 10.54 0
            //   M5 19a2 2 0 0 0 2 2h10a2 2 0 1 0 0 -4h-10a2 2 0 0 0 -2 2z
            //   M11 7a3 3 0 0 0 -3 3
            return [
                .move(6.73, 17.018),
                .curve(4.223, 14.823, 3.339, 11.303, 4.512, 8.184),
                .curve(5.684, 5.065, 8.668, 2.999, 12, 2.999),
                .curve(15.332, 2.999, 18.316, 5.065, 19.488, 8.184),
                .curve(20.661, 11.303, 19.777, 14.823, 17.27, 17.018),
                .move(5, 19),
                .curve(5, 20.105, 5.895, 21, 7, 21),
                .line(17, 21),
                .curve(18.105, 21, 19, 20.105, 19, 19),
                .curve(19, 17.895, 18.105, 17, 17, 17),
                .line(7, 17),
                .curve(5.895, 17, 5, 17.895, 5, 19),
                .close,
                .move(11, 7),
                .curve(9.343, 7, 8, 8.343, 8, 10),
            ]
        case .heart:
            // tabler-icons v3.19.0 outline/heart.svg
            //   M19.5 12.572l-7.5 7.428l-7.5 -7.428a5 5 0 1 1 7.5 -6.566a5 5 0 1 1 7.5 6.572
            return [
                .move(19.5, 12.572),
                .line(12, 20),
                .line(4.5, 12.572),
                .curve(3.151, 11.26, 2.654, 9.301, 3.212, 7.504),
                .curve(3.771, 5.707, 5.292, 4.376, 7.147, 4.06),
                .curve(9.002, 3.743, 10.877, 4.496, 12, 6.006),
                .curve(13.127, 4.507, 14.999, 3.765, 16.847, 4.084),
                .curve(18.696, 4.403, 20.21, 5.73, 20.769, 7.52),
                .curve(21.328, 9.311, 20.838, 11.264, 19.5, 12.578),
            ]
        case .bulb:
            // tabler-icons v3.19.0 outline/bulb.svg
            //   M3 12h1m8 -9v1m8 8h1m-15.4 -6.4l.7 .7m12.1 -.7l-.7 .7
            //   M9 16a5 5 0 1 1 6 0a3.5 3.5 0 0 0 -1 3a2 2 0 0 1 -4 0a3.5 3.5 0 0 0 -1 -3
            //   M9.7 17l4.6 0
            return [
                .move(3, 12),
                .line(4, 12),
                .move(12, 3),
                .line(12, 4),
                .move(20, 12),
                .line(21, 12),
                .move(5.6, 5.6),
                .line(6.3, 6.3),
                .move(18.4, 5.6),
                .line(17.7, 6.3),
                .move(9, 16),
                .curve(7.278, 14.709, 6.576, 12.461, 7.257, 10.419),
                .curve(7.937, 8.377, 9.848, 7, 12, 7),
                .curve(14.152, 7, 16.063, 8.377, 16.743, 10.419),
                .curve(17.424, 12.461, 16.722, 14.709, 15, 16),
                .curve(14.208, 16.784, 13.837, 17.898, 14, 19),
                .curve(14, 20.105, 13.105, 21, 12, 21),
                .curve(10.895, 21, 10, 20.105, 10, 19),
                .curve(10.163, 17.898, 9.792, 16.784, 9, 16),
                .move(9.7, 17),
                .line(14.3, 17),
            ]
        case .alertTriangle:
            // tabler-icons v3.19.0 outline/alert-triangle.svg
            //   M12 9v4
            //   M10.363 3.591l-8.106 13.534a1.914 1.914 0 0 0 1.636 2.871h16.214a1.914 1.914 0 0 0 1.636 -2.87l-8.106 -13.536a1.914 1.914 0 0 0 -3.274 0z
            //   M12 16h.01
            return [
                .move(12, 9),
                .line(12, 13),
                .move(10.363, 3.591),
                .line(2.257, 17.125),
                .curve(1.917, 17.714, 1.915, 18.439, 2.252, 19.03),
                .curve(2.588, 19.621, 3.213, 19.988, 3.893, 19.996),
                .line(20.107, 19.996),
                .curve(20.787, 19.988, 21.411, 19.62, 21.748, 19.03),
                .curve(22.084, 18.44, 22.083, 17.715, 21.743, 17.126),
                .line(13.637, 3.59),
                .curve(13.29, 3.017, 12.669, 2.668, 12, 2.668),
                .curve(11.331, 2.668, 10.71, 3.017, 10.363, 3.59),
                .close,
                .move(12, 16),
                .line(12.01, 16),
            ]
        }
    }
}
