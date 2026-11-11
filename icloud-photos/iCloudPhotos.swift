// iCloud Photos companion for vivo Office Kit.
//
// Apple does not expose the iCloud Photo Library to third-party apps. This small native
// window uses Apple's own WebKit engine to open iCloud.com/Photos, so a normal Apple ID
// (including US and other non-China regions) can sign in. Downloads are saved to
// ~/Pictures/iCloud Photos and can then be dragged into vivo Office Kit's Albums module
// or copied to the phone with File Manager.

import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var statusLabel: NSTextField!
    var destinations: [ObjectIdentifier: URL] = [:]

    let downloadDirectory: URL = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("iCloud Photos", isDirectory: true)
    }()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        buildMenu()
        buildWindow()
        load()
        NSApp.activate(ignoringOtherApps: true)

        if CommandLine.arguments.contains("--selftest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                self.webView.evaluateJavaScript("document.title + '\\n---\\n' + (document.body ? document.body.innerText.slice(0,800) : 'no body')") { result, error in
                    print("SELFTEST:", result ?? "nil")
                    if let error = error { print("SELFTEST-ERROR:", error) }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - UI

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About iCloud Photos", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Open Downloads Folder", action: #selector(openDownloadsFolder), keyEquivalent: "o").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide iCloud Photos", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit iCloud Photos", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let photosItem = NSMenuItem()
        mainMenu.addItem(photosItem)
        let photosMenu = NSMenu(title: "Photos")
        photosMenu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "r").target = self
        photosMenu.addItem(withTitle: "iCloud Photos", action: #selector(openICloud), keyEquivalent: "1").target = self
        photosMenu.addItem(.separator())
        photosMenu.addItem(withTitle: "Sign Out of iCloud", action: #selector(signOut), keyEquivalent: "").target = self
        photosItem.submenu = photosMenu

        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)
        webView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let hint = NSTextField(labelWithString: "Sign in to iCloud, select photos, then click Download. Files are saved to Pictures/iCloud Photos.")
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let folderButton = NSButton(title: "Open Downloads Folder", target: self, action: #selector(openDownloadsFolder))
        folderButton.bezelStyle = .rounded
        let reloadButton = NSButton(title: "Reload", target: self, action: #selector(reload))
        reloadButton.bezelStyle = .rounded

        let topBar = NSStackView(views: [hint, folderButton, reloadButton])
        topBar.orientation = .horizontal
        topBar.spacing = 8
        topBar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        topBar.setContentHuggingPriority(.defaultHigh, for: .vertical)

        statusLabel = NSTextField(labelWithString: "Downloads save to \(downloadDirectory.path)")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let stack = NSStackView(views: [topBar, webView, statusLabel])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 850),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "iCloud Photos"
        window.minSize = NSSize(width: 820, height: 620)
        window.contentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Navigation

    @objc private func load() {
        webView.load(URLRequest(url: URL(string: "https://www.icloud.com/photos/")!))
    }

    @objc private func openICloud() { load() }

    @objc private func reload() {
        if webView.url == nil { load() } else { webView.reload() }
    }

    @objc private func openDownloadsFolder() {
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(downloadDirectory)
    }

    @objc private func signOut() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            DispatchQueue.main.async {
                self.statusLabel.stringValue = "Signed out. Downloads folder: \(self.downloadDirectory.path)"
                self.load()
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        statusLabel.stringValue = "Could not load iCloud Photos: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusLabel.stringValue = "Downloads save to \(downloadDirectory.path)"
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // iCloud sometimes opens dialogs and links in a new window; keep them in this window.
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    // MARK: - WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        var url = downloadDirectory.appendingPathComponent(suggestedFilename)
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            url = downloadDirectory.appendingPathComponent(name)
            counter += 1
        }
        destinations[ObjectIdentifier(download)] = url
        statusLabel.stringValue = "Downloading \(suggestedFilename)…"
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let url = destinations[ObjectIdentifier(download)]
        if let url = url, url.pathExtension.lowercased() == "zip" {
            // iCloud sends multiple selected photos as a zip. Unpack it next to the zip.
            let folder = url.deletingPathExtension()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", url.path, folder.path]
            try? process.run()
            process.waitUntilExit()
            statusLabel.stringValue = "Saved and unpacked to \(folder.path)"
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            statusLabel.stringValue = "Saved to \(url?.path ?? downloadDirectory.path)"
            if let url = url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        NSSound(named: "Glass")?.play()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        statusLabel.stringValue = "Download failed: \(error.localizedDescription)"
        let alert = NSAlert()
        alert.messageText = "Download failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
