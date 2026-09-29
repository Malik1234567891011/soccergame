import XCTest
@testable import Panna

final class AppTests: XCTestCase {
    func testAppearanceRoundTrip() {
        let a = Appearance.random(seed: 5)
        XCTAssertEqual(Appearance.decode(a.encoded()), a)
    }
}
