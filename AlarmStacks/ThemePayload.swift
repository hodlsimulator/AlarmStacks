//
//  ThemePayload.swift
//  AlarmStacks
//
//  Created by . . on 8/19/25.
//

import Foundation
import SwiftUI

public struct RGBA: Codable, Equatable, Hashable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public init(_ color: Color) {
        #if canImport(UIKit)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let ui = UIColor(color)
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.r = Double(red); self.g = Double(green); self.b = Double(blue); self.a = Double(alpha)
        #else
        self.r = 0; self.g = 0; self.b = 0; self.a = 1
        #endif
    }
    public var color: Color { Color(red: r, green: g, blue: b).opacity(a) }
}

public struct ThemePayload: Codable, Equatable, Hashable {
    public var name: String
    public var accent: RGBA
    public var bgLight: RGBA
    public var bgDark: RGBA
    public init(name: String, accent: RGBA, bgLight: RGBA, bgDark: RGBA) {
        self.name = name; self.accent = accent; self.bgLight = bgLight; self.bgDark = bgDark
    }
}

public enum ThemeMap {
    // Keep in sync with ThemePickerView options
    public static func accent(for name: String) -> Color {
        switch name {
        case "Forest":   return Color(red: 0.16, green: 0.62, blue: 0.39)
        case "Coral":    return Color(red: 0.98, green: 0.45, blue: 0.35)
        case "Indigo":   return Color(red: 0.35, green: 0.37, blue: 0.80)
        case "Grape":    return Color(red: 0.56, green: 0.27, blue: 0.68)
        case "Mint":     return Color(red: 0.22, green: 0.77, blue: 0.58)
        case "Flamingo": return Color(red: 1.00, green: 0.35, blue: 0.62)
        case "Slate":    return Color(red: 0.36, green: 0.42, blue: 0.49)
        case "Midnight": return Color(red: 0.10, green: 0.14, blue: 0.28)
        default:         return Color(red: 0.04, green: 0.52, blue: 1.00)
        }
    }

    public static func background(for name: String, scheme: ColorScheme) -> Color {
        switch (name, scheme) {
        case ("Default", .light):  return Color(red: 1.00, green: 0.96, blue: 0.92)
        case ("Default", .dark):   return Color(red: 0.26, green: 0.22, blue: 0.18)

        case ("Forest", .light):   return Color(red: 0.99, green: 0.95, blue: 0.97)
        case ("Forest", .dark):    return Color(red: 0.21, green: 0.18, blue: 0.22)

        case ("Coral", .light):    return Color(red: 0.92, green: 0.98, blue: 0.97)
        case ("Coral", .dark):     return Color(red: 0.15, green: 0.20, blue: 0.20)

        case ("Indigo", .light):   return Color(red: 1.00, green: 0.97, blue: 0.90)
        case ("Indigo", .dark):    return Color(red: 0.26, green: 0.23, blue: 0.18)

        case ("Grape", .light):    return Color(red: 0.94, green: 0.99, blue: 0.96)
        case ("Grape", .dark):     return Color(red: 0.16, green: 0.22, blue: 0.19)

        case ("Mint", .light):     return Color(red: 0.96, green: 0.95, blue: 1.00)
        case ("Mint", .dark):      return Color(red: 0.20, green: 0.20, blue: 0.27)

        case ("Flamingo", .light): return Color(red: 0.93, green: 0.99, blue: 1.00)
        case ("Flamingo", .dark):  return Color(red: 0.18, green: 0.22, blue: 0.24)

        case ("Slate", .light):    return Color(red: 0.95, green: 0.97, blue: 1.00)
        case ("Slate", .dark):     return Color(red: 0.15, green: 0.17, blue: 0.21)

        case ("Midnight", .light): return Color(red: 1.00, green: 0.96, blue: 0.90)
        case ("Midnight", .dark):  return Color(red: 0.24, green: 0.20, blue: 0.15)

        default:
            return scheme == .dark
            ? Color(red: 0.20, green: 0.20, blue: 0.20)
            : Color(red: 0.97, green: 0.97, blue: 0.97)
        }
    }

    public static func payload(for name: String) -> ThemePayload {
        let accent = RGBA(accent(for: name))
        let bgL = RGBA(background(for: name, scheme: .light))
        let bgD = RGBA(background(for: name, scheme: .dark))
        return ThemePayload(name: name, accent: accent, bgLight: bgL, bgDark: bgD)
    }
}
