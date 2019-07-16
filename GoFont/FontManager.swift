//
//  Fonts.swift
//  GoFont
//
//  Created by Jason Stapels on 1/6/17.
//
// This file is part of the GoFont distribution (https://github.com/jstapels/GoFont)
// Copyright © 2017 Jason Stapels
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

///
/// The font manager
///
class FontManager {
    static let instance = FontManager()

    private var handlers = [FontHandler]()

    private let queue = DispatchQueue(label: "com.codeadepts.fontManager")

    private init() {}

    func addHandler(_ handler: FontHandler) {
        handlers.append(handler)
    }

    func queryFonts(search: String,
                    sort: FontSort = .alpha,
                    categories: Set<FontCategory> = Set(FontCategory.values),
                    weights: Set<FontWeight> = Set(FontWeight.values),
                    styles: Set<FontStyle> = Set(FontStyle.values)) -> [FontFamily] {

        return handlers.flatMap { $0.query(search: search, sort: sort) }
            .filter { categories.contains($0.category) }
            .filter { !weights.isDisjoint(with: $0.variants.values.map { $0.weight }) }
            .filter { !styles.isDisjoint(with: $0.variants.values.map { $0.style }) }
    }

    func getFont(name: String) -> FontFamily? {
        return handlers.flatMap({ $0.getFont(name: name) }).first
    }
}

///
/// A font handler is used to lookup fonts and download them
///
protocol FontHandler {
    func query(search: String, sort: FontSort) -> [FontFamily]
    func getFont(name: String) -> FontFamily?
}

/// A font family that contains one or more variants (styles).
protocol FontFamily: FontHtml {
    var name: String { get }
    var variants: [String: FontVariant] { get }
    var category: FontCategory { get }

    func download(id: String?) -> Data?
}

/// A variant (specific style and weight) of a font.
protocol FontVariant: CustomStringConvertible {
    var id: String { get }
    var filename: String { get }
    var weight: FontWeight { get }
    var style: FontStyle { get }
}

extension CustomStringConvertible where Self: FontVariant {
    var description: String {
        if style == .regular {
            return String(describing: weight)
        } else {
            return weight == .normal ? "italic" : String(describing: weight) + " italic"
        }
    }
}

struct AnyFont: Hashable, Comparable {
    var font: FontFamily
    var variantId: String

    var hashValue: Int {
        return 31 &* font.name.hashValue &+ variantId.hashValue
    }

    static func == (lhs: AnyFont, rhs: AnyFont) -> Bool {
        return lhs.font.name == rhs.font.name && lhs.variantId == rhs.variantId
    }

    static func < (lhs: AnyFont, rhs: AnyFont) -> Bool {
        if lhs == rhs {
            return lhs.variantId < rhs.variantId
        } else {
            return lhs.font.name < rhs.font.name
        }
    }
}

/// The supported font weights
///
/// - thin: a thin (100) font
/// - extraLight: an extra light (200) font
/// - light: a light (300) font
/// - normal: a normal (400) font
/// - medium: a medium (500) font
/// - semiBold: a semi-bold (600) font
/// - bold: a bold (700) font
/// - extraBold: an extra bold (800) font
/// - black: a heavy black (900) font
enum FontWeight: String {
    case thin = "100"
    case extraLight = "200"
    case light = "300"
    case normal = "regular"
    case medium = "500"
    case semiBold = "600"
    case bold = "700"
    case extraBold = "800"
    case black = "900"

    static let values: [FontWeight] = [.thin, .extraLight, .light, .normal, .medium, .semiBold, .bold, .extraBold, .black]
}

extension FontWeight: CustomStringConvertible {
    var description: String {
        switch self {
        case .thin: return "thin"
        case .extraLight: return "extra light"
        case .light: return "light"
        case .normal: return "normal"
        case .medium: return "medium"
        case .semiBold: return "semi bold"
        case .bold: return "bold"
        case .extraBold: return "extra bold"
        case .black: return "black"
        }
    }
}

extension FontWeight: Comparable {
    var order: Int {
        switch self {
        case .thin: return 0
        case .extraLight: return 1
        case .light: return 2
        case .normal: return 3
        case .medium: return 4
        case .semiBold: return 5
        case .bold: return 6
        case .extraBold: return 7
        case .black: return 8
        }
    }

    static func < (lhs: FontWeight, rhs: FontWeight) -> Bool {
        return lhs.order < rhs.order
    }
}

/// The supported font styles
///
/// - regular: regular style
/// - italic: italic style
enum FontStyle: String {
    case regular = "normal"
    case italic = "italic"

    static let values: [FontStyle] = [.regular, .italic]
}

extension FontStyle: CustomStringConvertible {
    var description: String {
        return self.rawValue
    }
}

extension FontStyle: Comparable {
    var order: Int {
        switch self {
        case .regular: return 0
        case .italic: return 1
        }
    }

    static func < (lhs: FontStyle, rhs: FontStyle) -> Bool {
        return lhs.order < rhs.order
    }
}


/// The supported font categories
///
/// - serif: <#serif description#>
/// - sansSerif: <#sansSerif description#>
/// - display: <#display description#>
/// - handwriting: <#handwriting description#>
enum FontCategory: String {
    case serif = "serif"
    case sansSerif = "sans-serif"
    case display = "display"
    case handwriting = "handwriting"
    case monospace = "monospace"
    case unknown = "unknown"

    static let values: [FontCategory] = [.serif, .sansSerif, .display, .handwriting, .monospace, .unknown]
}

extension FontCategory: CustomStringConvertible {
    var description: String {
        return self.rawValue
    }
}


/// The support font sorting algorithms
///
/// - alphabetical: sorted a-z
/// - date: sorted with newest fonts first
/// - popularity: sorted with most popular fonts first
/// - style: grouped by style, with the biggest one first
/// - trending: sorted with the most trending fonts firt
enum FontSort: String {
    case alpha
    case newest
    case popularity
    case trending

    static let values: [FontSort] = [.alpha, .newest, .popularity, .trending]
}

extension FontSort: CustomStringConvertible {
    var description: String {
        return self.rawValue
    }
}


