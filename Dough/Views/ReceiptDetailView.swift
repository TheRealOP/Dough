import SwiftData
import SwiftUI
import UIKit

struct ReceiptDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var confirmDelete = false
    let receipt: Receipt

    init(receipt: Receipt) {
        self.receipt = receipt
    }

    var body: some View {
        // The receipt can be deleted while this screen is still on the stack.
        if receipt.isDeleted || receipt.modelContext == nil {
            ContentUnavailableView("Receipt Deleted", systemImage: "trash")
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(receipt.total.currencyText)
                        .font(.largeTitle.bold())
                    Text(receipt.date, format: .dateTime.weekday(.wide).month().day().year())
                        .foregroundStyle(.secondary)
                }
            }

            if let data = receipt.imageData, let image = UIImage(data: data) {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                }
            }

            if !receipt.items.isEmpty || receipt.tax != 0 {
                Section("Items") {
                    ForEach(receipt.sortedItems) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.category.symbol)
                                .foregroundStyle(item.category.color)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(item.name.isEmpty ? "Item" : item.name)
                                if item.quantity != 1 {
                                    Text("Qty \(item.quantity.formatted())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(item.price.currencyText)
                                .monospacedDigit()
                        }
                    }
                    if receipt.tax != 0 {
                        LabeledContent("Tax", value: receipt.tax.currencyText)
                    }
                }
            }

            if !receipt.tags.isEmpty || !receipt.note.isEmpty {
                Section("Context") {
                    if !receipt.tags.isEmpty {
                        LabeledContent("Tags", value: receipt.tags.joined(separator: ", "))
                    }
                    if !receipt.note.isEmpty {
                        Text(receipt.note)
                    }
                }
            }
        }
        .navigationTitle(receipt.merchant.isEmpty ? "Unknown store" : receipt.merchant)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ReceiptReviewView(draft: ReceiptDraft(receipt: receipt), existing: receipt)
        }
        .confirmationDialog("Delete this receipt?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Receipt", role: .destructive) {
                dismiss()
                modelContext.delete(receipt)
            }
        }
    }
}
