import SwiftData
import SwiftUI

@main
struct DoughApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Home", systemImage: "house") { DashboardView() }
                Tab("Receipts", systemImage: "list.bullet.rectangle") { ReceiptListView() }
                Tab("Insights", systemImage: "chart.pie") { InsightsView() }
                Tab("Settings", systemImage: "gearshape") { SettingsView() }
            }
        }
        .modelContainer(for: [Receipt.self, LineItem.self])
    }
}
