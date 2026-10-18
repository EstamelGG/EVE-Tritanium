import XCTest

@MainActor
final class FittingCatalogNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openCatalog() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["EVE_FITTING_NAVIGATION_UI_TEST"] = "1"
        app.launch()
        let group = app.buttons["fixture.group"]
        XCTAssertTrue(group.waitForExistence(timeout: 10))
        group.tap()
        XCTAssertTrue(app.buttons["fitting.catalog.edit"].waitForExistence(timeout: 5))
        return app
    }

    func testNormalRowTapOpensLocalFitting() {
        let app = openCatalog()
        app.buttons["fixture.row.Local A"].tap()
        XCTAssertTrue(app.staticTexts["fixture.detail"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["fixture.detail"].label, "local:AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
    }

    func testNormalRowTapOpensOnlineFitting() {
        let app = openCatalog()
        app.buttons["fixture.row.Online A"].tap()
        XCTAssertTrue(app.staticTexts["fixture.detail"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["fixture.detail"].label, "online:123")
    }

    func testEditingSelectsRowsAndDoneRestoresNavigation() {
        let app = openCatalog()
        let edit = app.buttons["fitting.catalog.edit"]
        edit.tap()
        app.staticTexts["Local A"].tap()
        let delete = app.buttons["fitting.catalog.delete"]
        XCTAssertTrue(delete.isEnabled)
        XCTAssertTrue(delete.label.contains("1"))
        XCTAssertFalse(app.staticTexts["fixture.detail"].exists)
        app.buttons["fitting.catalog.selectAll.1"].tap()
        XCTAssertTrue(delete.label.contains("2"))
        edit.tap()
        XCTAssertFalse(delete.exists)
        app.buttons["fixture.row.Local A"].tap()
        XCTAssertTrue(app.staticTexts["fixture.detail"].waitForExistence(timeout: 5))
    }
}
