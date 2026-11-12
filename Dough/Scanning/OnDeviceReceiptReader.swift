import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads OCR'd receipt text with Apple's on-device language model (iOS 26+).
enum OnDeviceReceiptReader {
    struct UnavailableError: Error {}

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Throws `UnavailableError` when the model can't be used.
    static func read(ocrText: String) async throws -> ParsedReceipt {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if SystemLanguageModel.default.isAvailable {
                return try await FoundationModelsReceiptReader.read(ocrText: ocrText)
            }
        }
        #endif
        throw UnavailableError()
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
@Generable
enum GeneratedCategory {
    case groceries
    case dining
    case household
    case personalCare
    case health
    case transport
    case entertainment
    case shopping
    case other
}

@available(iOS 26.0, *)
@Generable
struct GeneratedItem {
    @Guide(description: "Product name, with receipt abbreviations expanded when obvious, e.g. \"ORG BNNA\" becomes \"Organic Bananas\"")
    var name: String
    @Guide(description: "Number of units bought, 1 if not shown")
    var quantity: Int
    @Guide(description: "Line total paid for this item; negative for discounts and coupons")
    var price: Double
    @Guide(description: "Spending category of this item")
    var category: GeneratedCategory
}

@available(iOS 26.0, *)
@Generable
struct GeneratedReceipt {
    @Guide(description: "Store or restaurant name")
    var merchant: String
    @Guide(description: "Purchase date formatted yyyy-MM-dd, or an empty string if not printed")
    var purchaseDate: String
    @Guide(description: "Final amount paid including tax, or 0 if unknown")
    var total: Double
    @Guide(description: "Total tax, or 0 if none")
    var tax: Double
    @Guide(description: "Purchased items in receipt order. Exclude subtotal, tax, total, tip, payment and change lines.")
    var items: [GeneratedItem]
}

@available(iOS 26.0, *)
enum FoundationModelsReceiptReader {
    static func read(ocrText: String) async throws -> ParsedReceipt {
        let session = LanguageModelSession(
            instructions: "You extract structured data from receipt text produced by OCR. The text may contain recognition errors. Only report values that appear on the receipt."
        )
        let prompt = "Receipt text:\n\n" + String(ocrText.prefix(6000))
        let generated = try await session.respond(
            to: prompt,
            generating: GeneratedReceipt.self,
            options: GenerationOptions(sampling: .greedy)
        ).content

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"

        var receipt = ParsedReceipt()
        let merchant = generated.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        receipt.merchant = merchant.isEmpty ? nil : merchant
        receipt.date = formatter.date(from: generated.purchaseDate.trimmingCharacters(in: .whitespaces))
        receipt.total = generated.total > 0 ? Money.decimal(generated.total) : nil
        receipt.tax = generated.tax > 0 ? Money.decimal(generated.tax) : nil
        receipt.items = generated.items.compactMap { item -> ParsedItem? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return ParsedItem(
                name: name,
                quantity: Double(max(1, item.quantity)),
                price: Money.decimal(item.price),
                category: spendingCategory(item.category)
            )
        }
        return receipt
    }

    private static func spendingCategory(_ category: GeneratedCategory) -> SpendingCategory {
        switch category {
        case .groceries: return .groceries
        case .dining: return .dining
        case .household: return .household
        case .personalCare: return .personalCare
        case .health: return .health
        case .transport: return .transport
        case .entertainment: return .entertainment
        case .shopping: return .shopping
        case .other: return .other
        }
    }
}

#endif
