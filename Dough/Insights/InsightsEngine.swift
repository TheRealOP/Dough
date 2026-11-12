import Foundation

struct CategoryTotal: Identifiable, Equatable {
    var category: SpendingCategory
    var amount: Decimal
    var id: SpendingCategory { category }
}

struct ItemStat: Identifiable, Equatable {
    var name: String
    var count: Int
    var spend: Decimal
    var id: String { name.lowercased() }
}

/// Pure calculations over spending records.
enum InsightsEngine {
    /// Spend per category, largest first. Each receipt's total (tax included) is split
    /// across its items' categories in proportion to the item prices.
    static func categoryTotals(_ records: [SpendingRecord]) -> [CategoryTotal] {
        var totals: [SpendingCategory: Decimal] = [:]
        for record in records {
            let itemsSum = record.items.reduce(Decimal(0)) { $0 + $1.price }
            if record.items.isEmpty || itemsSum <= 0 {
                totals[.other, default: 0] += record.total
                continue
            }
            for item in record.items {
                totals[item.category, default: 0] += item.price * record.total / itemsSum
            }
        }
        return totals
            .map { CategoryTotal(category: $0.key, amount: $0.value.rounded()) }
            .filter { $0.amount != 0 }
            .sorted {
                $0.amount != $1.amount ? $0.amount > $1.amount : $0.category.displayName < $1.category.displayName
            }
    }

    /// Items grouped by name (case- and whitespace-insensitive), highest spend first.
    static func topItems(_ records: [SpendingRecord], limit: Int) -> [ItemStat] {
        var stats: [String: ItemStat] = [:]
        var order: [String] = []
        for record in records {
            for item in record.items where item.price > 0 {
                let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = name.lowercased()
                if key.isEmpty { continue }
                if stats[key] == nil {
                    stats[key] = ItemStat(name: name, count: 0, spend: 0)
                    order.append(key)
                }
                stats[key]?.count += 1
                stats[key]?.spend += item.price
            }
        }
        let sorted = order.compactMap { stats[$0] }.sorted { $0.spend > $1.spend }
        return Array(sorted.prefix(max(limit, 0)))
    }

    /// Money left in the budget bucket: `starting`, plus `monthly` for every month from the one
    /// containing `start` through the one containing `now`, minus all spending since the
    /// beginning of `start`'s month.
    static func budgetBalance(
        starting: Decimal,
        monthly: Decimal,
        start: Date,
        now: Date = .now,
        spending: [(date: Date, total: Decimal)],
        calendar: Calendar = .current
    ) -> Decimal {
        guard let first = calendar.dateInterval(of: .month, for: start)?.start,
              let current = calendar.dateInterval(of: .month, for: now)?.start else { return starting + monthly }
        let months = max(0, calendar.dateComponents([.month], from: first, to: current).month ?? 0) + 1
        let spent = spending.filter { (first...).contains($0.date) }.reduce(Decimal(0)) { $0 + $1.total }
        return starting + monthly * Decimal(months) - spent
    }

    /// Compact plain-text briefing for the on-device language model.
    static func aiContext(current: [SpendingRecord], previous: [SpendingRecord], periodName: String, budget: Decimal?) -> String {
        let spent = current.reduce(Decimal(0)) { $0 + $1.total }
        let previousSpent = previous.reduce(Decimal(0)) { $0 + $1.total }

        var lines: [String] = []
        lines.append("Period: \(periodName) (currency \(Money.currencyCode))")
        lines.append("Spent: \(spent.currencyText) across \(current.count) receipts")
        lines.append("Previous period: \(previousSpent.currencyText) across \(previous.count) receipts")
        if let budget {
            let remaining = budget - spent
            if remaining >= 0 {
                lines.append("Budget this month: \(budget.currencyText), remaining \(remaining.currencyText)")
            } else {
                lines.append("Budget this month: \(budget.currencyText), over by \((spent - budget).currencyText)")
            }
        }

        let currentCategories = categoryTotals(current)
        let previousCategories = categoryTotals(previous)
        var previousByCategory: [SpendingCategory: Decimal] = [:]
        for entry in previousCategories { previousByCategory[entry.category] = entry.amount }

        lines.append("")
        lines.append("Categories (this period, previous period):")
        for entry in currentCategories {
            let before = previousByCategory[entry.category] ?? 0
            lines.append("- \(entry.category.displayName): \(entry.amount.currencyText) (previous \(before.currencyText))")
        }
        let currentSet = Set(currentCategories.map(\.category))
        for entry in previousCategories where !currentSet.contains(entry.category) {
            lines.append("- \(entry.category.displayName): \(Decimal(0).currencyText) (previous \(entry.amount.currencyText))")
        }

        let items = topItems(current, limit: 10)
        if !items.isEmpty {
            lines.append("")
            lines.append("Top items (times bought, total spend):")
            for item in items {
                lines.append("- \(item.name) ×\(item.count) \(item.spend.currencyText)")
            }
        }

        let largest = current.sorted { $0.total > $1.total }.prefix(8)
        if !largest.isEmpty {
            lines.append("")
            lines.append("Largest receipts (tags and notes are the user's own explanation):")
            for record in largest {
                let merchant = record.merchant.isEmpty ? "Unknown merchant" : record.merchant
                var line = "- \(record.date.formatted(date: .abbreviated, time: .omitted)), \(merchant), \(record.total.currencyText)"
                let tags = record.tags.filter { !$0.isEmpty }
                if !tags.isEmpty {
                    line += ", tags: \(tags.joined(separator: ", "))"
                }
                let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty {
                    line += ", note: \(note.count > 120 ? String(note.prefix(120)) + "…" : note)"
                }
                lines.append(line)
            }
        }

        let text = lines.joined(separator: "\n")
        return text.count > 2500 ? String(text.prefix(2500)) : text
    }
}
