import Foundation
import SwiftData
import SwiftUI

// MARK: - Categories

enum SpendingCategory: String, CaseIterable, Identifiable {
    case groceries, dining, household, personalCare, health, transport, entertainment, shopping, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groceries: return "Groceries"
        case .dining: return "Dining"
        case .household: return "Household"
        case .personalCare: return "Personal Care"
        case .health: return "Health"
        case .transport: return "Transport"
        case .entertainment: return "Entertainment"
        case .shopping: return "Shopping"
        case .other: return "Other"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .groceries: return "cart"
        case .dining: return "fork.knife"
        case .household: return "house"
        case .personalCare: return "drop"
        case .health: return "cross.case"
        case .transport: return "car"
        case .entertainment: return "ticket"
        case .shopping: return "bag"
        case .other: return "square.grid.2x2"
        }
    }

    var color: Color {
        switch self {
        case .groceries: return .green
        case .dining: return .orange
        case .household: return .brown
        case .personalCare: return .pink
        case .health: return .red
        case .transport: return .blue
        case .entertainment: return .purple
        case .shopping: return .indigo
        case .other: return .gray
        }
    }
}

// MARK: - Money

enum Money {
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    /// Exact two-decimal `Decimal` from a `Double` (avoids binary floating point noise).
    static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

extension Decimal {
    /// e.g. "$12.45" in the user's currency.
    var currencyText: String { formatted(.currency(code: Money.currencyCode)) }

    func rounded(_ scale: Int = 2) -> Decimal {
        var input = self
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }
}

/// `@AppStorage` keys for the optional budget: a bucket that begins with a starting amount,
/// gets the monthly amount added every month, and has every receipt subtracted.
/// `enabledKey` stores a `Bool` (default false); `amountKey` (added each month) and `startingKey`
/// a `Double` (default 0); `startKey` when the budget was turned on, as
/// `timeIntervalSinceReferenceDate` (0 = not recorded, treated as now).
enum BudgetSettings {
    static let enabledKey = "budget.enabled"
    static let amountKey = "budget.amount"
    static let startingKey = "budget.starting"
    static let startKey = "budget.start"
}

// MARK: - Persistent models

@Model
final class Receipt {
    var merchant: String = ""
    var date: Date = Date.now
    /// Final amount paid (including tax). This is what counts against the budget.
    var total: Decimal = 0
    var tax: Decimal = 0
    /// Free-form context such as "party" or "work".
    var tags: [String] = []
    var note: String = ""
    @Attribute(.externalStorage) var imageData: Data?
    @Relationship(deleteRule: .cascade, inverse: \LineItem.receipt)
    var items: [LineItem] = []

    init() {}

    /// Items in receipt order (SwiftData relationships are unordered).
    var sortedItems: [LineItem] { items.sorted { $0.position < $1.position } }

    /// Plain-value snapshot for insights and export.
    var record: SpendingRecord {
        SpendingRecord(
            merchant: merchant,
            date: date,
            total: total,
            tax: tax,
            tags: tags,
            note: note,
            items: sortedItems.map {
                SpendingRecord.Item(name: $0.name, quantity: $0.quantity, price: $0.price, category: $0.category)
            }
        )
    }
}

@Model
final class LineItem {
    var name: String = ""
    var quantity: Double = 1
    /// Line total (quantity × unit price). Negative for discounts.
    var price: Decimal = 0
    var categoryRaw: String = "other"
    var position: Int = 0
    var receipt: Receipt?

    init(name: String, quantity: Double, price: Decimal, category: SpendingCategory, position: Int) {
        self.name = name
        self.quantity = quantity
        self.price = price
        self.categoryRaw = category.rawValue
        self.position = position
    }

    var category: SpendingCategory {
        get { SpendingCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

// MARK: - Value types

/// A receipt as plain values, detached from SwiftData.
struct SpendingRecord: Hashable {
    struct Item: Hashable {
        var name: String
        var quantity: Double
        var price: Decimal
        var category: SpendingCategory
    }

    var merchant: String
    var date: Date
    var total: Decimal
    var tax: Decimal
    var tags: [String]
    var note: String
    var items: [Item]
}

/// An editable, not-yet-saved receipt. Produced by scanning, edited on the review screen.
struct ReceiptDraft: Identifiable {
    struct Item: Identifiable {
        var id = UUID()
        var name = ""
        var quantity: Double = 1
        var price: Decimal = 0
        var category: SpendingCategory = .other
    }

    var id = UUID()
    var merchant = ""
    var date = Date.now
    var total: Decimal = 0
    var tax: Decimal = 0
    var items: [Item] = []
    var tags: [String] = []
    var note = ""
    var imageData: Data?
    /// Shown on the review screen when reading the photo went badly.
    var notice: String?

    var itemsSum: Decimal { items.reduce(0) { $0 + $1.price } }

    init() {}

    /// A draft for editing an existing receipt.
    init(receipt: Receipt) {
        merchant = receipt.merchant
        date = receipt.date
        total = receipt.total
        tax = receipt.tax
        tags = receipt.tags
        note = receipt.note
        imageData = receipt.imageData
        items = receipt.sortedItems.map {
            Item(name: $0.name, quantity: $0.quantity, price: $0.price, category: $0.category)
        }
    }

    /// Writes the draft into `receipt`, replacing its items. Insert `receipt` into `context` first.
    func apply(to receipt: Receipt, in context: ModelContext) {
        receipt.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        receipt.date = date
        receipt.total = total
        receipt.tax = tax
        receipt.tags = tags
        receipt.note = note
        receipt.imageData = imageData
        for old in receipt.items { context.delete(old) }
        receipt.items = items.enumerated().map { index, item in
            LineItem(name: item.name, quantity: item.quantity, price: item.price, category: item.category, position: index)
        }
    }
}
