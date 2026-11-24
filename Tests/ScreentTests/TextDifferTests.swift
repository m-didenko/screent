import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import Screent

@Suite struct TextDifferTests {
    @Test func firstCaptureIsAllNew() {
        let d = TextDiffer.diff(previous: "", current: "Alex Morgan\nLet's start with the release plan")
        #expect(d.text == "Alex Morgan\nLet's start with the release plan")
        #expect(!d.continues)
    }

    @Test func growingLineReturnsOnlyContinuation() {
        let prev = "Alex Morgan\nSo before the demo, um... reviewing the new API docs made"
        let cur = "Alex Morgan\nSo before the demo, um... reviewing the new API docs made\nme think we need another QA pass."
        let d = TextDiffer.diff(previous: prev, current: cur)
        #expect(d.text == "me think we need another QA pass.")
        #expect(d.continues)
    }

    @Test func scrolledCaptions() {
        let prev = "any questions so far?\nAlex Morgan\nSo before the demo we should double check"
        let cur = "So before the demo we should double check\nthe staging config."
        let d = TextDiffer.diff(previous: prev, current: cur)
        #expect(d.text == "the staging config.")
        #expect(d.continues)
    }

    @Test func toleratesOcrNoise() {
        let prev = "we still need to update the changelog for the mobile release."
        let cur = "we still need to upd4te the changelog for the mobile release. Next point"
        let d = TextDiffer.diff(previous: prev, current: cur)
        #expect(d.text == "Next point")
        #expect(!d.continues)
    }

    @Test func unchangedIsEmpty() {
        let t = "Alex Morgan\nSome caption text here."
        #expect(TextDiffer.diff(previous: t, current: t).isEmpty)
        #expect(TextDiffer.diff(previous: "a b c d e f", current: "c d e").isEmpty)
    }

    @Test func unrelatedTextIsAllNew() {
        let d = TextDiffer.diff(previous: "completely different words here", current: "Brand new speaker says hello")
        #expect(d.wordCount == 5)
    }

    /// Optional: SCREENT_SAMPLE=/path/to/screenshot.png swift test
    @Test func ocrOnSampleScreenshot() async throws {
        let path = ProcessInfo.processInfo.environment["SCREENT_SAMPLE"] ?? ""
        guard !path.isEmpty, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
        let lines = try await OCR.recognize(img)
        print("OCR >>>\n" + lines.joined(separator: "\n"))
        #expect(!lines.isEmpty)
    }
}
