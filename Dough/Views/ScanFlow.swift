import PhotosUI
import SwiftUI
import UIKit

/// Add-a-receipt flow: choose a source, read the photo, then review.
struct ReceiptScanner: ViewModifier {
    @Binding var isPresented: Bool
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var draft: ReceiptDraft?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Add a receipt", isPresented: $isPresented, titleVisibility: .visible) {
                if DocumentScannerView.isSupported {
                    Button("Scan with Camera") { showCamera = true }
                }
                Button("Choose from Photos") { showPhotos = true }
                Button("Enter Manually") { draft = ReceiptDraft() }
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentScannerView(
                    onScan: { images in
                        showCamera = false
                        Task { await read(images) }
                    },
                    onCancel: { showCamera = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                isProcessing = true
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    if let data, let image = UIImage(data: data) {
                        await read([image])
                    } else {
                        isProcessing = false
                    }
                }
            }
            .overlay {
                if isProcessing {
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea()
                        ProgressView("Reading receipt…")
                    }
                }
            }
            .sheet(item: $draft) { draft in
                ReceiptReviewView(draft: draft)
            }
    }

    @MainActor
    private func read(_ images: [UIImage]) async {
        isProcessing = true
        let result = await ReceiptProcessor.process(images: images)
        isProcessing = false
        draft = result
    }
}

extension View {
    func receiptScanner(isPresented: Binding<Bool>) -> some View {
        modifier(ReceiptScanner(isPresented: isPresented))
    }
}
