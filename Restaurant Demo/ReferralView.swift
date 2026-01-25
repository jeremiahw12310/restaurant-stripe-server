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
            print("📦 Cached referral code for user \(userId)")
        }
    }
    
    static func load(userId: String) -> (code: String, shareUrl: String)? {
        guard let data = UserDefaults.standard.data(forKey: cacheKeyPrefix + userId),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else {
            return nil
        }
        print("📦 Loaded cached referral code for user \(userId)")
        return (cached.code, cached.shareUrl)
    }
    
    static func clear(userId: String) {
        UserDefaults.standard.removeObject(forKey: cacheKeyPrefix + userId)
        print("📦 Cleared referral cache for user \(userId)")
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
            print("🗑️ Cleared legacy referral cache: \(key)")
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
        NavigationView {
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
                        header
                        bigQRSection
                        codeSection
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
            .toolbar {
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
            print("🪪 ReferralView appeared")
            
            // Load from cache first for instant display
            if myCode.isEmpty, let userId = Auth.auth().currentUser?.uid {
                if let cached = ReferralCache.load(userId: userId) {
                    myCode = cached.code
                    shareURL = URL(string: cached.shareUrl)
                    print("✅ Referral code loaded from cache instantly")
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
        }
        .onDisappear {
            outboundListener?.remove(); outboundListener = nil
            inboundListener?.remove(); inboundListener = nil
            userDocListener?.remove(); userDocListener = nil
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
            Text("Give 50, Get 50")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(Theme.darkGoldGradient)
            Text("Refer a friend. When they earn 50 points you will both receive an additional 50 points.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
    }

    @ViewBuilder
    private var bigQRSection: some View {
        if let url = shareURL {
            VStack(spacing: 10) {
                LargeQRCodeView(url: url, size: 300)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                Text("Scan to join")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("QR code with your referral link"))
            .padding(.vertical, 4)
            .scaleEffect(hasAppeared ? 1.0 : 0.85)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.35), value: hasAppeared)
        }
    }

    private var inboundStatus: String { inboundConnection?.status ?? "" }
    private var outboundAwardedSignature: [String] {
        outboundConnections.map { "\($0.id)|\($0.status)" }
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
                    Text("New connections")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Show all") {
                        showHistory = true
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
        if !outboundConnections.isEmpty {
            result.append(contentsOf: outboundConnections.prefix(max(0, 3 - result.count)))
        }
        return Array(result.prefix(3))
    }

    @ViewBuilder
    private var codeSection: some View {
        referralCard {
            VStack(alignment: .leading, spacing: 16) {
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
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .monospaced()
                            .foregroundStyle(Theme.darkGoldGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.vertical, 16)
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
                .padding(.bottom, 12)
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
        db.collection("users").document(user.uid).getDocument { snap, _ in
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

    private func listenForConnections() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        // Outbound: I referred others
        outboundListener?.remove()
        outboundListener = db.collection("referrals")
            .whereField("referrerUserId", isEqualTo: uid)
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
                    let status = (statusRaw == "awarded") ? "Awarded" : "Pending"
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
                    self.outboundConnections = items.sorted { $0.name < $1.name }
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
                let referrerId = (data["referrerUserId"] as? String) ?? ""
                let statusRaw = (data["status"] as? String) ?? "pending"
                let status = (statusRaw == "awarded") ? "Awarded" : "Pending"
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                if !referrerId.isEmpty {
                    // IMPORTANT: Do not read users/{uid} for other users here (blocked by Firestore rules).
                    // Use denormalized names and progress stored on the referral doc.
                    let rawName = (data["referrerFirstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let name = rawName.isEmpty ? (self.inboundConnection?.name ?? "Friend") : rawName
                    // Read pointsTowards50 from referral doc (maintained by Cloud Function)
                    let ptsRaw = (data["pointsTowards50"] as? NSNumber)?.intValue ?? (data["pointsTowards50"] as? Int) ?? 0
                    let pointsTowards50 = min(max(ptsRaw, 0), 50) // Clamp to 0-50
                    DispatchQueue.main.async {
                        self.inboundConnection = ReferralDisplay(id: doc.documentID, name: name, status: status, isOutbound: false, pointsTowards50: pointsTowards50, createdAt: createdAt)
                    }
                } else {
                    self.inboundConnection = nil
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
                    let status = (statusRaw == "awarded") ? "Awarded" : "Pending"
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
                    db.collection("referrals").document(referralId).getDocument { refDoc, _ in
                        updateFromReferralDoc(refDoc)
                    }
                } else {
                    db.collection("referrals").whereField("referredUserId", isEqualTo: uid).limit(to: 1).getDocuments { snap, _ in
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
            // For inbound progress, we can use current user's own points as a fast-path
            // (since we can read our own user doc), but prefer referral doc value when available
            let currentUserPoints = (data["points"] as? Int) ?? 0
            let fallbackProgress = min(max(currentUserPoints, 0), 50)
            DispatchQueue.main.async {
                if self.inboundConnection == nil {
                    self.inboundConnection = ReferralDisplay(id: UUID().uuidString, name: "Friend", status: "Pending", isOutbound: false, pointsTowards50: fallbackProgress, createdAt: nil)
                } else if let existing = self.inboundConnection, existing.pointsTowards50 == 0 {
                    // Update progress if referral doc hasn't been updated yet
                    self.inboundConnection = ReferralDisplay(id: existing.id, name: existing.name, status: existing.status, isOutbound: existing.isOutbound, pointsTowards50: fallbackProgress, createdAt: existing.createdAt)
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
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                guard let http = resp as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300, let data = data else { return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let inbound = json["inbound"] as? [String: Any] {
                        let name = (inbound["referrerName"] as? String) ?? "Friend"
                        let statusRaw = (inbound["status"] as? String) ?? "pending"
                        let status = (statusRaw == "awarded") ? "Awarded" : "Pending"
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
                            let status = (statusRaw == "awarded") ? "Awarded" : "Pending"
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
        Text(status.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(status == "Awarded" ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            )
            .foregroundColor(status == "Awarded" ? .green : .orange)
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
            let url = URL(string: "\(Config.backendURL)/analytics/referral-share")!
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
            URLSession.shared.dataTask(with: req).resume()
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
            let url = URL(string: "\(Config.backendURL)/referrals/create")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.addValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = Data("{}".utf8)

            URLSession.shared.dataTask(with: req) { data, resp, err in
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
            let url = URL(string: "\(Config.backendURL)/referrals/accept")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            DeviceFingerprint.addToRequest(&req)
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
            let body: [String: Any] = ["code": trimmed, "deviceId": deviceId]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)

            URLSession.shared.dataTask(with: req) { data, resp, err in
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
                    let reason = (json["error"] as? String) ?? (json["message"] as? String) ?? "Failed"
                    DispatchQueue.main.async { self.acceptStatus = reason.replacingOccurrences(of: "_", with: " ") }
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
                if status == "Pending" {
                    GoldProgressBar(value: pointsTowards50)
                } else {
                    GoldProgressBar(value: 50)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(relationText) \(name), status \(status), progress \(min(pointsTowards50, 50))/50"))
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
        Text(status.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(status == "Awarded" ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            )
            .foregroundColor(status == "Awarded" ? .green : .orange)
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
