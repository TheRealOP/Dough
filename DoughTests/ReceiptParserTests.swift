import Foundation
import Testing
@testable import Dough

struct ReceiptParserTests {
    let calendar: Calendar
    let now: Date

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
    }

    private func parse(_ lines: [String]) -> ParsedReceipt {
        ReceiptParser.parse(lines: lines, now: now, calendar: calendar)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func money(_ text: String) -> Decimal {
        Decimal(string: text)!
    }

    @Test func groceryReceipt() {
        let receipt = parse([
            "TRADER JOE'S",
            "123 MAIN STREET",
            "SPRINGFIELD, IL 62701",
            "TEL (555) 123-4567",
            "ORG BANANAS 1.98",
            "2 @ 0.99",
            "MILK 2% GAL   4.49 F",
            "SOURDOUGH BREAD $ 3.99",
            "PAPER TOWELS 6.49 T",
            "SUBTOTAL 16.95",
            "TAX 0.52",
            "TOTAL 17.47",
            "VISA 17.47",
            "CHANGE 0.00",
            "03/05/2026 14:32",
        ])
        #expect(receipt.merchant == "Trader Joe's")
        #expect(receipt.date == day(2026, 3, 5))
        #expect(receipt.items.count == 4)
        #expect(receipt.items.map(\.name) == ["Org Bananas", "Milk 2% Gal", "Sourdough Bread", "Paper Towels"])
        #expect(receipt.items.map(\.price) == [money("1.98"), money("4.49"), money("3.99"), money("6.49")])
        #expect(receipt.items.map(\.quantity) == [2, 1, 1, 1])
        #expect(receipt.items.map(\.category) == [.groceries, .groceries, .groceries, .household])
        #expect(receipt.subtotal == money("16.95"))
        #expect(receipt.tax == money("0.52"))
        #expect(receipt.total == money("17.47"))
        #expect(receipt.totalIsExplicit)
    }

    @Test func restaurantReceipt() {
        let receipt = parse([
            "JOE'S DINER",
            "45 Elm St",
            "Table 4 Server: Amy",
            "1 Cheeseburger 12.50",
            "2 Coke 5.00",
            "Fries 3.75",
            "Subtotal 21.25",
            "Tax 1.86",
            "Tip 4.00",
            "Total 27.11",
        ])
        #expect(receipt.merchant == "Joe's Diner")
        #expect(receipt.items.map(\.name) == ["Cheeseburger", "Coke", "Fries"])
        #expect(receipt.items.map(\.quantity) == [1, 2, 1])
        #expect(receipt.items.map(\.price) == [money("12.50"), money("5.00"), money("3.75")])
        #expect(receipt.items.allSatisfy { $0.category == .dining })
        #expect(receipt.tax == money("1.86"))
        #expect(receipt.total == money("27.11"))
        #expect(receipt.totalIsExplicit)
    }

    @Test func commaDecimalAmounts() {
        let receipt = parse([
            "REWE Markt GmbH",
            "Bananen 1,99",
            "Vollmilch 1,15 A",
            "SUMME 3,14",
        ])
        #expect(receipt.merchant == "REWE Markt GmbH")
        #expect(receipt.items.map(\.name) == ["Bananen", "Vollmilch"])
        #expect(receipt.items.map(\.price) == [money("1.99"), money("1.15")])
        #expect(receipt.total == money("3.14"))
        #expect(receipt.totalIsExplicit)
    }

    @Test func trailingAmounts() {
        #expect(ReceiptParser.trailingAmount(in: "TV 1,234.56")?.value == money("1234.56"))
        #expect(ReceiptParser.trailingAmount(in: "Coupon -1.00")?.value == money("-1.00"))
        #expect(ReceiptParser.trailingAmount(in: "Coupon 1.00-")?.value == money("-1.00"))
        #expect(ReceiptParser.trailingAmount(in: "Gum $1.50")?.value == money("1.50"))
        #expect(ReceiptParser.trailingAmount(in: "Date 12.08.26")?.value == nil)
    }

    @Test func dateFormats() {
        let receipt = parse(["CORNER SHOP", "Date 12.08.26", "Gum 1.50", "TOTAL 1.50"])
        #expect(receipt.date == day(2026, 8, 12))
        #expect(receipt.items.map(\.price) == [money("1.50")])

        func date(_ line: String) -> Date? { parse([line]).date }
        #expect(date("03/05/2026") == day(2026, 3, 5))
        #expect(date("3/4/26 10:15") == day(2026, 3, 4))
        #expect(date("25/12/2025") == day(2025, 12, 25))
        #expect(date("2026-03-04") == day(2026, 3, 4))
        #expect(date("Mar 3, 2026") == day(2026, 3, 3))
        #expect(date("3 Mar 2026") == day(2026, 3, 3))
        #expect(date("02/30/2026") == nil)  // no Feb 30
        #expect(date("12/25/2026") == nil)  // in the future
        #expect(date("01/01/2010") == nil)  // too old
    }

    @Test func totalFallsBackToItemSum() {
        let receipt = parse(["QUICK MART", "Coffee 2.50", "Donut 1.25"])
        #expect(receipt.merchant == "Quick Mart")
        #expect(receipt.items.count == 2)
        #expect(receipt.total == money("3.75"))
        #expect(!receipt.totalIsExplicit)
    }

    @Test func rowGrouping() {
        let fragments = [
            TextRecognizer.Fragment(text: "4.49", minX: 0.8, midY: 0.748, height: 0.02),
            TextRecognizer.Fragment(text: "BANANAS", minX: 0.05, midY: 0.80, height: 0.02),
            TextRecognizer.Fragment(text: "TRADER JOE'S", minX: 0.3, midY: 0.95, height: 0.03),
            TextRecognizer.Fragment(text: "MILK", minX: 0.05, midY: 0.75, height: 0.02),
            TextRecognizer.Fragment(text: "1.98", minX: 0.8, midY: 0.805, height: 0.02),
        ]
        #expect(TextRecognizer.rows(from: fragments) == ["TRADER JOE'S", "BANANAS 1.98", "MILK 4.49"])
    }

    @Test func categorizer() {
        #expect(Categorizer.category(forItem: "Organic Bananas", merchant: nil) == .groceries)
        #expect(Categorizer.category(forItem: "Paper Towels", merchant: "Target") == .household)
        #expect(Categorizer.category(forItem: "Teal Towel", merchant: nil) == .household)
        #expect(Categorizer.category(forItem: "Anything", merchant: "Starbucks") == .dining)
        #expect(Categorizer.category(forItem: "Notebook", merchant: "Barnes & Noble") != .dining)
        #expect(Categorizer.category(forItem: "Mystery", merchant: "Shell") == .transport)
        #expect(Categorizer.category(forItem: "Mystery", merchant: nil) == .other)
        #expect(!Categorizer.matches("Ribeye Steak", keywords: ["tea"]))
        #expect(!Categorizer.matches("Barnes & Noble", keywords: ["bar"]))
        #expect(Categorizer.matches("Toilet Paper 12pk", keywords: ["toilet paper"]))
    }
}

struct ReceiptParserTotalsTests {
    private func money(_ text: String) -> Decimal {
        Decimal(string: text)!
    }

    @Test func tenderedAmountIsNotTheTotal() {
        let receipt = ReceiptParser.parse(lines: [
            "CORNER MARKET",
            "MILK 4.00",
            "TOTAL 4.00",
            "TOTAL TENDERED 20.00",
            "CHANGE 16.00",
        ])
        #expect(receipt.total == money("4.00"))
    }

    @Test func totalTaxLineIsNotAddedToTaxLines() {
        let receipt = ReceiptParser.parse(lines: [
            "CORNER MARKET",
            "MILK 4.00",
            "TAX 0.30",
            "TOTAL TAX 0.30",
            "TOTAL 4.30",
        ])
        #expect(receipt.tax == money("0.30"))
    }

    @Test func fallbackTotalIncludesTax() {
        let receipt = ReceiptParser.parse(lines: [
            "CORNER MARKET",
            "MILK 4.00",
            "TAX 0.30",
        ])
        #expect(receipt.total == money("4.30"))
        #expect(!receipt.totalIsExplicit)
    }

    @Test func quantityLineUsesTheNameAboveIt() {
        let receipt = ReceiptParser.parse(lines: [
            "CORNER MARKET",
            "MILK 4.00",
            "BANANAS",
            "2 @ 0.99 1.98",
        ])
        #expect(receipt.items.map(\.name) == ["Milk", "Bananas"])
        #expect(receipt.items.map(\.quantity) == [1, 2])
        #expect(receipt.items.map(\.price) == [money("4.00"), money("1.98")])
    }
}
