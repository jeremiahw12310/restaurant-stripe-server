import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import FirebaseAuth
import FirebaseFirestore

// MARK: - Referral Cache
fileprivate struct ReferralCache {
    // Updated cache key to v4: bust cache after referral code reset/migration
    private static let cacheKeyPrefix = "referral_cache_v4_"
    
    struct CachedData: Codable {
        let code: String
        let shareUrl: String
        let timestamp: Date
    }
    
    static func save(code: String, shareUrl: String, userId: String) {
        let data = CachedData(code: code, shareUrl: shareUrl, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: cacheKeyPrefix + userId)
            DebugLogger.debug("📦 Cached referral code for user \(userId)", category: "Referral")
        }
    }
    
    static func load(userId: String) -> (code: String, shareUrl: String)? {
        guard let data = UserDefaults.standard.data(forKey: cacheKeyPrefix + userId),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else {
            return nil
        }
        DebugLogger.debug("📦 Loaded cached referral code for user \(userId)", category: "Referral")
        return (cached.code, cached.shareUrl)
    }
    
    static func clear(userId: String) {
        UserDefaults.standard.removeObject(forKey: cacheKeyPrefix + userId)
        DebugLogger.debug("📦 Cleared referral cache for user \(userId)", category: "Referral")
    }
    
    static func clearAll() {
        // Clear all referral caches (useful on logout)
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix(cacheKeyPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    static func clearLegacyCache() {
        // Clear old cache formats (v1 and v2) that may contain wrong URLs
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix("referral_cache_") && !key.hasPrefix(cacheKeyPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
            DebugLogger.debug("🗑️ Cleared legacy referral cache: \(key)", category: "Referral")
        }
    }
}

struct ReferralView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLoading: Bool = false
    @State private var errorMessage: String = ""
    
    @State private var myCode: String = ""
    @State private var shareURL: URL? = nil
    
    @State private var acceptCode: String = ""
    @State private var acceptStatus: String = ""
    let initialCode: String?

    // Gating for enter-code visibility: show only if within 24h of account creation OR user has not used a referral
    
    init(initialCode: String? = nil) {
        self.initialCode = initialCode
    }
    @State private var canShowEnterCode: Bool = false
    @State private var hasUsedReferral: Bool = false

    @State private var showHistory: Bool = false
    
    // Entrance animation
    // Default to visible to avoid entrance animations/fx when opening referral.
    @State private var hasAppeared: Bool = true
    
    // Hero card animations
    @State private var heroAnimated: Bool = false
    @State private var stepsAnimated: Bool = false
    @State private var ringProgress: CGFloat = 0

    // UI feedback
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""

    // Share sheet
    private struct SharePayload: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let message: String
    }
    @State private var sharePayload: SharePayload? = nil

    // Referral connections
    struct ReferralDisplay: Identifiable {
        let id: String
        let name: String
        let status: String // "Pending" | "Awarded"
        let isOutbound: Bool // true if I referred them; false if they referred me
        let pointsTowards50: Int // 0-50; 0 if unknown
        let createdAt: Date? // When the referral was created
    }
    @State private var outboundConnections: [ReferralDisplay] = []
    @State private var inboundConnection: ReferralDisplay? = nil
    @State private var outboundListener: ListenerRegistration? = nil
    @State private var inboundListener: ListenerRegistration? = nil
    @State private var userDocListener: ListenerRegistration? = nil
    private var sessionKey: String {
        if let uid = Auth.auth().currentUser?.uid { return "referral_pending_\(uid)" }
        return "referral_pending"
    }

    var body: some View {
        NavigationStack {
            ZStack {
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        bigQRSection
                        codeSection
                        header
                        referralProgressHeroCard
                        referralJourneySteps
                        if canShowEnterCode { enterCodeSection }
                        connectionsSection
                        if !errorMessage.isEmpty { errorSection }
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .navigationDestination(isPresented: $showHistory) {
                        ReferralHistoryView()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Give 50, Get 50")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) { toastOverlay }
            .sheet(item: $sharePayload) { payload in
                ActivityView(items: [payload.message])
            }
        }
        .onAppear {
            DebugLogger.debug("🪪 ReferralView appeared", category: "Referral")
            
            // Load from cache first for instant display
            if myCode.isEmpty, let userId = Auth.auth().currentUser?.uid {
                if let cached = ReferralCache.load(userId: userId) {
                    myCode = cached.code
                    shareURL = URL(string: cached.shareUrl)
                    DebugLogger.debug("✅ Referral code loaded from cache instantly", category: "Referral")
                } else {
                    // Cache miss - fetch from server
                    fetchMyCode()
                }
            }
            
            hydrateFromSessionFlagIfPresent()
            evaluateEnterCodeGating { allowed in
                if allowed, let initCode = initialCode, !initCode.isEmpty, acceptCode.isEmpty {
                    acceptCode = initCode.uppercased()
                    // Auto-submit after a brief delay to ensure UI is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        acceptReferral()
                    }
                }
            }
            listenForConnections()
            startUserDocListener()
            
            // Trigger hero card and journey animations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    heroAnimated = true
                    stepsAnimated = true
                }
                
                // Animate the ring progress with a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 1.2)) {
                        ringProgress = referralProgress
                    }
                }
            }
        }
        .onDisappear {
            outboundListener?.remove(); outboundListener = nil
            inboundListener?.remove(); inboundListener = nil
            userDocListener?.remove(); userDocListener = nil
        }
        .onChange(of: outboundConnections.count) { _, newCount in
            // Update ring progress when connections change
            withAnimation(.easeOut(duration: 0.8)) {
                ringProgress = CGFloat(newCount) / 10.0
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !myCode.isEmpty, let url = shareURL {
                FloatingInviteBar(shareURL: url, code: myCode,
                                  onShare: {
                                      // Present share sheet immediately (no hearts here to avoid animation hitch).
                                      logShareEvent(action: "share")
                                      let inviteMessage = "Join me at Dumpling House! Sign up with my link and we'll both get 50 bonus points: \(url.absoluteString)"
                                      sharePayload = SharePayload(url: url, message: inviteMessage)
                                  },
                                  onCopy: {
                                      UIPasteboard.general.string = myCode
                                      logShareEvent(action: "copy")
                                      triggerHapticSuccess()
                                      showToastMessage("Copied code")
                                  })
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 30)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.8), value: hasAppeared)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refer up to 10 friends. When they earn 50 points you will both receive an additional 50 points.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
    }

    @ViewBuilder
    private func responsiveLargeQRCodeView(url: URL) -> some View {
        if #available(iOS 16.0, *) {
            ViewThatFits {
                LargeQRCodeView(url: url, size: 300)
                LargeQRCodeView(url: url, size: 260)
                LargeQRCodeView(url: url, size: 240)
                LargeQRCodeView(url: url, size: 220)
            }
        } else {
            LargeQRCodeView(url: url, size: 240)
        }
    }

    @ViewBuilder
    private var bigQRSection: some View {
        if let url = shareURL {
            VStack(spacing: 8) {
                responsiveLargeQRCodeView(url: url)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                Text("Scan to join")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("QR code with your referral link"))
            .padding(.vertical, 2)
            .scaleEffect(hasAppeared ? 1.0 : 0.85)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.35), value: hasAppeared)
        }
    }

    private var inboundStatus: String { inboundConnection?.status ?? "" }
    private var outboundAwardedSignature: [String] {
        outboundConnections.map { "\($0.id)|\($0.status)" }
    }
    
    // Referral count and cap
    private var referralCount: Int {
        outboundConnections.count
    }
    
    private var referralCountText: String {
        "\(referralCount)/10"
    }
    
    private var remainingReferrals: Int {
        max(0, 10 - referralCount)
    }
    
    // Count of awarded referrals (for bonus points display)
    private var awardedReferralCount: Int {
        outboundConnections.filter { $0.status == "Awarded" }.count
    }
    
    // Total bonus points earned from referrals
    private var totalReferralBonusPoints: Int {
        awardedReferralCount * 50
    }
    
    // Progress percentage for the ring (0.0 to 1.0)
    private var referralProgress: CGFloat {
        CGFloat(referralCount) / 10.0
    }

    // MARK: - Hero Progress Card
    
    @ViewBuilder
    private var referralProgressHeroCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 24) {
                // Circular Progress Ring
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(
                            Color.gray.opacity(0.2),
                            lineWidth: 10
                        )
                    
                    // Progress ring
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(
                            Theme.darkGoldGradient,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Theme.primaryGold.opacity(0.4), radius: 6, x: 0, y: 0)
                    
                    // Center content
                    VStack(spacing: 2) {
                        Text("\(referralCount)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.darkGoldGradient)
                        Text("of 10")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 100, height: 100)
                
                // Points summary
                VStack(alignment: .leading, spacing: 6) {
                    Text("REFERRAL PROGRESS")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.secondary)
                    
                    if totalReferralBonusPoints > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("+\(totalReferralBonusPoints)")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.darkGoldGradient)
                            Text("pts")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        Text("earned from referrals")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Share your code")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.modernPrimary)
                        Text("to start earning")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    
                    // Remaining count
                    if remainingReferrals > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.primaryGold)
                            Text("\(remainingReferrals) spot\(remainingReferrals == 1 ? "" : "s") left")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.primaryGold)
                        }
                        .padding(.top, 4)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.green)
                            Text("Limit reached")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.modernCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Theme.darkGoldGradient, lineWidth: 2)
                )
                .shadow(color: Theme.goldShadow, radius: 16, x: 0, y: 8)
                .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
        )
        .scaleEffect(heroAnimated ? 1.0 : 0.9)
        .opacity(heroAnimated ? 1 : 0)
        .animation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.25), value: heroAnimated)
    }
    
    // MARK: - Referral Journey Steps
    
    @ViewBuilder
    private var referralJourneySteps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HOW IT WORKS")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundColor(.secondary)
                .opacity(stepsAnimated ? 1 : 0)
                .animation(.easeInOut(duration: 0.4).delay(0.35), value: stepsAnimated)
            
            HStack(spacing: 0) {
                // Step 1: Share
                referralStepView(
                    stepNumber: 1,
                    icon: "square.and.arrow.up",
                    title: "Share",
                    isActive: true,
                    delay: 0.4
                )
                
                // Connector line
                stepConnector(isCompleted: referralCount > 0, delay: 0.5)
                
                // Step 2: Sign Up
                referralStepView(
                    stepNumber: 2,
                    icon: "person.badge.plus",
                    title: "Sign Up",
                    isActive: referralCount > 0,
                    delay: 0.5
                )
                
                // Connector line
                stepConnector(isCompleted: awardedReferralCount > 0, delay: 0.6)
                
                // Step 3: Earn 50
                referralStepView(
                    stepNumber: 3,
                    icon: "star.fill",
                    title: "Earn 50",
                    isActive: referralCount > 0 && outboundConnections.contains { $0.pointsTowards50 > 0 },
                    delay: 0.6
                )
                
                // Connector line
                stepConnector(isCompleted: awardedReferralCount > 0, delay: 0.7)
                
                // Step 4: Bonus
                referralStepView(
                    stepNumber: 4,
                    icon: "gift.fill",
                    title: "Bonus!",
                    isActive: awardedReferralCount > 0,
                    delay: 0.7
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.modernCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Theme.cardShadow, radius: 8, x: 0, y: 4)
        )
        .scaleEffect(stepsAnimated ? 1.0 : 0.95)
        .opacity(stepsAnimated ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: stepsAnimated)
    }
    
    @ViewBuilder
    private func referralStepView(stepNumber: Int, icon: String, title: String, isActive: Bool, delay: Double) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isActive ? Theme.darkGoldGradient : LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: isActive ? Theme.primaryGold.opacity(0.3) : Color.clear, radius: 6, x: 0, y: 3)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isActive ? .white : .gray)
            }
            
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(isActive ? Theme.modernPrimary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .opacity(stepsAnimated ? 1 : 0)
        .scaleEffect(stepsAnimated ? 1 : 0.8)
        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay), value: stepsAnimated)
    }
    
    @ViewBuilder
    private func stepConnector(isCompleted: Bool, delay: Double) -> some View {
        Rectangle()
            .fill(isCompleted ? Theme.darkGoldGradient : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
            .frame(height: 3)
            .frame(maxWidth: 24)
            .offset(y: -12)
            .opacity(stepsAnimated ? 1 : 0)
            .animation(.easeInOut(duration: 0.3).delay(delay), value: stepsAnimated)
    }

    // MARK: - Sections

    private func referralCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Theme.modernCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Theme.darkGoldGradient.opacity(0.6), lineWidth: 1.5)
                    )
                    .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 6)
            )
    }

    @ViewBuilder
    private var connectionsSection: some View {
        referralCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Your connections")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.darkGoldGradient)
                    Spacer()
                    Button("Show all") {
                        showHistory = true
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.primaryGold)
                }

                if previewConnections.isEmpty {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "megaphone.fill")
                            .foregroundColor(Theme.primaryGold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No invites yet")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text("Share your code to earn +50 when a friend reaches 50 points.")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    ForEach(previewConnections) { item in
                        ReferralConnectionRow(name: item.name,
                                              relationText: item.isOutbound ? "You referred" : "Referred by",
                                              status: item.status,
                                              pointsTowards50: item.pointsTowards50,
                                              tint: item.isOutbound ? .green : .orange,
                                              createdAt: item.createdAt)
                    }
                }
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.65), value: hasAppeared)
    }

    private var previewConnections: [ReferralDisplay] {
        var result: [ReferralDisplay] = []
        if let inbound = inboundConnection { result.append(inbound) }
        result.append(contentsOf: outboundConnections)
        // Sort by date (most recent first), then by name if dates are equal
        let sorted = result.sorted { item1, item2 in
            let date1 = item1.createdAt ?? Date.distantPast
            let date2 = item2.createdAt ?? Date.distantPast
            if date1 != date2 {
                return date1 > date2
            }
            return item1.name < item2.name
        }
        return Array(sorted.prefix(3))
    }

    @ViewBuilder
    private var codeSection: some View {
        referralCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your referral code")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                if isLoading {
                    ProgressView()
                } else if myCode.isEmpty {
                    Button(action: fetchMyCode) {
                        HStack {
                            Image(systemName: "link.badge.plus")
                            Text("Get My Code")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Theme.primaryGold)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                    }
                } else {
                    VStack(alignment: .center, spacing: 10) {
                        Text(myCode)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .monospaced()
                            .foregroundStyle(Theme.darkGoldGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Theme.modernCardSecondary)
                                    .shadow(color: Theme.cardShadow.opacity(0.6), radius: 10, x: 0, y: 5)
                            )
                            .onTapGesture {
                                UIPasteboard.general.string = myCode
                                logShareEvent(action: "copy")
                                // Immediate feedback for copy action (no share sheet conflict)
                                triggerHapticSuccess()
                                showToastMessage("Copied code")
                            }
                        Text("Friend enters this at sign up")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5), value: hasAppeared)
    }

    @ViewBuilder
    private var enterCodeSection: some View {
        referralCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Have a code?")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)

                HStack {
                    TextField("Enter code", text: $acceptCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .textCase(.uppercase)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)

                    Button(action: acceptReferral) {
                        Text("Submit")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(acceptCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !acceptStatus.isEmpty {
                    Text(acceptStatus)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        Text(errorMessage)
            .foregroundColor(.red)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
    }

    // MARK: - Actions
    private func triggerHapticSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showToast = false
            }
        }
    }
    
    // MARK: - Overlay helpers
    @ViewBuilder
    private var toastOverlay: some View {
        if showToast {
            ToastView(message: toastMessage)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 100)
        }
    }

    // MARK: - Sticky Invite Bar
    fileprivate struct StickyInviteBar: View {
        let shareURL: URL
        let onShare: () -> Void
        var body: some View {
            HStack {
                ShareLink(item: shareURL.absoluteString) {
                    Label("Refer a Friend", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .simultaneousGesture(TapGesture().onEnded({ onShare() }))
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    fileprivate struct FloatingInviteBar: View {
        let shareURL: URL
        let code: String
        let onShare: () -> Void
        let onCopy: () -> Void
        var body: some View {
            HStack(spacing: 12) {
                Button(action: onShare) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Refer a Friend")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Theme.primaryGold)
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    )
                }
                
                Button(action: onCopy) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func evaluateEnterCodeGating(completion: ((Bool) -> Void)? = nil) {
        guard let user = Auth.auth().currentUser else {
            self.canShowEnterCode = false
            completion?(false)
            return
        }
        // If a session flag exists (set during signup), treat as already used and hide input immediately
        if let _ = UserDefaults.standard.dictionary(forKey: sessionKey) as? [String: String] {
            self.hasUsedReferral = true
            self.canShowEnterCode = false
            completion?(false)
            return
        }
        // Account age gate: only within first 24 hours
        let creationDate = user.metadata.creationDate
        let within24h: Bool
        if let c = creationDate {
            within24h = Date().timeIntervalSince(c) < 24 * 60 * 60
        } else {
            within24h = false
        }
        let db = Firestore.firestore()
        db.collection("users").document(user.uid).getDocument { snap, error in
            if let error = error {
                DebugLogger.debug("❌ ReferralView: Error checking referral status: \(error.localizedDescription)", category: "Referral")
            }
            let used = (snap?.data()? ["referredBy"] as? String)?.isEmpty == false
            self.hasUsedReferral = used
            // Show only if within 24h AND no referral already used
            let allowed = within24h && !used
            DispatchQueue.main.async {
                self.canShowEnterCode = allowed
                completion?(allowed)
            }
        }
    }

    /// Maps raw Firestore status to display: "Awarded" | "Cancelled" | "Pending".
    private static func displayStatus(from raw: String) -> String {
        switch raw {
        case "awarded": return "Awarded"
        case "cancelled": return "Cancelled"
        default: return "Pending"
        }
    }

    private func listenForConnections() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        // Outbound: I referred others (limited to 100 for performance)
        outboundListener?.remove()
        outboundListener = db.collection("referrals")
            .whereField("referrerUserId", isEqualTo: uid)
            .limit(to: 100)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else {
                    self.outboundConnections = []
                    return
                }
                // IMPORTANT: Do not read users/{uid} for other users here (blocked by Firestore rules).
                // Use denormalized names and progress stored on the referral doc.
                let items: [ReferralDisplay] = docs.map { d in
                    let data = d.data()
                    let statusRaw = (data["status"] as? String) ?? "pending"
                    let status = Self.displayStatus(from: statusRaw)
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                    let rawName = (data["referredFirstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    // If this referral doc predates denormalized names, don't overwrite a better name
                    // that may have come from the server fallback.
                    let existingName = self.outboundConnections.first(where: { $0.id == d.documentID })?.name
                    let name = rawName.isEmpty ? (existingName ?? "Friend") : rawName
                    // Read pointsTowards50 from referral doc (maintained by Cloud Function)
                    let ptsRaw = (data["pointsTowards50"] as? NSNumber)?.intValue ?? (data["pointsTowards50"] as? Int) ?? 0
                    let pointsTowards50 = min(max(ptsRaw, 0), 50) // Clamp to 0-50
                    return ReferralDisplay(id: d.documentID, name: name, status: status, isOutbound: true, pointsTowards50: pointsTowards50, createdAt: createdAt)
                }
                DispatchQueue.main.async {
                    self.outboundConnections = items.sorted { item1, item2 in
                        // Sort by date (most recent first), then by name if dates are equal
                        let date1 = item1.createdAt ?? Date.distantPast
                        let date2 = item2.createdAt ?? Date.distantPast
                        if date1 != date2 {
                            return date1 > date2
                        }
                        return item1.name < item2.name
                    }
                }
            }

        // Inbound: I used someone's code (I was referred by)
        inboundListener?.remove()
        inboundListener = db.collection("referrals")
            .whereField("referredUserId", isEqualTo: uid)
            .limit(to: 1)
            .addSnapshotListener { snap, _ in
                guard let doc = snap?.documents.first else {
                    self.inboundConnection = nil
                    return
                }
                let data = doc.data()
                let statusRaw = (data["status"] as? String) ?? "pending"
                let status = Self.displayStatus(from: statusRaw)
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                // Tombstoned docs may have referrerUserId removed; we still show "Deleted User" from referrerFirstName.
                let rawName = (data["referrerFirstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let name = rawName.isEmpty ? (self.inboundConnection?.name ?? "Friend") : rawName
                let ptsRaw = (data["pointsTowards50"] as? NSNumber)?.intValue ?? (data["pointsTowards50"] as? Int) ?? 0
                let pointsTowards50 = min(max(ptsRaw, 0), 50) // Clamp to 0-50
                DispatchQueue.main.async {
                    self.inboundConnection = ReferralDisplay(id: doc.documentID, name: name, status: status, isOutbound: false, pointsTowards50: pointsTowards50, createdAt: createdAt)
                }
            }
    }

    private func startUserDocListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let within24h: Bool = {
            if let c = Auth.auth().currentUser?.metadata.creationDate {
                return Date().timeIntervalSince(c) < 24 * 60 * 60
            }
            return false
        }()
        let db = Firestore.firestore()
        userDocListener?.remove()
        userDocListener = db.collection("users").document(uid).addSnapshotListener { snap, _ in
            let data = snap?.data() ?? [:]
            let referredById = (data["referredBy"] as? String) ?? ""
            let referralId = (data["referralId"] as? String) ?? ""
            let used = !referredById.isEmpty
            self.hasUsedReferral = used
            self.canShowEnterCode = within24h && !used

            // If a referral was linked during sign-up, show inbound pending immediately
            if used {
                // IMPORTANT: Do not read users/{uid} for other users here (blocked by Firestore rules).
                // Fetch referral doc (read is allowed for referrer/referred) and use denormalized name fields.
                let updateFromReferralDoc: (DocumentSnapshot?) -> Void = { refDoc in
                    let refData = refDoc?.data() ?? [:]
                    let statusRaw = (refData["status"] as? String) ?? "pending"
                    let status = ReferralView.displayStatus(from: statusRaw)
                    let createdAt = (refData["createdAt"] as? Timestamp)?.dateValue()
                    let rawName = (refData["referrerFirstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let name = rawName.isEmpty ? (self.inboundConnection?.name ?? "Friend") : rawName
                    // Read pointsTowards50 from referral doc (maintained by Cloud Function)
                    let ptsRaw = (refData["pointsTowards50"] as? NSNumber)?.intValue ?? (refData["pointsTowards50"] as? Int) ?? 0
                    let pointsTowards50 = min(max(ptsRaw, 0), 50) // Clamp to 0-50
                    // For inbound, also check current user's own points as a fallback if referral doc doesn't have progress yet
                    let currentUserPoints = (data["points"] as? Int) ?? 0
                    let finalProgress = pointsTowards50 > 0 ? pointsTowards50 : min(max(currentUserPoints, 0), 50)
                    DispatchQueue.main.async {
                        let idToUse = (refDoc?.documentID ?? (referralId.isEmpty ? UUID().uuidString : referralId))
                        self.inboundConnection = ReferralDisplay(id: idToUse, name: name, status: status, isOutbound: false, pointsTowards50: finalProgress, createdAt: createdAt ?? self.inboundConnection?.createdAt)
                    }
                }

                if !referralId.isEmpty {
                    db.collection("referrals").document(referralId).getDocument { refDoc, error in
                        if let error = error {
                            DebugLogger.debug("❌ ReferralView: Error loading referral doc: \(error.localizedDescription)", category: "Referral")
                        }
                        updateFromReferralDoc(refDoc)
                    }
                } else {
                    db.collection("referrals").whereField("referredUserId", isEqualTo: uid).limit(to: 1).getDocuments { snap, error in
                        if let error = error {
                            DebugLogger.debug("❌ ReferralView: Error querying referrals: \(error.localizedDescription)", category: "Referral")
                        }
                        updateFromReferralDoc(snap?.documents.first)
                    }
                }
            }
        }
    }

    private func hydrateFromSessionFlagIfPresent() {
        guard let dict = UserDefaults.standard.dictionary(forKey: sessionKey) as? [String: String] else { return }
        // Hide input immediately
        self.hasUsedReferral = true
        self.canShowEnterCode = false
        if let rid = dict["referrerUserId"], !rid.isEmpty {
            // Can't read users/{rid} as a non-admin; show placeholder and let the
            // referrals listener / server fallback populate the real name.
            // Progress will be updated by the referral doc listener (which reads from referral doc)
            // or by the user doc listener (which can read our own points)
            DispatchQueue.main.async {
                if self.inboundConnection == nil {
                    self.inboundConnection = ReferralDisplay(id: UUID().uuidString, name: "Friend", status: "Pending", isOutbound: false, pointsTowards50: 0, createdAt: nil)
                }
            }
        }
        // Try server fallback to confirm and then clear session flag
        fetchConnectionsViaServer()
    }

    private func fetchConnectionsViaServer() {
        guard let user = Auth.auth().currentUser else { return }
        user.getIDToken { token, _ in
            guard let token = token, let url = URL(string: "\(Config.backendURL)/referrals/mine") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.configured.dataTask(with: req) { [weak self] data, resp, error in
                guard let self = self else { return }
                if let error = error {
                    DebugLogger.debug("❌ ReferralView: Error fetching connections: \(error.localizedDescription)", category: "Referral")
                    return
                }
                guard let http = resp as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300, let data = data else { return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let inbound = json["inbound"] as? [String: Any] {
                        let name = (inbound["referrerName"] as? String) ?? "Friend"
                        let statusRaw = (inbound["status"] as? String) ?? "pending"
                        let status = ReferralView.displayStatus(from: statusRaw)
                        DispatchQueue.main.async {
                            let pts = (inbound["pointsTowards50"] as? NSNumber)?.intValue ?? (inbound["pointsTowards50"] as? Int) ?? 0
                            // Note: Server API doesn't return createdAt, so we'll use nil and let the listener update it
                            self.inboundConnection = ReferralDisplay(id: (inbound["referralId"] as? String) ?? UUID().uuidString, name: name, status: status, isOutbound: false, pointsTowards50: min(max(pts, 0), 50), createdAt: nil)
                            // Clear session since server confirms
                            UserDefaults.standard.removeObject(forKey: self.sessionKey)
                        }
                    }
                    if let outs = json["outbound"] as? [[String: Any]] {
                        let mapped: [ReferralDisplay] = outs.map { o in
                            let name = (o["referredName"] as? String) ?? "Friend"
                            let statusRaw = (o["status"] as? String) ?? "pending"
                            let status = ReferralView.displayStatus(from: statusRaw)
                            let pts = (o["pointsTowards50"] as? NSNumber)?.intValue ?? (o["pointsTowards50"] as? Int) ?? 0
                            // Note: Server API doesn't return createdAt, so we'll use nil and let the listener update it
                            return ReferralDisplay(id: (o["referralId"] as? String) ?? UUID().uuidString, name: name, status: status, isOutbound: true, pointsTowards50: min(max(pts, 0), 50), createdAt: nil)
                        }
                        DispatchQueue.main.async { self.outboundConnections = mapped }
                    }
                }
            }.resume()
        }
    }
    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let (bg, fg): (Color, Color) = {
            switch status {
            case "Awarded": return (Color.green.opacity(0.2), Color.green)
            case "Cancelled": return (Color.gray.opacity(0.2), Color.gray)
            default: return (Color.orange.opacity(0.2), Color.orange)
            }
        }()
        Text(status.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(bg))
            .foregroundColor(fg)
    }

    @ViewBuilder
    private func avatar(for name: String, tint: Color) -> some View {
        let initial = String(name.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "F").uppercased()
        ZStack {
            Circle().fill(tint.opacity(0.15))
            Text(initial)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(tint)
        }
        .frame(width: 32, height: 32)
        .accessibilityLabel(Text("Friend: \(name)"))
    }

    private func logShareEvent(action: String) {
        guard let user = Auth.auth().currentUser else { return }
        guard !myCode.isEmpty else { return }
        user.getIDToken { token, _ in
            guard let token = token else { return }
            guard let url = URL(string: "\(Config.backendURL)/analytics/referral-share") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "code": myCode,
                "action": action,
                "shareUrl": shareURL?.absoluteString ?? ""
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            URLSession.configured.dataTask(with: req).resume()
        }
    }

    private func fetchMyCode() {
        guard let user = Auth.auth().currentUser else {
            self.errorMessage = "Please sign in to get your referral code."
            return
        }
        isLoading = true
        errorMessage = ""

        user.getIDToken(completion: { token, err in
            if let err = err {
                self.isLoading = false
                self.errorMessage = "Auth error: \(err.localizedDescription)"
                return
            }
            guard let token = token else {
                self.isLoading = false
                self.errorMessage = "Missing auth token."
                return
            }
            guard let url = URL(string: "\(Config.backendURL)/referrals/create") else {
                self.isLoading = false
                self.errorMessage = "Invalid URL configuration."
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.addValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = Data("{}".utf8)

            URLSession.configured.dataTask(with: req) { [weak self] data, resp, err in
                guard let self = self else { return }
                DispatchQueue.main.async { self.isLoading = false }
                if let err = err {
                    DispatchQueue.main.async { self.errorMessage = err.localizedDescription }
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    DispatchQueue.main.async { self.errorMessage = "No response from server" }
                    return
                }
                let status = http.statusCode
                if status < 200 || status >= 300 {
                    let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let serverError = (json["error"] as? String) ?? (json["message"] as? String) ?? "Server error \(status)"
                        DispatchQueue.main.async { self.errorMessage = serverError }
                    } else {
                        DispatchQueue.main.async { self.errorMessage = "Server error \(status): \(bodyText)" }
                    }
                    return
                }
                guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async { self.errorMessage = "Invalid server response (parse)" }
                    return
                }
                if let serverError = (json["error"] as? String) ?? (json["message"] as? String) {
                    DispatchQueue.main.async { self.errorMessage = serverError }
                    return
                }
                let code = (json["code"] as? String) ?? ""
                // Prefer web URL so QR/share works for users who don't have the app installed yet.
                let share = (json["webUrl"] as? String) ?? (json["shareUrl"] as? String) ?? ""
                if code.isEmpty {
                    DispatchQueue.main.async { self.errorMessage = "Missing code in response" }
                    return
                }
                DispatchQueue.main.async {
                    self.myCode = code
                    self.shareURL = URL(string: share)
                    
                    // Cache the referral code for instant loading next time
                    if let userId = Auth.auth().currentUser?.uid {
                        ReferralCache.save(code: code, shareUrl: share, userId: userId)
                    }
                }
            }.resume()
        })
    }

    private func acceptReferral() {
        guard canShowEnterCode else {
            self.acceptStatus = "Referral code entry not available."
            return
        }
        let trimmed = acceptCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        guard let user = Auth.auth().currentUser else {
            self.acceptStatus = "Please sign in to accept a referral."
            return
        }
        acceptStatus = "Linking..."
        errorMessage = ""

        user.getIDToken { token, err in
            if let err = err {
                DispatchQueue.main.async { self.acceptStatus = "Auth error: \(err.localizedDescription)" }
                return
            }
            guard let token = token else {
                DispatchQueue.main.async { self.acceptStatus = "Missing auth token." }
                return
            }
            guard let url = URL(string: "\(Config.backendURL)/referrals/accept") else {
                DispatchQueue.main.async { self.acceptStatus = "Invalid URL configuration." }
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            DeviceFingerprint.addToRequest(&req)
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
            let body: [String: Any] = ["code": trimmed, "deviceId": deviceId]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)

            URLSession.configured.dataTask(with: req) { [weak self] data, resp, err in
                guard let self = self else { return }
                if let err = err {
                    DispatchQueue.main.async { self.acceptStatus = err.localizedDescription }
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    DispatchQueue.main.async { self.acceptStatus = "No response from server" }
                    return
                }
                if http.statusCode >= 200 && http.statusCode < 300 {
                    var referrerId: String? = nil
                    var referrerFirstName: String? = nil
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        referrerId = json["referrerUserId"] as? String
                        referrerFirstName = json["referrerFirstName"] as? String
                    }
                    DispatchQueue.main.async {
                        // Update UI immediately without waiting for backend propagation
                        self.acceptStatus = "Linked! Award comes after your first 50 points."
                        self.hasUsedReferral = true
                        self.canShowEnterCode = false
                        triggerHapticSuccess()
                        showToastMessage("Referral linked")
                        // Persist session flag so other flows/screens also hide input immediately
                        var payload: [String: String] = [:]
                        if let rid = referrerId { payload["referrerUserId"] = rid }
                        UserDefaults.standard.set(payload, forKey: self.sessionKey)
                        if let rid = referrerId, !rid.isEmpty {
                            let rawName = (referrerFirstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let name = rawName.isEmpty ? "Friend" : rawName
                            self.inboundConnection = ReferralDisplay(id: UUID().uuidString, name: name, status: "Pending", isOutbound: false, pointsTowards50: 0, createdAt: nil)
                        }
                        // Also refresh the connections listeners to pick up the new referral doc
                        self.listenForConnections()
                        // Server fallback to confirm and clear session
                        self.fetchConnectionsViaServer()
                    }
                } else if let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let errorCode = json["error"] as? String ?? ""
                    let message = json["message"] as? String
                    
                    var displayMessage: String
                    if errorCode == "referral_cap_reached" {
                        displayMessage = "This user has reached their referral limit"
                    } else if errorCode == "referral_already_used" {
                        // Phone hash pair already exists - user previously used a referral with this referrer
                        displayMessage = "You've already used a referral code previously"
                    } else if errorCode == "already_used_referral" {
                        // User already has a referrer on this account
                        displayMessage = "You've already used a referral code"
                    } else if let msg = message {
                        displayMessage = msg
                    } else {
                        displayMessage = errorCode.replacingOccurrences(of: "_", with: " ").capitalized
                        if displayMessage.isEmpty {
                            displayMessage = "Failed to accept referral"
                        }
                    }
                    
                    DispatchQueue.main.async { self.acceptStatus = displayMessage }
                } else {
                    DispatchQueue.main.async { self.acceptStatus = "Failed to accept referral (\(http.statusCode))" }
                }
            }.resume()
        }
    }
}

// MARK: - Toast
fileprivate struct ToastView: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 2)
    }
}

// MARK: - Share Sheet
fileprivate struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - Referral Connection Row
fileprivate struct ReferralConnectionRow: View {
    let name: String
    let relationText: String
    let status: String // "Pending" | "Awarded"
    let pointsTowards50: Int
    let tint: Color
    let createdAt: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    (Text(relationText + " ") + Text(name).fontWeight(.bold))
                    Spacer()
                    badge(status)
                }
                if let date = createdAt {
                    Text(date, style: .date)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                if status == "Cancelled" {
                    // No progress bar for tombstoned referrals
                } else if status == "Pending" {
                    GoldProgressBar(value: pointsTowards50)
                } else {
                    GoldProgressBar(value: 50)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(relationText) \(name), status \(status)\(status == "Cancelled" ? "" : ", progress \(min(pointsTowards50, 50))/50")"))
    }

    @ViewBuilder
    private var avatar: some View {
        let initial = String(name.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "F").uppercased()
        ZStack {
            Circle().fill(tint.opacity(0.15))
            Text(initial)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(tint)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func badge(_ status: String) -> some View {
        let (bg, fg): (Color, Color) = {
            switch status {
            case "Awarded": return (Color.green.opacity(0.2), Color.green)
            case "Cancelled": return (Color.gray.opacity(0.2), Color.gray)
            default: return (Color.orange.opacity(0.2), Color.orange)
            }
        }()
        Text(status.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(bg))
            .foregroundColor(fg)
    }
}

// MARK: - QR Code
fileprivate final class QRCodeImageCache {
    static let shared = QRCodeImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func get(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

fileprivate enum QRCodeRenderer {
    static func renderCGImage(from string: String, size: CGFloat) -> CGImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scale = max(1, Int((size / output.extent.size.width).rounded()))
        let transform = CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))
        let scaled = output.transformed(by: transform)
        return context.createCGImage(scaled, from: scaled.extent)
    }
}

fileprivate struct QRCodeView: View {
    let url: URL
    @State private var image: UIImage? = nil

    private var cacheKey: String { "\(url.absoluteString)|small|72" }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.gray)
            }
        }
        .frame(width: 72, height: 72)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(Text("QR code for sharing"))
        .task(id: url.absoluteString) {
            if let cached = QRCodeImageCache.shared.get(cacheKey) {
                image = cached
                return
            }

            let string = url.absoluteString
            let cg: CGImage? = await Task.detached(priority: .userInitiated) {
                QRCodeRenderer.renderCGImage(from: string, size: 72)
            }.value

            guard let cg else { return }
            let ui = UIImage(cgImage: cg)
            QRCodeImageCache.shared.set(ui, for: cacheKey)
            image = ui
        }
    }
}

fileprivate struct LargeQRCodeView: View {
    let url: URL
    let size: CGFloat
    @State private var image: UIImage? = nil

    private var cacheKey: String { "\(url.absoluteString)|large|\(Int(size.rounded()))" }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.gray)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(Text("Large QR code for sharing"))
        .task(id: cacheKey) {
            if let cached = QRCodeImageCache.shared.get(cacheKey) {
                image = cached
                return
            }

            let string = url.absoluteString
            let targetSize = size
            let cg: CGImage? = await Task.detached(priority: .userInitiated) {
                QRCodeRenderer.renderCGImage(from: string, size: targetSize)
            }.value

            guard let cg else { return }
            let ui = UIImage(cgImage: cg)
            QRCodeImageCache.shared.set(ui, for: cacheKey)
            image = ui
        }
    }
}

// MARK: - Code Ticket Card
fileprivate struct ReferralCodeTicketCard: View {
    let code: String
    let shareURL: URL?
    let onShare: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(code)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .monospaced()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(14)

                Text("Friend enters this at signup")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    if shareURL != nil {
                        Button(action: onShare) {
                            Label("Refer a Friend", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(Text("Refer a friend"))
                    }

                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Copy code"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let url = shareURL {
                VStack(spacing: 6) {
                    QRCodeView(url: url)
                    Text("Scan to join")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - Gold Progress Bar
fileprivate struct GoldProgressBar: View {
    let value: Int // 0...50
    private var clamped: Int { min(max(value, 0), 50) }
    private var percent: CGFloat { CGFloat(clamped) / 50.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 8)
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.darkGoldGradient)
                        .frame(width: geo.size.width * percent, height: 8)
                        .animation(.easeOut(duration: 0.35), value: percent)
                }
                .frame(height: 8)
            }
            Text("\(clamped)/50")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .accessibilityLabel(Text("\(clamped) of 50 points"))
        }
    }
}
