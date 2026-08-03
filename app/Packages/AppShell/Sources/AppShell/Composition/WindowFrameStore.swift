import AppKit
import Foundation

struct WindowFrameStore {
    static let minWidth: CGFloat = 1280
    static let minHeight: CGFloat = 700

    private static let keyWidth = "windowFrameWidth"
    private static let keyHeight = "windowFrameHeight"
    private static let keyX = "windowFrameX"
    private static let keyY = "windowFrameY"

    static func save(frame: NSRect) {
        UserDefaults.standard.set(Double(frame.size.width), forKey: keyWidth)
        UserDefaults.standard.set(Double(frame.size.height), forKey: keyHeight)
        UserDefaults.standard.set(Double(frame.origin.x), forKey: keyX)
        UserDefaults.standard.set(Double(frame.origin.y), forKey: keyY)
    }

    static func load() -> NSRect? {
        guard let w = UserDefaults.standard.object(forKey: keyWidth) as? Double,
              let h = UserDefaults.standard.object(forKey: keyHeight) as? Double,
              let x = UserDefaults.standard.object(forKey: keyX) as? Double,
              let y = UserDefaults.standard.object(forKey: keyY) as? Double
        else { return nil }
        return NSRect(x: x, y: y, width: max(w, minWidth), height: max(h, minHeight))
    }

    static var savedSize: CGSize {
        load().map { $0.size } ?? CGSize(width: minWidth, height: minHeight)
    }
}
