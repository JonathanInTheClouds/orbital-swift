//
//  OrbitalUITests.swift
//  OrbitalUITests
//
//  Created by Jonathan on 4/13/26.
//

import XCTest

struct LabServerSpec {
    let name: String
    let port: String
}

class OrbitalUITestCase: XCTestCase {
    let labServers: [LabServerSpec] = [
        .init(name: "Lab Ubuntu", port: "2222"),
        .init(name: "Lab Debian", port: "2223"),
        .init(name: "Lab Fedora", port: "2224"),
        .init(name: "Lab Alpine", port: "2225")
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        return app
    }

    func openServerDetail(named serverName: String, in app: XCUIApplication) {
        let serverRow = serverRow(named: serverName, in: app)
        XCTAssertTrue(serverRow.waitForExistence(timeout: 10), "server row missing: \(serverName)")
        serverRow.tap()
        XCTAssertTrue(app.navigationBars[serverName].waitForExistence(timeout: 5), "detail view missing: \(serverName)")
    }

    func ensureLabServerExists(named serverName: String, in app: XCUIApplication) {
        guard let server = labServers.first(where: { $0.name == serverName }) else {
            XCTFail("missing lab server spec: \(serverName)")
            return
        }

        if serverRow(named: server.name, in: app).waitForExistence(timeout: 2) {
            return
        }

        presentAddServer(in: app)
        createServer(server, in: app)
        XCTAssertTrue(
            serverRow(named: server.name, in: app).waitForExistence(timeout: 10),
            "created server row missing: \(server.name)"
        )
    }

    func verifyLabServerCanPoll(named serverName: String, in app: XCUIApplication) {
        ensureLabServerExists(named: serverName, in: app)
        openServerDetail(named: serverName, in: app)

        let pollNowButton = app.buttons["server.detail.pollNow"]
        XCTAssertTrue(pollNowButton.waitForExistence(timeout: 5), "poll button missing for \(serverName)")
        pollNowButton.tap()

        let diskGauge = app.otherElements["metrics.gauge.disk"]
        assertNoConnectionError(in: app, serverName: serverName)
        revealMetricsGauge(diskGauge, in: app)
        XCTAssertTrue(diskGauge.waitForExistence(timeout: 20), "disk gauge missing for \(serverName)")

        let diskValue = diskGauge.value as? String ?? ""
        XCTAssertNotEqual(diskValue, "0%", "disk gauge remained zero for \(serverName)")
    }

    func presentAddServer(in app: XCUIApplication) {
        let emptyStateAddButton = app.buttons["servers.empty.addButton"]
        if emptyStateAddButton.waitForExistence(timeout: 2) {
            emptyStateAddButton.tap()
        } else {
            let toolbarAddButton = app.buttons["servers.addToolbarButton"]
            XCTAssertTrue(toolbarAddButton.waitForExistence(timeout: 5), "add server button missing")
            toolbarAddButton.tap()
        }

        XCTAssertTrue(app.navigationBars["Add Server"].waitForExistence(timeout: 5), "add server sheet missing")
    }

    func createServer(_ server: LabServerSpec, in app: XCUIApplication) {
        let nameField = app.textFields["serverEditor.identity.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "name field missing")
        replaceText(in: nameField, with: server.name)
        tapPrimaryEditorAction(in: app)

        let hostField = app.textFields["serverEditor.connection.host"]
        let portField = app.textFields["serverEditor.connection.port"]
        let usernameField = app.textFields["serverEditor.connection.username"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5), "host field missing")
        XCTAssertTrue(portField.waitForExistence(timeout: 5), "port field missing")
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5), "username field missing")
        replaceText(in: hostField, with: "127.0.0.1")
        replaceText(in: portField, with: server.port)
        replaceText(in: usernameField, with: "orbital")
        tapPrimaryEditorAction(in: app)

        let passwordMethodButton = app.buttons["serverEditor.authentication.method.password"]
        XCTAssertTrue(passwordMethodButton.waitForExistence(timeout: 5), "password auth option missing")
        passwordMethodButton.tap()

        let passwordField = app.secureTextFields["serverEditor.authentication.password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "password field missing")
        replaceText(in: passwordField, with: "orbital")
        tapPrimaryEditorAction(in: app)

        let createButton = app.buttons["serverEditor.action.primary"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5), "create button missing")
        createButton.tap()

        assertNoSaveFailure(in: app)
        waitForElementToDisappear(
            app.navigationBars["Add Server"],
            timeout: 10,
            failureMessage: "add server sheet did not dismiss for \(server.name)"
        )
    }

    func tapPrimaryEditorAction(in app: XCUIApplication) {
        let primaryButton = app.buttons["serverEditor.action.primary"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 5), "primary editor action missing")
        primaryButton.tap()
    }

    func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.exists, "input missing for replacement")
        element.tap()

        if let currentValue = element.value as? String,
           shouldClearCurrentValue(currentValue) {
            let deleteSequence = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            element.typeText(deleteSequence)
        }

        element.typeText(text)
    }

    func shouldClearCurrentValue(_ currentValue: String) -> Bool {
        guard !currentValue.isEmpty else { return false }

        let placeholderValues = [
            "Production API",
            "192.168.1.100",
            "root",
            "Optional if already in Keychain"
        ]

        if placeholderValues.contains(currentValue) {
            return false
        }

        return true
    }

    func serverRow(named serverName: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: serverRowIdentifier(for: serverName))
            .firstMatch
    }

    func assertNoSaveFailure(in app: XCUIApplication) {
        let saveFailedAlert = app.alerts["Save Failed"]
        guard saveFailedAlert.waitForExistence(timeout: 2) else { return }

        let message = saveFailedAlert.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty && $0 != "Save Failed" }
            .joined(separator: " ")
        XCTFail("save failed: \(message)")
    }

    func assertNoConnectionError(in app: XCUIApplication, serverName: String) {
        let connectionErrorAlert = app.alerts["Connection Error"]
        guard connectionErrorAlert.waitForExistence(timeout: 2) else { return }

        let message = connectionErrorAlert.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty && $0 != "Connection Error" }
            .joined(separator: " ")
        XCTFail("connection error for \(serverName): \(message)")
    }

    func revealMetricsGauge(_ diskGauge: XCUIElement, in app: XCUIApplication) {
        guard !diskGauge.exists else { return }

        let scrollView = app.scrollViews.firstMatch
        guard scrollView.waitForExistence(timeout: 5) else { return }

        for _ in 0..<4 {
            if diskGauge.exists {
                return
            }
            scrollView.swipeDown()
        }
    }

    func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval, failureMessage: String) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, failureMessage)
    }

    func serverRowIdentifier(for serverName: String) -> String {
        let sanitizedName = serverName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return "servers.row.\(sanitizedName)"
    }
}

final class OrbitalUITests: OrbitalUITestCase {
    @MainActor
    func testLaunchShowsServersEmptyState() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["No Servers Yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add Your First Server"].exists)
    }

    @MainActor
    func testRootTabsAreReachable() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let serversTab = tabBar.buttons["Servers"]
        let terminalsTab = tabBar.buttons["Terminals"]
        let containersTab = tabBar.buttons["Containers"]
        let settingsTab = tabBar.buttons["Settings"]

        XCTAssertTrue(serversTab.exists)
        XCTAssertTrue(terminalsTab.exists)
        XCTAssertTrue(containersTab.exists)
        XCTAssertTrue(settingsTab.exists)

        terminalsTab.tap()
        XCTAssertTrue(app.staticTexts["No Active Sessions"].waitForExistence(timeout: 5))

        containersTab.tap()
        XCTAssertTrue(app.staticTexts["No Containers"].waitForExistence(timeout: 5))

        settingsTab.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        serversTab.tap()
        XCTAssertTrue(app.staticTexts["No Servers Yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddServerFlowPresentsSheetFromEmptyState() throws {
        let app = makeApp()
        app.launch()

        let addButton = app.buttons["Add Your First Server"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))

        addButton.tap()

        XCTAssertTrue(app.navigationBars["Add Server"].waitForExistence(timeout: 5))
    }
}

final class OrbitalLabUITests: OrbitalUITestCase {
    @MainActor
    func testLabUbuntuCanPollMetrics() throws {
        let app = makeApp()
        app.launch()

        verifyLabServerCanPoll(named: "Lab Ubuntu", in: app)
    }

    @MainActor
    func testLabDebianCanPollMetrics() throws {
        let app = makeApp()
        app.launch()

        verifyLabServerCanPoll(named: "Lab Debian", in: app)
    }

    @MainActor
    func testLabFedoraCanPollMetrics() throws {
        let app = makeApp()
        app.launch()

        verifyLabServerCanPoll(named: "Lab Fedora", in: app)
    }

    @MainActor
    func testLabAlpineCanPollMetrics() throws {
        let app = makeApp()
        app.launch()

        verifyLabServerCanPoll(named: "Lab Alpine", in: app)
    }
}
