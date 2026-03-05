import SwiftUI

struct SettingsView: View {

    @State private var apiKeyInput: String = APIKeyStore.load() ?? ""
    @State private var isShowingKey = false
    @State private var savedConfirmation = false
    @State private var showMemoryDebug = false

    private var isKeyFromPlist: Bool {
        UserDefaults.standard.string(forKey: "anthropicAPIKey") == nil && APIKeyStore.isConfigured
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: API Key
                Section {
                    HStack(spacing: 8) {
                        Group {
                            if isShowingKey {
                                TextField("sk-ant-api03-...", text: $apiKeyInput)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .font(.system(.footnote, design: .monospaced))
                            } else {
                                SecureField("sk-ant-api03-...", text: $apiKeyInput)
                                    .font(.system(.footnote, design: .monospaced))
                            }
                        }
                        Button {
                            isShowingKey.toggle()
                        } label: {
                            Image(systemName: isShowingKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Save Key") {
                        APIKeyStore.save(apiKeyInput)
                        savedConfirmation = true
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !apiKeyInput.isEmpty {
                        Button("Clear", role: .destructive) {
                            APIKeyStore.clear()
                            apiKeyInput = ""
                        }
                    }
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    if isKeyFromPlist {
                        Text("Currently using key from Config.plist. Save a key here to override it.")
                    } else {
                        Text("Required for all AI features. Get your key at console.anthropic.com")
                    }
                }

                // MARK: Debug
                Section("Debug") {
                    Button("Memory Inspector") {
                        showMemoryDebug = true
                    }
                }

                // MARK: About
                Section("About") {
                    LabeledContent("App", value: "Pulse")
                    LabeledContent("Model (daily)", value: "claude-haiku-4-5")
                    LabeledContent("Model (analysis)", value: "claude-sonnet-4-6")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showMemoryDebug) {
                NavigationStack {
                    MemoryDebugView()
                }
            }
            .alert("API Key Saved", isPresented: $savedConfirmation) {
                Button("OK") {}
            } message: {
                Text("Your key has been saved. All AI features will use it immediately.")
            }
        }
    }
}
