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

    @State private var bridge = TerminalBridge()

    var body: some View {
        TerminalWebView(session: session, bridge: bridge)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(session.serverName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .secondaryAction) {
                    Button("Ctrl+C") { session.write(Data([0x03])) }
                    Button("Ctrl+D") { session.write(Data([0x04])) }
                    Button("Tab")    { session.write(Data([0x09])) }
                    Button("Esc")    { session.write(Data([0x1B])) }
                    Button("↑")      { session.write(Data([0x1B, 0x5B, 0x41])) }
                    Button("↓")      { session.write(Data([0x1B, 0x5B, 0x42])) }
                    Button("→")      { session.write(Data([0x1B, 0x5B, 0x43])) }
                    Button("←")      { session.write(Data([0x1B, 0x5B, 0x44])) }
                }
            }
            .task {
                for await chunk in session.outputStream {
                    bridge.send(chunk)
                }
            }
            .onDisappear {
                bridge.reset()
            }
    }
}

// MARK: - Terminal Bridge

@MainActor
private final class TerminalBridge {
    weak var webView: WKWebView?
    private var isReady = false
    private var pendingChunks: [String] = []

    func attach(webView: WKWebView) {
        self.webView = webView
        isReady = false
        pendingChunks.removeAll(keepingCapacity: true)
    }

    func markReady() {
        isReady = true
        flushPendingChunks()
    }

    func send(_ data: Data) {
        let base64 = data.base64EncodedString()
        guard isReady else {
            pendingChunks.append(base64)
            return
        }
        evaluateReceiveData(base64)
    }

    func reset() {
        webView = nil
        isReady = false
        pendingChunks.removeAll(keepingCapacity: false)
    }

    private func flushPendingChunks() {
        guard isReady else { return }
        for base64 in pendingChunks {
            evaluateReceiveData(base64)
        }
        pendingChunks.removeAll(keepingCapacity: true)
    }

    private func evaluateReceiveData(_ base64: String) {
        webView?.evaluateJavaScript("receiveData('\(base64)')", completionHandler: nil)
    }
}

// MARK: - UIViewRepresentable

private struct TerminalWebView: UIViewRepresentable {
    let session: SSHSession
    let bridge: TerminalBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, bridge: bridge)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: MessageName.input)
        userContentController.add(context.coordinator, name: MessageName.resize)
        userContentController.add(context.coordinator, name: MessageName.ready)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.102, green: 0.106, blue: 0.149, alpha: 1)
        webView.scrollView.isScrollEnabled = false

        if let htmlURL = Bundle.main.url(forResource: "terminal", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        bridge.attach(webView: webView)
        context.coordinator.webView = webView

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        let controller = uiView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: MessageName.input)
        controller.removeScriptMessageHandler(forName: MessageName.resize)
        controller.removeScriptMessageHandler(forName: MessageName.ready)
        coordinator.bridge.reset()
    }

    private enum MessageName {
        static let input = "terminalInput"
        static let resize = "terminalResize"
        static let ready = "terminalReady"
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let session: SSHSession
        let bridge: TerminalBridge
        weak var webView: WKWebView?

        init(session: SSHSession, bridge: TerminalBridge) {
            self.session = session
            self.bridge = bridge
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case MessageName.input:
                guard let text = message.body as? String,
                      let data = text.data(using: .utf8) else { return }
                session.write(data)

            case MessageName.resize:
                guard let dict = message.body as? [String: Int],
                      let cols = dict["cols"],
                      let rows = dict["rows"],
                      cols > 0,
                      rows > 0 else { return }
                session.resize(to: SSHTerminalSize(columns: cols, rows: rows))

            case MessageName.ready:
                bridge.markReady()

            default:
                break
            }
        }
    }
}
