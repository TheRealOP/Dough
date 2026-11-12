import Foundation

struct ParsedItem: Equatable {
    var name: String
    var quantity: Double
    var price: Decimal
    var category: SpendingCategory
}

struct ParsedReceipt: Equatable {
    var merchant: String?
    var date: Date?
    var subtotal: Decimal?
    var tax: Decimal?
    var total: Decimal?
    /// True when `total` came from a printed TOTAL line.
    var totalIsExplicit = false
    var items: [ParsedItem] = []
}

/// Heuristic parser for OCR'd receipt lines.
enum ReceiptParser {
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static let taxWords: Set<String> = ["tax", "hst", "gst", "pst", "vat", "mwst", "iva", "tva"]
    private static let totalWords: Set<String> = ["total", "summe", "gesamt"]
    /// A "total" on one of these lines is how the customer paid, not what the receipt cost.
    private static let tenderWords: Set<String> = [
        "tender", "tendered", "cash", "change", "visa", "mastercard", "amex", "discover", "debit", "credit",
        "payment", "paid",
    ]
    private static let savingsWords: Set<String> = ["savings", "saved", "points"]
    private static let ignoreWords: Set<String> = [
        "change", "cash", "visa", "mastercard", "amex", "discover", "debit", "credit", "tender", "tendered",
        "payment", "paid", "auth", "approval", "approved", "terminal", "account", "acct", "balance", "tip",
        "gratuity", "tel", "phone", "cashier", "register", "invoice", "transaction", "thank", "www", "http", "https",
    ]
    private static let merchantStopWords: Set<String> = ["welcome", "receipt", "tel", "phone", "www", "http", "https"]
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    static func parse(lines rawLines: [String], now: Date = .now, calendar: Calendar = .current) -> ParsedReceipt {
        let lines = rawLines.map(normalize).filter { !$0.isEmpty }
        var receipt = ParsedReceipt()
        receipt.merchant = merchant(in: lines)
        for line in lines {
            if let found = date(in: line, now: now, calendar: calendar) {
                receipt.date = found
                break
            }
        }

        var totals: [Decimal] = []
        var taxes: [Decimal] = []
        var totalTax: Decimal?
        var reachedTotals = false
        // A product name printed on its own line, waiting for a "2 @ 0.99" line below it.
        var pendingName: String?

        for line in lines {
            let trailing = trailingAmount(in: line)
            let amount = trailing?.value
            let words = tokens(line)
            let phrase = " " + words.joined(separator: " ") + " "

            if words.contains("subtotal") || phrase.contains(" sub total ") {
                if let amount {
                    receipt.subtotal = amount
                    reachedTotals = true
                }
                continue
            }
            if words.contains(where: { savingsWords.contains($0) }) { continue }
            if words.contains("total") && words.contains(where: { $0.hasPrefix("incl") }) {
                if let amount {
                    totals.append(amount)
                    reachedTotals = true
                }
                continue
            }
            if words.contains(where: { taxWords.contains($0) }) {
                if let amount {
                    // "TOTAL TAX" repeats the individual tax lines, so it replaces their sum.
                    if words.contains("total") { totalTax = amount } else { taxes.append(amount) }
                    reachedTotals = true
                }
                continue
            }
            if words.contains(where: { totalWords.contains($0) })
                || phrase.contains(" amount due ") || phrase.contains(" balance due ") {
                if let amount, !words.contains(where: { tenderWords.contains($0) }) {
                    totals.append(amount)
                    reachedTotals = true
                }
                continue
            }
            if words.contains(where: { ignoreWords.contains($0) }) { continue }
            if reachedTotals { continue }
            guard let found = trailing else {
                pendingName = itemName(in: line, nameEnd: line.endIndex)?.name
                continue
            }

            if let multiple = quantityLine(line) {
                let price = multiple.lineTotal ?? (Decimal(multiple.count) * multiple.unit).rounded(2)
                if let name = pendingName {
                    receipt.items.append(ParsedItem(
                        name: name, quantity: Double(multiple.count), price: price,
                        category: Categorizer.category(forItem: name, merchant: receipt.merchant)
                    ))
                } else if !receipt.items.isEmpty {
                    let index = receipt.items.count - 1
                    receipt.items[index].quantity = Double(multiple.count)
                    receipt.items[index].price = price
                }
                pendingName = nil
                continue
            }
            pendingName = nil

            guard let parsed = itemName(in: line, nameEnd: found.start) else { continue }
            let category: SpendingCategory
            if found.value < 0, let previous = receipt.items.last {
                category = previous.category
            } else {
                category = Categorizer.category(forItem: parsed.name, merchant: receipt.merchant)
            }
            receipt.items.append(
                ParsedItem(name: parsed.name, quantity: parsed.quantity, price: found.value, category: category)
            )
        }

        receipt.tax = totalTax ?? (taxes.isEmpty ? nil : taxes.reduce(Decimal(0), +))
        if let maxTotal = totals.max() {
            receipt.total = maxTotal
            receipt.totalIsExplicit = true
        } else if let subtotal = receipt.subtotal {
            receipt.total = subtotal + (receipt.tax ?? 0)
        } else if !receipt.items.isEmpty {
            receipt.total = receipt.items.reduce(Decimal(0)) { $0 + $1.price } + (receipt.tax ?? 0)
        }
        return receipt
    }

    // MARK: - Lines

    /// Trims, collapses whitespace and joins "$ 4.99" into "$4.99".
    static func normalize(_ line: String) -> String {
        line.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .replacingOccurrences(of: "$ ", with: "$")
    }

    /// Lowercased runs of letters.
    static func tokens(_ line: String) -> [String] {
        line.lowercased().split(whereSeparator: { !$0.isLetter }).map { String($0) }
    }

    /// The money value at the end of `line`, and where the text before it ends (an index into `line`).
    static func trailingAmount(in line: String) -> (value: Decimal, start: String.Index)? {
        let pattern = #/(?:^|\s|\$)(-)?\$?(\d{1,3}(?:,\d{3})+|\d+)[.,](\d{2})(-)?(?:\s[A-Za-z]{1,2})?$/#
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let integer = String(match.output.2).replacingOccurrences(of: ",", with: "")
        guard var value = Decimal(string: "\(integer).\(match.output.3)", locale: posix) else { return nil }
        if match.output.1 != nil || match.output.4 != nil {
            value = -value
        }
        return (value, match.range.lowerBound)
    }

    /// "2 @ 0.99", "2 x 0.99" or "2 @ 0.99 1.98".
    static func quantityLine(_ line: String) -> (count: Int, unit: Decimal, lineTotal: Decimal?)? {
        let pattern = #/(\d{1,3})\s*[@xX]\s*\$?(\d+[.,]\d{2})(?:\s\$?(\d+[.,]\d{2}))?(?:\s[A-Za-z]{1,2})?/#
        guard let match = line.wholeMatch(of: pattern),
              let count = Int(match.output.1), count > 0,
              let unit = decimal(String(match.output.2)) else { return nil }
        let lineTotal = match.output.3.flatMap { decimal(String($0)) }
        return (count, unit, lineTotal)
    }

    private static func decimal(_ text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: posix)
    }

    /// Cleaned item name and quantity from the text before the amount, or nil if it isn't a product name.
    static func itemName(in line: String, nameEnd: String.Index) -> (name: String, quantity: Double)? {
        var name = String(line[..<nameEnd])
        if let sku = name.firstMatch(of: #/^\d{3,}\s/#) {
            name = String(name[sku.range.upperBound...])
        }
        if let code = name.firstMatch(of: #/(?:\s\d{5,})+$/#) {
            name = String(name[..<code.range.lowerBound])
        }
        var quantity = 1.0
        if let match = name.wholeMatch(of: #/(\d{1,2})\s([A-Za-z].*)/#),
           let count = Int(match.output.1), count > 0 {
            quantity = Double(count)
            name = String(match.output.2)
        }
        let allowed = Set("&'%-./")
        name = name.filter { $0.isLetter || $0.isNumber || $0 == " " || allowed.contains($0) }
        name = name.split(separator: " ").joined(separator: " ")
        guard name.filter({ $0.isLetter }).count >= 2 else { return nil }
        return (titleCased(name), quantity)
    }

    /// "TRADER JOE'S" -> "Trader Joe's". Text that already has lowercase letters is returned unchanged.
    static func titleCased(_ text: String) -> String {
        guard text.contains(where: { $0.isLetter }), !text.contains(where: { $0.isLowercase }) else { return text }
        return text.split(separator: " ")
            .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    // MARK: - Merchant

    static func merchant(in lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let characters = line.filter { !$0.isWhitespace }
            let letters = characters.filter { $0.isLetter }.count
            let words = tokens(line)
            guard letters >= 3,
                  letters * 2 > characters.count,
                  let first = characters.first, !first.isNumber,
                  trailingAmount(in: line) == nil,
                  !words.contains(where: { merchantStopWords.contains($0) }),
                  !line.lowercased().contains(".com") else { continue }
            return titleCased(line)
        }
        return nil
    }

    // MARK: - Date

    static func date(in line: String, now: Date, calendar: Calendar) -> Date? {
        let numeric = #/(?:^|\D)(\d{1,4})([-/.])(\d{1,2})[-/.](\d{2,4})(?:\D|$)/#
        for match in line.matches(of: numeric) {
            let (first, separator, second, third) = (match.output.1, match.output.2, match.output.3, match.output.4)
            guard let a = Int(first), let b = Int(second), let c = Int(third) else { continue }
            let year, month, day: Int
            if first.count == 4 {
                guard third.count <= 2 else { continue }
                year = a
                month = b
                day = c
            } else {
                guard first.count <= 2, third.count != 3 else { continue }
                year = third.count == 2 ? 2000 + c : c
                let dayFirst = separator == "." || a > 12
                month = dayFirst ? b : a
                day = dayFirst ? a : b
            }
            if let date = makeDate(year: year, month: month, day: day, now: now, calendar: calendar) {
                return date
            }
        }

        let lower = line.lowercased()
        let monthDayYear = #/(?:^|[^a-z])(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})/#
        for match in lower.matches(of: monthDayYear) {
            if let month = months.firstIndex(of: String(match.output.1)),
               let day = Int(match.output.2), let year = Int(match.output.3),
               let date = makeDate(year: year, month: month + 1, day: day, now: now, calendar: calendar) {
                return date
            }
        }
        let dayMonthYear = #/(?:^|\D)(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+(\d{4})/#
        for match in lower.matches(of: dayMonthYear) {
            if let month = months.firstIndex(of: String(match.output.2)),
               let day = Int(match.output.1), let year = Int(match.output.3),
               let date = makeDate(year: year, month: month + 1, day: day, now: now, calendar: calendar) {
                return date
            }
        }
        return nil
    }

    private static func makeDate(year: Int, month: Int, day: Int, now: Date, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        // Range checks, not `<=`/`>=`: the iOS 27 SDK links Date's own `<=`/`>=`, which crash on older iOS.
        guard let oldest = calendar.date(byAdding: .year, value: -10, to: now),
              (oldest...now.addingTimeInterval(86_400)).contains(date) else { return nil }
        return date
    }
}
