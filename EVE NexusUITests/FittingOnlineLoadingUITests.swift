import XCTest

@MainActor
final class FittingOnlineLoadingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["EVE_FITTING_LOADING_UI_TEST"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["fixture.openFittings"].waitForExistence(timeout: 20))
        return app
    }

    func testOnlineListSurvivesRepeatedReturnToHome() {
        let app = launch()
        for _ in 0 ..< 4 {
            app.buttons["fixture.openFittings"].tap()
            let online = app.segmentedControls.firstMatch.buttons.element(boundBy: 1)
            XCTAssertTrue(online.waitForExistence(timeout: 5), app.debugDescription)
            online.tap()
            let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fitting.group.'")).firstMatch
            XCTAssertTrue(group.waitForExistence(timeout: 5), app.debugDescription)
            app.navigationBars.buttons["Fixture home"].tap()
            XCTAssertTrue(app.buttons["fixture.openFittings"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["fixture.loading.status"].label.contains("network=1"))
    }

    func testOnlineDataIsPreparedWhileLocalPageIsVisible() {
        let app = launch()
        app.buttons["fixture.openFittings"].tap()
        let status = app.staticTexts["fixture.loading.status"]
        let cached = NSPredicate(format: "label CONTAINS 'cached=true'")
        expectation(for: cached, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons.element(boundBy: 0).isSelected)
        let readyStatus = status.label
        for _ in 0 ..< 3 {
            app.segmentedControls.firstMatch.buttons.element(boundBy: 1).tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fitting.group.'")).firstMatch.waitForExistence(timeout: 2))
            app.segmentedControls.firstMatch.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.segmentedControls.firstMatch.buttons.element(boundBy: 0).isSelected)
        }
        XCTAssertEqual(status.label, readyStatus, "来源切换应复用已准备的目录，不重新进入加载流程")
    }
}
