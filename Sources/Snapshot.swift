import AppKit

/// Debug helper: renders the panel's content to a PNG so the layout can be reviewed
/// without screen-recording permission. The window material is transparent when
/// captured this way, so a synthetic backdrop is composited underneath.
enum Snapshot {
    @discardableResult
    static func capture(window: NSWindow, to path: String) -> Bool {
        guard let view = window.contentView else { return false }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return false }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 1, height > 1 else { return false }

        guard let final = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return false }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: final) else {
            NSGraphicsContext.restoreGraphicsState()
            return false
        }
        NSGraphicsContext.current = context
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.19, alpha: 1),
            NSColor(calibratedRed: 0.32, green: 0.17, blue: 0.27, alpha: 1)
        ])
        gradient?.draw(in: rect, angle: 40)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.draw(in: rect)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = final.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }
}
