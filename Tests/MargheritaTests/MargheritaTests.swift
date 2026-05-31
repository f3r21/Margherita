import XCTest
@testable import Margherita

@MainActor
final class MargheritaTests: XCTestCase {

    func testIndicatorFileDecoding() throws {
        let json = """
        {
          "updated_at": "2026-05-20T03:43:56Z",
          "primary_meter": "seven_day",
          "rate_limits": {
            "seven_day": {
              "used_percentage": 25.5,
              "resets_at_unix": 1782000000.0
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(IndicatorFile.self, from: data)
        XCTAssertEqual(decoded.primaryMeter, "seven_day")
        XCTAssertEqual(decoded.rateLimits["seven_day"]?.usedPercentage, 25.5)
        XCTAssertEqual(decoded.rateLimits["seven_day"]?.resetsAtUnix, 1782000000.0)
    }

    func testIsDataStale() {
        let model = IndicatorModel()
        model.dataSource = .statusLine
        
        let nowStr = ISO8601DateFormatter().string(from: Date())
        let fileNotStale = IndicatorFile(updatedAt: nowStr, primaryMeter: "seven_day", rateLimits: [:])
        model.applyStatusLineData(fileNotStale)
        XCTAssertFalse(model.isDataStale)

        let ancientDate = Date().addingTimeInterval(-13 * 3600) // 13 hours ago
        let ancientStr = ISO8601DateFormatter().string(from: ancientDate)
        let fileStale = IndicatorFile(updatedAt: ancientStr, primaryMeter: "seven_day", rateLimits: [:])
        model.applyStatusLineData(fileStale)
        XCTAssertTrue(model.isDataStale)
    }

    func testRecomputePercentage() {
        let model = IndicatorModel()
        model.dataSource = .statusLine
        model.primaryMeter = "seven_day"
        
        let meter = MeterData(usedPercentage: 35.0, resetsAtUnix: Date().timeIntervalSince1970 + 3600)
        let file = IndicatorFile(
            updatedAt: "2026-05-20T03:43:56Z",
            primaryMeter: "seven_day",
            rateLimits: ["seven_day": meter]
        )
        model.applyStatusLineData(file)
        
        XCTAssertEqual(model.percent, 65.0)
        XCTAssertEqual(model.resetProgress, 0.0)
    }

    func testResetProgressCalculation() {
        let model = IndicatorModel()
        model.dataSource = .statusLine
        model.primaryMeter = "seven_day"
        
        // Simular que el modelo ya estaba en 0 (para que no establezca hitZeroAt = ahora y así use la ventana del meter)
        model.percent = 0.0
        
        // resetsAtUnix en 1 hora más, y asumimos ventana de 7 días.
        let targetResetTime = Date().timeIntervalSince1970 + 3600
        let meter = MeterData(usedPercentage: 100.0, resetsAtUnix: targetResetTime)
        let file = IndicatorFile(
            updatedAt: "2026-05-20T03:43:56Z",
            primaryMeter: "seven_day",
            rateLimits: ["seven_day": meter]
        )
        model.applyStatusLineData(file)
        
        XCTAssertEqual(model.percent, 0.0)
        XCTAssertTrue(model.resetProgress > 90.0, "El reset progress debería ser alto (~99%) ya que falta solo 1 hora de una ventana de 7 días")
        XCTAssertTrue(model.resetProgress <= 100.0)
    }

    func testHumanDurationBuckets() {
        let now = Date()
        XCTAssertEqual(
            IndicatorModel.humanDuration(until: now.addingTimeInterval(-10), now: now),
            Localizer.shared.tr("soon")
        )
        XCTAssertTrue(IndicatorModel.humanDuration(until: now.addingTimeInterval(30 * 60), now: now).contains("30"))
        XCTAssertTrue(IndicatorModel.humanDuration(until: now.addingTimeInterval(3 * 3600), now: now).contains("3"))
        XCTAssertTrue(IndicatorModel.humanDuration(until: now.addingTimeInterval(2 * 24 * 3600), now: now).contains("2"))
    }

    func testEffectiveMeterKeyFallsBackWhenPrimaryAbsent() {
        let model = IndicatorModel()
        model.dataSource = .statusLine
        model.primaryMeter = "seven_day"

        // Payload de un plan SIN seven_day: el icono debe seguir actualizándose.
        let meter = MeterData(usedPercentage: 20.0, resetsAtUnix: Date().timeIntervalSince1970 + 3600)
        model.applyStatusLineData(IndicatorFile(
            updatedAt: "2026-05-20T03:43:56Z", primaryMeter: "five_hour",
            rateLimits: ["five_hour": meter]
        ))

        XCTAssertEqual(model.effectiveMeterKey, "five_hour")
        XCTAssertEqual(model.percent, 80.0)
    }

    func testMenuBarTextHonorsToggle() {
        let model = IndicatorModel()
        model.dataSource = .statusLine
        model.primaryMeter = "seven_day"
        let meter = MeterData(usedPercentage: 35.0, resetsAtUnix: Date().timeIntervalSince1970 + 3600)
        model.applyStatusLineData(IndicatorFile(
            updatedAt: "2026-05-20T03:43:56Z", primaryMeter: "seven_day",
            rateLimits: ["seven_day": meter]
        ))

        model.showPercentInMenuBar = false
        XCTAssertNil(model.menuBarText)

        model.showPercentInMenuBar = true
        XCTAssertEqual(model.menuBarText, "65%")
    }

    func testMeterLabelHumanizesUnknownKey() {
        XCTAssertEqual(Localizer.shared.meterLabel("monthly_opus"), "Monthly Opus")
    }
}
