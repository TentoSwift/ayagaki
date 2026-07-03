import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// "#RRGGBB" から生成
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    private var rgbComponents: (r: Double, g: Double, b: Double) {
        #if os(macOS)
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #endif
    }

    var hexString: String {
        let c = rgbComponents
        func u(_ v: Double) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", u(c.r), u(c.g), u(c.b))
    }

    /// 明度を上下（amount は -255〜255 相当）
    func shaded(by amount: Double) -> Color {
        let c = rgbComponents
        func f(_ v: Double) -> Double { max(0, min(1, v + amount / 255)) }
        return Color(.sRGB, red: f(c.r), green: f(c.g), blue: f(c.b), opacity: 1)
    }
}
