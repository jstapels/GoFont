//
//  ViewController.swift
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

import Cocoa
import WebKit
import os.log

/// The view controller for GoFont's main window.
class ViewController: NSViewController, NSTextFieldDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    static let panagrams = [
        "Grumpy wizards make toxic brew for the evil Queen and Jack.",
        "The quick brown fox jumps over the lazy dog.",
        "Jack amazed a few girls by dropping the antique onyx vase.",
        "Six crazy kings vowed to abolish my quite pitiful jousts.",
        "Five or six big jet planes zoomed quickly by the tower.",
        "My grandfather picks up quartz and valuable onyx jewels.",
        "Pack my box with five dozen liquor jugs."
        ]

    private let viewLog = OSLog(subsystem: "com.codeadepts.GoFont", category: "View")

    private let maxShown = 20
    private let sampleText = panagrams[Int(arc4random_uniform(UInt32(panagrams.count)))];

    private let loadPage = "loadPage"
    private let selectFont = "selectFont"
    private let unselectFont = "unselectFont"

    private let fontManager = FontManager.instance

    private let searchQueue = DispatchQueue(label: "com.codeadepts.searchQueue", qos: .userInitiated)
    private let workQueue = DispatchQueue(label: "com.codeadepts.workQueue", qos: .userInitiated)
    private let downloadQueue = DispatchQueue(label: "com.codeadepts.downloadQueue", qos: .background)

    private let splashDelay = DispatchTimeInterval.seconds(3)
    private let searchDelay = DispatchTimeInterval.milliseconds(250)
    private let sampleDelay = DispatchTimeInterval.milliseconds(10)
    private var searchTask: DispatchWorkItem?
    private var sampleTask: DispatchWorkItem?
    private var sizeTask: DispatchWorkItem?

    private let statusDelay = DispatchTimeInterval.seconds(3)
    private var statusTask: DispatchWorkItem?

    private var lastSearch = ""
    private var customText = ""
    private var searchResults = [FontFamily]()
    private var selectedFonts = Set<AnyFont>()
    private var curPage = 1
    private var fontSize = "12pt"

    private var categoryFilter: Set<FontCategory> = Set(FontCategory.values)
    private var weightFilter: Set<FontWeight> = Set(FontWeight.values)
    private var styleFilter: Set<FontStyle> = Set(FontStyle.values)
    private var sorting = FontSort.popularity

    private var selectedFamilyIds: Set<String> {
        return workQueue.sync { Set(selectedFonts.map({$0.font.name})) }
    }



    //MARK: Properties
    @IBOutlet weak private var searchField: NSTextField!
    @IBOutlet weak private var customView: NSView!
    @IBOutlet weak private var downloadButton: NSButton!
    @IBOutlet weak private var statusBar: NSTextField!
    @IBOutlet weak var sampleField: NSTextField!

    private var webView: WKWebView!


    override func viewDidLoad() {
        os_log("Starting up...", log: viewLog, type: .info)
        super.viewDidLoad()

        // Load initial html.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let copyright = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
        let welcomeHtml = HtmlTemplate(resource: "GoFont").render(["version": version, "copyright": copyright])

        // Setup web view.
        let webFrame = CGRect(origin: .zero, size: customView.frame.size)
        let webConfig = WKWebViewConfiguration()
        webConfig.userContentController.add(self, name: loadPage)
        webConfig.userContentController.add(self, name: selectFont)
        webConfig.userContentController.add(self, name: unselectFont)
        webView = WKWebView(frame: webFrame, configuration: webConfig)
        webView.loadHTMLString(welcomeHtml, baseURL: FontsViewHtml.baseURL)
        webView.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        webView.navigationDelegate = self
#if DEBUG
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
#endif
        customView.addSubview(webView)

        // Add text field delegate for quick searching.
        searchField.delegate = self
        sampleField.delegate = self

        // Load Google fonts and trigger post-splash search.
        updateStatusBar("Initializing Google Fonts...")
        searchTask = DispatchWorkItem { self.performSearch() }
        let splashDeadline = DispatchTime.now() + splashDelay
        searchQueue.async {
            self.fontManager.addHandler(GoogleFonts())
            self.updateStatusBar("Google Fonts Ready", cleanup: true)

            self.searchTask = DispatchWorkItem { self.performSearch() }
            self.searchQueue.asyncAfter(deadline: splashDeadline, execute: self.searchTask!)
        }
    }

//    override var representedObject: Any? {
//        didSet {
//        // Update the view, if already loaded.
//        }
//    }

    //MARK: Actions

    private func handleSegmentedFilter(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        let selected = sender.isSelected(forSegment: index)

        // Handle special first selection.
        if selected {
            if index == 0 {
                for i in 1..<sender.segmentCount {
                    sender.setSelected(false, forSegment: i)
                }
            } else {
                sender.setSelected(false, forSegment: 0)
            }
        } else {
            // Make sure there's always at least one selection.
            var anySelected = false
            for i in 0..<sender.segmentCount {
                anySelected = anySelected || sender.isSelected(forSegment: i)
            }
            if !anySelected {
                sender.setSelected(true, forSegment: index)
            }
        }
    }

    private func getFilter<T>(_ sender: NSSegmentedControl, mapping: Array<T>) -> Set<T> {
        var filter: Set<T> = []

        if sender.isSelected(forSegment: 0) {
            filter = Set(mapping);
        } else {
            for i in 1..<sender.segmentCount {
                if sender.isSelected(forSegment: i) {
                    filter.insert(mapping[i - 1])
                }
            }
        }

        return filter;
    }

    @IBAction func categoryAction(_ sender: NSSegmentedControl) {
        os_log("Category action: %@", log: viewLog, type: .debug, sender.selectedSegment.description)

        handleSegmentedFilter(sender)
        let filter = getFilter(sender, mapping: FontCategory.values)

        // Update filter.
        searchQueue.async {
            os_log("Category filter: %@", log: self.viewLog, type: .debug, filter.description)
            self.categoryFilter = filter
            self.performSearch()
        }
    }

    @IBAction func weightAction(_ sender: NSSegmentedControl) {
        os_log("Weight action: %@", log: viewLog, type: .debug, sender.selectedSegment.description)

        handleSegmentedFilter(sender)
        let filter = getFilter(sender, mapping: FontWeight.values)

        // Update filter.
        searchQueue.async {
            os_log("Weight filter: %@", log: self.viewLog, type: .debug, filter.description)
            self.weightFilter = filter
            self.performSearch()
        }
    }
    
    @IBAction func styleAction(_ sender: NSSegmentedControl) {
        os_log("Style action: %@", log: viewLog, type: .debug, sender.selectedSegment.description)

        let filter = self.getFilter(sender, mapping: FontStyle.values)

        // Update filter.
        searchQueue.async {
            os_log("Style filter: %@", log: self.viewLog, type: .debug, filter.description)
            self.styleFilter = filter
            self.performSearch()
        }
    }


    // Called when the search field changes.
    override func controlTextDidChange(_ obj: Notification) {
        guard let sender = obj.object as? NSTextField else {
            return
        }

        let input = sender.stringValue.trimmingCharacters(in: .whitespaces)

        switch sender {
        case searchField:
            searchTask?.cancel()
            searchTask = DispatchWorkItem {
                if input != self.lastSearch {
                    self.lastSearch = input
                    self.performSearch(input)
                }
            }
            searchQueue.asyncAfter(deadline: .now() + searchDelay, execute: searchTask!)
        case sampleField:
            sampleTask?.cancel()
            sampleTask = DispatchWorkItem {
                if input != self.customText {
                    self.customText = input
                    self.updateView()
                }
            }
            searchQueue.asyncAfter(deadline: .now() + sampleDelay, execute: sampleTask!)
        default: return
        }
    }


    /// Called when someone pressed enter on a search field.
    /// Used to kick off a search.
    ///
    /// - Parameter sender: reference to the text field
    @IBAction func searchFieldAction(_ sender: NSTextField) {
        let input = sender.stringValue.trimmingCharacters(in: .whitespaces)

        searchQueue.async {
            if input != self.lastSearch {
                self.lastSearch = input
                self.performSearch(input)
            }
        }
    }

    @IBAction func sampleFieldAction(_ sender: NSTextField) {
        let input = sender.stringValue.trimmingCharacters(in: .whitespaces)

        searchQueue.async {
            if input != self.customText {
                self.customText = input
                self.updateView()
            }
        }
    }

    @IBAction func sizeSliderAction(_ sender: NSSlider) {
        let input = sender.stringValue + "pt"

        sizeTask?.cancel()
        sizeTask = DispatchWorkItem {
            if input != self.fontSize {
                self.fontSize = input
                self.updateView()
            }
        }
        searchQueue.asyncAfter(deadline: .now() + sampleDelay, execute: sizeTask!)
    }

    @IBAction func sortingAction(_ sender: NSPopUpButton) {
        os_log("Sorting action: %@", log: viewLog, type: .debug, sender.indexOfSelectedItem.description)

        let index = sender.indexOfSelectedItem
        searchQueue.async {
            self.sorting = FontSort.values[index]
            os_log("Sorting: %@", log: self.viewLog, type: .debug, self.sorting.description)
            self.performSearch()
        }
    }

    /// Performs a font search based on the specified string.
    /// Happens asynchronously after a short delay, and will cancel
    /// a previous search if it hadn't started yet.
    ///
    /// - Parameter text: text to search for, otherwise most recent search text is used
    private func performSearch(_ text: String? = nil) {
        searchTask?.cancel()
        let searchText = text ?? lastSearch
        updateStatusBar("Searching...")
        searchResults = fontManager.queryFonts(search: searchText, sort: sorting, categories: categoryFilter, weights: weightFilter, styles: styleFilter)
        updateStatusBar()
        updateView(page: 1)
    }

    /// Attempts to lookup a font by it's name.
    ///
    /// - Parameter name: font family name
    /// - Returns: the font family if found
    func getFont(name: String) -> FontFamily? {
        return self.fontManager.getFont(name: name)
    }

    /// Attempts to lookup a font and it's variant information by a lookup id.
    ///
    /// - Parameter fontId: a font id in the form "familyName|variantId"
    /// - Returns: a tuple containing the font family and font variant
    func getFont(id: String) -> (family: FontFamily, variantId: String)? {
        let fontSplit = id.components(separatedBy: "|")
        let fontName = fontSplit[0]
        let variantId = fontSplit[1]

        guard let font = getFont(name: fontName) else {
            os_log("Unable to find font family: %@", log: viewLog, type: .error, fontName)
            return nil
        }

        guard font.variants.keys.contains(variantId) else {
            os_log("Unable to find variant: %@", log: viewLog, type: .error, variantId)
            return nil
        }

        return (font, variantId)
    }

    /// Called when a user clicks the download button.
    ///
    /// - Parameter sender: <#sender description#>
    @IBAction func downloadFiles(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        let action = openPanel.runModal()

        if action.rawValue == NSFileHandlingPanelCancelButton {
            os_log("Download canceled!", log: viewLog, type: .debug)
            return;
        }

        guard let destFolder = openPanel.urls.first else {
            os_log("Nothing was selected!", log: viewLog, type: .info)
            return
        }

        os_log("Attempting to save to %@", log: viewLog, type:.info, destFolder.description)

        let selections = workQueue.sync { () -> [AnyFont] in
            let tmp = selectedFonts.sorted()
            selectedFonts = []
            return tmp
        }
        DispatchQueue.main.async { self.downloadButton.isEnabled = false }

        downloadQueue.async {
            selections.forEach { selection in
                let font = selection.font
                let variantId = selection.variantId

                guard let variant = font.variants[variantId] else {
                    os_log("Unable to find variant %@: %@", log: self.viewLog, type: .error, variantId, font.name)
                    return
                }

                let fontFile = destFolder.appendingPathComponent(variant.filename)
                os_log("Font filename %@", log: self.viewLog, type: .debug, fontFile.description)

                do {
                    self.updateStatusBar("Downloading \(variant.filename)...")
                    os_log("Downloading %@", log: self.viewLog, variant.filename)
                    let variantData = font.download(id: variant.id)!
                    self.updateStatusBar("Saving \(variant.filename)...")
                    os_log("Saving %@", log: self.viewLog, variant.filename)
                    try variantData.write(to: fontFile)
                } catch {
                    os_log("Failed to download and save font: %@", log: self.viewLog, type: .error, error.localizedDescription)
                }
            }

            self.updateStatusBar("Font Downloads Complete", cleanup: true)
        }
    }


    func getSelectedVariants(name: String) -> [String] {
        return workQueue.sync {
            selectedFonts
                .filter {$0.font.name == name}
                .map {$0.variantId}
        }
    }

    func getSelectedFontHtml(name: String) -> String? {
        let sample = customText.isEmpty ? sampleText : customText

        if let font = getFont(name: name) {
            let ids = getSelectedVariants(name: name)
            return font.html(sample: sample, size: fontSize, ids: ids, selected: ids)
        }
        return nil
    }

    private func paginationHtml(page: Int, count: Int) -> String {
        if count > maxShown {
            let totalPages = (count - 1) / maxShown + 1
            var pageLinks = [String]()
            for i in 1 ... totalPages {
                if i == page {
                    pageLinks.append("\(i)")
                } else if i == 1 || i == totalPages || i % 5 == 0 || abs(i - page) < 3 {
                    pageLinks.append("<a href='javascript:loadPage(\(i))'>\(i)</a>")
                } else {
                    if pageLinks.last != "-" {
                        pageLinks.append("-")
                    }
                }
            }
            return "[ " + pageLinks.joined(separator: " | ") + " ]"
        }

        return ""
    }

    /// Used to update the webview with the specified font HTML.
    ///
    /// - Parameter fonts: fonts to display
    private func updateView(fonts: [FontFamily]? = nil, page newPage: Int? = nil) {
        curPage = newPage ?? curPage
        let results = fonts ?? searchResults
        let page = curPage
        let count = results.count
        let offset = (page - 1) * maxShown
        let shown = Array(results.dropFirst(offset).prefix(maxShown))
        let sample = customText.isEmpty ? sampleText : customText

        let summary = count == 0
            ? "No results"
            : "\(count) results"

        let pagination = paginationHtml(page: page, count: count)

        let totalPages = (count - 1) / maxShown + 1
        let pages = "Page \(page) of \(totalPages)"

        // Search results html.
        var fontHtml = String()
        shown.forEach { font in
            let ids = font.variants.values
                .filter { self.weightFilter.contains($0.weight) }
                .filter { self.styleFilter.contains($0.style) }
                .sorted { $0.weight == $1.weight ? $0.style < $1.style : $0.weight < $1.weight }
                .map { $0.id }
            fontHtml.append(font.html(sample: sample, size: fontSize, ids: ids, selected: getSelectedVariants(name: font.name)))
        }

        // Fonts currently being shown.
        let shownIds = Set(shown.map({$0.name}))

        // Selected fonts html.
        let selectionsHtml = selectedFamilyIds
            .filter { !shownIds.contains($0) }
            .compactMap { getSelectedFontHtml(name: $0) }
            .joined()

        // Render output.
        let html = FontsViewHtml.render([
            "summary": summary,
            "index" : pagination,
            "pages" : pages,
            "fonts": fontHtml,
            "selectedFonts": selectionsHtml.isEmpty ? "" : "Previously Selected Fonts",
            "selections": selectionsHtml
            ])

        updateStatusBar("Loading...")
        DispatchQueue.main.async {
            self.webView.loadHTMLString(html, baseURL: FontsViewHtml.baseURL)
        }
    }


    /// Called when a user checks or unchecks a font in the web view.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        os_log("Got javascript message: %@", log: viewLog, type: .debug, message.name)

        switch message.name {
        case loadPage:
            guard let page = message.body as? Int else {
                os_log("Invalid page load request (not a number)!", log: viewLog, type: .error)
                break
            }

            searchQueue.async { self.updateView(page: page) }

        case selectFont, unselectFont:
            guard let fontId = message.body as? String else {
                os_log("Invalid un/selection (not a string)!", log: viewLog, type: .error)
                break
            }

            guard let (font, variantId) = getFont(id: fontId) else {
                os_log("Unable to lookup font: %@", log: viewLog, type: .error, fontId)
                break
            }

            let selection = AnyFont(font: font, variantId: variantId)
            if (message.name == selectFont) {
                os_log("Selecting: %@", log: viewLog, type: .debug, fontId)
                workQueue.sync {
                    selectedFonts.insert(selection)
                    DispatchQueue.main.async {
                        self.downloadButton.isEnabled = true
                    }
                }
            } else {
                os_log("Unselecting: %@", log: viewLog, type: .debug, fontId)
                workQueue.sync {
                    selectedFonts.remove(selection)
                    let enabled = !selectedFonts.isEmpty
                    DispatchQueue.main.async {
                        self.downloadButton.isEnabled = enabled
                    }
                }
            }
            break;

        default:
            os_log("Unexpected javascript event!", log: viewLog, type: .error)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateStatusBar()
    }

    /// Updates the status bar of the application.
    ///
    /// - Parameters:
    ///   - status: the new status text to display
    ///   - cleanup: true if the status should clean itself up after a short delay
    func updateStatusBar(_ status: String? = nil, cleanup: Bool = false) {
        os_log("Status update: %@", log: viewLog, type: .debug, status ?? "[cleared]")
        workQueue.async {
            self.statusTask?.cancel()

            if (cleanup) {
                self.statusTask = DispatchWorkItem {
                    DispatchQueue.main.async {
                        self.statusBar.stringValue = ""
                    }
                }
                self.workQueue.asyncAfter(deadline: .now() + self.statusDelay, execute: self.statusTask!)
            }

            let text = status ?? ""
            DispatchQueue.main.async {
                self.statusBar.stringValue = text
            }
        }
    }
}

