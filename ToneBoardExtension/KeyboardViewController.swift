//
//  KeyboardViewController.swift
//  ToneBoardExtension
//
//  CRITICAL: iOS physically blocks all custom keyboard haptics unless the user toggles
//  "Allow Full Access" in Settings (Settings > General > Keyboard > Keyboards > ToneBoard).
//  Additionally, haptics CANNOT be tested in the Mac Xcode Simulator. You must build
//  and test on a physical iOS device!
//

import UIKit
import SwiftUI
import Combine
import KeyboardKit

class KeyboardViewController: KeyboardInputViewController {
    
    // The App Group ID we set up to fetch the API Key later
    let appGroupID = "group.com.matt.cpplearning.ToneBoard"
    
    // Antigravity Architecture: State trackers
    private var isPolishing: Bool = false
    private var lastInsertedAIString: String?
    
    // Bulletproof Debounce Trackers
    private var lastObservedText = ""
    private var debounceTimer: DispatchWorkItem?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // KeyboardKit v10+ requires explicit view setup via viewWillSetupKeyboardView.
        // We no longer rely on implicit view injection here.
    }
    
    override func viewWillSetupKeyboardView() {
        super.viewWillSetupKeyboardView()
        
        setupKeyboardView { [weak self] controller in
            guard let self = self else { return AnyView(EmptyView()) }
            
            // Enable native haptics globally (required for any haptics to fire in KKv10)
            controller.state.feedbackContext.settings.isHapticFeedbackEnabled = true
            
            // KeyboardKit v10 natively supports heavy impacts via configuration:
            controller.state.feedbackContext.hapticConfiguration.press = .heavyImpact
            controller.state.feedbackContext.hapticConfiguration.release = .heavyImpact
            
            // Enable Real-Time Autocorrect & Autocomplete
            controller.state.autocompleteContext.settings.isAutocompleteEnabled = true
            controller.state.autocompleteContext.settings.isAutocorrectEnabled = true
            
            // Injecting the native KeyboardView
            // By omitting view builders, KeyboardKit provides the standard AutocompleteToolbar automatically
            let view = KeyboardView(
                services: controller.services
            )
            return AnyView(view)
        }
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        
        let currentText = textDocumentProxy.documentContextBeforeInput ?? ""
        
        // Safety Check 1: Do not start timer if actively polishing
        if isPolishing {
            return
        }
        
        // Safety Check 2: Prevent infinite loop of the AI polishing its own text
        if let inserted = lastInsertedAIString {
            if currentText.hasSuffix(inserted) {
                // This textDidChange was likely fired by our own insertion.
                lastObservedText = currentText
                return
            } else {
                // User has modified the text, clear the lock so we can polish again later
                lastInsertedAIString = nil
            }
        }
        
        // CRITICAL: ONLY cancel and restart the timer if the text has actually changed.
        // This ignores phantom events like cursor blinks.
        if currentText == lastObservedText {
            return
        }
        
        lastObservedText = currentText
        
        debounceTimer?.cancel()
        
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return
        }
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task {
                await self.triggerAutoPolish(draftText: currentText)
            }
        }
        
        debounceTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: workItem)
    }
    
    @MainActor
    private func triggerAutoPolish(draftText: String) async {
        guard !isPolishing else { return }
        
        isPolishing = true
        
        // HAPTIC: 0.7s debounce finished, AI gets to work
        let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
        rigidHaptic.prepare()
        rigidHaptic.impactOccurred()
        
        let defaults = UserDefaults(suiteName: appGroupID)
        let savedKey = defaults?.string(forKey: "apiKey") ?? ""
        let tone = defaults?.string(forKey: "selectedTone") ?? "Professional"
        
        let apiKey = savedKey.isEmpty ? "YOUR_API_KEY_HERE" : savedKey
        
        do {
            let polishedText = try await fetchPolishedText(draft: draftText, tone: tone, apiKey: apiKey)
            
            // API Latency Optimization & State Management:
            // Verify the user hasn't typed anything else while we were waiting for the AI
            let currentContext = textDocumentProxy.documentContextBeforeInput ?? ""
            guard currentContext == draftText else {
                // The context changed during the API call, abort safely!
                isPolishing = false
                return
            }
            
            lastInsertedAIString = polishedText
            
            let codeUnitCount = draftText.utf16.count
            
            // HAPTIC: Zipper erasing effect loop
            let softHaptic = UIImpactFeedbackGenerator(style: .soft)
            softHaptic.prepare()
            
            // Antigravity Architecture: Deterministic exact UTF-16 deletion
            for _ in 0..<codeUnitCount {
                textDocumentProxy.deleteBackward()
                softHaptic.impactOccurred()
            }
            
            // Insert the new text natively
            textDocumentProxy.insertText(polishedText)
            
            // HAPTIC: Satisfying success bump (Apple Pay double-bump)
            let successHaptic = UINotificationFeedbackGenerator()
            successHaptic.prepare()
            successHaptic.notificationOccurred(.success)
            
        } catch {
            // Check if context has changed before inserting error; standard safety check
            let currentContext = textDocumentProxy.documentContextBeforeInput ?? ""
            guard currentContext == draftText else {
                isPolishing = false
                return
            }
            
            // HAPTIC: API failed warning
            let errorHaptic = UINotificationFeedbackGenerator()
            errorHaptic.prepare()
            errorHaptic.notificationOccurred(.error)
            
            // Write the error directly into the text field so we can see what failed!
            textDocumentProxy.insertText(" [API Error: \(error.localizedDescription)] ")
        }
        
        isPolishing = false
    }
    
    // MARK: - API Network Layer
    
    private func fetchPolishedText(draft: String, tone: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are a silent, invisible keyboard autocorrect assistant. The user will provide a rough draft.
        1. Fix all spelling, grammar, and syntax errors.
        2. Adjust the tone to be \(tone).
        3. CRITICAL INSTRUCTION: Output ONLY the raw corrected text. Do NOT wrap in quotes. Do NOT add markdown. Do NOT use emojis unless expressly asked. Do NOT include conversational filler.
        """
        
        let body: [String: Any] = [
            "model": "grok-4-1-fast-reasoning", // Using the fast reasoning model
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": draft]
            ],
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            struct APIError: LocalizedError {
                let msg: String
                var errorDescription: String? { return msg }
            }
            throw APIError(msg: "HTTP \(code) - \(responseBody)")
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            
            // Strip chain-of-thought inside <think>...</think> tags if reasoning models are used.
            let strippedContent = content.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            return strippedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        throw URLError(.cannotParseResponse)
    }
}
