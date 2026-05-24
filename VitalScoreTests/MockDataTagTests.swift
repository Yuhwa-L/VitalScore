import XCTest
@testable import VitalScore

final class MockDataTagTests: XCTestCase {
    func test_tagFixturesDailyAndVoiceRowsIncludeTags() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixtureNames = ["morning_7_day", "gym_7_day", "alcohol_7_day"]

        for fixtureName in fixtureNames {
            let url = try XCTUnwrap(Bundle.main.url(
                forResource: fixtureName,
                withExtension: "json",
                subdirectory: "TagData"
            ))
            let data = try Data(contentsOf: url)
            let fixture = try decoder.decode(WellnessDemoDataFixture.self, from: data)

            XCTAssertEqual(fixture.dailyRecords.count, 7)
            XCTAssertEqual(fixture.eyeFocusResults.count, 7)
            XCTAssertEqual(fixture.voiceSessions.count, 7)
            XCTAssertTrue(fixture.dailyRecords.allSatisfy { $0.experimentTag == fixture.tag })
            XCTAssertTrue(fixture.voiceSessions.allSatisfy { $0.experimentTag == fixture.tag })
        }
    }

    func test_tagGazeLogFixturesDecodeAndIncludeTags() throws {
        let urls = try XCTUnwrap(Bundle.main.urls(
            forResourcesWithExtension: "json",
            subdirectory: "TagData/GazeLogs"
        ))
        XCTAssertEqual(urls.count, 21)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var countsByTag: [String: Int] = [:]

        for url in urls {
            let log = try decoder.decode(GazeLogFile.self, from: Data(contentsOf: url))
            let tag = ExperimentTagValue.normalized(log.experimentTag)
            countsByTag[tag, default: 0] += 1
            XCTAssertNotNil(log.metrics)
            XCTAssertNotNil(log.reaction)
            XCTAssertFalse(log.samples.isEmpty)
        }

        XCTAssertEqual(countsByTag["Morning"], 7)
        XCTAssertEqual(countsByTag["Gym"], 7)
        XCTAssertEqual(countsByTag["Alcohol"], 7)
    }

    func test_tagFixturesUseNonDirectionalRandomizedSeries() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixtureNames = ["morning_7_day", "gym_7_day", "alcohol_7_day"]

        for fixtureName in fixtureNames {
            let url = try XCTUnwrap(Bundle.main.url(
                forResource: fixtureName,
                withExtension: "json",
                subdirectory: "TagData"
            ))
            let fixture = try decoder.decode(
                WellnessDemoDataFixture.self,
                from: Data(contentsOf: url)
            )
            assertMixedDirection(fixture.dailyRecords.map(\.sleepHours), fixtureName: fixtureName)
            assertMixedDirection(fixture.dailyRecords.map(\.stepCount), fixtureName: fixtureName)
            assertMixedDirection(fixture.dailyRecords.map { Optional(Double($0.wellnessDeltaScore)) }, fixtureName: fixtureName)
            assertMixedDirection(fixture.dailyRecords.map(\.gazeScore), fixtureName: fixtureName)
            assertMixedDirection(fixture.dailyRecords.map(\.gazeAccuracyPx), fixtureName: fixtureName)
            assertMixedDirection(fixture.dailyRecords.map(\.gazeStabilityPx), fixtureName: fixtureName)
            assertMixedDirection(fixture.dailyRecords.map(\.voiceScore), fixtureName: fixtureName)
        }
    }

    func test_gazeLogFileEncodesExperimentTag() throws {
        let log = GazeLogFile(
            experimentTag: "Morning",
            backend: "test",
            startedAt: Date(),
            testStartedAt: Date(),
            durationSeconds: 1,
            frameCount: 0,
            screenWidthPx: 390,
            screenHeightPx: 844,
            calibration: nil,
            metrics: nil,
            reaction: nil,
            samples: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(log)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GazeLogFile.self, from: data)

        XCTAssertEqual(decoded.experimentTag, "Morning")
    }

    private func assertMixedDirection(
        _ values: [Double?],
        fixtureName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let compact = values.compactMap { $0 }
        let pairs = Array(zip(compact, compact.dropFirst()))
        let upCount = pairs.filter { $0.1 > $0.0 }.count
        let downCount = pairs.filter { $0.1 < $0.0 }.count
        XCTAssertGreaterThanOrEqual(upCount, 2, "\(fixtureName) should include multiple upward changes.", file: file, line: line)
        XCTAssertGreaterThanOrEqual(downCount, 2, "\(fixtureName) should include multiple downward changes.", file: file, line: line)
    }
}
