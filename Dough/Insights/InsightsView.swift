import Charts
import SwiftData
import SwiftUI

/// Spending insights for the current calendar month.
struct InsightsView: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @AppStorage(BudgetSettings.enabledKey) private var budgetEnabled = false
    @AppStorage(BudgetSettings.amountKey) private var budgetAmount = 0.0
    @State private var analyst = SpendingAnalyst()
    @State private var question = ""

    var body: some View {
        let months = splitByMonth()
        NavigationStack {
            Group {
                if months.current.isEmpty {
                    ContentUnavailableView(
                        "No Receipts This Month",
                        systemImage: "chart.bar",
                        description: Text("Scan a receipt to see where your money goes.")
                    )
                } else {
                    content(current: months.current, previous: months.previous)
                }
            }
            .navigationTitle("Insights")
        }
    }

    private func content(current: [SpendingRecord], previous: [SpendingRecord]) -> some View {
        let spent = Self.total(current)
        let lastSpent = Self.total(previous)
        let categories = InsightsEngine.categoryTotals(current)
        let items = InsightsEngine.topItems(current, limit: 8)

        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spent this month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(spent.currencyText)
                        .font(.largeTitle.bold())
                    Text(current.count == 1 ? "1 receipt" : "\(current.count) receipts")
                    Text("Last month: \(lastSpent.currencyText)")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Where it went") {
                Chart(categories) { entry in
                    BarMark(
                        x: .value("Amount", Money.double(entry.amount)),
                        y: .value("Category", entry.category.displayName)
                    )
                    .foregroundStyle(entry.category.color)
                    .annotation(position: .trailing) {
                        Text(entry.amount.currencyText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(categories.count) * 36)
                .padding(.vertical, 4)
            }

            if !items.isEmpty {
                Section("Most bought") {
                    ForEach(items) { item in
                        HStack {
                            Text(item.name)
                            Text("×\(item.count)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(item.spend.currencyText)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
                if let reason = SpendingAnalyst.unavailableReason {
                    Text(reason)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Analyze my spending", systemImage: "sparkles") {
                        ask(nil, current: current, previous: previous)
                    }
                    .buttonStyle(.borderless)
                    .disabled(analyst.isWorking)

                    HStack {
                        TextField("Ask a question", text: $question)
                            .onSubmit { askQuestion(current: current, previous: previous) }
                        Button {
                            askQuestion(current: current, previous: previous)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(analyst.isWorking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send")
                    }

                    if analyst.isWorking {
                        ProgressView()
                    }
                    if !analyst.answer.isEmpty {
                        Text(analyst.answer)
                            .textSelection(.enabled)
                    }
                    if let error = analyst.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Ask Dough")
            } footer: {
                Text("Runs entirely on your iPhone. Your data never leaves the device.")
            }
        }
    }

    private func askQuestion(current: [SpendingRecord], previous: [SpendingRecord]) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        ask(text, current: current, previous: previous)
    }

    private func ask(_ question: String?, current: [SpendingRecord], previous: [SpendingRecord]) {
        let budget: Decimal? = budgetEnabled && budgetAmount > 0 ? Money.decimal(budgetAmount) : nil
        let context = InsightsEngine.aiContext(
            current: current,
            previous: previous,
            periodName: Date.now.formatted(.dateTime.month(.wide).year()),
            budget: budget
        )
        Task { await analyst.ask(question, context: context) }
    }

    /// Records for this calendar month and the previous one.
    private func splitByMonth() -> (current: [SpendingRecord], previous: [SpendingRecord]) {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: .now),
              let lastMonthDay = calendar.date(byAdding: .month, value: -1, to: thisMonth.start),
              let lastMonth = calendar.dateInterval(of: .month, for: lastMonthDay)
        else { return ([], []) }

        var current: [SpendingRecord] = []
        var previous: [SpendingRecord] = []
        for receipt in receipts {
            let date = receipt.date
            if date >= thisMonth.start && date < thisMonth.end {
                current.append(receipt.record)
            } else if date >= lastMonth.start && date < lastMonth.end {
                previous.append(receipt.record)
            }
        }
        return (current, previous)
    }

    private static func total(_ records: [SpendingRecord]) -> Decimal {
        records.reduce(Decimal(0)) { $0 + $1.total }
    }
}
