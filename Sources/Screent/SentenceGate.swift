import Foundation

/// Auto mode: decides when the accumulated new caption text is a finished thought worth translating,
/// so Claude isn't asked to translate half a sentence that the next frame will complete.
enum SendDecision: Equatable {
    case wait
    /// Send all the new text.
    case all
    /// Send only the first `words` words (complete sentences); keep the rest accumulating.
    case upTo(words: Int)
}

enum SentenceGate {
    /// A finished sentence shorter than this waits one more tick in case another one follows.
    static let minWords = 8
    /// Ticks (0.8 s each) without any change = the speaker paused: send even an unfinished sentence.
    static let pauseTicks = 3
    /// While the speaker keeps going, finished sentences totalling this many words are sent right away.
    static let flushWords = 20
    /// A monologue with no punctuation at all is sent anyway at this length.
    static let maxWords = 80

    static func decide(text: String, stableTicks: Int) -> SendDecision {
        let tokens = TextDiffer.tokenize(text)
        guard !tokens.isEmpty else { return .wait }
        let words = tokens.count
        let complete = endsSentence(tokens[words - 1].raw)

        if complete, stableTicks >= 1, words >= minWords || stableTicks >= 2 { return .all }
        if stableTicks >= pauseTicks { return .all }
        // The speaker is still talking: flush the sentences that are already finished.
        if let cut = tokens.dropLast().lastIndex(where: { endsSentence($0.raw) }).map({ $0 + 1 }),
           cut >= flushWords {
            return .upTo(words: cut)
        }
        if words >= maxWords { return .all }
        return .wait
    }

    static func endsSentence(_ word: String) -> Bool {
        let core = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"”’')]»"))
        guard let last = core.last else { return false }
        return ".!?…".contains(last)
    }
}

extension TextDiffer {
    /// The first `n` words of a diff, keeping its line breaks (speaker labels).
    static func prefix(_ diff: TextDiff, words n: Int) -> TextDiff {
        let t = tokenize(diff.text)
        return TextDiff(text: join(t.prefix(n)), continues: diff.continues, wordCount: min(n, t.count))
    }

    /// `text` without its last `n` words: what has been sent when the tail is held back.
    static func dropLast(_ n: Int, of text: String) -> String {
        join(tokenize(text).dropLast(n))
    }

    private static func join<S: Sequence>(_ tokens: S) -> String where S.Element == Token {
        var out = ""
        for t in tokens {
            if !out.isEmpty { out += t.lineStart ? "\n" : " " }
            out += t.raw
        }
        return out
    }
}
