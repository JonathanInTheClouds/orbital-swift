//
//  LocalNetworkAuthorizationRequester.swift
//  Orbital
//
//  Created by Jonathan on 4/18/26.
//

import Foundation
import Network

@MainActor
final class LocalNetworkAuthorizationRequester: NSObject {
    static let shared = LocalNetworkAuthorizationRequester()

    private static let bonjourServiceType = "_orbital-permission-check._tcp"
    private static let bonjourServiceName = "Orbital"

    private var browser: NWBrowser?
    private var netService: NetService?
    private var hasActiveRequest = false

    private override init() {
        super.init()
    }

    func requestIfNeeded() {
        guard !hasActiveRequest else { return }

        hasActiveRequest = true

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjour(type: Self.bonjourServiceType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .failed, .cancelled:
                Task { @MainActor [weak self] in
                    self?.stop()
                }
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }

        let netService = NetService(
            domain: "local.",
            type: Self.bonjourServiceType,
            name: Self.bonjourServiceName,
            port: 9
        )

        self.browser = browser
        self.netService = netService

        browser.start(queue: .main)
        netService.publish()
    }

    private func stop() {
        browser?.cancel()
        browser = nil

        netService?.stop()
        netService = nil

        hasActiveRequest = false
    }
}
