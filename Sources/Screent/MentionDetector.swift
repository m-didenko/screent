import Foundation

/// Шукає ім'я користувача в нових субтитрах. Субтитри — поганий voice-to-text,
/// тому порівнюємо фонетично: Mykyta = Mikita = Микита, Nick = Nic = Нік.
enum MentionDetector {
    /// «Nick, Mykyta» → [["nik"], ["mikita"]]; багатослівні імена — кілька токенів.
    static func parse(_ names: String) -> [[String]] {
        names.split(separator: ",")
            .map { TextDiffer.tokenize(String($0)).map { phonetic($0.norm) } }
            .filter { !$0.isEmpty }
    }

    /// Повертає рядок тексту, у якому згадано одне з імен, або nil.
    static func findMention(in text: String, names: [[String]]) -> String? {
        guard !names.isEmpty else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let tokens = TextDiffer.tokenize(String(line)).map { phonetic($0.norm) }
            for name in names where name.count <= tokens.count {
                for start in 0...(tokens.count - name.count) {
                    let window = tokens[start..<(start + name.count)]
                    if zip(window, name).allSatisfy({ matches($0, $1) }) {
                        return String(line).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        return nil
    }

    /// Обидва аргументи — вже у фонетичній формі.
    static func matches(_ token: String, _ name: String) -> Bool {
        if token == name { return true }
        // Присвійна / множина: Nick's → niks
        if name.count >= 3, token.count == name.count + 1, token.hasPrefix(name), token.hasSuffix("s") { return true }
        // Залишкові помилки розпізнавання для достатньо довгих імен
        let allowed = name.count >= 7 ? 2 : (name.count >= 4 ? 1 : 0)
        guard allowed > 0, abs(token.count - name.count) <= allowed else { return false }
        return TextDiffer.levenshtein(Array(token), Array(name)) <= allowed
    }

    /// Груба фонетична форма: транслітерація кирилиці, y→i, c/ck/q→k, w→v, ph→f, без подвоєних літер.
    static func phonetic(_ word: String) -> String {
        var s = ""
        for ch in word.lowercased() { s += cyrillic[ch] ?? String(ch) }
        for (a, b) in [("ck", "k"), ("ph", "f"), ("kh", "h"), ("x", "ks"), ("q", "k"), ("c", "k"),
                       ("w", "v"), ("y", "i"), ("j", "i"), ("ee", "i"), ("oo", "u")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        var out = ""
        for ch in s where ch != out.last { out.append(ch) }
        return out
    }

    private static let cyrillic: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "h", "ґ": "g", "д": "d", "е": "e", "є": "ie", "ж": "zh",
        "з": "z", "и": "y", "і": "i", "ї": "i", "й": "i", "к": "k", "л": "l", "м": "m", "н": "n",
        "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
        "ч": "ch", "ш": "sh", "щ": "shch", "ь": "", "ю": "iu", "я": "ia", "ё": "io", "ы": "y",
        "э": "e", "ъ": "",
    ]
}
