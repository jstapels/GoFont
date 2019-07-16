//
//  FontRenderer.swift
//  GoFont
//
//  Created by Jason Stapels on 4/10/17.
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

// Base font template
let FontsViewHtml = HtmlTemplate(resource: "FontsView")


/// A font that will generate an html sample with a specific sample text.
protocol FontHtml {
    var name: String { get }
    func html(sample: String, size: String, ids: [String]?, selected: [String]?) -> String
}

extension FontHtml {
    func html(sample: String, size: String, ids: [String]? = nil) -> String {
        return html(sample: sample, size: size, ids: ids, selected: nil)
    }

    func html(sample: String, size: String, selected: [String]?) -> String {
        return html(sample: sample, size: size, ids: nil, selected: selected)
    }
}
