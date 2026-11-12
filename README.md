# Dough

Dough is an iPhone app that tracks your spending from photos of receipts. Snap a receipt, and Dough reads it on-device, splits it into line items with categories, and saves it. Over time you build your own item-level record of what you actually buy: not just "$140 at the grocery store", but the cereal, the milk, and the $80 of bread because there was a party. Tags and notes on each receipt capture that context, and an on-device model can look over your spending with you.

## Features (v1)

- Scan a receipt with the camera, or pick a photo from your library.
- On-device text recognition and parsing into merchant, date, total, tax and line items.
- Automatic categories per item (groceries, dining, household, …), editable on a review screen.
- Tags and a note on each receipt to explain unusual spending.
- Optional monthly budget.
- Insights for the current month: spend by category, most-bought items, and comparison with last month.
- "Ask Dough": an on-device analysis of your month, or answers to your own questions.
- CSV export and delete-all.

## Requirements

- Xcode 26 (iOS 26 SDK).
- iPhone with iOS 18 or later.
- AI receipt reading and "Ask Dough" use Apple's on-device Foundation Models, so they need iOS 26 on an Apple Intelligence-capable iPhone with Apple Intelligence turned on. Everything else works without them.

## Running

1. Open `Dough.xcodeproj`.
2. Select the Dough target, and under Signing & Capabilities pick your team.
3. Run on a device or simulator.

In the simulator the camera scanner is unavailable: drag a receipt photo into the simulator's Photos app and use "Choose from Photos". In debug builds, Settings → "Load sample data" fills the app with example receipts.

Tests use Swift Testing and run with ⌘U.

> **Note:** the initial code was written without access to a Swift compiler, so the first Xcode build may need a few small fixes.

## How it works

1. **Scan:** VisionKit's document camera (or the photo picker) captures the receipt image.
2. **Read:** Vision's text recognition (OCR) turns the image into lines of text.
3. **Parse:** a heuristic `ReceiptParser` extracts merchant, date, totals and line items. On iOS 26 devices with Apple Intelligence, the on-device language model can improve the result and assign categories.
4. **Review:** you check and fix the parsed receipt, and add tags or a note.
5. **Save:** the receipt and its items are stored with SwiftData.
6. **Insights:** `InsightsEngine` computes category totals and top items for the month and builds a compact text summary that "Ask Dough" hands to the on-device model.

## Project layout

| Path | Contents |
| --- | --- |
| `Dough/Models.swift` | SwiftData models (`Receipt`, `LineItem`), categories, money helpers, budget settings keys |
| `Dough/Scanning/` | Camera/photo capture, OCR, receipt parsing |
| `Dough/Views/` | Home, receipt list, review/edit and settings screens |
| `Dough/Insights/` | `InsightsEngine`, `SpendingAnalyst` (on-device model) and `InsightsView` |
| `DoughTests/` | Unit tests (Swift Testing) |

## Privacy

Everything happens on your iPhone. There are no accounts and no network calls: OCR, parsing and analysis all run on-device, and your receipts are stored only in the app. You can export everything as CSV or delete all data from Settings.

## Scope

v1 follows YAGNI: it does the core loop (scan, review, save, understand) and nothing more. Card linking, receipt/transaction matching, subscription detection and deeper analysis are deliberately left out; see [docs/ROADMAP.md](docs/ROADMAP.md).
