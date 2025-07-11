//
//  ChatbotView.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/27/25.
//

import SwiftUI
import Combine

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
}

class ChatbotViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var showSuggestions: Bool = true
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Add welcome message
        messages.append(ChatMessage(
            content: "Hi! I'm Dumpling Hero, your friendly guide to all things delicious at Dumpling House! 🥟✨ What can I help you with today?",
            isUser: false,
            timestamp: Date()
        ))
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
            "conversation_history": conversationHistory
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("Error serializing request: \(error)")
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
                        print("Error: \(error)")
                        self.messages.append(ChatMessage(
                            content: "Sorry, I'm having trouble connecting right now. Please try again!",
                            isUser: false,
                            timestamp: Date()
                        ))
                    }
                },
                receiveValue: { response in
                    self.messages.append(ChatMessage(
                        content: response.response,
                        isUser: false,
                        timestamp: Date()
                    ))
                }
            )
            .store(in: &cancellables)
    }
    
    func sendSuggestion(_ suggestion: String) {
        inputText = suggestion
        showSuggestions = false
        sendMessage()
    }
}

struct ChatResponse: Codable {
    let response: String
}

struct ChatbotView: View {
    @StateObject private var viewModel = ChatbotViewModel()
    @State private var pulseAnimation = false
    
    // Dark gold color scheme
    private let darkGold = Color(red: 0.8, green: 0.6, blue: 0.2)
    private let lightGold = Color(red: 0.9, green: 0.7, blue: 0.3)
    private let deepGold = Color(red: 0.6, green: 0.4, blue: 0.1)
    
    var body: some View {
        ZStack {
            // Clean dark gradient background
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.1, green: 0.08, blue: 0.05),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Subtle animated glow
            RadialGradient(
                colors: [
                    darkGold.opacity(0.15),
                    Color.clear
                ],
                center: .center,
                startRadius: pulseAnimation ? 150 : 200,
                endRadius: pulseAnimation ? 400 : 500
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
            
            VStack(spacing: 0) {
                // Clean header with Dumpling Hero
                headerView
                
                // Messages ScrollView
                messagesView
                
                // Suggestions (when visible)
                if viewModel.showSuggestions {
                    suggestionsView
                }
                
                // Input area
                inputView
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Clean avatar with gold border
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [darkGold, lightGold],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)
                        .shadow(color: darkGold.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image("hero")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dumpling Hero")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [lightGold, darkGold],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Your AI Guide to Dumpling House")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    
                    Text("Online")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [darkGold.opacity(0.1), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
    }
    
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, darkGold: darkGold, lightGold: lightGold)
                            .id(message.id)
                    }
                    
                    if viewModel.isLoading {
                        LoadingIndicator(darkGold: darkGold, lightGold: lightGold)
                            .id("loading")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .onChange(of: viewModel.messages.count) { oldValue, newValue in
                withAnimation(.easeInOut(duration: 0.3)) {
                    if let lastMessage = viewModel.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { oldValue, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var suggestionsView: some View {
        VStack(spacing: 12) {
            Text("Try asking me about:")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestionChips, id: \.self) { suggestion in
                        Button(action: {
                            viewModel.sendSuggestion(suggestion)
                        }) {
                            Text(suggestion)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [lightGold, darkGold],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: darkGold.opacity(0.3), radius: 4, x: 0, y: 2)
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 16)
    }
    
    private var inputView: some View {
        VStack(spacing: 0) {
            Divider()
                .background(darkGold.opacity(0.3))
            
            HStack(spacing: 16) {
                TextField("Ask Dumpling Hero anything...", text: $viewModel.inputText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(
                                        LinearGradient(
                                            colors: [darkGold.opacity(0.3), lightGold.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .foregroundColor(.white)
                    .onSubmit {
                        viewModel.sendMessage()
                    }
                
                Button(action: {
                    viewModel.sendMessage()
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [lightGold, darkGold],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: darkGold.opacity(0.4), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                .opacity(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, darkGold.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
    }
    
    private var suggestionChips: [String] {
        [
            "What are your most popular dumplings?",
            "Tell me about your Half & Half option",
            "Do you have vegetarian options?",
            "What drinks do you recommend?",
            "How long is the wait time?",
            "Tell me about your location",
            "Do you deliver?",
            "What's your spiciest dish?"
        ]
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let darkGold: Color
    let lightGold: Color
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                
                Text(message.content)
                    .font(.system(size: 16))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [lightGold, darkGold],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: darkGold.opacity(0.3), radius: 6, x: 0, y: 3)
                    )
                    .foregroundColor(.black)
                    .fontWeight(.medium)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    // Bot avatar
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [darkGold, lightGold],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                            .shadow(color: darkGold.opacity(0.3), radius: 4, x: 0, y: 2)
                        
                        Image("hero")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                    }
                    
                    Text(message.content)
                        .font(.system(size: 16))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(
                                            LinearGradient(
                                                colors: [darkGold.opacity(0.2), lightGold.opacity(0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .foregroundColor(.white)
                }
                
                Spacer()
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: message.id)
    }
}

struct LoadingIndicator: View {
    @State private var isAnimating = false
    let darkGold: Color
    let lightGold: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Bot avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [darkGold, lightGold],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: darkGold.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Image("hero")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            }
            
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [lightGold, darkGold],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 8, height: 8)
                        .scaleEffect(isAnimating ? 1.3 : 0.7)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: [darkGold.opacity(0.2), lightGold.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            
            Spacer()
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    ChatbotView()
} 