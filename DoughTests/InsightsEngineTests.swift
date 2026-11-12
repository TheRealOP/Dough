import Foundation
import Testing
@testable import Dough

struct InsightsEngineTests {
    private func d(_ string: String) -> Decimal { Decimal(string: string)! }

    private func record(
        merchant: String = "Store",
        total: String,
        tags: [String] = [],
        note: String = "",
        items: [(String, String, SpendingCategory)] = []
    ) -> SpendingRecord {
        SpendingRecord(
            merchant: merchant,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            total: d(total),
            tax: 0,
            tags: tags,
            note: note,
            items: items.map { SpendingRecord.Item(name: $0.0, quantity: 1, price: d($0.1), category: $0.2) }
        )
    }

    @Test func budgetBalanceAddsMonthlyAndSubtractsReceipts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
        }
        // Started mid-September with 500, 100 a month: September, October and November top-ups by November.
        let balance = InsightsEngine.budgetBalance(
            starting: 500,
            monthly: 100,
            start: day(9, 15),
            now: day(11, 12),
            spending: [
                (day(8, 30), 999),  // before the starting month: ignored
                (day(9, 1), 40),    // same month as the start: counted
                (day(11, 5), 60),
            ],
            calendar: calendar
        )
        #expect(balance == 700)
    }

    @Test func categoryTotalsSplitTaxProportionally() {
        // Items sum to 10.00; total 10.80 includes 8% tax.
        let receipt = record(total: "10.80", items: [
            ("Apples", "6.00", .groceries),
            ("Coffee", "4.00", .dining),
        ])
        let totals = InsightsEngine.categoryTotals([receipt])

        #expect(totals.count == 2)
        #expect(totals[0] == CategoryTotal(category: .groceries, amount: d("6.48")))
        #expect(totals[1] == CategoryTotal(category: .dining, amount: d("4.32")))
        #expect(totals.reduce(Decimal(0)) { $0 + $1.amount } == d("10.80"))
    }

    @Test func receiptWithoutItemsCountsAsOther() {
        let receipts = [
            record(total: "5.00"),
            record(total: "3.00", items: [("Gum", "3.00", .groceries)]),
        ]
        let totals = InsightsEngine.categoryTotals(receipts)

        #expect(totals == [
            CategoryTotal(category: .other, amount: d("5.00")),
            CategoryTotal(category: .groceries, amount: d("3.00")),
        ])
    }

    @Test func topItemsMergesNamesAndSortsBySpend() {
        let receipts = [
            record(total: "10.00", items: [("Bread", "4.00", .groceries), ("Milk", "3.00", .groceries)]),
            record(total: "10.00", items: [("bread ", "5.00", .groceries), ("Cereal", "6.00", .groceries)]),
            record(total: "1.00", items: [("Coupon", "-1.00", .other)]),
        ]
        let items = InsightsEngine.topItems(receipts, limit: 10)

        #expect(items.map(\.name) == ["Bread", "Cereal", "Milk"])
        #expect(items[0].count == 2)
        #expect(items[0].spend == d("9.00"))
        #expect(InsightsEngine.topItems(receipts, limit: 1).count == 1)
    }

    @Test func aiContextIncludesTagsAndNotes() {
        let receipt = record(
            merchant: "Bakery",
            total: "80.00",
            tags: ["party"],
            note: "Bread for Sam's birthday",
            items: [("Bread", "80.00", .groceries)]
        )
        let context = InsightsEngine.aiContext(current: [receipt], previous: [], periodName: "November 2026", budget: d("500"))

        #expect(context.contains("November 2026"))
        #expect(context.contains("Bakery"))
        #expect(context.contains("tags: party"))
        #expect(context.contains("note: Bread for Sam's birthday"))
        #expect(context.count <= 2500)
    }
}
