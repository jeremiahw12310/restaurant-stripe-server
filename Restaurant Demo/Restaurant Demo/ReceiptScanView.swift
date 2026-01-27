import SwiftUI
import Vision
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import CoreMedia

struct ReceiptScanView: View {
    @StateObject private var userVM = UserViewModel()
    @StateObject private var menuVM = MenuViewModel()
    @State private var showCamera = false
    @State private var scannedImage: UIImage?
    @State private var isProcessing = false
    @State private var showCongratulations = false
    @State private var showReceiptUsedScreen = false
    @State private var receiptTotal: Double = 0.0
    @State private var pointsEarned: Int = 0
    @State private var errorMessage = ""
    @State private var showCameraPermissionScreen = false
    @State private var cameraPermissionDenied = false
    @State private var scannedText = ""
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var onPointsEarned: ((Int) -> Void)? = nil
    @State private var showLoadingOverlay = false
    @State private var showDumplingRain = false
    @State private var shouldSwitchToHome = false
    @State private var lastOrderNumber: String? = nil
    @State private var lastOrderDate: String? = nil
    // Combo interstitial + result
    @State private var isComboReady = false
    @State private var isInterstitialDone = false
    @State private var hasStartedComboGeneration = false
    @State private var personalizedCombo: PersonalizedCombo?
    @State private var showComboResult = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var presentedOutcome: ReceiptScanOutcome? = nil
    @State private var comboState: ComboGenerationState = .loading
    @State private var showReferral = false
    // Interstitial control: allow early cut and clean looping
    @State private var interstitialEarlyCutRequested = false
    // Validation state to prevent premature success screen
    @State private var receiptPassedValidation = false
    @State private var pendingPoints: Int = 0
    @State private var pendingTotal: Double = 0.0
    // Store pending error outcome if validation fails during interstitial
    @State private var pendingErrorOutcome: ReceiptScanOutcome? = nil
    // Store last captured image for retry functionality
    @State private var lastCapturedImage: UIImage? = nil
    // Admin debug: save preprocessed receipt images to Photos
    @State private var savePreprocessedReceiptToPhotosDebug = false
    // Interstitial coordination: avoid infinite loops / stop on response
    @State private var serverHasResponded = false
    @State private var interstitialTimedOut = false
    @State private var interstitialTimeoutWorkItem: DispatchWorkItem? = nil
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            mainView
            if isProcessing || showLoadingOverlay {
                loadingOverlay
            }
        }
        .onAppear {
            userVM.loadUserData()
            menuVM.fetchMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
            // Handle switching to home tab
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { presentedOutcome != nil },
            set: { newValue in if !newValue { presentedOutcome = nil } }
        )) {
            if let outcome = presentedOutcome {
                ReceiptResultView(
                    outcome: outcome,
                    comboState: comboState,
                    personalizedCombo: personalizedCombo,
                    onPrimary: { handlePrimaryAction(for: outcome) },
                    onSecondary: { handleSecondaryAction(for: outcome) },
                    onDismiss: { presentedOutcome = nil },
                    onRetryCombo: { retryComboGeneration() }
                )
                .environmentObject(menuVM)
            }
        }
        .onChange(of: showLoadingOverlay) { _, _ in
            // Combo generation removed
        }
        .onChange(of: shouldSwitchToHome) { newValue, _ in
            if newValue {
                switchToHomeTab()
                // Reset all relevant state
                showReceiptUsedScreen = false
                showCongratulations = false
                errorMessage = ""
                showDumplingRain = false
                shouldSwitchToHome = false
            }
        }
        .sheet(isPresented: $showCameraPermissionScreen) {
            CameraPrePermissionView(
                isPermissionDenied: cameraPermissionDenied,
                onRequestAccess: { requestCameraAccess() },
                onOpenSettings: { openAppSettings() },
                onDismiss: { showCameraPermissionScreen = false }
            )
        }
        .sheet(isPresented: $showCamera) {
            CameraViewWithOverlay(image: $scannedImage) { image in
                showCamera = false
                if let image = image {
                    // Guard: don't process if already processing
                    guard !isProcessing else {
                        DebugLogger.debug("⚠️ Image capture ignored - already processing", category: "ReceiptScan")
                        return
                    }
                    showLoadingOverlay = true
                    processReceiptImage(image)
                }
            }
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            // Non-skippable interstitial using combo_gen video with double flash
            VideoInterstitialView(
                videoName: "scandump",
                videoType: "mov",
                flashStyle: .double,
                earlyCutRequested: $interstitialEarlyCutRequested,
                earlyCutLeadSeconds: 1.0
            ) {
                interstitialDidFinish()
            }
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Text(" ")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .transition(.opacity)
        .zIndex(10)
    }
    
    private var mainView: some View {
        ZStack {
            // Hybrid Energy background to match Home/Chatbot
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
            // Always-on gold blob background (subtle, slow)
            GoldBlobBackground()
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 20)

                // Text-only header (reduced hero prominence)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scan & Earn")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.darkGoldGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                    }
                    .layoutPriority(1)
                    Spacer()
                    // Dumpphone image in header (no glow/shimmer), 50% larger with small-screen cap
                    Image("dumpphone")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: min(90, UIScreen.main.bounds.width * 0.22),
                            height: min(90, UIScreen.main.bounds.width * 0.22)
                        )
                        .layoutPriority(0)
                }
                .padding(.horizontal, 24)

                // Small Refer button near top
                HStack {
                    Spacer()
                    Button(action: { showReferral = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16, weight: .bold))
                            Text("Refer a Friend")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(height: 48)
                        .background(
                            Capsule()
                                .fill(LinearGradient(gradient: Gradient(colors: [Theme.energyBlue, Theme.energyBlue.opacity(0.85)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: Theme.cardShadow, radius: 6, x: 0, y: 3)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 24)
                }

                // Glass info card with steps
                VStack(spacing: 18) {
                    HStack(alignment: .center, spacing: 12) {
                        stepIcon("camera.fill", color: Theme.energyBlue)
                        stepText(title: "Scan your receipt", subtitle: "Keep the whole receipt visible")
                        Spacer()
                    }
                    HStack(alignment: .center, spacing: 12) {
                        Image("newhero")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                        stepText(title: "Dumpling Hero AI counts points", subtitle: "Your receipt is processed securely")
                        Spacer()
                    }
                    HStack(alignment: .center, spacing: 12) {
                        stepIcon("gift.fill", color: Theme.primaryGold)
                        stepText(title: "Earn Rewards", subtitle: "5 pts per dollar, instantly")
                        Spacer()
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Theme.modernCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Theme.darkGoldGradient, lineWidth: 2)
                        )
                        .shadow(color: Theme.cardShadow, radius: 14, x: 0, y: 6)
                )
                .padding(.horizontal, 24)

                // Admin-only old receipt testing toggle
                if userVM.isAdmin {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $userVM.oldReceiptTestingEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Allow old receipts for testing")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text("Admin only. Temporarily relaxes the 48-hour limit for this account. Tampering checks still apply.")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.modernSecondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Theme.energyBlue))
                        .onChange(of: userVM.oldReceiptTestingEnabled) { newValue in
                            userVM.updateOldReceiptTestingEnabled(newValue)
                        }
                    }
                    .padding(.horizontal, 24)

                    #if DEBUG
                    // Admin debug toggle: save preprocessed images to Photos to verify cropping
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $savePreprocessedReceiptToPhotosDebug) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save preprocessed receipt image to Photos (debug)")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text("Admin only. Saves the cropped/perspective-corrected image before upload so you can verify detection.")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.modernSecondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Theme.energyOrange))
                        .onChange(of: savePreprocessedReceiptToPhotosDebug) { newValue in
                            if newValue {
                                requestPhotoLibraryAddPermissionIfNeeded()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    #endif
                }

                Spacer()

                // Primary CTA
                VStack(spacing: 14) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.primaryGold))
                    } else {
                        Button(action: { checkCameraPermission() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 19, weight: .bold))
                                Text("Start Scan")
                                    .font(.system(size: 19, weight: .black, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(Theme.darkGoldGradient)
                                    .shadow(color: Theme.goldShadow, radius: 12, x: 0, y: 6)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 24)
                    }

                    // Secondary affordances
                    Text("Trouble scanning? Try brighter lighting and keep the receipt flat.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.modernSecondary)
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 36)
            }
        }
        .sheet(isPresented: $showReferral) {
            ReferralView(initialCode: nil)
                .environmentObject(userVM)
        }
    }
    
    private var congratulationsView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Celebration headline
            VStack(spacing: 10) {
                Text("+\(pointsEarned) pts")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.darkGoldGradient)
                    .shadow(color: Theme.goldShadow.opacity(0.35), radius: 10, x: 0, y: 6)
                Text("Added to your balance")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.modernSecondary)
            }

            // Glass stats card
            VStack(spacing: 14) {
                detailRow(title: "Receipt Total", value: String(format: "$%.2f", receiptTotal))
                detailRow(title: "Rate", value: "5 pts per dollar")
                detailRow(title: "Points Earned", value: "\(pointsEarned)")
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.modernCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Theme.darkGoldGradient, lineWidth: 2)
                    )
                    .shadow(color: Theme.cardShadow, radius: 14, x: 0, y: 6)
            )
            .padding(.horizontal, 24)

            // CTAs
            HStack(spacing: 12) {
                Button(action: {
                    NotificationCenter.default.post(name: Notification.Name("openRewards"), object: nil)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("View Rewards")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Theme.darkGoldGradient)
                            .shadow(color: Theme.goldShadow, radius: 8, x: 0, y: 4)
                    )
                }

                Button(action: {
                    NotificationCenter.default.post(name: Notification.Name("openOrder"), object: nil)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "bag.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Order Now")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Theme.energyOrange, Theme.energyRed]),
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .shadow(color: Theme.energyOrange.opacity(0.35), radius: 8, x: 0, y: 4)
                    )
                }
            }
            .padding(.horizontal, 24)

            // Auto-return note
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Theme.primaryGold)
                Text("Returning to home…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.modernSecondary)
            }
            .padding(.top, 4)
            .padding(.bottom, 36)

            Spacer(minLength: 0)
        }
        .onAppear {
            // Auto-dismiss after 2.5 seconds for smoother transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                shouldSwitchToHome = true
                NotificationCenter.default.post(name: .didEarnPoints, object: nil, userInfo: ["points": pointsEarned])
                onPointsEarned?(pointsEarned)
                withAnimation(.easeInOut(duration: 0.6)) {
                    showCongratulations = false
                    errorMessage = ""
                    showDumplingRain = false
                }
            }
        }
    }
    
    private var receiptUsedView: some View {
        VStack(spacing: 30) {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
                Text("Receipt Already Used")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("A receipt cannot be used more than once. +0 points")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.red)
                if let order = lastOrderNumber, let date = lastOrderDate {
                    Text("Order #: \(order)\nDate: \(date)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            Button("Return to Home") {
                shouldSwitchToHome = true
            }
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 40)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.red))
            .padding(.bottom, 60)
        }
        .transition(.opacity)
    }
    
    private func instructionCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.modernCard)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.darkGoldGradient, lineWidth: 1))
                .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 4)
        )
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
    }
    
    private func switchToHomeTab() {
        // Since this is a tab-based app, we need to use a different approach
        // We'll post a notification that the main app can listen to
        NotificationCenter.default.post(name: .switchToHomeTab, object: nil)
    }
    
    private func processReceiptImage(_ image: UIImage, onTotalsGateFail: (() -> Void)? = nil) {
        isProcessing = true
        errorMessage = ""
        scannedText = ""
        // Reset validation state for new scan
        interstitialEarlyCutRequested = false
        receiptPassedValidation = false
        serverHasResponded = false
        interstitialTimedOut = false
        pendingPoints = 0
        pendingTotal = 0.0
        pendingErrorOutcome = nil
        lastOrderNumber = nil
        lastOrderDate = nil
        interstitialTimeoutWorkItem?.cancel()
        interstitialTimeoutWorkItem = nil
        // Store image for potential retry
        lastCapturedImage = image
        let currentPoints = userVM.points

        // 45s failsafe: if the server never responds, stop looping and show an error.
        // This prevents infinite interstitial loops on hung requests.
        let timeoutItem = DispatchWorkItem {
            guard !self.serverHasResponded else { return }
            self.serverHasResponded = true
            self.interstitialTimedOut = true
            self.isProcessing = false
            self.pendingErrorOutcome = .server
            self.interstitialEarlyCutRequested = true
            NotificationCenter.default.post(name: .interstitialEarlyCutRequested, object: nil)
        }
        interstitialTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 45.0, execute: timeoutItem)

        // Preprocess (crop/perspective-correct) ONLY for receipt scanning to reduce distractions.
        preprocessReceiptImageForUpload(image, debugSaveToPhotos: userVM.isAdmin && savePreprocessedReceiptToPhotosDebug) { processedImage in
            // Client-side gate: prevent hallucinated totals by requiring the Subtotal/Tax/Total section to be visible
            receiptHasSubtotalTaxTotal(processedImage) { hasTotals in
                guard hasTotals else {
                    DispatchQueue.main.async {
                        // Cancel server timeout and stop the interstitial immediately with a clear outcome
                        self.serverHasResponded = true
                        self.interstitialTimeoutWorkItem?.cancel()
                        self.interstitialTimeoutWorkItem = nil
                        self.isProcessing = false
                        self.showLoadingOverlay = false
                        if let onTotalsGateFail {
                            self.interstitialEarlyCutRequested = true
                            NotificationCenter.default.post(name: .interstitialEarlyCutRequested, object: nil)
                            // Small delay to ensure state is reset before reopening camera
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onTotalsGateFail()
                            }
                        } else {
                            self.errorMessage = "Make sure all receipt text is visible and try again."
                            self.pendingErrorOutcome = .totalsNotVisible
                            self.interstitialEarlyCutRequested = true
                            NotificationCenter.default.post(name: .interstitialEarlyCutRequested, object: nil)
                        }
                    }
                    return
                }

                uploadReceiptImage(processedImage) { result in
                    DispatchQueue.main.async {
                    self.isProcessing = false
                    self.serverHasResponded = true
                    self.interstitialTimeoutWorkItem?.cancel()
                    self.interstitialTimeoutWorkItem = nil
                    // If 45s timeout already fired, we presented .server; skip present/post to avoid flash.
                    if self.interstitialTimedOut { return }
                    switch result {
                case .success(let json):
                    // Check if the response contains an error
                    if let errorMessage = json["error"] as? String {
                        let errorCode = json["errorCode"] as? String
                        let errorOutcome = mapErrorToOutcome(errorCode: errorCode, message: errorMessage)
                        self.errorMessage = errorMessage
                        // If interstitial is still showing, store the error to show when it finishes
                        if self.showLoadingOverlay {
                            self.pendingErrorOutcome = errorOutcome
                            // Stop interstitial immediately and show error
                            self.interstitialEarlyCutRequested = true
                            NotificationCenter.default.post(name: .interstitialEarlyCutRequested, object: nil)
                        } else {
                            // Interstitial already finished, show error immediately
                            self.showLoadingOverlay = false
                            presentOutcome(errorOutcome)
                        }
                        return
                    }

                    // Server-authoritative submit-receipt response:
                    // { success: true, receipt: {orderNumber, orderTotal, orderDate, orderTime, ...}, pointsAwarded, ... }
                    if let success = json["success"] as? Bool, success == true,
                       let receipt = json["receipt"] as? [String: Any],
                       let orderNumberRaw = receipt["orderNumber"] as? String,
                       let orderTotal = receipt["orderTotal"] as? Double,
                       let orderDateRaw = receipt["orderDate"] as? String,
                       let pointsAwarded = json["pointsAwarded"] as? Int {

                        let orderNumber = orderNumberRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let orderDate = normalizeReceiptMonthDay(orderDateRaw)

                        self.scannedText = "Order #: \(orderNumber)\nDate: \(orderDate)\nTotal: $\(orderTotal)"
                        self.pendingTotal = orderTotal
                        self.pendingPoints = pointsAwarded
                        self.lastOrderNumber = orderNumber
                        self.lastOrderDate = orderDate

                        // ✅ Server already validated + awarded points atomically.
                        self.receiptTotal = self.pendingTotal
                        self.pointsEarned = self.pendingPoints
                        self.receiptPassedValidation = true
                        // Allow the interstitial to finish early now that the server work is done.
                        self.interstitialEarlyCutRequested = true
                        // Stop interstitial immediately (bypasses SwiftUI binding delay)
                        NotificationCenter.default.post(name: .interstitialEarlyCutRequested, object: nil)

                        DebugLogger.debug("✅ Server awarded receipt points: \(self.pointsEarned), Total: \(self.receiptTotal)", category: "ReceiptScan")
                    } else {
                        self.errorMessage = "Unexpected server response. Please try again."
                        let errorOutcome: ReceiptScanOutcome = .server
                        // If interstitial is still showing, store the error to show when it finishes
                        if self.showLoadingOverlay {
                            self.pendingErrorOutcome = errorOutcome
                            // Stop interstitial immediately and show error
                            self.interstitialEarlyCutRequested = true
                            NotificationCenter.default.post(name: .interstitialEarlyCutRequested, object: nil)
                        } else {
                            self.showLoadingOverlay = false
                            presentOutcome(errorOutcome)
                        }
                    }
                case .failure(let error):
                    self.errorMessage = "Upload failed: \(error.localizedDescription)"
                    let errorOutcome: ReceiptScanOutcome
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .notConnectedToInternet, .timedOut, .networkConnectionLost, .dataNotAllowed:
                            errorOutcome = .network
                        default:
                            errorOutcome = .server
                        }
                    } else {
                        errorOutcome = .server
                    }
                    // If interstitial is still showing, store the error to show when it finishes
                    if self.showLoadingOverlay {
                        self.pendingErrorOutcome = errorOutcome
                        // Stop interstitial immediately and show error
                        self.interstitialEarlyCutRequested = true
                        NotificationCenter.default.post(name: .interstitialEarlyCutRequested, object: nil)
                    } else {
                        self.showLoadingOverlay = false
                        presentOutcome(errorOutcome)
                    }
                }
                    }
                }
            }
        }
    }

    private func interstitialDidFinish() {
        isInterstitialDone = true
        // Immediately hide overlay to prevent video restart
        DispatchQueue.main.async {
            self.showLoadingOverlay = false
            
            // Check if there's a pending error outcome (validation failed during interstitial)
            if let errorOutcome = self.pendingErrorOutcome {
                DebugLogger.debug("⚠️ Interstitial finished - showing error outcome that occurred during processing", category: "ReceiptScan")
                self.pendingErrorOutcome = nil
                self.presentOutcome(errorOutcome)
                return
            }
            
            // 🛡️ CRITICAL: Only show success if validation actually passed
            guard self.receiptPassedValidation else {
                DebugLogger.debug("⚠️ Interstitial finished but validation didn't pass - no error outcome stored, showing server error", category: "ReceiptScan")
                // Fallback: if somehow we don't have an error outcome, show server error
                self.presentOutcome(.server)
                return
            }
            // Present success once interstitial completes
            self.presentOutcome(.success(points: self.pointsEarned, total: self.receiptTotal))
        }
    }

    private func startComboGeneration() {
        guard !userVM.firstName.isEmpty else {
            comboState = .failed
            return
        }
        comboState = .loading
        let userName = userVM.firstName
        let dietaryPreferences = DietaryPreferences(
            likesSpicyFood: userVM.likesSpicyFood,
            dislikesSpicyFood: userVM.dislikesSpicyFood,
            hasPeanutAllergy: userVM.hasPeanutAllergy,
            isVegetarian: userVM.isVegetarian,
            hasLactoseIntolerance: userVM.hasLactoseIntolerance,
            doesntEatPork: userVM.doesntEatPork,
            tastePreferences: userVM.tastePreferences
        )
        let service = PersonalizedComboService()
        service.generatePersonalizedCombo(
            userName: userName,
            dietaryPreferences: dietaryPreferences,
            menuItems: menuVM.allMenuItems,
            previousRecommendations: nil
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    DebugLogger.debug("❌ Combo generation (receipt) failed: \(error)", category: "ReceiptScan")
                    self.comboState = .failed
                }
            },
            receiveValue: { combo in
                self.personalizedCombo = combo
                self.isComboReady = true
                self.comboState = .ready
                self.maybeShowComboResult()
            }
        )
        .store(in: &cancellables)
    }
    
    private func retryComboGeneration() {
        hasStartedComboGeneration = false
        isComboReady = false
        personalizedCombo = nil
        comboState = .loading
        hasStartedComboGeneration = true
        startComboGeneration()
    }

    private func maybeShowComboResult() {
        if isComboReady && isInterstitialDone && presentedOutcome == nil {
            showComboResult = true
        }
    }

    private func presentOutcome(_ outcome: ReceiptScanOutcome) {
        triggerHaptic(for: outcome)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            presentedOutcome = outcome
        }
    }

    private func triggerHaptic(for outcome: ReceiptScanOutcome) {
        let generator = UINotificationFeedbackGenerator()
        switch outcome {
        case .success:
            generator.notificationOccurred(.success)
        case .duplicate, .mismatch, .suspicious:
            generator.notificationOccurred(.error)
        default:
            generator.notificationOccurred(.warning)
        }
    }

    private func mapErrorToOutcome(errorCode: String?, message: String) -> ReceiptScanOutcome {
        if let code = errorCode?.uppercased() {
            switch code {
            // Definitive outcomes based solely on errorCode
            case "DUPLICATE_RECEIPT":
                return .duplicate(orderNumber: lastOrderNumber, date: lastOrderDate)
            case "EXPIRED_48H":
                return .tooOld(date: lastOrderDate)
            case "FUTURE_DATE":
                return .tooOld(date: lastOrderDate) // Future date is effectively "can't scan now"
            case "NO_IMAGE":
                return .unreadable
            // Server/auth errors
            case "UNAUTHENTICATED", "USER_NOT_FOUND":
                return .server
            case "RATE_LIMITED":
                return .rateLimited
            case "DAILY_RECEIPT_LIMIT_REACHED":
                return .dailyLimitReached
            case "TOTAL_SECTION_NOT_VISIBLE":
                return .totalsNotVisible
            case "TOTAL_INCONSISTENT":
                return .mismatch
            case let c where c.hasPrefix("SERVER_"):
                return .server
            // For these codes, the message contains more specific info (e.g., "not Dumpling House", "tampered")
            // so we fall through to string-based matching below
            case "AI_VALIDATION_FAILED", "KEY_FIELDS_INVALID":
                break
            // Technical extraction/format failures → unreadable
            case "DATE_FORMAT_INVALID", "TIME_FORMAT_INVALID", "ORDER_NUMBER_INVALID", "TOTAL_INVALID",
                 "MISSING_FIELDS", "AI_JSON_EXTRACT_FAILED", "DOUBLE_PARSE_MISMATCH", "ORDER_NUMBER_SOURCE_INVALID":
                return .unreadable
            default:
                break
            }
        }
        // Fall back to string-based mapping for nuanced outcomes (notFromRestaurant, suspicious, etc.)
        return mapErrorMessageToOutcome(message)
    }

    private func mapErrorMessageToOutcome(_ message: String) -> ReceiptScanOutcome {
        let msg = message.lowercased()
        
        // 0) Totals section missing (fail closed to prevent guessed totals)
        if msg.contains("total section not visible") ||
           msg.contains("make sure all receipt text is visible") ||
           (msg.contains("include subtotal") && msg.contains("tax") && msg.contains("total")) ||
           (msg.contains("subtotal") && msg.contains("tax") && msg.contains("total") && msg.contains("not visible")) {
            return .totalsNotVisible
        }

        // 1) Restaurant mismatch (not from Dumpling House)
        if msg.contains("not from dumpling") ||
           msg.contains("not a dumpling house") ||
           msg.contains("wrong restaurant") ||
           ((msg.contains("dumpling house") || msg.contains("dumpling")) &&
            (msg.contains("invalid") || msg.contains("must be") || msg.contains("not from") || msg.contains("wrong"))) {
            return .notFromRestaurant
        }
        
        // 2) Suspicious / tampering (intentional manipulation)
        if msg.contains("tampered") ||
           msg.contains("photoshopped") ||
           msg.contains("edited") ||
           msg.contains("photo of a photo") ||
           msg.contains("photo of photo") ||
           msg.contains("screen photo") ||
           msg.contains("screenshot") ||
           msg.contains("digitally altered") ||
           msg.contains("brightened to hide") ||
           msg.contains("white-out") ||
           msg.contains("whiteout") ||
           msg.contains("scribbled") ||
           msg.contains("crossed out") ||
           msg.contains("written over") {
            return .suspicious
        }
        
        // 3) Expired / too old
        if msg.contains("too old") || msg.contains("expired") || msg.contains("outside the window") || msg.contains("48 hours") {
            return .tooOld(date: lastOrderDate)
        }
        
        // 4) Duplicate / already submitted
        if msg.contains("already submitted") ||
           msg.contains("already been processed") ||
           msg.contains("duplicate receipt") ||
           msg.contains("duplicate") {
            return .duplicate(orderNumber: lastOrderNumber, date: lastOrderDate)
        }
        
        // 5) Mismatch (validation discrepancy)
        if msg.contains("mismatch") || msg.contains("doesn't add up") || msg.contains("totals") {
            return .mismatch
        }
        
        // 6) Server errors
        if msg.contains("server") || msg.contains("internal") || msg.contains("500") {
            return .server
        }
        
        // 7) Unreadable / poor quality (catch-all for image issues)
        if msg.contains("unreadable") ||
           msg.contains("blurry") ||
           msg.contains("low confidence") ||
           msg.contains("could not extract") ||
           msg.contains("faded") ||
           msg.contains("unclear") ||
           msg.contains("poor image quality") ||
           msg.contains("clearer photo") ||
           msg.contains("no valid order number") ||
           msg.contains("invalid order number") ||
           msg.contains("invalid date") ||
           msg.contains("invalid time") ||
           msg.contains("numbers are covered") ||
           msg.contains("numbers are obstructed") ||
           msg.contains("obscured") ||
           msg.contains("key information") ||
           msg.contains("no image file") {
            return .unreadable
        }
        
        // Default to unreadable for unknown validation errors (not server - those would have "server" in message)
        return .unreadable
    }

    private func handlePrimaryAction(for outcome: ReceiptScanOutcome) {
        switch outcome {
        case .success:
            NotificationCenter.default.post(name: Notification.Name("openRewards"), object: nil)
            presentedOutcome = nil
        case .duplicate:
            NotificationCenter.default.post(name: Notification.Name("openReceiptHistory"), object: nil)
            presentedOutcome = nil
        case .network, .server:
            // Retry upload with last captured image
            if let image = lastCapturedImage {
                presentedOutcome = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.showLoadingOverlay = true
                    self.processReceiptImage(image)
                }
            } else {
                // No image stored, just dismiss
                presentedOutcome = nil
            }
        case .totalsNotVisible:
            // Rescan: dismiss and reopen camera
            presentedOutcome = nil
            lastCapturedImage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkCameraPermission()
            }
        case .dailyLimitReached, .notFromRestaurant, .unreadable, .tooOld, .mismatch, .suspicious, .rateLimited:
            // Just dismiss (buttons now say "Got It")
            presentedOutcome = nil
        }
    }

    private func handleSecondaryAction(for outcome: ReceiptScanOutcome) {
        switch outcome {
        case .success:
            // Order Now -> open the order website
            presentedOutcome = nil
            NotificationCenter.default.post(name: Notification.Name("openOrder"), object: nil)
        case .network, .server:
            // For network/server errors, "Scan Another" allows retry with new image
            presentedOutcome = nil
            lastCapturedImage = nil // Clear stored image since user wants to scan new one
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkCameraPermission()
            }
        default:
            // Scan Another - give a moment for dismiss animation
            presentedOutcome = nil
            lastCapturedImage = nil // Clear stored image
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkCameraPermission()
            }
        }
    }
    
    // Helper to extract MM-DD from a date string (ignoring year)
    private func extractMonthDay(from dateString: String) -> String {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it's already in MM/DD format, convert to MM-DD for consistency
        if trimmed.contains("/") {
            let components = trimmed.components(separatedBy: "/")
            if components.count == 2 {
                return "\(components[0])-\(components[1])"
            }
        }
        
        // Try to match YYYY-MM-DD or MM/DD/YYYY or MM-DD-YYYY
        let patterns = [
            "^(\\d{4})-(\\d{2})-(\\d{2})$", // YYYY-MM-DD
            "^(\\d{2})/(\\d{2})/(\\d{4})$", // MM/DD/YYYY
            "^(\\d{2})-(\\d{2})-(\\d{4})$"  // MM-DD-YYYY
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) {
                if pattern == patterns[0], match.numberOfRanges == 4 {
                    // YYYY-MM-DD
                    let mm = (trimmed as NSString).substring(with: match.range(at: 2))
                    let dd = (trimmed as NSString).substring(with: match.range(at: 3))
                    return "\(mm)-\(dd)"
                } else if pattern == patterns[1], match.numberOfRanges == 4 {
                    // MM/DD/YYYY
                    let mm = (trimmed as NSString).substring(with: match.range(at: 1))
                    let dd = (trimmed as NSString).substring(with: match.range(at: 2))
                    return "\(mm)-\(dd)"
                } else if pattern == patterns[2], match.numberOfRanges == 4 {
                    // MM-DD-YYYY
                    let mm = (trimmed as NSString).substring(with: match.range(at: 1))
                    let dd = (trimmed as NSString).substring(with: match.range(at: 2))
                    return "\(mm)-\(dd)"
                }
            }
        }
        // If no match, return the original string
        return trimmed
    }
    
    // NOTE: Client-side points awarding was removed.
    // Receipt validation + dedupe + points awarding now happen server-side via POST /submit-receipt.
    
    private func checkCameraPermission() {
        errorMessage = ""
        scannedText = ""
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Guard: don't open camera if still processing
            guard !isProcessing else {
                DebugLogger.debug("⚠️ Camera open blocked - still processing", category: "ReceiptScan")
                return
            }
            showCamera = true
        case .notDetermined:
            presentCameraPermissionScreen(isDenied: false)
        case .denied, .restricted:
            presentCameraPermissionScreen(isDenied: true)
        @unknown default:
            presentCameraPermissionScreen(isDenied: true)
        }
    }

    private func presentCameraPermissionScreen(isDenied: Bool) {
        cameraPermissionDenied = isDenied
        showCameraPermissionScreen = true
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    self.showCameraPermissionScreen = false
                    // Guard: don't open camera if still processing
                    guard !self.isProcessing else {
                        DebugLogger.debug("⚠️ Camera open blocked - still processing", category: "ReceiptScan")
                        return
                    }
                    self.showCamera = true
                } else {
                    self.cameraPermissionDenied = true
                }
            }
        }
    }

    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    // NOTE: Client-side duplicate tracking (usedReceipts) was removed.
    // Server-side duplicate prevention is enforced in POST /submit-receipt.

    // Normalize a month/day string for receipt keys and Firestore to MM/DD.
    // Accepts MM/DD, MM-DD, or strings containing a date with year.
    private func normalizeReceiptMonthDay(_ dateString: String) -> String {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        // MM/DD or MM-DD
        let monthDayRegex = try? NSRegularExpression(pattern: "^(\\d{2})[/-](\\d{2})$")
        if let monthDayRegex,
           let match = monthDayRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           match.numberOfRanges == 3 {
            let mm = (trimmed as NSString).substring(with: match.range(at: 1))
            let dd = (trimmed as NSString).substring(with: match.range(at: 2))
            return "\(mm)/\(dd)"
        }

        // YYYY-MM-DD
        let ymdRegex = try? NSRegularExpression(pattern: "^(\\d{4})-(\\d{2})-(\\d{2})$")
        if let ymdRegex,
           let match = ymdRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           match.numberOfRanges == 4 {
            let mm = (trimmed as NSString).substring(with: match.range(at: 2))
            let dd = (trimmed as NSString).substring(with: match.range(at: 3))
            return "\(mm)/\(dd)"
        }

        // MM/DD/YYYY
        let mdySlashRegex = try? NSRegularExpression(pattern: "^(\\d{2})/(\\d{2})/(\\d{4})$")
        if let mdySlashRegex,
           let match = mdySlashRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           match.numberOfRanges == 4 {
            let mm = (trimmed as NSString).substring(with: match.range(at: 1))
            let dd = (trimmed as NSString).substring(with: match.range(at: 2))
            return "\(mm)/\(dd)"
        }

        // MM-DD-YYYY
        let mdyDashRegex = try? NSRegularExpression(pattern: "^(\\d{2})-(\\d{2})-(\\d{4})$")
        if let mdyDashRegex,
           let match = mdyDashRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)),
           match.numberOfRanges == 4 {
            let mm = (trimmed as NSString).substring(with: match.range(at: 1))
            let dd = (trimmed as NSString).substring(with: match.range(at: 2))
            return "\(mm)/\(dd)"
        }

        // Fallback: if it contains dashes in the first 5 chars, convert just those.
        if trimmed.count >= 5 {
            let prefix = String(trimmed.prefix(5)).replacingOccurrences(of: "-", with: "/")
            if prefix.range(of: #"^\d{2}/\d{2}$"#, options: .regularExpression) != nil {
                return prefix
            }
        }
        return trimmed
    }
}

// Minimal corner-glow overlay for receipt scanning (Option 1)
struct MinimalReceiptGuideOverlay: View {
    let frameSize: CGSize
    let cornerLength: CGFloat
    let cornerThickness: CGFloat
    let cornerRadius: CGFloat
    let maskOpacity: Double
    let showGlow: Bool
    let instructionTitle: String?
    let instructionSubtitle: String?

    init(
        frameSize: CGSize,
        cornerLength: CGFloat = 26,
        cornerThickness: CGFloat = 3,
        cornerRadius: CGFloat = 16,
        maskOpacity: Double = 0.28,
        showGlow: Bool = true,
        instructionTitle: String? = nil,
        instructionSubtitle: String? = nil
    ) {
        self.frameSize = frameSize
        self.cornerLength = cornerLength
        self.cornerThickness = cornerThickness
        self.cornerRadius = cornerRadius
        self.maskOpacity = maskOpacity
        self.showGlow = showGlow
        self.instructionTitle = instructionTitle
        self.instructionSubtitle = instructionSubtitle
    }

    var body: some View {
        GeometryReader { geo in
            let container = geo.size
            let rectOrigin = CGPoint(
                x: (container.width - frameSize.width) / 2,
                y: (container.height - frameSize.height) / 2
            )
            let rect = CGRect(origin: rectOrigin, size: frameSize)
            let inset = max(1.0, cornerThickness) // keep a safe inset

            ZStack {
                // Subtle inner stroke for definition
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                // Corner guides (rounded caps), positioned inside the cutout
                Group {
                    // Top-left
                    cornerLine(width: cornerLength, height: cornerThickness)
                        .position(x: rect.minX + cornerRadius + cornerLength / 2,
                                  y: rect.minY + inset)
                        .zIndex(1)
                    cornerLine(width: cornerThickness, height: cornerLength)
                        .position(x: rect.minX + inset,
                                  y: rect.minY + cornerRadius + cornerLength / 2)
                        .zIndex(1)

                    // Top-right
                    cornerLine(width: cornerLength, height: cornerThickness)
                        .position(x: rect.maxX - cornerRadius - cornerLength / 2,
                                  y: rect.minY + inset)
                        .zIndex(1)
                    cornerLine(width: cornerThickness, height: cornerLength)
                        .position(x: rect.maxX - inset,
                                  y: rect.minY + cornerRadius + cornerLength / 2)
                        .zIndex(1)

                    // Bottom-left
                    cornerLine(width: cornerThickness, height: cornerLength)
                        .position(x: rect.minX + inset,
                                  y: rect.maxY - cornerRadius - cornerLength / 2)
                        .zIndex(1)
                    cornerLine(width: cornerLength, height: cornerThickness)
                        .position(x: rect.minX + cornerRadius + cornerLength / 2,
                                  y: rect.maxY - inset)
                        .zIndex(1)

                    // Bottom-right
                    cornerLine(width: cornerThickness, height: cornerLength)
                        .position(x: rect.maxX - inset,
                                  y: rect.maxY - cornerRadius - cornerLength / 2)
                        .zIndex(1)
                    cornerLine(width: cornerLength, height: cornerThickness)
                        .position(x: rect.maxX - cornerRadius - cornerLength / 2,
                                  y: rect.maxY - inset)
                        .zIndex(1)
                }

                // Instruction pill inside the cutout near the bottom
                if let instructionTitle = instructionTitle {
                    VStack(spacing: 6) {
                        Text(instructionTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                        if let instructionSubtitle = instructionSubtitle, !instructionSubtitle.isEmpty {
                            Text(instructionSubtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.35))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .frame(maxWidth: rect.width - 48)
                    .position(x: rect.midX, y: rect.maxY - 44)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cornerLine(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.95))
            .frame(width: width, height: height)
            .shadow(color: showGlow ? Color.white.opacity(0.18) : Color.clear, radius: showGlow ? 3 : 0, x: 0, y: 0)
    }
}

// MARK: - Splash helpers
private func stepIcon(_ systemName: String, color: Color) -> some View {
    ZStack {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
        Image(systemName: systemName)
            .foregroundColor(.white)
            .font(.system(size: 16, weight: .bold))
    }
}

private func stepText(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
        Text(subtitle)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }
}

// MARK: - Gold blob background (always-on, slow, gold-only)
private struct GoldBlobBackground: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                // Performance knobs
                let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                let blobCount = lowPower ? 3 : 5
                let baseOpacity: Double = lowPower ? 0.10 : 0.14
                let maxRadius = min(size.width, size.height) * 0.6
                for i in 0..<blobCount {
                    let fi = Double(i)
                    let speed = 0.02 + 0.01 * fi
                    let r = maxRadius * (0.48 + 0.08 * sin(t * speed + fi))
                    let cx = size.width * (0.5 + 0.35 * sin(t * speed * 0.6 + fi * 1.7))
                    let cy = size.height * (0.5 + 0.35 * cos(t * speed * 0.5 + fi * 1.3))
                    let center = CGPoint(x: cx, y: cy)
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    let path = Path(ellipseIn: rect)
                    let gradient = Gradient(colors: [
                        Theme.primaryGold.opacity(baseOpacity * 0.9),
                        Theme.deepGold.opacity(0.0)
                    ])
                    context.fill(path, with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: r))
                }
            }
        }
        .opacity(1.0)
    }
}

struct CameraViewWithOverlay: View {
    @Binding var image: UIImage?
    var onImageCaptured: (UIImage?) -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var cameraController: CameraController
    @State private var isCapturing = false
    
    init(image: Binding<UIImage?>, onImageCaptured: @escaping (UIImage?) -> Void) {
        self._image = image
        self.onImageCaptured = onImageCaptured
        _cameraController = StateObject(wrappedValue: CameraController())
    }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraController: cameraController)
                .ignoresSafeArea()
            
            // Loading overlay
            if !cameraController.isSetup && cameraController.errorMessage == nil {
                Color.black.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 24) {
                            ProgressView()
                                .scaleEffect(1.8)
                                .tint(.white)
                            Text("Setting up camera...")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                        }
                    )
            }
            
            // Error overlay
            if let errorMessage = cameraController.errorMessage {
                Color.black.ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 24) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)
                            Text("Camera Error")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text(errorMessage)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            VStack(spacing: 12) {
                                Button("Try Again") {
                                    cameraController.errorMessage = nil
                                    cameraController.checkPermissionAndSetup()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .font(.system(size: 16, weight: .semibold))
                                
                                Button("Cancel") {
                                    dismiss()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    )
            }
            
            // UI overlay (only show when camera is ready)
            if cameraController.isSetup && cameraController.errorMessage == nil {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Top section with cancel button
                        HStack {
                            Button(action: { dismiss() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20, weight: .medium))
                                    Text("Cancel")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.4))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, geometry.safeAreaInsets.top + 16)
                        
                        Spacer()
                        
                        // Configure a scan ROI for live detection (restrict search area to reduce "imaginary boxes").
                        // We keep this generous so holding the receipt up still works, but it avoids most background edges.
                        let roiInsetX: CGFloat = 28
                        let roiInsetY: CGFloat = 110
                        let roiLayerRect = CGRect(
                            x: roiInsetX,
                            y: roiInsetY,
                            width: max(1, geometry.size.width - roiInsetX * 2),
                            height: max(1, geometry.size.height - roiInsetY * 2)
                        )
                        Color.clear
                            .frame(width: 1, height: 1)
                            .onAppear {
                                cameraController.setLiveScanROI(fromLayerRect: roiLayerRect)
                            }
                            .onChange(of: geometry.size) { _ in
                                cameraController.setLiveScanROI(fromLayerRect: roiLayerRect)
                            }

                        // Center guide (only when we haven't detected a receipt yet)
                        if cameraController.detectedReceiptQuad == nil {
                            let topArea: CGFloat = geometry.safeAreaInsets.top + 80 // Cancel button area
                            let bottomArea: CGFloat = 120 // Status pill area
                            let availableHeight = geometry.size.height - topArea - bottomArea
                            let cutoutWidth = min(geometry.size.width * 0.75, 320)
                            let cutoutHeight = min(availableHeight, cutoutWidth * 1.9)

                            VStack(spacing: 16) {
                                Text("Finding receipt…")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.30))
                                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                                    )

                                MinimalReceiptGuideOverlay(
                                    frameSize: CGSize(width: cutoutWidth, height: cutoutHeight),
                                    cornerLength: 28,
                                    cornerThickness: 3.5,
                                    cornerRadius: 18,
                                    maskOpacity: 0.20,
                                    showGlow: true,
                                    instructionTitle: nil,
                                    instructionSubtitle: nil
                                )
                                .frame(height: cutoutHeight)
                            }
                        }
                        
                        Spacer()
                        
                        // Bottom status (no manual capture button — auto-capture only)
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                if isCapturing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isCapturing ? "Capturing…" : cameraController.liveScanStatusText)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.35))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                            )

                            Text("Hold steady • Good lighting helps")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.black.opacity(0.22)))
                        }
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 40)
                    }
                }
            }

            // Dim-outside + outline highlight (document-scanner style)
            if cameraController.isSetup && cameraController.errorMessage == nil,
               let quad = cameraController.detectedReceiptQuad {
                LiveReceiptDimOverlay(quad: quad, previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            cameraController.checkPermissionAndSetup()
        }
        .onDisappear {
            // Ensure the camera hardware is released immediately after leaving the sheet
            cameraController.stopSession()
        }
        .onReceive(cameraController.$shouldAutoCapture) { should in
            guard should else { return }
            guard !isCapturing else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isCapturing = true
            }
            cameraController.shouldAutoCapture = false
            cameraController.capturePhoto { capturedImage in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isCapturing = false
                }
                if let capturedImage = capturedImage {
                    image = capturedImage
                    onImageCaptured(capturedImage)
                }
            }
        }
        .onReceive(cameraController.$errorMessage) { errorMessage in
            if let errorMessage = errorMessage {
                DebugLogger.debug("📸 Camera error: \(errorMessage)", category: "ReceiptScan")
            }
        }
    }
}

// MARK: - Live auto-scan overlay

// Must not be `private`/`fileprivate` because it is used by `CameraController`'s @Published properties.
struct DetectedQuad: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
    let boundingBox: CGRect
    let confidence: Float
    let score: Double
}

private struct LiveReceiptDimOverlay: View {
    let quad: DetectedQuad
    let previewLayer: AVCaptureVideoPreviewLayer

    var body: some View {
        Canvas { context, size in
            let quadPath = quadPathInLayerCoordinates()

            // Dim everything outside the quad using even-odd fill.
            var mask = Path()
            mask.addRect(CGRect(origin: .zero, size: size))
            mask.addPath(quadPath)

            context.fill(
                mask,
                with: .color(Color.black.opacity(0.45)),
                style: FillStyle(eoFill: true)
            )

            // Subtle outline for clarity
            context.stroke(
                quadPath,
                with: .color(Color.white.opacity(0.92)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func quadPathInLayerCoordinates() -> Path {
        func toLayer(_ p: CGPoint) -> CGPoint {
            // Vision normalized points are bottom-left origin; captureDevicePoint is top-left origin.
            let devicePoint = CGPoint(x: p.x, y: 1.0 - p.y)
            return previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
        }

        let tl = toLayer(quad.topLeft)
        let tr = toLayer(quad.topRight)
        let br = toLayer(quad.bottomRight)
        let bl = toLayer(quad.bottomLeft)

        var path = Path()
        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: br)
        path.addLine(to: bl)
        path.closeSubpath()
        return path
    }
}

// Camera preview view
struct CameraPreviewView: UIViewRepresentable {
    let cameraController: CameraController
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black // Set background to black instead of white
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Check if preview layer exists and isn't already added
        if cameraController.previewLayer.superlayer == nil {
            cameraController.previewLayer.frame = uiView.bounds
            cameraController.previewLayer.videoGravity = .resizeAspectFill
            uiView.layer.addSublayer(cameraController.previewLayer)
        }
        
        // Update frame if needed
        DispatchQueue.main.async {
            if cameraController.previewLayer.frame != uiView.bounds {
                cameraController.previewLayer.frame = uiView.bounds
            }
            if let connection = cameraController.previewLayer.connection, connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
    }
}

// Camera controller
class CameraController: NSObject, ObservableObject {
    @Published var isSetup = false
    /// Stops the capture session if it is currently running and resets setup flag.
    /// Calling this proactively ensures the camera hardware is released as soon as
    /// the scanning view disappears instead of waiting for deinitialization.
    func stopSession() {
        setTorch(on: false)
        torchLatchedOn = false
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        // Note: Don't reset isSetup flag here - let it be reset when setupCamera is called again
    }
    @Published var errorMessage: String?
    let captureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    var previewLayer: AVCaptureVideoPreviewLayer!
    var completionHandler: ((UIImage?) -> Void)?
    private var cameraDevice: AVCaptureDevice?

    // Live auto-scan state
    @Published var detectedReceiptQuad: DetectedQuad? = nil
    @Published var shouldAutoCapture: Bool = false
    @Published var liveScanStatusText: String = "Finding receipt…"
    var isAutoScanEnabled: Bool = true
    var autoTorchEnabled: Bool = true

    private let videoQueue = DispatchQueue(label: "camera.video.frames.queue", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "camera.vision.queue", qos: .userInitiated)
    private var lastVisionAt: CFTimeInterval = 0
    private var isAnalyzing: Bool = false

    // Live ROI in Vision normalized coordinates (origin bottom-left).
    private var liveScanROI: CGRect? = nil

    // Tracking / smoothing / hysteresis
    private var trackedQuadRaw: DetectedQuad? = nil
    private var smoothedQuad: DetectedQuad? = nil
    private var stabilityScore: Int = 0
    private var hasTriggeredAutoCapture: Bool = false
    private var lastCandidateAt: CFTimeInterval = 0
    private var lastGoodQuadAt: CFTimeInterval = 0
    private let quadHoldGraceSeconds: CFTimeInterval = 0.85
    private let lockDelaySeconds: CFTimeInterval = 0.20 // was 0.35
    private var lockedQuad: DetectedQuad? = nil
    private var statusCandidateText: String? = nil
    private var statusCandidateSince: CFTimeInterval = 0
    private let statusHysteresisSeconds: CFTimeInterval = 0.8
    
    // Stuck detection
    private var trackedQuadStartTime: CFTimeInterval = 0
    private var trackedQuadBestStability: Int = 0
    private let stuckDetectionTimeout: CFTimeInterval = 3.5

    // Auto torch (flashlight) during scanning
    private var lastTorchEvalAt: CFTimeInterval = 0
    private var lastTorchChangeAt: CFTimeInterval = 0
    private var torchDesiredOn: Bool = false
    private var torchLatchedOn: Bool = false
    private let torchEvalInterval: CFTimeInterval = 0.35
    private let torchMinToggleInterval: CFTimeInterval = 0.9
    private let lowLightOnThreshold: Double = 0.20  // 0..1 (lower = darker)
    private let lowLightOffThreshold: Double = 0.28 // hysteresis

    // Pre-capture totals OCR hint (throttled, low-res check)
    private var lastFastTotalsCheckAt: CFTimeInterval = 0
    private var lastTotalsCheckAt: CFTimeInterval = 0
    private var totalsHintCandidate: Bool = false
    private var totalsHintPassed: Bool = false
    private let fastTotalsCheckInterval: CFTimeInterval = 0.22 // fast hint (~4.5 fps)
    private let totalsCheckInterval: CFTimeInterval = 0.30 // full hint (~3.3 fps)
    private let ocrQueue = DispatchQueue(label: "camera.ocr.totals.queue", qos: .utility)

    private enum LiveScanPhase {
        case searching
        case tracking
        case locked
        case capturing
    }
    private var phase: LiveScanPhase = .searching

    func setLiveScanROI(fromLayerRect layerRect: CGRect) {
        // Convert from preview-layer coordinates -> AVFoundation normalized (top-left origin),
        // then convert to Vision normalized (bottom-left origin).
        let avRect = previewLayer.metadataOutputRectConverted(fromLayerRect: layerRect)
        let visionRect = CGRect(
            x: avRect.origin.x,
            y: max(0, 1.0 - avRect.origin.y - avRect.size.height),
            width: avRect.size.width,
            height: avRect.size.height
        )
        // Clamp
        let clamped = visionRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        liveScanROI = clamped.isNull ? nil : clamped
    }
    
    override init() {
        super.init()
        setupPreviewLayer()
    }
    
    func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = UIColor.black.cgColor
    }
    
    func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.errorMessage = "Camera access denied"
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.errorMessage = "Camera access denied. Please enable in Settings."
            }
        @unknown default:
            DispatchQueue.main.async {
                self.errorMessage = "Camera access not available"
            }
        }
    }
    
    func setupCamera() {
        // Reset setup flag and clear error
        DispatchQueue.main.async {
            self.isSetup = false
            self.errorMessage = nil
        }
        
        // Reset auto-scan state for clean start
        phase = .searching
        stabilityScore = 0
        hasTriggeredAutoCapture = false
        totalsHintCandidate = false
        totalsHintPassed = false
        lastFastTotalsCheckAt = 0
        lastTotalsCheckAt = 0
        trackedQuadRaw = nil
        smoothedQuad = nil
        lockedQuad = nil
        statusCandidateText = nil
        statusCandidateSince = 0
        trackedQuadStartTime = 0
        trackedQuadBestStability = 0
        
        // Stop any existing session
        if captureSession.isRunning {
            setTorch(on: false)
            torchLatchedOn = false
            captureSession.stopRunning()
        }
        
        // Remove existing inputs and outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async {
                self.errorMessage = "Camera not available"
            }
            return
        }
        self.cameraDevice = camera
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot add camera input"
                }
                return
            }
            
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot add photo output"
                }
                return
            }

            // Video output for live auto-scan (frames → Vision)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            } else {
                DebugLogger.debug("⚠️ Cannot add video output; live auto-scan disabled", category: "ReceiptScan")
            }

            // Try to keep output orientation portrait for preview; Vision uses explicit orientation below.
            if let conn = videoOutput.connection(with: .video), conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
            
            // Start the session on a background queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
                DispatchQueue.main.async {
                    self?.isSetup = true
                    DebugLogger.debug("📸 Camera setup completed successfully", category: "ReceiptScan")
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Camera setup error: \(error.localizedDescription)"
            }
            DebugLogger.debug("📸 Camera setup error: \(error)", category: "ReceiptScan")
        }
    }

    private func applyStatusText(_ text: String, force: Bool = false) {
        if force {
            liveScanStatusText = text
            statusCandidateText = nil
            return
        }
        if text == liveScanStatusText {
            statusCandidateText = nil
            return
        }
        let now = CACurrentMediaTime()
        if statusCandidateText != text {
            statusCandidateText = text
            statusCandidateSince = now
            return
        }
        if now - statusCandidateSince >= statusHysteresisSeconds {
            liveScanStatusText = text
            statusCandidateText = nil
        }
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard captureSession.isRunning else {
            DebugLogger.debug("📸 Camera session not running", category: "ReceiptScan")
            completion(nil)
            return
        }
        
        completionHandler = completion
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        DispatchQueue.main.async {
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    deinit {
        setTorch(on: false)
        torchLatchedOn = false
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func setTorch(on: Bool) {
        guard autoTorchEnabled else { return }
        guard let device = cameraDevice, device.hasTorch else { return }

        let now = CACurrentMediaTime()
        if now - lastTorchChangeAt < torchMinToggleInterval { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if on {
                guard device.isTorchModeSupported(.on) else { return }
                let level = min(0.55, AVCaptureDevice.maxAvailableTorchLevel)
                try device.setTorchModeOn(level: level)
            } else {
                guard device.isTorchModeSupported(.off) else { return }
                device.torchMode = .off
            }

            lastTorchChangeAt = now
        } catch {
            DebugLogger.debug("⚠️ Torch config failed: \(error.localizedDescription)", category: "ReceiptScan")
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DebugLogger.debug("Photo capture error: \(error)", category: "ReceiptScan")
            completionHandler?(nil)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            completionHandler?(nil)
            return
        }
        
        completionHandler?(image)
    }
}

// MARK: - Live auto-scan (video frames → Vision)

extension CameraController {
    /// Ultra-fast, low-fidelity hint that totals text is likely present.
    /// Used to unlock the heavier totals check sooner.
    private func checkFastTotalsHintOnLiveFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, completion: @escaping (Bool) -> Void) {
        ocrQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            let scale: CGFloat = 0.38 // more aggressive downscale for speed
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let scaledImage = ciImage.transformed(by: transform)

            // Focus on the bottom slice to reduce OCR work.
            let height = scaledImage.extent.height
            let cropRect = CGRect(x: 0, y: 0, width: scaledImage.extent.width, height: height * 0.45)
            guard let cgImage = context.createCGImage(scaledImage, from: cropRect) else {
                completion(false)
                return
            }

            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation(from: orientation))
            let hasTotalsHint = fastTotalsHintFromImage(uiImage)
            completion(hasTotalsHint)
        }
    }

    /// Fast, throttled OCR check on live frame to detect totals section before auto-capture.
    /// Uses downscaled image and bottom region only for speed.
    private func checkTotalsHintOnLiveFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, completion: @escaping (Bool) -> Void) {
        ocrQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            
            // Convert pixel buffer to CGImage (downscaled for speed)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            let scale: CGFloat = 0.5 // Downscale to 50% for speed
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let scaledImage = ciImage.transformed(by: transform)
            
            guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
                completion(false)
                return
            }
            
            // Create UIImage with proper orientation
            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation(from: orientation))
            
            // Check totals using existing logic (bottom 65% region)
            let hasTotals = receiptHasSubtotalTaxTotalSync(uiImage)
            completion(hasTotals)
        }
    }
    
    /// Convert Vision orientation to UIImage orientation
    private func imageOrientation(from visionOrientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch visionOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Very fast keyword-only OCR hint (no amounts required).
    private func fastTotalsHintFromImage(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02
        request.regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.55)

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return false
        }

        let strings = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        let text = strings.joined(separator: " ").lowercased()
        return text.contains("total") || text.contains("subtotal") || text.contains("sub total") || text.contains("tax")
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isAutoScanEnabled else { return }
        guard !hasTriggeredAutoCapture else { return }

        // Auto torch evaluation (flashlight) during scanning.
        if autoTorchEnabled {
            let now = CACurrentMediaTime()
            if now - lastTorchEvalAt >= torchEvalInterval {
                lastTorchEvalAt = now
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let brightness = estimateBrightnessBGRA(pixelBuffer)
                    if brightness >= 0 {
                        // Latch behavior: once the torch turns on due to low light, keep it on for the
                        // rest of the scanning session (prevents flickering as exposure/brightness fluctuates).
                        if torchLatchedOn {
                            setTorch(on: true)
                        } else {
                            if brightness < lowLightOnThreshold {
                                torchLatchedOn = true
                                torchDesiredOn = true
                                setTorch(on: true)
                            } else if brightness > lowLightOffThreshold {
                                torchDesiredOn = false
                                setTorch(on: false)
                            }
                        }
                    }
                }
            }
        }

        // Throttle Vision work
        let now = CACurrentMediaTime()
        if now - lastVisionAt < 0.08 { return } // ~12 fps (was 0.14 / ~7 fps)
        lastVisionAt = now

        // Avoid piling up analyses
        if isAnalyzing { return }
        isAnalyzing = true

        visionQueue.async { [weak self] in
            defer { self?.isAnalyzing = false }
            guard let self else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            // Portrait back camera: .right is typically correct for buffers.
            let orientation = CGImagePropertyOrientation.right

            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 8
            request.minimumConfidence = 0.45
            request.minimumAspectRatio = 0.10
            request.maximumAspectRatio = 0.90
            request.minimumSize = 0.08
            request.quadratureTolerance = 35.0 // was 25.0 - increased for tilted receipts
            if let roi = self.liveScanROI {
                request.regionOfInterest = roi
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.detectedReceiptQuad = nil
                    self.applyStatusText("Finding receipt…", force: true)
                }
                return
            }

            guard let obs = request.results, !obs.isEmpty else {
                // Dropout tolerance: keep showing the last good quad briefly instead of blinking out.
                let now = CACurrentMediaTime()
                let withinGrace = (now - self.lastGoodQuadAt) <= self.quadHoldGraceSeconds
                if withinGrace {
                    // Decay stability slowly but keep overlay/track.
                    self.stabilityScore = max(0, self.stabilityScore - 2)
                    DispatchQueue.main.async {
                        if self.hasTriggeredAutoCapture {
                            self.applyStatusText("Capturing…", force: true)
                        } else if self.phase == .tracking || self.phase == .locked {
                            self.applyStatusText("Hold steady…")
                        } else {
                            self.applyStatusText("Finding receipt…", force: true)
                        }
                    }
                } else {
                    // True loss: reset.
                    self.phase = .searching
                    self.lockedQuad = nil
                    self.totalsHintCandidate = false
                    self.totalsHintPassed = false
                    self.lastFastTotalsCheckAt = 0
                    self.lastTotalsCheckAt = 0
                    self.lastFastTotalsCheckAt = 0
                    self.lastTotalsCheckAt = 0
                    DispatchQueue.main.async {
                        self.detectedReceiptQuad = nil
                        self.applyStatusText("Finding receipt…", force: true)
                    }
                    self.trackedQuadRaw = nil
                    self.smoothedQuad = nil
                    self.stabilityScore = 0
                    self.trackedQuadStartTime = 0
                    self.trackedQuadBestStability = 0
                }
                return
            }

            func score(_ o: VNRectangleObservation) -> Double {
                let bb = o.boundingBox
                let area = Double(bb.width * bb.height)
                let w = Double(bb.width)
                let h = Double(bb.height)
                let longSide = max(w, h)
                let shortSide = min(w, h)
                let aspect = longSide > 0 ? (shortSide / longSide) : 0.0
                let conf = Double(o.confidence)

                // Prefer long rectangles and decent longSide fill.
                let aspectTarget = 0.33
                let aspectScore = max(0.0, 1.0 - abs(aspect - aspectTarget) / 0.55)

                // Prefer centered.
                let dx = Double(bb.midX - 0.5)
                let dy = Double(bb.midY - 0.5)
                let centerDist = sqrt(dx * dx + dy * dy)
                let centerScore = max(0.0, 1.0 - centerDist / 0.70)

                // Confidence weight increased (was 0.55 + 0.45*conf) to better reject low-contrast edges
                return pow(area, 1.1) * (0.40 + 0.60 * conf) * (0.55 + 0.45 * aspectScore) * (0.65 + 0.35 * centerScore) * (0.6 + 0.4 * longSide)
            }

            // Build candidates and apply stronger receipt-like filtering (reduces "imaginary boxes").
            struct Candidate {
                let quad: DetectedQuad
                let longSide: Double
                let aspect: Double
                let area: Double
            }

            func makeCandidate(_ o: VNRectangleObservation) -> Candidate? {
                let bb = o.boundingBox
                let w = Double(bb.width)
                let h = Double(bb.height)
                let longSide = max(w, h)
                let aspect = longSide > 0 ? (min(w, h) / longSide) : 0.0
                let area = Double(bb.width * bb.height)

                // Reject squares / tiny junk early.
                // Relaxed for tilted receipts (bounding box becomes more square when tilted)
                if aspect > 0.88 { return nil } // was 0.82
                if area < 0.035 { return nil }
                if longSide < 0.30 { return nil } // was 0.35
                
                // Edge contrast validation: reject very low confidence detections
                // (likely false positives on white backgrounds or from hands)
                // This helps filter out "ghost" rectangles that Vision sometimes detects
                if o.confidence < 0.50 { return nil } // was implicit 0.45 from request

                let q = DetectedQuad(
                    topLeft: o.topLeft,
                    topRight: o.topRight,
                    bottomLeft: o.bottomLeft,
                    bottomRight: o.bottomRight,
                    boundingBox: o.boundingBox,
                    confidence: o.confidence,
                    score: score(o)
                )
                return Candidate(quad: q, longSide: longSide, aspect: aspect, area: area)
            }

            let candidates = obs.compactMap(makeCandidate).sorted { $0.quad.score > $1.quad.score }
            guard let top = candidates.first else {
                // No valid candidates after filtering: apply the same dropout tolerance.
                let now = CACurrentMediaTime()
                let withinGrace = (now - self.lastGoodQuadAt) <= self.quadHoldGraceSeconds
                if withinGrace {
                    self.stabilityScore = max(0, self.stabilityScore - 2)
                    DispatchQueue.main.async {
                        self.applyStatusText("Hold steady…")
                    }
                } else {
                    self.phase = .searching
                    self.lockedQuad = nil
                    self.totalsHintCandidate = false
                    self.totalsHintPassed = false
                    DispatchQueue.main.async {
                        self.detectedReceiptQuad = nil
                        self.applyStatusText("Finding receipt…", force: true)
                    }
                    self.trackedQuadRaw = nil
                    self.smoothedQuad = nil
                    self.stabilityScore = 0
                    self.trackedQuadStartTime = 0
                    self.trackedQuadBestStability = 0
                }
                return
            }

            // Hysteresis: stick to the currently tracked quad unless a new candidate is clearly better
            // or is very close geometrically (same receipt, slight jitter).
            func avgCornerDelta(_ a: DetectedQuad, _ b: DetectedQuad) -> CGFloat {
                let d1 = hypot(a.topLeft.x - b.topLeft.x, a.topLeft.y - b.topLeft.y)
                let d2 = hypot(a.topRight.x - b.topRight.x, a.topRight.y - b.topRight.y)
                let d3 = hypot(a.bottomLeft.x - b.bottomLeft.x, a.bottomLeft.y - b.bottomLeft.y)
                let d4 = hypot(a.bottomRight.x - b.bottomRight.x, a.bottomRight.y - b.bottomRight.y)
                return (d1 + d2 + d3 + d4) / 4.0
            }
            
            // Calculate true quad dimensions from corners (rotation-invariant).
            // This handles tilted receipts better than axis-aligned bounding box.
            func trueQuadDimensions(_ quad: DetectedQuad) -> (longSide: CGFloat, aspect: CGFloat) {
                let topEdge = hypot(quad.topRight.x - quad.topLeft.x, quad.topRight.y - quad.topLeft.y)
                let bottomEdge = hypot(quad.bottomRight.x - quad.bottomLeft.x, quad.bottomRight.y - quad.bottomLeft.y)
                let leftEdge = hypot(quad.bottomLeft.x - quad.topLeft.x, quad.bottomLeft.y - quad.topLeft.y)
                let rightEdge = hypot(quad.bottomRight.x - quad.topRight.x, quad.bottomRight.y - quad.topRight.y)
                
                let avgWidth = (topEdge + bottomEdge) / 2
                let avgHeight = (leftEdge + rightEdge) / 2
                let longSide = max(avgWidth, avgHeight)
                let shortSide = min(avgWidth, avgHeight)
                let aspect = longSide > 0 ? shortSide / longSide : 0
                
                return (longSide, aspect)
            }

            let scoreGap: Double = (candidates.count >= 2) ? (candidates[0].quad.score - candidates[1].quad.score) : candidates[0].quad.score
            let ambiguous = candidates.count >= 2 && scoreGap / max(1e-6, candidates[0].quad.score) < 0.15 // was 0.10 - less sensitive to close scores

            var chosenRaw: DetectedQuad = top.quad
            let now = CACurrentMediaTime()
            
            // Check if we're stuck on the current tracked quad
            let isStuck = self.trackedQuadRaw != nil &&
                (now - self.trackedQuadStartTime) > self.stuckDetectionTimeout &&
                self.stabilityScore < (self.trackedQuadBestStability + 3)
            
            if isStuck {
                // Reset tracking to allow fresh detection
                self.trackedQuadRaw = nil
                self.smoothedQuad = nil
                self.trackedQuadStartTime = 0
                self.trackedQuadBestStability = 0
                chosenRaw = top.quad
            } else if let tracked = self.trackedQuadRaw {
                // Find the closest candidate to the tracked quad.
                let closest = candidates.min(by: { avgCornerDelta($0.quad, tracked) < avgCornerDelta($1.quad, tracked) })?.quad
                if let closest {
                    let delta = avgCornerDelta(closest, tracked)
                    let bestScore = candidates[0].quad.score
                    let trackedScore = tracked.score
                    
                    // Get geometry for comparison
                    let (bestLongSide, bestAspect) = trueQuadDimensions(candidates[0].quad)
                    let (trackedLongSide, trackedAspect) = trueQuadDimensions(tracked)
                    let bestArea = candidates[0].area
                    let trackedArea = Double(tracked.boundingBox.width * tracked.boundingBox.height)
                    
                    // Geometry-based switching: prefer larger area and better aspect ratio
                    let hasBetterGeometry = bestArea > trackedArea * 1.15 && 
                                          bestAspect < trackedAspect * 1.1 && 
                                          bestLongSide > trackedLongSide * 1.05
                    
                    // Stability-based switching: if stability isn't improving, be more lenient
                    let stabilityNotImproving = (now - self.trackedQuadStartTime) > 2.0 &&
                                               self.stabilityScore <= self.trackedQuadBestStability
                    let stabilityBasedSwitch = stabilityNotImproving && bestScore > trackedScore * 1.10

                    // Prefer staying on the same physical receipt (geometric proximity).
                    if delta < 0.060 {
                        chosenRaw = closest
                    } else if bestScore > trackedScore * 1.15 && !ambiguous { // Reduced from 1.20
                        // Switch if clearly better and not ambiguous.
                        chosenRaw = candidates[0].quad
                    } else if hasBetterGeometry && !ambiguous {
                        // Switch if geometry is significantly better (larger, better aspect)
                        chosenRaw = candidates[0].quad
                    } else if stabilityBasedSwitch && !ambiguous {
                        // Switch if stability isn't improving and new candidate is better
                        chosenRaw = candidates[0].quad
                    } else {
                        // Keep tracked to prevent jumping.
                        chosenRaw = tracked
                    }
                } else {
                    chosenRaw = tracked
                }
            } else {
                // No tracked quad - prefer best candidate with good geometry
                chosenRaw = top.quad
            }

            // Update tracking state when quad changes
            let previousTracked = self.trackedQuadRaw
            self.trackedQuadRaw = chosenRaw
            self.lastCandidateAt = CACurrentMediaTime()
            
            // If we switched to a new quad, reset tracking timers
            if previousTracked == nil || avgCornerDelta(chosenRaw, previousTracked!) > 0.10 {
                self.trackedQuadStartTime = now
                self.trackedQuadBestStability = self.stabilityScore
            }

            // Smooth the quad to remove jitter (EMA with adaptive alpha).
            func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            // Adaptive alpha: snap quickly for large movements, smooth for small jitter
            // was fixed at 0.22
            if let prev = self.smoothedQuad {
                let rawDelta = avgCornerDelta(chosenRaw, prev)
                let alpha: CGFloat = rawDelta > 0.05 ? 0.55 : (rawDelta > 0.02 ? 0.38 : 0.22)
                let tl = lerp(prev.topLeft, chosenRaw.topLeft, alpha)
                let tr = lerp(prev.topRight, chosenRaw.topRight, alpha)
                let bl = lerp(prev.bottomLeft, chosenRaw.bottomLeft, alpha)
                let br = lerp(prev.bottomRight, chosenRaw.bottomRight, alpha)

                let minX = min(tl.x, tr.x, bl.x, br.x)
                let maxX = max(tl.x, tr.x, bl.x, br.x)
                let minY = min(tl.y, tr.y, bl.y, br.y)
                let maxY = max(tl.y, tr.y, bl.y, br.y)
                let bb = CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))

                self.smoothedQuad = DetectedQuad(
                    topLeft: tl,
                    topRight: tr,
                    bottomLeft: bl,
                    bottomRight: br,
                    boundingBox: bb,
                    confidence: chosenRaw.confidence,
                    score: chosenRaw.score
                )
            } else {
                self.smoothedQuad = chosenRaw
            }

            guard let publishQuad = self.smoothedQuad else { return }
            self.lastGoodQuadAt = CACurrentMediaTime()
            if self.phase == .searching {
                self.phase = .tracking
                // Reset totals hint when starting to track
                self.totalsHintCandidate = false
                self.totalsHintPassed = false
                self.lastFastTotalsCheckAt = 0
                self.lastTotalsCheckAt = 0
            }

            // Lock behavior: once locked, stop updating the quad (freeze highlight) and commit to capture.
            if self.phase == .locked || self.phase == .capturing {
                if let locked = self.lockedQuad {
                    DispatchQueue.main.async {
                        self.detectedReceiptQuad = locked
                        self.applyStatusText("Capturing…", force: true)
                    }
                }
                return
            }

            // Stability on the smoothed quad (more reliable when holding receipt up).
            let previous = self.detectedReceiptQuad
            let delta = (previous != nil) ? avgCornerDelta(previous!, publishQuad) : 1.0
            let motionStable = delta < 0.018 // was 0.013 - relaxed for faster lock

            // Score-based stability (not perfect consecutive frames):
            // - stable + unambiguous: ramp up quickly
            // - ambiguous: still gain but slower
            // - unstable: decay slowly
            let previousStability = self.stabilityScore
            if motionStable && !ambiguous {
                self.stabilityScore = min(30, self.stabilityScore + 5) // faster ramp when steady
            } else if motionStable && ambiguous {
                self.stabilityScore = min(30, self.stabilityScore + 3) // allow gains even when ambiguous
            } else if ambiguous {
                self.stabilityScore = max(0, self.stabilityScore - 1)
            } else {
                self.stabilityScore = max(0, self.stabilityScore - 1)
            }
            
            // Update best stability if we improved
            if self.stabilityScore > previousStability && self.stabilityScore > self.trackedQuadBestStability {
                self.trackedQuadBestStability = self.stabilityScore
            }

            // Fast totals hint first, then full hint (throttled)
            if self.stabilityScore >= 12 && !self.totalsHintCandidate && !self.hasTriggeredAutoCapture {
                if (now - self.lastFastTotalsCheckAt) >= self.fastTotalsCheckInterval {
                    self.lastFastTotalsCheckAt = now
                    self.checkFastTotalsHintOnLiveFrame(pixelBuffer, orientation: orientation) { [weak self] hasTotalsHint in
                        guard let self else { return }
                        DispatchQueue.main.async {
                            self.totalsHintCandidate = hasTotalsHint
                            if !hasTotalsHint {
                                self.totalsHintPassed = false
                            }
                        }
                    }
                }
            }

            let shouldCheckTotals = self.totalsHintCandidate &&
                self.stabilityScore >= 15 &&
                (now - self.lastTotalsCheckAt) >= self.totalsCheckInterval

            if shouldCheckTotals && !self.hasTriggeredAutoCapture {
                self.lastTotalsCheckAt = now
                self.checkTotalsHintOnLiveFrame(pixelBuffer, orientation: orientation) { [weak self] hasTotals in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        self.totalsHintPassed = hasTotals
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.detectedReceiptQuad = publishQuad
                if self.hasTriggeredAutoCapture {
                    self.applyStatusText("Capturing…", force: true)
                } else if self.stabilityScore >= 18 {
                    // Guide user if totals are missing
                    if self.totalsHintPassed || self.totalsHintCandidate {
                        self.applyStatusText("Hold steady…")
                    } else {
                        self.applyStatusText("Move receipt down to include totals")
                    }
                } else {
                    self.applyStatusText("Finding receipt…", force: true)
                }
            }

            // Trigger auto-capture once stable enough and receipt-like.
            if self.stabilityScore >= 18 && !self.hasTriggeredAutoCapture { // was 24
                // Use true quad geometry (rotation-invariant) for gating tilted receipts.
                let (trueLongSide, trueAspect) = trueQuadDimensions(publishQuad)
                // Relaxed thresholds: was longSide >= 0.52 && aspect <= 0.72
                if trueLongSide >= 0.45 && trueAspect <= 0.78 && !ambiguous {
                    self.phase = .locked
                    self.lockedQuad = publishQuad
                    self.hasTriggeredAutoCapture = true
                    DispatchQueue.main.async {
                        self.detectedReceiptQuad = publishQuad
                        self.applyStatusText("Capturing…", force: true)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.lockDelaySeconds) {
                        // If something external cancelled auto scan, respect it.
                        guard self.isAutoScanEnabled else { return }
                        self.phase = .capturing
                        self.shouldAutoCapture = true
                    }
                }
            }
        }
    }

    /// Returns a rough 0..1 brightness estimate from a BGRA pixel buffer.
    /// Samples a sparse grid (fast) and uses the green channel as a luminance proxy.
    private func estimateBrightnessBGRA(_ pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return -1 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        if width <= 0 || height <= 0 { return -1 }

        // Sample ~40x40 grid max.
        let stepX = max(1, width / 40)
        let stepY = max(1, height / 40)

        var sum: Int64 = 0
        var count: Int64 = 0

        for y in stride(from: 0, to: height, by: stepY) {
            let row = base.advanced(by: y * bpr)
            for x in stride(from: 0, to: width, by: stepX) {
                let px = row.advanced(by: x * 4)
                // BGRA: [B, G, R, A]
                let g = px.load(fromByteOffset: 1, as: UInt8.self)
                sum += Int64(g)
                count += 1
            }
        }

        guard count > 0 else { return -1 }
        return Double(sum) / Double(count * 255)
    }
}

func uploadReceiptImage(_ image: UIImage, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    let urlString = "\(Config.backendURL)/submit-receipt"
    DebugLogger.debug("📤 Uploading receipt to: \(urlString)", category: "ReceiptScan")
    
    guard let url = URL(string: urlString) else {
        DebugLogger.debug("❌ Invalid URL: \(urlString)", category: "ReceiptScan")
        completion(.failure(NSError(domain: "Invalid URL", code: 0)))
        return
    }
    
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
        DebugLogger.debug("❌ Failed to convert image to JPEG data", category: "ReceiptScan")
        completion(.failure(NSError(domain: "Image conversion failed", code: 0)))
        return
    }
    
    guard let currentUser = Auth.auth().currentUser else {
        DebugLogger.debug("❌ No authenticated user found when uploading receipt", category: "ReceiptScan")
        completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
        return
    }
    
    currentUser.getIDToken { token, error in
        if let error = error {
            DebugLogger.debug("❌ Failed to get ID token: \(error.localizedDescription)", category: "ReceiptScan")
            completion(.failure(error))
            return
        }
        
        guard let token = token else {
            DebugLogger.debug("❌ ID token is nil", category: "ReceiptScan")
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unable to get auth token"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        DeviceFingerprint.addToRequest(&request)
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "x-user-timezone")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add the image part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"receipt.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add the closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Set the content length
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        
        DebugLogger.debug("📤 Request body size: \(body.count) bytes", category: "ReceiptScan")
        
        // Use a session with better connectivity behavior
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        let session = URLSession(configuration: config)
        session.uploadTask(with: request, from: body) { data, response, error in
            if let error = error {
                DebugLogger.debug("❌ Network error: \(error.localizedDescription)", category: "ReceiptScan")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            var statusCode: Int = -1
            if let httpResponse = response as? HTTPURLResponse {
                statusCode = httpResponse.statusCode
                DebugLogger.debug("📡 HTTP Status: \(statusCode)", category: "ReceiptScan")
            }
            
            guard let data = data else {
                DebugLogger.debug("❌ No response data received", category: "ReceiptScan")
                DispatchQueue.main.async { completion(.failure(NSError(domain: "No data", code: 0))) }
                return
            }
            
            // Print response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                DebugLogger.debug("📥 Response: \(responseString)", category: "ReceiptScan")
            }
            
            // If non-2xx, attempt to surface a server error as JSON for better UX mapping
            if !(200...299).contains(statusCode), statusCode != -1 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var enriched = json
                    if enriched["error"] == nil {
                        enriched["error"] = "Server error \(statusCode)"
                    }
                    DebugLogger.debug("⚠️ Non-2xx with JSON body, surfacing as error: \(enriched)", category: "ReceiptScan")
                    DispatchQueue.main.async { completion(.success(enriched)) }
                    return
                } else {
                    let message = "Server error \(statusCode)"
                    DebugLogger.debug("⚠️ Non-2xx without JSON body, surfacing generic error: \(message)", category: "ReceiptScan")
                    DispatchQueue.main.async { completion(.success(["error": message])) }
                    return
                }
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DebugLogger.debug("✅ Successfully parsed JSON response", category: "ReceiptScan")
                    DispatchQueue.main.async { completion(.success(json)) }
                } else {
                    DebugLogger.debug("❌ Failed to parse JSON response", category: "ReceiptScan")
                    DispatchQueue.main.async { completion(.failure(NSError(domain: "Invalid JSON", code: 0))) }
                }
            } catch {
                DebugLogger.debug("❌ JSON parsing error: \(error.localizedDescription)", category: "ReceiptScan")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}

// MARK: - Client-side OCR gate (prevent hallucinated totals)

/// Fast on-device check to ensure the receipt image includes the Subtotal/Tax/Total section.
/// If this fails, we reject locally to avoid the model guessing a total from incomplete evidence.
private func receiptHasSubtotalTaxTotal(_ image: UIImage, completion: @escaping (Bool) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let ok = receiptHasSubtotalTaxTotalSync(image)
        DispatchQueue.main.async { completion(ok) }
    }
}

private func receiptHasSubtotalTaxTotalSync(_ image: UIImage) -> Bool {
    guard let cgImage = image.cgImage else { return false }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    // Focus on the bottom portion where Subtotal/Tax/Total typically live (origin is bottom-left).
    request.regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.65)

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return false
    }

    let strings = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    let text = strings.joined(separator: "\n").lowercased()

    let hasSubtotal = text.contains("subtotal") || text.contains("sub total")
    let hasTax = text.contains("tax")
    let hasTotal = text.contains("total")
    let keywordCount = [hasSubtotal, hasTax, hasTotal].filter { $0 }.count
    guard keywordCount >= 2 else { return false }

    // Require at least one currency-like amount to reduce false positives.
    let pattern = #"\b\d+\.\d{2}\b"#
    let regex = try? NSRegularExpression(pattern: pattern, options: [])
    if let regex = regex {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
    return false
}

// MARK: - Receipt image preprocessing (Option B: detect receipt rectangle + perspective correction)

/// Runs Vision rectangle detection + CoreImage perspective correction to isolate the receipt area.
/// If anything fails, returns the original image (orientation-normalized) so scans never block.
private func preprocessReceiptImageForUpload(_ image: UIImage, debugSaveToPhotos: Bool, completion: @escaping (UIImage) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let normalized = normalizeImageOrientation(image)
        let downscaled = downscaleIfNeeded(normalized, maxDimension: 2000)

        guard let processed = detectAndCorrectReceipt(in: downscaled, debugLog: debugSaveToPhotos) else {
            // Fallback: when rectangle detection fails, attempt a conservative text-box crop to reduce background.
            // This is still guarded by the Subtotal/Tax/Total OCR gate upstream (fail closed).
            let heuristic = heuristicTextCropReceipt(downscaled, debugLog: debugSaveToPhotos)
            if heuristic != nil {
                DebugLogger.debug("🧾 Receipt preprocessing fallback: using heuristic text crop (no rectangle detected)", category: "ReceiptScan")
            } else {
                DebugLogger.debug("🧾 Receipt preprocessing skipped (no rectangle detected) - using original image", category: "ReceiptScan")
            }
            if debugSaveToPhotos {
                saveToPhotoLibrary(downscaled, label: "receipt-debug-original")
                if let heuristic {
                    saveToPhotoLibrary(heuristic, label: "receipt-debug-heuristic")
                }
            }
            DispatchQueue.main.async { completion(heuristic ?? downscaled) }
            return
        }
        DebugLogger.debug("🧾 Receipt preprocessing succeeded - using cropped/perspective-corrected image", category: "ReceiptScan")
        if debugSaveToPhotos {
            saveToPhotoLibrary(processed, label: "receipt-debug-processed")
        }
        DispatchQueue.main.async { completion(processed) }
    }
}

/// Fallback crop when rectangle detection fails: union all recognized text boxes and crop conservatively.
/// The crop is biased to keep the bottom portion (where totals usually live) and expands width generously.
private func heuristicTextCropReceipt(_ image: UIImage, debugLog: Bool) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.02

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
        try handler.perform([request])
    } catch {
        if debugLog {
            DebugLogger.debug("🧾 Heuristic text crop OCR error: \(error)", category: "ReceiptScan")
        }
        return nil
    }

    let boxes = request.results?.map { $0.boundingBox } ?? []
    guard var union = boxes.first else { return nil }
    for b in boxes.dropFirst() {
        union = union.union(b)
    }

    // Vision bounding boxes are normalized with origin at bottom-left.
    // Make a conservative crop that keeps the bottom of the image and includes all detected text.
    let padX: CGFloat = 0.06
    let padTop: CGFloat = 0.08

    // Start from bottom (y=0) up to the top of detected text (+ padding).
    var x0 = max(0.0, union.minX - padX)
    var x1 = min(1.0, union.maxX + padX)
    var h = min(1.0, union.maxY + padTop)

    // Expand width aggressively to avoid clipping receipt edges.
    if (x1 - x0) < 0.92 {
        x0 = 0.0
        x1 = 1.0
    }

    // Ensure we keep enough vertical content to include totals (even if text detection is sparse).
    h = max(h, 0.60)
    h = min(h, 1.0)

    let cropNorm = CGRect(x: x0, y: 0.0, width: max(0.01, x1 - x0), height: max(0.01, h))

    let imgW = CGFloat(cgImage.width)
    let imgH = CGFloat(cgImage.height)

    // Convert Vision-normalized (bottom-left origin) to CGImage pixel rect (top-left origin).
    let cropX = cropNorm.minX * imgW
    let cropW = cropNorm.width * imgW
    let cropH = cropNorm.height * imgH
    let cropYTopLeft = imgH - cropH

    let rect = CGRect(x: cropX, y: cropYTopLeft, width: cropW, height: cropH).integral
    guard rect.width > 10, rect.height > 10 else { return nil }
    guard let croppedCG = cgImage.cropping(to: rect) else { return nil }

    if debugLog {
        DebugLogger.debug("🧾 Heuristic text crop: cropRect=\(rect) from (\(cgImage.width)x\(cgImage.height))", category: "ReceiptScan")
    }
    return UIImage(cgImage: croppedCG, scale: 1.0, orientation: .up)
}

private func normalizeImageOrientation(_ image: UIImage) -> UIImage {
    guard image.imageOrientation != .up else { return image }
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
}

private func downscaleIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let w = image.size.width
    let h = image.size.height
    let maxSide = max(w, h)
    guard maxSide > maxDimension, maxSide > 0 else { return image }

    let scale = maxDimension / maxSide
    let newSize = CGSize(width: floor(w * scale), height: floor(h * scale))
    guard newSize.width > 0, newSize.height > 0 else { return image }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0 // we are explicitly controlling pixel size
    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
}

private func detectAndCorrectReceipt(in image: UIImage, debugLog: Bool) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }

    // Detect rectangles
    let request = VNDetectRectanglesRequest()
    // Consider more candidates; we will score them ourselves.
    request.maximumObservations = 12
    // Lower slightly to avoid missing faint edges on white receipts/sheets; scoring + guards will reject junk.
    request.minimumConfidence = 0.55
    // Receipts are typically long rectangles; de-emphasize near-squares.
    request.minimumAspectRatio = 0.12
    request.maximumAspectRatio = 0.85
    request.quadratureTolerance = 20.0
    // Allow narrower receipts (long + skinny) to be detected when the user doesn't fill the frame perfectly.
    request.minimumSize = 0.10

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
        try handler.perform([request])
    } catch {
        DebugLogger.debug("🧾 Rectangle detection error: \(error)", category: "ReceiptScan")
        return nil
    }

    guard let observations = request.results, !observations.isEmpty else { return nil }

    // Score candidates for "receipt-like" geometry: big + long-rectangle + roughly centered.
    func candidateScore(_ o: VNRectangleObservation) -> Double {
        let bb = o.boundingBox
        let area = Double(bb.width * bb.height) // normalized
        let w = Double(bb.width)
        let h = Double(bb.height)
        let minSide = min(w, h)
        let maxSide = max(w, h)
        let aspect = maxSide > 0 ? (minSide / maxSide) : 0.0 // 1.0 = square, smaller = longer rectangle

        // Prefer a long rectangle (receipts): peak around ~0.33, penalize near-squares.
        let targetAspect = 0.33
        let aspectRange = 0.45 // broad tolerance (covers many receipt widths)
        let aspectScore = max(0.0, 1.0 - abs(aspect - targetAspect) / aspectRange)

        // Prefer rectangles near the center (user aligns within guide frame).
        let cx = Double(bb.midX)
        let cy = Double(bb.midY)
        let dx = cx - 0.5
        let dy = cy - 0.5
        let centerDist = sqrt(dx * dx + dy * dy) // 0..~0.707
        let centerScore = max(0.0, 1.0 - (centerDist / 0.65))

        // Combine: area dominates, then confidence, with shape/center nudges.
        let conf = Double(o.confidence)
        return pow(area, 1.25) * (0.6 + 0.4 * conf) * (0.55 + 0.45 * aspectScore) * (0.65 + 0.35 * centerScore)
    }

    let best = observations.max { a, b in
        candidateScore(a) < candidateScore(b)
    }

    guard let rect = best else { return nil }

    // Guardrail: if the best candidate is too small or too square-ish, skip cropping.
    // This prevents "random square/rectangle" crops when Vision latches onto a high-contrast patch.
    let bb = rect.boundingBox
    let area = Double(bb.width * bb.height)
    let w = Double(bb.width)
    let h = Double(bb.height)
    let longSide = max(w, h)
    let aspect = longSide > 0 ? min(w, h) / longSide : 0.0 // 1.0 = square, smaller = longer rectangle

    // Accept long receipts even if area is modest (narrow width), as long as the long side fills most of the frame.
    let looksLikeLongReceipt = (longSide >= 0.70 && aspect <= 0.55)
    // Otherwise require a minimum area to avoid cropping random patches.
    let areaTooSmall = area < 0.06
    let tooSquare = aspect > 0.80

    if tooSquare || (areaTooSmall && !looksLikeLongReceipt) {
        if debugLog {
            DebugLogger.debug("🧾 Receipt preprocessing guard: rejecting best rectangle (area=\(String(format: "%.3f", area)), aspect=\(String(format: "%.3f", aspect)), longSide=\(String(format: "%.3f", longSide)), conf=\(String(format: "%.2f", rect.confidence)))", category: "ReceiptScan")
        }
        return nil
    }

    // Perspective correction using CoreImage
    let ciImage = CIImage(cgImage: cgImage)
    let extent = ciImage.extent
    let width = extent.width
    let height = extent.height

    func denorm(_ p: CGPoint) -> CGPoint {
        // VNRectangleObservation points are normalized with origin at bottom-left, which matches CoreImage coordinates.
        CGPoint(x: p.x * width, y: p.y * height)
    }

    var topLeft = denorm(rect.topLeft)
    var topRight = denorm(rect.topRight)
    var bottomLeft = denorm(rect.bottomLeft)
    var bottomRight = denorm(rect.bottomRight)

    // Inflate the quad so we don't clip header/totals due to tight detection.
    // Add extra bottom padding to ensure Subtotal/Tax/Total section is never cropped.
    (topLeft, topRight, bottomLeft, bottomRight) = inflateQuadWithVerticalPadding(
        topLeft: topLeft,
        topRight: topRight,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
        scale: 1.08,
        extraTopPaddingFraction: 0.10,
        extraBottomPaddingFraction: 0.26, // Increased to protect totals section
        bounds: extent
    )

    let filter = CIFilter.perspectiveCorrection()
    filter.inputImage = ciImage
    filter.topLeft = topLeft
    filter.topRight = topRight
    filter.bottomLeft = bottomLeft
    filter.bottomRight = bottomRight

    guard let output = filter.outputImage else { return nil }

    let context = CIContext(options: nil)
    guard let outCG = context.createCGImage(output, from: output.extent) else { return nil }
    return UIImage(cgImage: outCG, scale: 1.0, orientation: .up)
}

private func inflateQuad(
    topLeft: CGPoint,
    topRight: CGPoint,
    bottomLeft: CGPoint,
    bottomRight: CGPoint,
    scale: CGFloat,
    bounds: CGRect
) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    let cx = (topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4.0
    let cy = (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4.0
    let center = CGPoint(x: cx, y: cy)

    func scaled(_ p: CGPoint) -> CGPoint {
        let dx = p.x - center.x
        let dy = p.y - center.y
        let out = CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        return CGPoint(
            x: min(max(out.x, bounds.minX), bounds.maxX),
            y: min(max(out.y, bounds.minY), bounds.maxY)
        )
    }

    return (scaled(topLeft), scaled(topRight), scaled(bottomLeft), scaled(bottomRight))
}

/// Inflates a quad uniformly, then adds extra padding specifically on the "top" edge
/// (useful for long receipts where Vision sometimes detects a slightly-short rectangle and clips headers).
private func inflateQuadWithTopPadding(
    topLeft: CGPoint,
    topRight: CGPoint,
    bottomLeft: CGPoint,
    bottomRight: CGPoint,
    scale: CGFloat,
    extraTopPaddingFraction: CGFloat,
    bounds: CGRect
) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    var (tl, tr, bl, br) = inflateQuad(
        topLeft: topLeft,
        topRight: topRight,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
        scale: scale,
        bounds: bounds
    )

    // Compute direction from bottom edge to top edge.
    let topMid = CGPoint(x: (tl.x + tr.x) / 2.0, y: (tl.y + tr.y) / 2.0)
    let bottomMid = CGPoint(x: (bl.x + br.x) / 2.0, y: (bl.y + br.y) / 2.0)
    let dx = topMid.x - bottomMid.x
    let dy = topMid.y - bottomMid.y
    let len = max(1.0, sqrt(dx * dx + dy * dy))
    let dir = CGPoint(x: dx / len, y: dy / len)

    // Pad the top edge outward by a fraction of the detected receipt height.
    let extra = len * max(0.0, extraTopPaddingFraction)
    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(p.x, bounds.minX), bounds.maxX),
            y: min(max(p.y, bounds.minY), bounds.maxY)
        )
    }

    tl = clamp(CGPoint(x: tl.x + dir.x * extra, y: tl.y + dir.y * extra))
    tr = clamp(CGPoint(x: tr.x + dir.x * extra, y: tr.y + dir.y * extra))
    return (tl, tr, bl, br)
}

/// Inflates a quad uniformly, then adds extra padding on both the top and bottom edges.
/// Useful to avoid clipping both the header and the Subtotal/Tax/Total section on long receipts.
private func inflateQuadWithVerticalPadding(
    topLeft: CGPoint,
    topRight: CGPoint,
    bottomLeft: CGPoint,
    bottomRight: CGPoint,
    scale: CGFloat,
    extraTopPaddingFraction: CGFloat,
    extraBottomPaddingFraction: CGFloat,
    bounds: CGRect
) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    var (tl, tr, bl, br) = inflateQuad(
        topLeft: topLeft,
        topRight: topRight,
        bottomLeft: bottomLeft,
        bottomRight: bottomRight,
        scale: scale,
        bounds: bounds
    )

    let topMid = CGPoint(x: (tl.x + tr.x) / 2.0, y: (tl.y + tr.y) / 2.0)
    let bottomMid = CGPoint(x: (bl.x + br.x) / 2.0, y: (bl.y + br.y) / 2.0)
    let dx = topMid.x - bottomMid.x
    let dy = topMid.y - bottomMid.y
    let len = max(1.0, sqrt(dx * dx + dy * dy))
    let dir = CGPoint(x: dx / len, y: dy / len)

    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(p.x, bounds.minX), bounds.maxX),
            y: min(max(p.y, bounds.minY), bounds.maxY)
        )
    }

    let extraTop = len * max(0.0, extraTopPaddingFraction)
    let extraBottom = len * max(0.0, extraBottomPaddingFraction)

    // Push top edge outward along dir
    tl = clamp(CGPoint(x: tl.x + dir.x * extraTop, y: tl.y + dir.y * extraTop))
    tr = clamp(CGPoint(x: tr.x + dir.x * extraTop, y: tr.y + dir.y * extraTop))
    // Push bottom edge outward opposite dir
    bl = clamp(CGPoint(x: bl.x - dir.x * extraBottom, y: bl.y - dir.y * extraBottom))
    br = clamp(CGPoint(x: br.x - dir.x * extraBottom, y: br.y - dir.y * extraBottom))

    return (tl, tr, bl, br)
}

private func requestPhotoLibraryAddPermissionIfNeeded() {
    // We only need Add-Only access for saving debug images.
    if #available(iOS 14, *) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
        default:
            DebugLogger.debug("📷 Photo library add-only permission not granted; debug saves may fail.", category: "ReceiptScan")
        }
    } else {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { _ in }
        default:
            DebugLogger.debug("📷 Photo library permission not granted; debug saves may fail.", category: "ReceiptScan")
        }
    }
}

private func saveToPhotoLibrary(_ image: UIImage, label: String) {
    // Use UIImageWriteToSavedPhotosAlbum for simplicity; the label is logged only.
    DispatchQueue.main.async {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        DebugLogger.debug("📷 Saved \(label) image to Photos (\(Int(image.size.width))x\(Int(image.size.height)))", category: "ReceiptScan")
    }
}

// Animated dumpling rain view
struct DumplingRainView: View {
    @State private var animating = false
    let dumplingCount = 16
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<dumplingCount, id: \.self) { i in
                    DumplingEmojiView(index: i, width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct DumplingEmojiView: View {
    let index: Int
    let width: CGFloat
    let height: CGFloat
    @State private var y: CGFloat = -100
    var body: some View {
        let x = CGFloat.random(in: 0...(width-40))
        let delay = Double.random(in: 0...(index.isMultiple(of: 2) ? 0.5 : 1.0))
        Text("🥟")
            .font(.system(size: 40))
            .position(x: x, y: y)
            .onAppear {
                withAnimation(.easeIn(duration: 2.0).delay(delay)) {
                    y = height + 40
                }
            }
    }
}

// Animated boba rain view
struct BobaRainView: View {
    @State private var animating = false
    let bobaCount = 16
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<bobaCount, id: \.self) { i in
                    BobaEmojiView(index: i, width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct BobaEmojiView: View {
    let index: Int
    let width: CGFloat
    let height: CGFloat
    @State private var y: CGFloat = -100
    var body: some View {
        let x = CGFloat.random(in: 0...(width-40))
        let delay = Double.random(in: 0...(index.isMultiple(of: 2) ? 0.5 : 1.0))
        Text("🧋")
            .font(.system(size: 40))
            .position(x: x, y: y)
            .onAppear {
                withAnimation(.easeIn(duration: 2.0).delay(delay)) {
                    y = height + 40
                }
            }
    }
}

