//
//  ChatbotView.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/27/25.
//

import SwiftUI
import Combine
import Speech
import AVFoundation
import MapKit
import UIKit

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    var errorState: Bool = false
    var isHelpful: Bool = false
    var isPinned: Bool = false
    
    // For retry functionality
    var failedToSend: Bool {
        errorState && isUser
    }
}

class ChatbotViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var showSuggestions: Bool = false
    @Published var showHeartBurst: Bool = false
    @Published var heartBurstPosition: CGPoint = .zero
    @Published var showMagicPreview: Bool = false
    @Published var magicPreviewComment: String = ""
    @Published var isGeneratingMagic: Bool = false
    @Published var isRecording: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    // Use the shared UserViewModel from the app (injected by the view) to avoid
    // spinning up an extra Firestore listener / console spam on first open in Debug.
    private weak var userViewModel: UserViewModel?
    private(set) var introMessageId: UUID?
    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    
    var pinnedMessages: [ChatMessage] {
        messages.filter { $0.isPinned }
    }
    
    init() {
        // Add initial welcome message (will be updated when first name loads)
        let intro = ChatMessage(
            content: "Hi! I'm Dumpling Hero, your friendly guide to all things delicious at Dumpling House! 🥟✨ What can I help you with today?",
            isUser: false,
            timestamp: Date()
        )
        messages.append(intro)
        introMessageId = intro.id
    }

    /// Attaches the app's shared UserViewModel. Safe to call multiple times.
    func attachUserViewModel(_ userVM: UserViewModel) {
        // Avoid re-subscribing if we're already attached to the same instance.
        if self.userViewModel === userVM { return }
        self.userViewModel = userVM

        // If a name is already loaded, update immediately.
        let existing = userVM.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty {
            updateGreetingMessage(with: existing)
        }

        // Listen for changes to the user's first name and update the greeting
        userVM.$firstName
            .dropFirst() // Skip the initial empty value
            .filter { !$0.isEmpty } // Only update when we have a real first name
            .sink { [weak self] firstName in
                self?.updateGreetingMessage(with: firstName)
            }
            .store(in: &cancellables)
    }
    
    private func updateGreetingMessage(with firstName: String) {
        // Update the first message (greeting) with the user's first name
        if !messages.isEmpty {
            messages[0] = ChatMessage(
                content: "Hi, \(firstName)! I'm Dumpling Hero, your friendly guide to all things delicious at Dumpling House! 🥟✨ What can I help you with today?",
                isUser: false,
                timestamp: Date()
            )
        }
    }
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = ChatMessage(
            content: inputText,
            isUser: true,
            timestamp: Date()
        )
        
        messages.append(userMessage)
        let messageToSend = inputText
        inputText = ""
        isLoading = true
        showSuggestions = false
        
        // Prepare conversation history
        let conversationHistory = messages.map { message in
            [
                "role": message.isUser ? "user" : "assistant",
                "content": message.content
            ]
        }
        
        // Send to backend
        guard let url = URL(string: "\(Config.backendURL)/chat") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "message": messageToSend,
            "conversation_history": conversationHistory,
            "userFirstName": userViewModel?.firstName ?? "",
            "userPoints": userViewModel?.points ?? 0,
            "userPreferences": [
                "likesSpicyFood": userViewModel?.likesSpicyFood ?? false,
                "dislikesSpicyFood": userViewModel?.dislikesSpicyFood ?? false,
                "hasPeanutAllergy": userViewModel?.hasPeanutAllergy ?? false,
                "isVegetarian": userViewModel?.isVegetarian ?? false,
                "hasLactoseIntolerance": userViewModel?.hasLactoseIntolerance ?? false,
                "doesntEatPork": userViewModel?.doesntEatPork ?? false,
                "hasCompletedPreferences": userViewModel?.hasCompletedPreferences ?? false
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DebugLogger.debug("Error serializing request: \(error)", category: "Chatbot")
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: ChatResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoading = false
                    if case .failure(let error) = completion {
                        DebugLogger.debug("Error: \(error)", category: "Chatbot")
                        self.messages.append(ChatMessage(
                            content: "Sorry, I'm having trouble connecting right now. Please try again!",
                            isUser: false,
                            timestamp: Date()
                        ))
                    }
                },
                receiveValue: { response in
                    // End loading immediately so glow begins fading as bubble arrives
                    self.isLoading = false
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                        self.messages.append(ChatMessage(
                            content: response.response,
                            isUser: false,
                            timestamp: Date()
                        ))
                    }
                    if !UIAccessibility.isReduceMotionEnabled {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func sendSuggestion(_ suggestion: String) {
        inputText = suggestion
        showSuggestions = false
        sendMessage()
    }
    
    // MARK: - UX Polish Methods
    
    func copyMessage(_ message: ChatMessage) {
        UIPasteboard.general.string = message.content
        // Could show a toast here
    }
    
    func shareMessage(_ message: ChatMessage) {
        let activityVC = UIActivityViewController(
            activityItems: [message.content],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    func retryMessage(_ message: ChatMessage) {
        // Remove failed message
        messages.removeAll { $0.id == message.id }
        // Resend
        inputText = message.content
        sendMessage()
    }
    
    func toggleHelpful(_ message: ChatMessage, at position: CGPoint) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            var updated = messages[index]
            updated.isHelpful.toggle()
            messages[index] = updated
            
            // Trigger heart burst animation
            if updated.isHelpful {
                heartBurstPosition = position
                showHeartBurst = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.showHeartBurst = false
                }
            }
        }
    }
    
    func togglePin(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            var updated = messages[index]
            updated.isPinned.toggle()
            messages[index] = updated
        }
    }
    
    func regenerateLastResponse() {
        // Regenerate: immediately remove the last assistant bubble from UI,
        // do NOT add a duplicate user message, and request a different variation.
        guard let lastAssistantIndex = messages.lastIndex(where: { !$0.isUser }),
              let lastUserMessage = messages[..<lastAssistantIndex].last(where: { $0.isUser }) else { return }

        // 1) Remove old assistant response immediately from screen
        let conversationSlice = Array(messages.prefix(lastAssistantIndex))
        messages = conversationSlice
        isLoading = true

        // 2) Build conversation history up to the prior user message
        let conversationHistory = conversationSlice.map { message in
            [
                "role": message.isUser ? "user" : "assistant",
                "content": message.content
            ]
        }

        // 3) Send request with a hint to vary the answer (server will ignore if unsupported)
        guard let url = URL(string: "\(Config.backendURL)/chat") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let variedPrompt = lastUserMessage.content + " (Please provide a different variation; avoid repeating earlier phrasing.)"
        let requestBody: [String: Any] = [
            "message": variedPrompt,
            "conversation_history": conversationHistory,
            "userFirstName": userViewModel?.firstName ?? "",
            "userPoints": userViewModel?.points ?? 0,
            "userPreferences": [
                "likesSpicyFood": userViewModel?.likesSpicyFood ?? false,
                "dislikesSpicyFood": userViewModel?.dislikesSpicyFood ?? false,
                "hasPeanutAllergy": userViewModel?.hasPeanutAllergy ?? false,
                "isVegetarian": userViewModel?.isVegetarian ?? false,
                "hasLactoseIntolerance": userViewModel?.hasLactoseIntolerance ?? false,
                "doesntEatPork": userViewModel?.doesntEatPork ?? false,
                "hasCompletedPreferences": userViewModel?.hasCompletedPreferences ?? false
            ],
            "regenerate": true
        ]

        do { request.httpBody = try JSONSerialization.data(withJSONObject: requestBody) } catch { return }

        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: ChatResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoading = false
                    if case .failure(let error) = completion {
                        self.messages.append(ChatMessage(content: "Sorry, I'm having trouble connecting right now. Please try again!", isUser: false, timestamp: Date()))
                        DebugLogger.debug("Regenerate error: \(error)", category: "Chatbot")
                    }
                },
                receiveValue: { response in
                    self.isLoading = false
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                        self.messages.append(ChatMessage(content: response.response, isUser: false, timestamp: Date()))
                    }
                    if !UIAccessibility.isReduceMotionEnabled {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Community Magic Methods
    
    func generateMagicCommentPreview() {
        isGeneratingMagic = true
        
        guard let url = URL(string: "\(Config.backendURL)/preview-dumpling-hero-comment") else {
            isGeneratingMagic = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use last assistant message as context
        let lastMessage = messages.last(where: { !$0.isUser })?.content ?? ""
        
        let requestBody: [String: Any] = [
            "prompt": lastMessage,
            "postContext": [:]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DebugLogger.debug("Error serializing magic preview request: \(error)", category: "Chatbot")
            isGeneratingMagic = false
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: MagicPreviewResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isGeneratingMagic = false
                    if case .failure(let error) = completion {
                        DebugLogger.debug("Magic preview error: \(error)", category: "Chatbot")
                    }
                },
                receiveValue: { response in
                    self.magicPreviewComment = response.comment.commentText
                    self.showMagicPreview = true
                }
            )
            .store(in: &cancellables)
    }
    
    func postMagicComment(completion: @escaping (Bool) -> Void) {
        // This would integrate with CommunityViewModel to actually post
        // For now, just simulating success
        completion(true)
    }
    
    // MARK: - Voice Input
    func startRecording() {
        guard !audioEngine.isRunning else { return }
        ensurePermissions { granted, failureMessage in
            DispatchQueue.main.async {
                if granted {
                    self.beginSpeechSession()
                } else {
                    // Graceful feedback instead of freeze
                    self.messages.append(ChatMessage(
                        content: failureMessage ?? "To use voice, please allow Microphone and Speech permissions in Settings.",
                        isUser: false,
                        timestamp: Date()
                    ))
                }
            }
        }
    }

    private enum MicPermission {
        case granted
        case denied
        case undetermined
    }
    
    private func currentMicPermission() -> MicPermission {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        }
    }
    
    private func requestMicPermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                completion(granted)
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                completion(granted)
            }
        }
    }
    
    private func ensurePermissions(completion: @escaping (_ granted: Bool, _ failureMessage: String?) -> Void) {
        // Note: keep this robust across iOS versions; do NOT trust a single snapshot.
        var speechGranted: Bool?
        var micGranted: Bool?
        
        func maybeFinish() {
            guard let s = speechGranted, let m = micGranted else { return }
            if s && m {
                completion(true, nil)
                return
            }
            
            // Build a precise, actionable message so we don't mislead users when only one permission is off.
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            let micStatus = currentMicPermission()
            
            var parts: [String] = []
            if !s {
                switch speechStatus {
                case .denied:
                    parts.append("Speech Recognition is off for this app. Turn it on in Settings > Privacy & Security > Speech Recognition.")
                case .restricted:
                    parts.append("Speech Recognition is restricted (Screen Time / parental controls).")
                case .notDetermined:
                    parts.append("Speech Recognition permission hasn’t been granted yet. Please try again to allow the prompt.")
                default:
                    parts.append("Speech Recognition permission isn’t available.")
                }
            }
            if !m {
                switch micStatus {
                case .denied:
                    parts.append("Microphone is off for this app. Turn it on in Settings > Privacy & Security > Microphone (or Settings > Restaurant Demo).")
                case .undetermined:
                    parts.append("Microphone permission hasn’t been granted yet. Please try again to allow the prompt.")
                case .granted:
                    break
                }
            }
            
            completion(false, parts.joined(separator: " "))
        }
        
        // Speech
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechGranted = true
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    speechGranted = (status == .authorized)
                    maybeFinish()
                }
            }
        case .denied, .restricted:
            speechGranted = false
        @unknown default:
            speechGranted = false
        }
        
        // Microphone
        switch currentMicPermission() {
        case .granted:
            micGranted = true
        case .undetermined:
            requestMicPermission { granted in
                DispatchQueue.main.async {
                    micGranted = granted
                    maybeFinish()
                }
            }
        case .denied:
            micGranted = false
        }
        
        // If both were immediately known, finish synchronously.
        DispatchQueue.main.async {
            maybeFinish()
        }
    }
    
    private func beginSpeechSession() {
        isRecording = true
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.inputText = result.bestTranscription.formattedString
                // Restart silence timer on every partial result
                self.resetSilenceTimer()
                if result.isFinal {
                    self.finalizeAndSend()
                }
            }
            if error != nil {
                self.finalizeAndSend()
            }
        }
    }
    
    func stopRecording() {
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        // Deactivate audio session to release hardware resources
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            self.finalizeAndSend()
        }
    }
    
    private func finalizeAndSend() {
        stopRecording()
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sendMessage()
        }
    }
}

struct MagicPreviewResponse: Codable {
    let success: Bool
    let comment: MagicComment
}

struct MagicComment: Codable {
    let commentText: String
}

struct ChatResponse: Codable {
    let response: String
}

struct ChatbotView: View {
    @StateObject private var viewModel = ChatbotViewModel()
    @State private var pulseAnimation = false
    @State private var glowPhase: CGFloat = 0
    @State private var glowProgress: Double = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var time: Double = 0
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var rewardsVM: RewardsViewModel
    @State private var showRewardsSheet: Bool = false
    @State private var allowAnimations: Bool = true
    @State private var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    
    // Use Theme colors for consistency with HomeView (Hybrid Energy)
    private let modernPrimary = Theme.modernPrimary
    private let modernAccent = Theme.primaryGold
    private let modernGold = Theme.lightGold
    private let modernBackground = Theme.modernBackground
    private let modernCard = Theme.modernCard
    private let modernSecondary = Theme.modernSecondary
    
    private var shouldAnimate: Bool {
        return allowAnimations && !reduceMotion && !isLowPowerMode
    }

    var body: some View {
        ZStack {
            // Hybrid Energy background (matching HomeView)
            LinearGradient(
                gradient: Gradient(colors: [
                    Theme.modernBackground,
                    Theme.modernCardSecondary,
                    Theme.modernBackground
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Subtle JellyGlimmer ambient layer (low opacity)
            JellyGlimmerView(
                scrollOffset: scrollOffset,
                time: time,
                colorScheme: colorScheme,
                pop: false
            )
            .opacity(reduceMotion ? 0.02 : 0.05)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            
            // Aurora spot near header (hero avatar area)
            RadialGradient(
                colors: [
                    modernAccent.opacity(reduceMotion ? 0.02 : 0.06),
                    modernGold.opacity(reduceMotion ? 0.01 : 0.03),
                    Color.clear
                ],
                center: .init(x: 0.15, y: 0.08),
                startRadius: pulseAnimation ? 80 : 100,
                endRadius: pulseAnimation ? 200 : 240
            )
            .ignoresSafeArea()
            .animation(shouldAnimate ? .easeInOut(duration: 5.0).repeatForever(autoreverses: true) : nil, value: pulseAnimation)
            
            // Aurora spot near composer (bottom)
            RadialGradient(
                colors: [
                    modernGold.opacity(reduceMotion ? 0.01 : 0.025),
                    modernAccent.opacity(reduceMotion ? 0.008 : 0.012),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.92),
                startRadius: pulseAnimation ? 80 : 90,
                endRadius: pulseAnimation ? 170 : 200
            )
            .ignoresSafeArea()
            .animation(shouldAnimate ? .easeInOut(duration: 6.0).repeatForever(autoreverses: true) : nil, value: pulseAnimation)
            .onAppear {
                // Attach shared user state (avoids creating a second UserViewModel / Firestore listener)
                viewModel.attachUserViewModel(userVM)

                pulseAnimation = shouldAnimate
                if shouldAnimate {
                    withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                        glowPhase = 1
                    }
                }
                
                // Auto-focus text field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
            .onDisappear {
                pulseAnimation = false
            }
            
            VStack(spacing: 8) {
                // Header
                headerView
                    .zIndex(1)
                
                // Messages area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if viewModel.messages.isEmpty {
                                // no suggestions view anymore
                            } else {
                                // Pinned section
                                if !viewModel.pinnedMessages.isEmpty {
                                    pinnedSection
                                }
                                let lastAssistantId = viewModel.messages.last(where: { !$0.isUser })?.id
                                ForEach(viewModel.messages) { message in
                                    MessageBubble(
                                        message: message,
                                        onShowRewards: {
                                            showRewardsSheet = true
                                        },
                                        showRegenerate: message.id == lastAssistantId,
                                        isNewAssistant: (message.id == lastAssistantId) && !message.isUser,
                                        viewModel: viewModel,
                                        modernPrimary: modernPrimary,
                                        modernAccent: modernAccent,
                                        modernGold: modernGold,
                                        modernCard: modernCard,
                                        modernSecondary: modernSecondary
                                    )
                                    .id(message.id)
                                }
                                
                                // (Dot loading indicator removed)
                                
                                // Bottom anchor for reliable scrolling
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                        .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: viewModel.messages.count) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let lastMessage = viewModel.messages.last {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onChange(of: viewModel.isLoading) { isLoading in
                        if isLoading {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                // Context chips row (moved above the typing box)
                contextChipsView

                // Input area
                inputView
            }
            
            // Heart burst overlay (for "Helpful" reactions)
            if viewModel.showHeartBurst {
                HeartBurstView()
                    .position(viewModel.heartBurstPosition)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(isPresented: $viewModel.showMagicPreview) {
            MagicPreviewSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showRewardsSheet) {
            UnifiedRewardsScreen(mode: .modal)
                .environmentObject(userVM)
                .environmentObject(rewardsVM)
        }
        // (Search overlay removed)
        .overlay(alignment: .bottom) {
            GoldGlowView(progress: glowProgress)
                .padding(.bottom, 24)
                .allowsHitTesting(false)
        }
        .onChange(of: viewModel.isLoading) { isLoading in
            if isLoading {
                withAnimation(reduceMotion ? .none : .easeIn(duration: 2.0)) {
                    glowProgress = 1.0
                }
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    glowProgress = 0.0
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                allowAnimations = true
                if shouldAnimate {
                    pulseAnimation = true
                    withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                        glowPhase = 1
                    }
                }
            default:
                allowAnimations = false
                pulseAnimation = false
                withAnimation(.none) { glowPhase = 0 }
                if viewModel.isRecording {
                    viewModel.stopRecording()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            if !shouldAnimate {
                pulseAnimation = false
            } else if scenePhase == .active {
                pulseAnimation = true
                withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                    glowPhase = 1
                }
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // One-line header with hero and title
                HStack(spacing: 10) {
                    Image("newhero")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 63, height: 63)
                    Text("Dumpling Hero")
                        .font(.system(size: 35, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [modernPrimary, modernAccent]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }

                Spacer()

                // (Search icon removed)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 0)
        }
        // Keep header minimal; removed heavy glass background per new compact style
    }
    
    // (Search bar removed)
    
    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pin.fill").foregroundColor(Theme.primaryGold)
                Text("PINNED")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(modernSecondary)
                Spacer()
            }
            .padding(.horizontal, 24)
            
            ForEach(Array(viewModel.pinnedMessages.prefix(3))) { pinned in
                HStack(alignment: .top, spacing: 12) {
                    Image("newhero")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                    Text(pinned.content)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(modernPrimary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Theme.primaryGold.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Theme.cardShadow, radius: 6, x: 0, y: 2)
                )
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 4)
    }
    
    private var contextChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ContextChip(icon: "fork.knife", title: "Menu", color: Theme.primaryGold) {
                    viewModel.inputText = "Show me your menu highlights"
                    viewModel.sendMessage()
                    isTextFieldFocused = false
                }
                
                ContextChip(icon: "gift.fill", title: "Rewards", color: Theme.energyOrange) {
                    viewModel.inputText = "What rewards can I redeem?"
                    viewModel.sendMessage()
                    isTextFieldFocused = false
                }
                
                ContextChip(icon: "clock.fill", title: "Hours", color: Theme.energyBlue) {
                    viewModel.inputText = "What are your hours?"
                    viewModel.sendMessage()
                    isTextFieldFocused = false
                }
                
                ContextChip(icon: "mappin.and.ellipse", title: "Directions", color: Theme.energyGreen) {
                    // Inject a local directions card without calling the backend
                    let text = "Here you go! Tap Directions to navigate to Dumpling House."
                    let bot = ChatMessage(content: text, isUser: false, timestamp: Date())
                    viewModel.messages.append(bot)
                    isTextFieldFocused = false
                }
                
                ContextChip(icon: "phone.fill", title: "Call", color: Theme.energyRed) {
                    if let url = URL(string: "tel:+16158914728"), UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                    isTextFieldFocused = false
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        // Removed background to avoid faint line and overlapping text
    }
    
    private var inputView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack(alignment: .leading) {
                    // Text field (no native placeholder; we'll control our own)
                    TextField("", text: $viewModel.inputText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.9),
                                            Color.white.opacity(0.7)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    modernGold.opacity(0.3),
                                                    modernAccent.opacity(0.2)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .disabled(viewModel.isLoading)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                viewModel.sendMessage()
                                isTextFieldFocused = false
                            }
                        }

                    // Custom placeholder that hides during loading and when text is not empty
                    if !viewModel.isLoading && viewModel.inputText.isEmpty {
                        Text("Ask Dumpling Hero anything...")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.leading, 24)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
                            .allowsHitTesting(false)
                    }

                    // Generating… overlay when loading
                    if viewModel.isLoading {
                        HStack(spacing: 6) {
                            GeneratingDotsText()
                                .foregroundColor(.black)
                                .padding(.leading, 24)
                        }
                        .allowsHitTesting(false)
                    }
                }

                Button(action: {
                    if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.sendMessage()
                        isTextFieldFocused = false
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            modernAccent,
                                            Theme.deepGold,
                                            modernAccent
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: modernAccent.opacity(0.4), radius: 8, x: 0, y: 4)
                        .scaleEffect(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.8 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.inputText.isEmpty)
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)

                // Voice input
                Button(action: {
                    if viewModel.isRecording { viewModel.stopRecording() } else { viewModel.startRecording() }
                }) {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(viewModel.isRecording ? .red : Theme.energyBlue)
                }
                .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start voice input")
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(
            ZStack {
                // Glass morphism background
                Rectangle()
                    .fill(modernCard)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.85)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.0), radius: 22, x: 0, y: -8)
                    .shadow(color: Theme.deepGold.opacity(0.2 + 0.4 * glowProgress), radius: 60, x: 0, y: -18)
            }
        )
        .animation(.easeInOut(duration: 0.2), value: glowProgress)
    }

    // Animated "generating…" text with cycling dots
    private struct GeneratingDotsText: View {
        @State private var dotCount: Int = 0
        private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

        var body: some View {
            Text("generating" + String(repeating: ".", count: (dotCount % 3) + 1))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .onReceive(timer) { _ in
                    dotCount = (dotCount + 1) % 3
                }
        }
    }
    
    // Removed legacy suggestion chips
}

struct MessageBubble: View {
    let message: ChatMessage
    let onShowRewards: () -> Void
    let showRegenerate: Bool
    let isNewAssistant: Bool
    @ObservedObject var viewModel: ChatbotViewModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let modernPrimary: Color
    let modernAccent: Color
    let modernGold: Color
    let modernCard: Color
    let modernSecondary: Color
    @State private var flyIn: Bool = true
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                
                Text(message.content)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(nil)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Theme.primaryGold, Theme.deepGold],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 2)
                    )
                    .foregroundColor(modernPrimary)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    // Hero avatar - clean PNG, no background circles
                    Image("newhero")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text(message.content)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        
                        // Inline Rewards card when assistant mentions rewards
                        if message.content.localizedCaseInsensitiveContains("reward") || message.content.localizedCaseInsensitiveContains("points") {
                            RewardsInlineCard(onOpenRewards: onShowRewards)
                        }
                        if message.content.localizedCaseInsensitiveContains("directions") || message.content.localizedCaseInsensitiveContains("navigate") {
                            DirectionsInlineCard()
                        }
                        
                        // Action row for assistant messages (no persistent rewards button)
                        if message.id != viewModel.introMessageId && showRegenerate {
                        HStack(spacing: 12) {
                            Button(action: { viewModel.copyMessage(message) }) {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .labelStyle(.titleAndIcon)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(modernSecondary)
                            
                            Button(action: { viewModel.regenerateLastResponse() }) {
                                Label("Regenerate", systemImage: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(modernSecondary)
                        }
                        }
                    }
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            modernCard.opacity(0.95),
                                            modernCard.opacity(0.8)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    modernAccent.opacity(0.3),
                                                    modernPrimary.opacity(0.2)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                                .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 6)
                                .shadow(color: modernAccent.opacity(0.1), radius: 25, x: 0, y: 10)
                        )
                        .foregroundColor(modernPrimary)
                }
                
                Spacer()
            }
        }
        .offset(y: (isNewAssistant && flyIn && !reduceMotion) ? 40 : 0)
        .opacity((isNewAssistant && flyIn && !reduceMotion) ? 0 : 1)
        .onAppear {
            if isNewAssistant && !reduceMotion {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    flyIn = false
                }
            }
        }
        .contextMenu {
            if !message.isUser {
                Button(action: {
                    // Get position for heart burst
                    viewModel.toggleHelpful(message, at: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2))
                }) {
                    Label(message.isHelpful ? "Remove Helpful" : "Mark Helpful", systemImage: message.isHelpful ? "heart.fill" : "heart")
                }
                
                Button(action: {
                    viewModel.togglePin(message)
                }) {
                    Label(message.isPinned ? "Unpin" : "Pin", systemImage: message.isPinned ? "pin.slash" : "pin")
                }
                
                Divider()
            }
            
            Button(action: {
                viewModel.copyMessage(message)
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                viewModel.shareMessage(message)
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            if message.failedToSend {
                Divider()
                Button(action: {
                    viewModel.retryMessage(message)
                }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: message.id)
        .transition(message.isUser ? .identity : (reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)))
    }
}

struct LoadingIndicator: View {
    @State private var isAnimating = false
    let modernAccent: Color
    let modernGold: Color
    let modernCard: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Hero avatar - clean PNG, no background circles
            Image("newhero")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            
            HStack(spacing: 10) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    modernAccent,
                                    modernGold
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 10)
                        .shadow(color: modernAccent.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(isAnimating ? 1.4 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.7)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                modernCard.opacity(0.95),
                                modernCard.opacity(0.8)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        modernAccent.opacity(0.2),
                                        modernGold.opacity(0.2)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 6)
                    .shadow(color: modernAccent.opacity(0.1), radius: 25, x: 0, y: 10)
            )
            
            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Magic Preview Sheet
struct MagicPreviewSheet: View {
    @ObservedObject var viewModel: ChatbotViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isPosting = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Preview card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image("newhero")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Dumpling Hero")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                
                                Text("AI")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.primaryGold)
                                    .cornerRadius(6)
                            }
                            
                            Text("Just now")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Text(viewModel.magicPreviewComment)
                        .font(.body)
                        .padding(.vertical, 8)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                )
                .padding()
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        isPosting = true
                        viewModel.postMagicComment { success in
                            isPosting = false
                            if success {
                                dismiss()
                            }
                        }
                    }) {
                        HStack {
                            if isPosting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Posting...")
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("Post to Community")
                            }
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Theme.energyOrange,
                                    Theme.energyRed
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                    .disabled(isPosting)
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Magic Comment Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Context Chip Component
struct ContextChip: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                color,
                                color.opacity(0.8)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Note: HeartBurstView is imported from CommunityAnimations.swift

// MARK: - Rewards Inline Card
struct RewardsInlineCard: View {
    let onOpenRewards: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.energyOrange)
                    .frame(width: 36, height: 36)
                Image(systemName: "gift.fill")
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Check your rewards")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("See what you can redeem today")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onOpenRewards) {
                Text("OPEN")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.darkGoldGradient))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.modernCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                )
                .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Gold Glow Loader
struct GoldGlowView: View {
    let progress: Double
    var body: some View {
        let clamped = max(0.0, min(1.0, progress))
        let inner = min(0.98, 0.95 * clamped)
        let mid = min(0.7, 0.55 * clamped) // slightly less spread on the lighter layer
        let endR: CGFloat = 260 + CGFloat(560 * clamped) // darker bottom travels farther upward
        let blur: CGFloat = 20 + CGFloat(46 * clamped)
        let height: CGFloat = 140 + CGFloat(360 * clamped)
        return ZStack {
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.deepGold.opacity(inner),
                            Theme.primaryGold.opacity(mid),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.5, y: 1.05),
                        startRadius: 6,
                        endRadius: endR
                    )
                )
                .blur(radius: blur)
                .frame(height: height)
        }
        .opacity(clamped)
        .compositingGroup()
        .blendMode(.screen)
        .scaleEffect(x: 1.0, y: 2.0 + 1.2 * clamped, anchor: .bottom)
    }
}

// MARK: - Directions Inline Card
struct DirectionsInlineCard: View {
    @State private var showMapsAlert = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.energyGreen)
                    .frame(width: 36, height: 36)
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Directions to Dumpling House")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("2117 Belcourt Ave, Nashville, TN")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                showMapsAlert = true
            }) {
                Text("Directions")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.energyGreen))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.modernCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                )
                .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
        )
        .alert("Choose Navigation App", isPresented: $showMapsAlert) {
            Button("Apple Maps") { openAppleMaps() }
            Button("Google Maps") { openGoogleMaps() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Select your preferred navigation app to get directions to Dumpling House")
        }
    }
    
    private func openAppleMaps() {
        let coordinate = CLLocationCoordinate2D(latitude: 36.13663, longitude: -86.80233)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = "Dumpling House"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
    
    private func openGoogleMaps() {
        let coordinate = CLLocationCoordinate2D(latitude: 36.13663, longitude: -86.80233)
        let urlString = "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=driving"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            let webUrlString = "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)&travelmode=driving"
            if let webUrl = URL(string: webUrlString) {
                UIApplication.shared.open(webUrl)
            }
        }
    }
}

// MARK: - Heart Burst Animation View
struct HeartBurstView: View {
    @State private var hearts: [HeartParticle] = []
    
    struct HeartParticle: Identifiable {
        let id = UUID()
        var offset: CGSize
        var opacity: Double
        var scale: CGFloat
        var rotation: Double
    }
    
    var body: some View {
        ZStack {
            ForEach(hearts) { heart in
                Text("❤️")
                    .font(.system(size: 24))
                    .offset(heart.offset)
                    .opacity(heart.opacity)
                    .scaleEffect(heart.scale)
                    .rotationEffect(.degrees(heart.rotation))
            }
        }
        .onAppear {
            createHearts()
        }
    }
    
    private func createHearts() {
        for i in 0..<12 {
            let angle = Double(i) * (360.0 / 12.0)
            let radians = angle * .pi / 180
            
            var heart = HeartParticle(
                offset: .zero,
                opacity: 1.0,
                scale: 0.5,
                rotation: Double.random(in: -30...30)
            )
            hearts.append(heart)
            
            let index = hearts.count - 1
            let distance: CGFloat = CGFloat.random(in: 40...80)
            
            withAnimation(.easeOut(duration: 0.6)) {
                hearts[index].offset = CGSize(
                    width: cos(radians) * distance,
                    height: sin(radians) * distance
                )
                hearts[index].scale = CGFloat.random(in: 0.8...1.2)
            }
            
            withAnimation(.easeIn(duration: 0.4).delay(0.4)) {
                hearts[index].opacity = 0
            }
        }
    }
}

#Preview {
    ChatbotView()
}
