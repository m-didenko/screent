import XCTest
@testable import Screent

final class SentenceGateTests: XCTestCase {
    func testWaitsWhileSentenceIsUnfinished() {
        XCTAssertEqual(SentenceGate.decide(text: "So the plan for the next sprint is to", stableTicks: 0), .wait)
        XCTAssertEqual(SentenceGate.decide(text: "So the plan for the next sprint is to", stableTicks: 1), .wait)
    }

    func testSendsFinishedStableSentence() {
        let s = "So the plan for the next sprint is to migrate the database."
        XCTAssertEqual(SentenceGate.decide(text: s, stableTicks: 0), .wait) // may still be edited
        XCTAssertEqual(SentenceGate.decide(text: s, stableTicks: 1), .all)
    }

    func testShortSentenceWaitsOneMoreTick() {
        XCTAssertEqual(SentenceGate.decide(text: "Okay, sounds good.", stableTicks: 1), .wait)
        XCTAssertEqual(SentenceGate.decide(text: "Okay, sounds good.", stableTicks: 2), .all)
    }

    func testPauseSendsUnfinishedThought() {
        XCTAssertEqual(SentenceGate.decide(text: "and then we could maybe", stableTicks: 3), .all)
    }

    func testFlushesFinishedSentencesWhileSpeakerContinues() {
        let done = "We tested the release on staging yesterday and everything looked fine. The only issue was the login page timing out."
        let text = done + " So what I would suggest is"
        let words = TextDiffer.tokenize(done).count
        XCTAssertEqual(SentenceGate.decide(text: text, stableTicks: 0), .upTo(words: words))
    }

    func testShortFinishedPartIsNotFlushed() {
        XCTAssertEqual(SentenceGate.decide(text: "Yes, I agree. But what about the", stableTicks: 0), .wait)
    }

    func testLongUnpunctuatedMonologueIsSent() {
        let text = Array(repeating: "word", count: 80).joined(separator: " ")
        XCTAssertEqual(SentenceGate.decide(text: text, stableTicks: 0), .all)
    }

    func testQuotedSentenceEnd() {
        XCTAssertTrue(SentenceGate.endsSentence("done.\""))
        XCTAssertTrue(SentenceGate.endsSentence("why?)"))
        XCTAssertFalse(SentenceGate.endsSentence("3.5x"))
    }

    func testPartialSendKeepsDiffWorking() {
        let current = "Anna\nWe shipped it yesterday. Now the next step is the"
        let diff = TextDiffer.diff(previous: "", current: current)
        let part = TextDiffer.prefix(diff, words: 5)
        XCTAssertEqual(part.text, "Anna\nWe shipped it yesterday.")
        let sent = TextDiffer.dropLast(diff.wordCount - 5, of: current)
        XCTAssertEqual(sent, "Anna\nWe shipped it yesterday.")
        // The next frame: only the held-back tail plus the new words, as a fresh sentence.
        let next = TextDiffer.diff(previous: sent, current: current + " database migration.")
        XCTAssertEqual(next.text, "Now the next step is the database migration.")
        XCTAssertFalse(next.continues)
    }
}
