import CoreGraphics
import Vision

/// Локальне розпізнавання тексту через Apple Vision.
enum OCR {
    static func recognize(_ image: CGImage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

            let items: [(CGRect, String)] = (request.results ?? []).compactMap { obs in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                return (obs.boundingBox, text)
            }
            return groupLines(items)
        }.value
    }

    /// Перший виклик Vision завантажує модель (це може тривати секунди) — робимо це заздалегідь.
    static func warmUp() async {
        let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        ctx?.setFillColor(gray: 1, alpha: 1)
        ctx?.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        if let img = ctx?.makeImage() { _ = try? await recognize(img) }
    }

    /// Збирає фрагменти в рядки: зверху вниз, у рядку — зліва направо.
    static func groupLines(_ items: [(CGRect, String)]) -> [String] {
        let sorted = items.sorted { $0.0.midY > $1.0.midY } // у Vision y росте вгору
        var rows: [[(CGRect, String)]] = []
        for item in sorted {
            if let anchor = rows.last?.first,
               abs(anchor.0.midY - item.0.midY) < min(anchor.0.height, item.0.height) * 0.5 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { row in
            row.sorted { $0.0.minX < $1.0.minX }.map(\.1).joined(separator: " ")
        }
    }
}
