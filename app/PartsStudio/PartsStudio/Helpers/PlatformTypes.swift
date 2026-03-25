import SwiftUI

#if os(iOS)
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
#else
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
#endif

extension PlatformColor {
    /// Initialize from hex string (6 or 8 char, optional # prefix).
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var hexInt: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&hexInt)

        let r, g, b, a: CGFloat
        switch hex.count {
        case 6:
            r = CGFloat((hexInt >> 16) & 0xFF) / 255
            g = CGFloat((hexInt >> 8) & 0xFF) / 255
            b = CGFloat(hexInt & 0xFF) / 255
            a = 1.0
        case 8:
            r = CGFloat((hexInt >> 24) & 0xFF) / 255
            g = CGFloat((hexInt >> 16) & 0xFF) / 255
            b = CGFloat((hexInt >> 8) & 0xFF) / 255
            a = CGFloat(hexInt & 0xFF) / 255
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
