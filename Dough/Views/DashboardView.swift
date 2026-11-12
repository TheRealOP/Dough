import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @AppStorage(BudgetSettings.enabledKey) private var budgetEnabled = false
    @AppStorage(BudgetSettings.amountKey) private var budgetAmount = 0.0
    @AppStorage(BudgetSettings.startingKey) private var budgetStarting = 0.0
    @AppStorage(BudgetSettings.startKey) private var budgetStart = 0.0
    @State private var showScanner = false

    private var spent: Decimal {
        receipts
            .filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.total }
    }

    /// What was available at the start of this month: the bucket balance with this month's spending added back.
    private var budget: Decimal? {
        guard budgetEnabled, budgetAmount > 0 || budgetStarting > 0 else { return nil }
        return InsightsEngine.budgetBalance(
            starting: Money.decimal(budgetStarting),
            monthly: Money.decimal(budgetAmount),
            start: budgetStart > 0 ? Date(timeIntervalSinceReferenceDate: budgetStart) : .now,
            spending: receipts.map { ($0.date, $0.total) }
        ) + spent
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    budgetCard
                }

                Section {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan a receipt", systemImage: "doc.text.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Recent") {
                    if receipts.isEmpty {
                        Text("No receipts yet. Scan one to get started.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(receipts.prefix(5)) { receipt in
                            NavigationLink(value: receipt) {
                                ReceiptRow(receipt: receipt)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Dough")
            .navigationDestination(for: Receipt.self) { ReceiptDetailView(receipt: $0) }
        }
        .receiptScanner(isPresented: $showScanner)
    }

    private var budgetCard: some View {
        VStack(spacing: 12) {
            Text(Date.now, format: .dateTime.month(.wide))
                .font(.headline)

            if let budget {
                let used = budget > 0 ? Money.double(spent / budget) : 2
                let progress = min(max(used, 0), 1)
                let remaining = budget - spent
                let color: Color = used > 1 ? .red : (used > 0.8 ? .orange : .green)
                let remainingText: String = remaining < 0
                    ? "\((-remaining).currencyText) over"
                    : "\(remaining.currencyText) left"

                ZStack {
                    Circle()
                        .stroke(color.opacity(0.2), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(remainingText)
                            .font(.title2.bold())
                            .foregroundStyle(remaining < 0 ? Color.red : Color.primary)
                        Text("of \(budget.currencyText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)

                Text("Spent \(spent.currencyText) this month")
                    .foregroundStyle(.secondary)
            } else {
                Text("Spent \(spent.currencyText) this month")
                    .font(.title2.bold())
                Text("You can set a monthly budget in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}

/// One receipt in a list: category icon, store, date, tags and total.
struct ReceiptRow: View {
    let receipt: Receipt

    private var category: SpendingCategory {
        receipt.items.max { $0.price < $1.price }?.category ?? .other
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .foregroundStyle(category.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant.isEmpty ? "Unknown store" : receipt.merchant)
                    .font(.headline)
                Text(receipt.date, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !receipt.tags.isEmpty {
                    Text(receipt.tags.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(receipt.total.currencyText)
                .monospacedDigit()
        }
    }
}
