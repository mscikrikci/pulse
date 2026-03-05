import SwiftUI

struct PendingChatContext: Equatable {
    /// Shown as an assistant bubble in Chat — not sent to the API.
    let uiPreamble: String
    /// Injected into the LLM context so the model has full check-in awareness.
    let checkInContext: String
    /// Pre-filled in the input field. User reviews and sends manually.
    let prefillText: String
}

struct ContentView: View {
    @State private var selectedTab: String = "today"
    @State private var pendingChat: PendingChatContext? = nil
    @State private var showLLMLog = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "sun.max", value: "today") {
                TodayView(onOpenChat: { ctx in
                    pendingChat = ctx
                    selectedTab = "chat"
                })
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: "progress") {
                GoalProgressTab()
            }
            Tab("Goals", systemImage: "target", value: "goals") {
                GoalsView()
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: "chat") {
                ChatView(pendingChat: $pendingChat)
            }
            Tab("Settings", systemImage: "gearshape", value: "settings") {
                SettingsView()
            }
        }
        // Long-press anywhere on the tab bar for 2 seconds to open the LLM debug log.
        .onLongPressGesture(minimumDuration: 2) {
            showLLMLog = true
        }
        .sheet(isPresented: $showLLMLog) {
            NavigationStack {
                LLMLogView(logStore: sharedLLMLogStore)
            }
        }
    }
}
