import SwiftUI

@main
struct PulseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Load persisted LLM log from disk.
                    // AnthropicClient reads sharedLLMLogStore at call time,
                    // so this just needs to complete before the first API call.
                    sharedLLMLogStore = await LLMInteractionStore.load()
                }
        }
    }
}
