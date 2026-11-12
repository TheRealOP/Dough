import UIKit
import Vision

enum TextRecognizer {
    /// One OCR observation. `minX`/`midY`/`height` are normalized, origin bottom-left (Vision coordinates).
    struct Fragment {
        var text: String
        var minX: Double
        var midY: Double
        var height: Double
    }

    /// Recognized text as visual rows, top to bottom. Expects an upright (`.up`) image.
    static func recognizeLines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try handler.perform([request])
            let observations: [VNRecognizedTextObservation] = request.results ?? []
            let fragments = observations.compactMap { observation -> Fragment? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return Fragment(
                    text: candidate.string,
                    minX: Double(box.minX),
                    midY: Double(box.midY),
                    height: Double(box.height)
                )
            }
            return TextRecognizer.rows(from: fragments)
        }.value
    }

    /// Groups fragments into rows so a name on the left and its price on the right become one line.
    static func rows(from fragments: [Fragment]) -> [String] {
        let sorted = fragments.sorted { $0.midY > $1.midY }
        var rows: [[Fragment]] = []
        for fragment in sorted {
            if let first = rows.last?.first,
               abs(first.midY - fragment.midY) < 0.5 * max(first.height, fragment.height) {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map { $0.text }.joined(separator: " ")
        }
    }
}
