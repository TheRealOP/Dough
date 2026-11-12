import UIKit

/// Turns scanned pages into an editable draft: OCR, heuristic parsing, and on-device AI when available.
enum ReceiptProcessor {
    /// Never throws; on failure returns a draft with `notice` set so the user can type it in.
    static func process(images: [UIImage]) async -> ReceiptDraft {
        var draft = ReceiptDraft()
        if let first = images.first {
            draft.imageData = upright(first, maxSide: 1600).jpegData(compressionQuality: 0.6)
        }

        var lines: [String] = []
        for image in images {
            if let pageLines = try? await TextRecognizer.recognizeLines(in: upright(image, maxSide: 2400)) {
                lines += pageLines
            }
        }
        guard !lines.isEmpty else {
            draft.notice = "Couldn't read this photo. Enter the details below or try a sharper picture."
            return draft
        }

        var receipt = ReceiptParser.parse(lines: lines)
        if OnDeviceReceiptReader.isAvailable,
           let ai = try? await OnDeviceReceiptReader.read(ocrText: lines.joined(separator: "\n")) {
            receipt = merge(heuristic: receipt, ai: ai)
        }

        draft.merchant = receipt.merchant ?? ""
        draft.date = receipt.date ?? .now
        draft.tax = receipt.tax ?? 0
        draft.items = receipt.items.map {
            ReceiptDraft.Item(name: $0.name, quantity: $0.quantity, price: $0.price, category: $0.category)
        }
        draft.total = receipt.total ?? 0
        if draft.total == 0 {
            draft.total = draft.itemsSum + draft.tax
        }
        return draft
    }

    private static func merge(heuristic: ParsedReceipt, ai: ParsedReceipt) -> ParsedReceipt {
        var result = heuristic
        if let merchant = ai.merchant, !merchant.isEmpty { result.merchant = merchant }
        result.date = heuristic.date ?? ai.date
        if !ai.items.isEmpty { result.items = ai.items }
        result.tax = heuristic.tax ?? ai.tax
        if !heuristic.totalIsExplicit, let aiTotal = ai.total, aiTotal > 0 {
            result.total = aiTotal
        }
        return result
    }

    /// Redraws `image` upright (orientation `.up`) with its longest side at most `maxSide` pixels.
    private static func upright(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        let longest = max(width, height)
        guard longest > 0 else { return image }
        let factor = min(1, maxSide / longest)
        let size = CGSize(width: (width * factor).rounded(), height: (height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
