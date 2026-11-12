import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Receipt.date) private var receipts: [Receipt]
    @AppStorage(BudgetSettings.enabledKey) private var budgetEnabled = false
    @AppStorage(BudgetSettings.amountKey) private var budgetAmount = 0.0
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Monthly budget", isOn: $budgetEnabled)
                    if budgetEnabled {
                        LabeledContent("Amount") {
                            TextField("Amount", value: $budgetAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Budget")
                } footer: {
                    Text("Optional. Each receipt is subtracted from this amount every month.")
                }

                Section {
                    ShareLink(
                        item: CSVExport(records: receipts.map(\.record)),
                        preview: SharePreview("Dough receipts.csv")
                    ) {
                        Label("Export as CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(receipts.isEmpty)

                    Button("Delete all data", role: .destructive) { confirmDeleteAll = true }
                        .disabled(receipts.isEmpty)
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything stays on this iPhone. Export it any time — it's yours.")
                }

                #if DEBUG
                Section("Developer") {
                    Button("Load sample data", action: loadSampleData)
                }
                #endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { endEditing() }
                }
            }
            .confirmationDialog(
                "Delete all \(receipts.count) receipts?",
                isPresented: $confirmDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    for receipt in receipts {
                        modelContext.delete(receipt)
                    }
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    #if DEBUG
    private func loadSampleData() {
        struct Sample {
            var monthsAgo: Int
            var day: Int
            var merchant: String
            var items: [(String, String, SpendingCategory)]
            var tax = "0"
            var tags: [String] = []
            var note = ""
        }

        let samples: [Sample] = [
            Sample(monthsAgo: 0, day: 1, merchant: "Trader Joe's", items: [("Bread", "3.99", .groceries), ("Milk", "4.29", .groceries), ("Bananas", "1.74", .groceries)]),
            Sample(monthsAgo: 0, day: 3, merchant: "Shell", items: [("Unleaded 11.2 gal", "42.10", .transport)]),
            Sample(monthsAgo: 0, day: 4, merchant: "Corner Bakery", items: [("Bread", "4.25", .groceries)]),
            Sample(monthsAgo: 0, day: 6, merchant: "Chipotle", items: [("Burrito bowl", "11.45", .dining), ("Chips & guac", "4.95", .dining)], tax: "1.34"),
            Sample(monthsAgo: 0, day: 8, merchant: "CVS Pharmacy", items: [("Ibuprofen", "8.99", .health), ("Toothpaste", "4.49", .personalCare)], tax: "0.92"),
            Sample(monthsAgo: 0, day: 9, merchant: "Corner Bakery", items: [("Bread", "4.25", .groceries)]),
            Sample(monthsAgo: 0, day: 10, merchant: "Sweet Crumb Bakery", items: [("Sourdough loaves x6", "42.00", .groceries), ("Baguettes x8", "28.00", .groceries), ("Focaccia", "10.00", .groceries)], tags: ["party"], note: "Bread for Sam's birthday party"),
            Sample(monthsAgo: 0, day: 11, merchant: "Safeway", items: [("Bread", "3.79", .groceries), ("Eggs", "5.49", .groceries), ("Paper towels", "9.99", .household), ("Chicken thighs", "11.82", .groceries)], tax: "0.82"),
            Sample(monthsAgo: 1, day: 2, merchant: "Safeway", items: [("Bread", "3.79", .groceries), ("Apples", "4.58", .groceries), ("Dish soap", "3.49", .household)], tax: "0.29"),
            Sample(monthsAgo: 1, day: 5, merchant: "Chevron", items: [("Unleaded 10.4 gal", "39.52", .transport)]),
            Sample(monthsAgo: 1, day: 9, merchant: "Corner Bakery", items: [("Bread", "4.25", .groceries)]),
            Sample(monthsAgo: 1, day: 14, merchant: "Olive Garden", items: [("Dinner for two", "48.60", .dining)], tax: "4.25", tags: ["work"]),
            Sample(monthsAgo: 1, day: 18, merchant: "Walgreens", items: [("Allergy relief", "14.99", .health), ("Shampoo", "6.99", .personalCare)], tax: "1.76"),
            Sample(monthsAgo: 1, day: 22, merchant: "AMC Theatres", items: [("Tickets x2", "29.98", .entertainment), ("Popcorn", "8.50", .dining)]),
            Sample(monthsAgo: 1, day: 27, merchant: "Trader Joe's", items: [("Bread", "3.99", .groceries), ("Coffee", "8.99", .groceries), ("Frozen dumplings", "4.49", .groceries)]),
        ]

        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now

        for sample in samples {
            let month = calendar.date(byAdding: .month, value: -sample.monthsAgo, to: startOfMonth) ?? startOfMonth
            let day = calendar.date(byAdding: .day, value: sample.day - 1, to: month) ?? month

            var draft = ReceiptDraft()
            draft.merchant = sample.merchant
            draft.date = min(day.addingTimeInterval(12 * 3600), .now)
            draft.items = sample.items.map {
                ReceiptDraft.Item(name: $0.0, quantity: 1, price: Decimal(string: $0.1)!, category: $0.2)
            }
            draft.tax = Decimal(string: sample.tax)!
            draft.total = draft.itemsSum + draft.tax
            draft.tags = sample.tags
            draft.note = sample.note

            let receipt = Receipt()
            modelContext.insert(receipt)
            draft.apply(to: receipt, in: modelContext)
        }
    }
    #endif
}

/// CSV export of plain receipt values, written to a temporary file when shared.
struct CSVExport: Transferable {
    let records: [SpendingRecord]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dough receipts.csv")
            try export.csv.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    var csv: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var lines = ["date,merchant,receipt_total,tax,item,quantity,price,category,tags,note"]
        for record in records {
            let head = [formatter.string(from: record.date), record.merchant, "\(record.total)", "\(record.tax)"]
            let tail = [record.tags.joined(separator: ";"), record.note]
            let items: [[String]] = record.items.isEmpty
                ? [["", "", "", ""]]
                : record.items.map { [$0.name, "\($0.quantity)", "\($0.price)", $0.category.displayName] }
            for item in items {
                lines.append((head + item + tail).map(Self.escape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
