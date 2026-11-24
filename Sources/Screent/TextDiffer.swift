import Foundation

struct TextDiff {
    /// Новий текст, якого ще не надсилали (зі збереженими переносами рядків).
    let text: String
    /// Новий текст продовжує незавершене речення з попереднього надсилання.
    let continues: Bool
    let wordCount: Int
    var isEmpty: Bool { wordCount == 0 }

    static let empty = TextDiff(text: "", continues: false, wordCount: 0)
}

/// Субтитри прокручуються, тож кожен новий кадр здебільшого повторює попередній.
/// Шукаємо найдовший «хвіст» попереднього тексту на початку нового і повертаємо лише решту.
enum TextDiffer {
    struct Token {
        let raw: String
        let norm: String
        let lineStart: Bool
    }

    static func tokenize(_ text: String) -> [Token] {
        var out: [Token] = []
        for line in text.split(whereSeparator: \.isNewline) {
            var first = true
            for word in line.split(whereSeparator: \.isWhitespace) {
                let raw = String(word)
                let norm = raw.lowercased().filter { $0.isLetter || $0.isNumber }
                guard !norm.isEmpty else { continue }
                out.append(Token(raw: raw, norm: norm, lineStart: first))
                first = false
            }
        }
        return out
    }

    static func normalized(_ text: String) -> String {
        tokenize(text).map(\.norm).joined(separator: " ")
    }

    static func diff(previous: String, current: String) -> TextDiff {
        let c = tokenize(current)
        guard !c.isEmpty else { return .empty }
        let p = tokenize(previous)
        guard !p.isEmpty else { return make(c, from: 0, continues: false) }

        // Увесь поточний текст уже був у попередньому — нічого нового.
        let pj = " " + p.map(\.norm).joined(separator: " ") + " "
        let cj = " " + c.map(\.norm).joined(separator: " ") + " "
        if pj.contains(cj) { return .empty }

        var bestK = 0
        var bestEnd = 0
        let maxOffset = min(c.count - 1, 12) // зверху можуть з'явитися ім'я мовця чи сміття
        for j in 0...maxOffset {
            var k = min(p.count, c.count - j)
            while k >= 3 && k > bestK {
                let allowed = k / 6 // допуск на помилки OCR та виправлення ASR
                var mismatches = 0
                var ok = true
                for i in 0..<k where !similar(p[p.count - k + i].norm, c[j + i].norm) {
                    mismatches += 1
                    if mismatches > allowed { ok = false; break }
                }
                if ok {
                    bestK = k
                    bestEnd = j + k
                    break
                }
                k -= 1
            }
        }

        guard bestK > 0 else { return make(c, from: 0, continues: false) }
        let ended = p.last?.raw.last.map { ".!?…\"”".contains($0) } ?? true
        return make(c, from: bestEnd, continues: !ended)
    }

    private static func make(_ tokens: [Token], from start: Int, continues: Bool) -> TextDiff {
        guard start < tokens.count else { return .empty }
        var text = ""
        for (i, t) in tokens[start...].enumerated() {
            if i > 0 { text += t.lineStart ? "\n" : " " }
            text += t.raw
        }
        return TextDiff(text: text, continues: continues, wordCount: tokens.count - start)
    }

    private static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 5, b.count >= 5, abs(a.count - b.count) <= 1 else { return false }
        return levenshtein(Array(a), Array(b)) <= 1
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
