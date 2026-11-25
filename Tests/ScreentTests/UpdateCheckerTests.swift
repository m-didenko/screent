import XCTest
@testable import Screent

final class UpdateCheckerTests: XCTestCase {
    func testVersionCompare() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0.3", than: "1.0.0.2"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0.10", than: "1.0.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0.2", than: "1.0.0.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0.1", than: "1.0.0.2"))
    }

    func testParsesRelease() throws {
        let json = """
        {"tag_name":"v1.0.0.3","draft":false,"prerelease":false,
         "html_url":"https://github.com/m-didenko/screent/releases/tag/v1.0.0.3",
         "assets":[{"name":"Screent-1.0.0.3.zip.sha256","browser_download_url":"https://x/a.sha256"},
                   {"name":"Screent-1.0.0.3.zip","browser_download_url":"https://x/a.zip"}]}
        """
        let r = try XCTUnwrap(UpdateChecker.parse(Data(json.utf8)))
        XCTAssertEqual(r.version, "1.0.0.3")
        XCTAssertEqual(r.zipURL.absoluteString, "https://x/a.zip")
    }

    func testIgnoresPrereleaseAndMissingZip() {
        let pre = #"{"tag_name":"v2","prerelease":true,"html_url":"https://x","assets":[{"name":"a.zip","browser_download_url":"https://x/a.zip"}]}"#
        XCTAssertNil(UpdateChecker.parse(Data(pre.utf8)))
        let noZip = #"{"tag_name":"v2","html_url":"https://x","assets":[]}"#
        XCTAssertNil(UpdateChecker.parse(Data(noZip.utf8)))
    }
}
