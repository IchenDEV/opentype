import XCTest
@testable import OpenType

@MainActor
final class OverlayLayoutTests: XCTestCase {
    func testCompactRecordingOverlayUsesCapsuleRadius() {
        let appState = AppState()
        appState.phase = .recording
        appState.rawTranscription = ""

        let layout = OverlayLayout(appState: appState)

        XCTAssertEqual(layout.height, 64)
        XCTAssertEqual(layout.outerCornerRadius, layout.height / 2)
    }
}
