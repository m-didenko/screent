import Testing
@testable import Screent

@Suite struct MentionDetectorTests {
    let names = MentionDetector.parse("Nick, Nikita, Нік")

    @Test func findsExactAndPossessive() {
        #expect(MentionDetector.findMention(in: "Alex Morgan\nNick, can you take this one?", names: names)
                == "Nick, can you take this one?")
        #expect(MentionDetector.findMention(in: "that was Nick's change", names: names) != nil)
    }

    @Test func toleratesMisrecognition() {
        #expect(MentionDetector.findMention(in: "maybe Nikitah knows", names: names) != nil)
        #expect(MentionDetector.findMention(in: "Нік, що скажеш?", names: names) != nil)
    }

    @Test func ignoresUnrelatedWords() {
        #expect(MentionDetector.findMention(in: "we need a quick nickname for the nickel build", names: names) == nil)
        #expect(MentionDetector.findMention(in: "nothing here", names: names) == nil)
        #expect(MentionDetector.findMention(in: "Nick is here", names: []) == nil)
    }

    @Test func phoneticSpellings() {
        let me = MentionDetector.parse("Mykyta")
        #expect(MentionDetector.findMention(in: "so maybe let's ask Mikita", names: me) != nil)
        #expect(MentionDetector.findMention(in: "Микита, що думаєш?", names: me) != nil)
        #expect(MentionDetector.findMention(in: "Mykita can you check", names: me) != nil)
        #expect(MentionDetector.findMention(in: "my kit is ready", names: me) == nil)
        let nick = MentionDetector.parse("Нік")
        #expect(MentionDetector.findMention(in: "Nick, thoughts?", names: nick) != nil)
    }

    @Test func multiWordNames() {
        let full = MentionDetector.parse("Mary Ann")
        #expect(MentionDetector.findMention(in: "thanks Mary Ann for that", names: full) != nil)
        #expect(MentionDetector.findMention(in: "Mary said", names: full) == nil)
    }
}
