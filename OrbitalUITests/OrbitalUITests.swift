//
//  OrbitalUITests.swift
//  OrbitalUITests
//
//  Created by Jonathan on 4/13/26.
//

import XCTest

final class OrbitalUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

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

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        return app
    }
}
