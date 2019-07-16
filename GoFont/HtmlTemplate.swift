//
//  HtmlTemplate.swift
//  GoFont
//
//  Created by Jason Stapels on 2/4/17.
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


/// A very simplistic *handlebars-like* html template rendering engine.
struct HtmlTemplate {
    
    let html: String
    
    let baseURL: URL
    
    init(resource: String) {
        if let pathUrl = Bundle.main.url(forResource: resource, withExtension: "html") {
            baseURL = pathUrl.deletingLastPathComponent()
            html = try! String(contentsOf: pathUrl)
        } else {
            baseURL = Bundle.main.bundleURL
            html = "Error finding resource: \(resource)"
        }
    }
    
    func render(_ data: [String: String] = [:]) -> String {
        var output = html
    
        data.forEach { key, value in
            output = output.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        
        return output
    }
}
