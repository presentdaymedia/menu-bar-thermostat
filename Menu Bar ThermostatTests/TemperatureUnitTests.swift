import XCTest

final class TemperatureUnitTests: XCTestCase {
    func testTemperatureUnitConvertsAndFormatsDisplayValues() {
        XCTAssertEqual(TemperatureUnit.celsius.value(fromCelsius: 21), 21, accuracy: 0.001)
        XCTAssertEqual(TemperatureUnit.fahrenheit.value(fromCelsius: 21), 69.8, accuracy: 0.001)
        XCTAssertEqual(TemperatureUnit.celsius.celsius(from: 21), 21, accuracy: 0.001)
        XCTAssertEqual(TemperatureUnit.fahrenheit.celsius(from: 69.8), 21, accuracy: 0.001)
        XCTAssertEqual(TemperatureUnit.fahrenheit.formatted(69.8), "69.8°F")
    }
}
