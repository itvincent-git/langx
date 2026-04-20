import AppKit

enum AppIconRenderer {
    static func makeApplicationIcon(size: CGFloat = 512) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize)
        image.lockFocus()

        let canvas = NSRect(origin: .zero, size: imageSize)
        let cornerRadius = size * 0.23

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = size * 0.05
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
        shadow.set()

        let background = NSBezierPath(roundedRect: canvas, xRadius: cornerRadius, yRadius: cornerRadius)
        let backgroundGradient = NSGradient(
            colors: [
                NSColor(srgbRed: 0.11, green: 0.46, blue: 0.98, alpha: 1),
                NSColor(srgbRed: 0.04, green: 0.23, blue: 0.87, alpha: 1),
            ]
        )
        backgroundGradient?.draw(in: background, angle: -35)

        let inset = size * 0.09
        let highlightRect = canvas.insetBy(dx: inset, dy: inset)
        let highlight = NSBezierPath(roundedRect: highlightRect, xRadius: size * 0.18, yRadius: size * 0.18)
        NSColor.white.withAlphaComponent(0.08).setStroke()
        highlight.lineWidth = size * 0.012
        highlight.stroke()

        drawPrimaryBubble(in: canvas, size: size)
        drawSecondaryBubble(in: canvas, size: size)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawPrimaryBubble(in canvas: NSRect, size: CGFloat) {
        let bubbleRect = NSRect(
            x: size * 0.09,
            y: size * 0.12,
            width: size * 0.58,
            height: size * 0.58
        )

        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: size * 0.13, yRadius: size * 0.13)
        bubble.appendSpeechTail(
            points: [
                NSPoint(x: size * 0.23, y: size * 0.17),
                NSPoint(x: size * 0.18, y: size * 0.05),
                NSPoint(x: size * 0.33, y: size * 0.14),
            ]
        )

        let gradient = NSGradient(
            colors: [
                NSColor(srgbRed: 0.97, green: 0.99, blue: 1, alpha: 0.98),
                NSColor(srgbRed: 0.85, green: 0.93, blue: 1, alpha: 0.94),
            ]
        )
        gradient?.draw(in: bubble, angle: 90)

        NSColor.white.withAlphaComponent(0.45).setStroke()
        bubble.lineWidth = size * 0.01
        bubble.stroke()

        let text = "A"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.25, weight: .bold),
            .foregroundColor: NSColor(srgbRed: 0.04, green: 0.23, blue: 0.74, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        let textRect = NSRect(
            x: bubbleRect.minX,
            y: bubbleRect.minY + size * 0.11,
            width: bubbleRect.width,
            height: size * 0.28
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private static func drawSecondaryBubble(in canvas: NSRect, size: CGFloat) {
        let bubbleRect = NSRect(
            x: size * 0.45,
            y: size * 0.37,
            width: size * 0.38,
            height: size * 0.38
        )

        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: size * 0.11, yRadius: size * 0.11)
        bubble.appendSpeechTail(
            points: [
                NSPoint(x: size * 0.69, y: size * 0.38),
                NSPoint(x: size * 0.79, y: size * 0.24),
                NSPoint(x: size * 0.60, y: size * 0.33),
            ]
        )

        let gradient = NSGradient(
            colors: [
                NSColor(srgbRed: 0.99, green: 0.81, blue: 0.33, alpha: 1),
                NSColor(srgbRed: 0.98, green: 0.56, blue: 0.18, alpha: 1),
            ]
        )
        gradient?.draw(in: bubble, angle: 135)

        NSColor.white.withAlphaComponent(0.35).setStroke()
        bubble.lineWidth = size * 0.009
        bubble.stroke()

        let text = "文"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.16, weight: .heavy),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let textRect = NSRect(
            x: bubbleRect.minX,
            y: bubbleRect.minY + size * 0.08,
            width: bubbleRect.width,
            height: size * 0.18
        )
        text.draw(in: textRect, withAttributes: attributes)
    }
}

private extension NSBezierPath {
    func appendSpeechTail(points: [NSPoint]) {
        guard points.count == 3 else {
            return
        }

        move(to: points[0])
        line(to: points[1])
        line(to: points[2])
        close()
    }
}
