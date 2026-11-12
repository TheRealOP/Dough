import SwiftData
import SwiftUI
import UIKit

struct ReceiptReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReceiptDraft
    @State private var newTag = ""
    private let existing: Receipt?

    private static let suggestedTags = ["party", "work", "gift", "travel", "bulk"]

    init(draft: ReceiptDraft, existing: Receipt? = nil) {
        _draft = State(initialValue: draft)
        self.existing = existing
    }

    private var expectedTotal: Decimal { draft.itemsSum + draft.tax }

    private var totalMismatch: Bool {
        guard !draft.items.isEmpty else { return false }
        return abs(expectedTotal - draft.total) > Decimal(string: "0.05")!
    }

    private var tagOptions: [String] {
        draft.tags + Self.suggestedTags.filter { !draft.tags.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let notice = draft.notice {
                    Section {
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if let data = draft.imageData, let image = UIImage(data: data) {
                    Section {
                        Color.clear
                            .frame(height: 160)
                            .overlay {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipped()
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section("Purchase") {
                    TextField("Store", text: $draft.merchant)
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                }

                Section {
                    ForEach($draft.items) { $item in
                        VStack {
                            HStack {
                                TextField("Item", text: $item.name)
                                moneyField("Price", value: $item.price)
                                    .frame(maxWidth: 100)
                            }
                            HStack {
                                Picker("Category", selection: $item.category) {
                                    ForEach(SpendingCategory.allCases) { category in
                                        Label(category.displayName, systemImage: category.symbol)
                                            .tag(category)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                Spacer()
                                Stepper("Qty \(item.quantity.formatted())", value: $item.quantity, in: 1...999)
                                    .fixedSize()
                            }
                        }
                    }
                    .onDelete { draft.items.remove(atOffsets: $0) }

                    Button("Add item", systemImage: "plus") {
                        draft.items.append(ReceiptDraft.Item())
                    }
                } header: {
                    Text("Items")
                } footer: {
                    Text("Items add up to \(draft.itemsSum.currencyText)")
                }

                Section("Totals") {
                    LabeledContent("Tax") {
                        moneyField("Tax", value: $draft.tax)
                    }
                    LabeledContent("Total") {
                        moneyField("Total", value: $draft.total)
                            .bold()
                    }
                    if totalMismatch {
                        Label("Items and tax don't match the total.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Use items + tax (\(expectedTotal.currencyText))") {
                            draft.total = expectedTotal
                        }
                    }
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(tagOptions, id: \.self) { tag in
                                let selected = draft.tags.contains(tag)
                                Button(tag) { toggle(tag) }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                                    .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                    TextField("Add a tag", text: $newTag)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit(addTag)
                    TextField("Note", text: $draft.note, axis: .vertical)
                } header: {
                    Text("Context")
                } footer: {
                    Text("Tags and notes help explain unusual spending later.")
                }
            }
            .navigationTitle(existing == nil ? "New Receipt" : "Edit Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.total == 0 && draft.items.isEmpty)
                }
            }
        }
    }

    private func moneyField(_ title: String, value: Binding<Decimal>) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(2)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
    }

    private func toggle(_ tag: String) {
        if let index = draft.tags.firstIndex(of: tag) {
            draft.tags.remove(at: index)
        } else {
            draft.tags.append(tag)
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty && !draft.tags.contains(tag) {
            draft.tags.append(tag)
        }
        newTag = ""
    }

    private func save() {
        let receipt: Receipt
        if let existing {
            receipt = existing
        } else {
            receipt = Receipt()
            modelContext.insert(receipt)
        }
        draft.apply(to: receipt, in: modelContext)
        dismiss()
    }
}
