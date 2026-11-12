import SwiftData
import SwiftUI

struct ReceiptListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @State private var showScanner = false

    private struct MonthGroup: Identifiable {
        let month: Date
        var receipts: [Receipt]
        var id: Date { month }
        var total: Decimal { receipts.reduce(0) { $0 + $1.total } }
    }

    private var groups: [MonthGroup] {
        var result: [MonthGroup] = []
        for receipt in receipts {
            let month = Calendar.current.dateInterval(of: .month, for: receipt.date)?.start ?? receipt.date
            if result.last?.month == month {
                result[result.count - 1].receipts.append(receipt)
            } else {
                result.append(MonthGroup(month: month, receipts: [receipt]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if receipts.isEmpty {
                    ContentUnavailableView {
                        Label("No Receipts", systemImage: "doc.text.viewfinder")
                    } description: {
                        Text("Scan a receipt to start tracking your spending.")
                    } actions: {
                        Button("Scan a receipt") { showScanner = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.receipts) { receipt in
                                    NavigationLink(value: receipt) {
                                        ReceiptRow(receipt: receipt)
                                    }
                                }
                                .onDelete { offsets in
                                    for index in offsets {
                                        modelContext.delete(group.receipts[index])
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(group.month, format: .dateTime.month(.wide).year())
                                    Spacer()
                                    Text(group.total.currencyText)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Receipts")
            .navigationDestination(for: Receipt.self) { ReceiptDetailView(receipt: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Receipt", systemImage: "plus") { showScanner = true }
                }
            }
        }
        .receiptScanner(isPresented: $showScanner)
    }
}
