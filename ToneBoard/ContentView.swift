import SwiftUI

enum ToneOption: String, CaseIterable {
    case professional = "Professional"
    case casual = "Casual"
    case witty = "Witty"
    case genZ = "Gen-Z"
}

struct ContentView: View {
    let appGroupID = "group.com.matt.cpplearning.ToneBoard"
    
    @AppStorage("apiKey", store: UserDefaults(suiteName: "group.com.matt.cpplearning.ToneBoard"))
    var apiKey: String = ""
    
    @AppStorage("selectedTone", store: UserDefaults(suiteName: "group.com.matt.cpplearning.ToneBoard"))
    var selectedTone: ToneOption = .professional
    
    @AppStorage("apiUrl", store: UserDefaults(suiteName: "group.com.matt.cpplearning.ToneBoard"))
    var apiUrl: String = "http://127.0.0.1:1234/v1"
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Configuration"), footer: Text("Your API key is stored locally in the App Group and shared securely with the keyboard extension.")) {
                    SecureField("xAI / Groq API Key", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        
                    TextField("API Base URL", text: $apiUrl)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    
                    Picker("Auto-Polish Tone", selection: $selectedTone) {
                        ForEach(ToneOption.allCases, id: \.self) { tone in
                            Text(tone.rawValue).tag(tone)
                        }
                    }
                }
                
                Section(header: Text("Keyboard Setup")) {
                    Button(action: openSettings) {
                        HStack {
                            Text("1. Open Settings")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                        }
                    }
                    
                    Text("2. Go to Keyboards")
                    Text("3. Enable 'ToneBoardExtension'")
                    Text("4. Enable 'Allow Full Access'")
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("ToneBoard")
        }
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}