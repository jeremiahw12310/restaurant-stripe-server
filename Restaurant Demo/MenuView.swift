import SwiftUI
import Combine

struct MenuView: View {
    @State private var showSearchPage = false
    @StateObject private var menuVM = MenuViewModel()
    @StateObject private var userVM = UserViewModel()
    @StateObject private var viewModel = MenuViewViewModel()
    @Environment(\.scenePhase) private var scenePhase
    // Track the currently selected category by ID to make NavigationLink more reliable
    @State private var selectedCategoryId: String?
    @State private var showAdminTools = false
    @State private var showAdminDashboard = false
    @State private var showComboErrorAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if menuVM.isLoading {
                    VStack {
                        ProgressView("Loading Menu...")
                            .scaleEffect(1.2)
                            .tint(.white)
                        Text("Please wait while we fetch the latest menu")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 8)
                    }
                } else {
                    ScrollView {
                    LazyVStack(spacing: 8) {
                            // Last update indicator (subtle)
                            if let lastUpdate = menuVM.lastMenuUpdate {
                                HStack {
                                    Spacer()
                                    Text("Updated \(lastUpdate.formatted(.relative(presentation: .named)))")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .padding(.horizontal, 4)
                                .padding(.bottom, 4)
                            }

                            // Personalized Combo Card (appears before every category)
                            PersonalizedComboCard {
                                viewModel.handlePersonalizedComboTap(userVM: userVM, menuVM: menuVM)
                            }
                            
                            ForEach(menuVM.orderedMenuCategories) { category in
                                NavigationLink(
                                    destination: CategoryDetailView(
                                        category: category,
                                        menuVM: menuVM,
                                        showAdminTools: $showAdminTools
                                    ),
                                    tag: category.id,
                                    selection: $selectedCategoryId
                                ) {
                                    CategoryRow(category: category)
                                        .environmentObject(menuVM)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 0)
                        .padding(.bottom, 160) // Extra space to scroll past the Order Online button (increased from 120 to prevent button overlap)
                    }
                    .refreshable {
                        // Pull-to-refresh: Force fetch fresh data from Firebase
                        await withCheckedContinuation { continuation in
                            menuVM.forceRefreshMenu()
                            // Wait a moment for the refresh to complete
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                continuation.resume()
                            }
                        }
                    }
                }

                // Interstitial overlay (no slide transition)
                if viewModel.showComboInterstitial {
                    VideoInterstitialView(
                        videoName: "combogen",
                        videoType: "mov",
                        flashStyle: .double,
                        earlyCutRequested: $viewModel.requestEarlyCut,
                        earlyCutLeadSeconds: 2.5,
                        earlyCutMinPlaySeconds: 4.5
                    ) {
                        viewModel.interstitialDidFinish()
                    }
                    .transition(.identity)
                    .zIndex(10)
                }

            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(viewModel.showComboInterstitial)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !viewModel.showComboInterstitial {
                        if userVM.isAdmin {
                            Button("Admin") {
                                showAdminDashboard = true
                            }
                            .foregroundColor(.white)
                        }
                        Button(action: {
                            showSearchPage = true
                        }) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            // Bottom-floating Order Online pill (only on Menu/Order tab)
            .overlay(alignment: .bottom) {
                if !viewModel.showComboInterstitial {
                    Button(action: { viewModel.showOrderWebView = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "bag.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text("ORDER ONLINE")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .tracking(0.6)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.red,
                                            Color.red.opacity(0.9)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
        .onAppear {
            // Reset selection whenever the Menu tab appears to avoid stale links
            selectedCategoryId = nil
            // NOTE: Menu data is loaded from cache on init, no need to fetch every time
            // The cache-first approach in MenuViewModel.init() handles this
            userVM.loadUserData()
            // Start menu order listener based on current admin status
            menuVM.startMenuOrderListenerIfAdmin(isAdmin: userVM.isAdmin)
            // Reload cached images when view appears (in case they were cleared)
            if !menuVM.menuCategories.isEmpty {
                menuVM.reloadCachedImages()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Reload cached images when app becomes active (after being in background)
            if newPhase == .active && oldPhase != .active && !menuVM.menuCategories.isEmpty {
                menuVM.reloadCachedImages()
            }
        }
        .onChange(of: userVM.isAdmin) { _, newIsAdmin in
            // When admin status changes (e.g., after login), update the menu order listener
            menuVM.startMenuOrderListenerIfAdmin(isAdmin: newIsAdmin)
        }
        .sheet(isPresented: $showAdminDashboard) {
            MenuAdminDashboard(menuVM: menuVM)
        }
        .sheet(isPresented: $showSearchPage) {
            NavigationView {
                SearchView()
                    .environmentObject(menuVM)
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .fullScreenCover(isPresented: $viewModel.showComboLoading) {
            PersonalizedComboLoadingView()
        }
        .sheet(isPresented: $viewModel.showComboResult) {
            if let combo = viewModel.personalizedCombo {
                PersonalizedComboResultView(
                    combo: combo,
                    onOrder: {
                        viewModel.showComboResult = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            viewModel.showOrderWebView = true
                        }
                    },
                    onBack: { viewModel.showComboResult = false }
                )
                .environmentObject(menuVM)
            }
        }
        .sheet(isPresented: $viewModel.showOrderWebView) {
            if let url = URL(string: "https://dumplinghousetn.kwickmenu.com/") {
                SimplifiedSafariView(
                    url: url,
                    onDismiss: {
                        viewModel.showOrderWebView = false
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("regeneratePersonalizedCombo"))) { _ in
            // Dismiss the current result and run the flow again with interstitial
            viewModel.showComboResult = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                viewModel.handlePersonalizedComboTap(userVM: userVM, menuVM: menuVM)
            }
        }
        // Surface combo flow errors (e.g., rate limited, preferences not completed)
        .onChange(of: viewModel.error) { _, newValue in
            showComboErrorAlert = (newValue?.isEmpty == false)
        }
        .alert("Combo Generation", isPresented: $showComboErrorAlert) {
            Button("Got It", role: .cancel) { }
        } message: {
            Text(viewModel.error ?? "Unable to generate combo right now. Please try again in a moment.")
        }
    }
    

}

#Preview {
    MenuView()
} 