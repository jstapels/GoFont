//
//  GoogleFonts.swift
//  GoFont
//
//  Created by Jason Stapels on 1/10/17.
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

struct GoogleFonts: FontHandler {
    static let apiKey = Bundle.main.infoDictionary?["GoogleFontApiKey"] as? String ?? ""
    static let url = URL(string: "https://www.googleapis.com/webfonts/v1/webfonts?key=\(apiKey)")!
    static let urlPopular = URL(string: "https://www.googleapis.com/webfonts/v1/webfonts?key=\(apiKey)&sort=popularity")!
    static let urlTrending = URL(string: "https://www.googleapis.com/webfonts/v1/webfonts?key=\(apiKey)&sort=trending")!
    static let urlNewest = URL(string: "https://www.googleapis.com/webfonts/v1/webfonts?key=\(apiKey)&sort=date")!

    private let fonts: [String: GoogleFontFamily]
    private let families: [FontSort: [String]]

    init() {
        fonts = GoogleFonts.getFontData(url: GoogleFonts.url)

        families = [
            .alpha: fonts.keys.sorted(),
            .popularity: GoogleFonts.getFamilies(url: GoogleFonts.urlPopular),
            .trending: GoogleFonts.getFamilies(url: GoogleFonts.urlTrending),
            .newest: GoogleFonts.getFamilies(url: GoogleFonts.urlNewest)
        ]
    }

    private static func getFontData(url: URL) -> [String: GoogleFontFamily] {
        guard let data = try? Data(contentsOf: url) else {
            // FIXME: Log
            return [:]
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            // FIXME: Log
            return [:]
        }

        guard let dict = json as? [String: Any] else {
            // FIXME: Log
            return [:]
        }

        return convertJson(dict)
    }

    private static func getFamilies(url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url) else {
            // FIXME: Log
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            // FIXME: Log
            return []
        }

        guard let dict = json as? [String: Any] else {
            // FIXME: Log
            return []
        }

        return convertJsonFamilies(dict)
    }

    private static func convertJson(_ json: [String: Any]) -> [String: GoogleFontFamily] {
        var itemData = [String: GoogleFontFamily]()

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        if let items = json["items"] as? [[String: Any]] {
            for item in items {
                let kind = item["kind"] as! String
                let family = item["family"] as! String
                let category = FontCategory(rawValue: item["category"] as! String) ?? FontCategory.unknown
                let variantIds = item["variants"] as! [String]
                let subsets = item["subsets"] as! [String]
                let version = item["version"] as! String
                let lastModified = dateFormatter.date(from: item["lastModified"] as! String)!
                var files = [String: URL]()
                for (variantId, url) in item["files"] as! [String: String] {
                    let urlString = url.replacingOccurrences(of: "http:", with: "https:") // Force https
                    files[variantId] = URL(string: urlString)!
                }
                var variantData = [String: FontVariant]()
                variantIds.forEach { id in
                    let lookup = id.replacingOccurrences(of: "italic", with: "")
                    let weight = FontWeight(rawValue: lookup.isEmpty ? "regular" : lookup)!
                    let style = id.contains("italic") ? FontStyle.italic : FontStyle.regular
                    let url = files[id]!

                    variantData[id] = GoogleFontVariant(
                        id: id,
                        familyName: family,
                        weight: weight,
                        style: style,
                        url: url)
                }

                let data = GoogleFontFamily(
                    kind: kind,
                    name: family,
                    category: category,
                    variantIds: variantIds,
                    variants: variantData,
                    subsets: subsets,
                    version: version,
                    lastModified: lastModified)

                itemData[family] = data
            }
        }

        return itemData
    }

    private static func convertJsonFamilies(_ json: [String: Any]) -> [String] {
        var families = [String]()

        if let items = json["items"] as? [[String: Any]] {
            for item in items {
                families.append(item["family"] as! String)
            }
        }
        
        return families
    }
    
    func query(search: String, sort: FontSort) -> [FontFamily] {
        return families[sort]!
            .filter { search.isEmpty || $0.lowercased().contains(search.lowercased()) }
            .map { fonts[$0]! }
    }

    func getFont(name: String) -> FontFamily? {
        return fonts[name]
    }
}



struct GoogleFontFamily: FontFamily {
    var kind: String
    var name: String
    var category: FontCategory
    var variantIds: [String]
    var variants: [String: FontVariant]
    var subsets: [String]
    var version: String
    var lastModified: Date

    func download(id: String?) -> Data? {
        guard let fontId = id else {
            debugPrint("Must specify a variant id")
            return nil
        }

        guard let variant = (variants[fontId] as? GoogleFontVariant) else {
            debugPrint("Variant id not found \(fontId)")
            return nil
        }

        do {
            return try Data(contentsOf: variant.url)
        } catch {
            debugPrint("Failed to download \(error)")
            return nil
        }
    }
}

extension GoogleFontFamily: FontHtml {
    private static let familyHtml = HtmlTemplate(resource: "GoogleFontsFamily")

    func html(sample: String, size: String, ids: [String]? = nil, selected: [String]? = nil) -> String {
        let fontIds = ids ?? variantIds
        let checked = Set(selected ?? [])
        let samples = fontIds
            .filter({ variantIds.contains($0) })
            .map({ (variants[$0] as! GoogleFontVariant).html(sample: sample, size: size, selected: checked.contains($0)) })
        let familyId = name.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")

        let output = GoogleFontFamily.familyHtml.render([
            "family": name,
            "familyId" : familyId,
            "variants": variants.keys.joined(separator: ","),
            "samples": samples.joined(separator: "\n")
            ])

        return output
    }
}

struct GoogleFontVariant: FontVariant {
    private static let variantHtml = HtmlTemplate(resource: "GoogleFontsVariant")

    var id: String
    var familyName: String
    var weight: FontWeight
    var style: FontStyle
    var url: URL

    var filename: String {
        let weightToken: String
        switch weight {
        case .thin: weightToken = "Thin"
        case .extraLight: weightToken = "ExtraLight"
        case .light: weightToken = "Light"
        case .normal: weightToken = "Regular"
        case .medium: weightToken = "Medium"
        case .semiBold: weightToken = "SemiBold"
        case .bold: weightToken = "Bold"
        case .extraBold: weightToken = "ExtraBold"
        case .black: weightToken = "Black"
        }

        let styleToken: String
        switch style {
        case .regular: styleToken = ""
        case .italic: styleToken = "Italic"
        }

        let baseName = familyName.replacingOccurrences(of: " ", with: "")
        return "\(baseName)-\(weightToken)\(styleToken).ttf"
    }

    func html(sample: String, size: String, selected: Bool = false) -> String {
        let familyId = familyName.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")

        return GoogleFontVariant.variantHtml.render([
            "familyId": familyId,
            "variantId": id,
            "checked" : selected ? "checked" : "",
            "style": style.rawValue,
            "weight": weight.rawValue,
            "description": String(describing: self),
            "sample": sample,
            "size": size
            ])
    }
}
