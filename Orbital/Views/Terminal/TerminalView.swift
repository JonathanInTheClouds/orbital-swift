//
//  TerminalView.swift
//  Orbital
//
//  Created by Jonathan on 4/13/26.
//

import SwiftUI
import WebKit

// MARK: - TerminalView

struct TerminalView: View {
    let session: SSHSession

    @State private var webView: WKWebView?
    @Environment(SSHService.self) private var sshService

    var body: some View {
        TerminalWebView(session: session, webView: $webView)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(session.serverName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button("Ctrl+C") {
                        session.write(Data([0x03]))
                    }
                    Button("Ctrl+D") {
                        session.write(Data([0x04]))
                    }
                    Button("Tab") {
                        session.write(Data([0x09]))
                    }
                    Button("Esc") {
                        session.write(Data([0x1B]))
                    }
                }
            }
            .task {
                // Forward incoming SSH data to xterm.js
                for await chunk in session.outputStream {
                    await sendToTerminal(chunk)
                }
            }
    }

    @MainActor
    private func sendToTerminal(_ data: Data) async {
        let base64 = data.base64EncodedString()
        let escaped = base64.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("receiveData('\(escaped)')", completionHandler: nil)
    }
}

// MARK: - UIViewRepresentable

struct TerminalWebView: UIViewRepresentable {
    let session: SSHSession
    @Binding var webView: WKWebView?

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "terminalInput")
        userContentController.add(context.coordinator, name: "terminalResize")

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        // Allow loading local files
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let wk = WKWebView(frame: .zero, configuration: config)
        wk.isOpaque = false
        wk.backgroundColor = UIColor(red: 0.102, green: 0.106, blue: 0.149, alpha: 1) // #1a1b26
        wk.scrollView.isScrollEnabled = false

        // Load terminal.html from the app bundle Resources folder
        if let htmlURL = Bundle.main.url(forResource: "terminal", withExtension: "html") {
            wk.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        context.coordinator.webView = wk

        // Surface the WKWebView to the parent view for JS evaluation
        DispatchQueue.main.async {
            self.webView = wk
        }

        return wk
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let session: SSHSession
        weak var webView: WKWebView?

        init(session: SSHSession) {
            self.session = session
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "terminalInput":
                guard let text = message.body as? String,
                      let data = text.data(using: .utf8) else { return }
                session.write(data)

            case "terminalResize":
                guard let dict = message.body as? [String: Int],
                      let cols = dict["cols"],
                      let rows = dict["rows"],
                      cols > 0,
                      rows > 0 else { return }
                session.resize(to: SSHTerminalSize(columns: cols, rows: rows))

            default:
                break
            }
        }
    }
}
