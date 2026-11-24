import Foundation

/// Підказка від Claude у форматі:
///   TIP: що відбувається і що варто додати
///   EN: готова фраза англійською
///   TR: її переклад мовою перекладу (лише коли переклад увімкнено)
struct Hint: Equatable {
    var tip = ""
    var en = ""
    var ua = ""

    /// «TIP: —» або порожньо — Claude вирішив, що додати нічого.
    var isEmpty: Bool {
        let t = tip.trimmingCharacters(in: .whitespaces)
        return en.isEmpty && (t.isEmpty || t == "—" || t == "-")
    }

    static func parse(_ raw: String) -> Hint {
        var h = Hint()
        var current: WritableKeyPath<Hint, String> = \.tip
        for line in raw.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let upper = t.uppercased()
            if upper.hasPrefix("TIP:") { current = \.tip; h.tip = rest(t) }
            else if upper.hasPrefix("EN:") { current = \.en; h.en = rest(t) }
            else if upper.hasPrefix("TR:") || upper.hasPrefix("UA:") || upper.hasPrefix("RU:") {
                current = \.ua; h.ua = rest(t)
            }
            else { h[keyPath: current] += (h[keyPath: current].isEmpty ? "" : " ") + t }
        }
        return h
    }

    private static func rest(_ line: String) -> String {
        guard let i = line.firstIndex(of: ":") else { return line }
        return line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»"))
    }
}
