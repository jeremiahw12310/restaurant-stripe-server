import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

struct AdminOfficeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var userViewModel = AdminOfficeViewModel()
    @State private var searchText = ""
    @State private var selectedTab: Int = 0 // 0 = Users, 1 = Receipts
    @State private var selectedUser: UserAccount?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(red: 0.98, green: 0.96, blue: 0.94)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    header
                    tabSelector
                    Divider()
                        .padding(.bottom, 4)
                    tabContent
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            userViewModel.loadUsers()
        }
    }
    
    private var header: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Text("Admin Office")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    if selectedTab == 0 {
                        userViewModel.refreshUsers()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 20)
            
            if selectedTab == 0 {
                // Search + sort only apply to Users tab
                VStack(spacing: 12) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search by name, email, or phone...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .onChange(of: searchText) { _, newValue in
                                userViewModel.searchUsers(query: newValue)
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    )
                    
                    // Sort Controls
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(AdminOfficeViewModel.SortOption.allCases, id: \.self) { option in
                                Button(option.rawValue) {
                                    userViewModel.sortOption = option
                                    userViewModel.sortUsers()
                                }
                            }
                        } label: {
                            HStack {
                                Text("Sort by: \(userViewModel.sortOption.rawValue)")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                        }
                        
                        Button(action: {
                            userViewModel.sortOrder = userViewModel.sortOrder == .ascending ? .descending : .ascending
                            userViewModel.sortUsers()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: userViewModel.sortOrder == .ascending ? "arrow.up" : "arrow.down")
                                    .font(.caption)
                                Text(userViewModel.sortOrder.rawValue)
                                    .font(.subheadline)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 10)
    }
    
    private var tabSelector: some View {
        HStack(spacing: 12) {
            tabButton(title: "Users", icon: "person.3", index: 0)
            tabButton(title: "Receipts", icon: "doc.text.viewfinder", index: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedTab == index ? Color.white : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black.opacity(selectedTab == index ? 0.08 : 0.04), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var tabContent: some View {
        Group {
            if selectedTab == 0 {
                usersTab
            } else {
                AdminReceiptsView()
            }
        }
    }
    
    private var usersTab: some View {
        Group {
            if userViewModel.isLoading {
                Spacer()
                ProgressView("Loading users...")
                    .scaleEffect(1.2)
                Spacer()
            } else if userViewModel.filteredUsers.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "person.3")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text(searchText.isEmpty ? "No users found" : "No users match your search")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    if !searchText.isEmpty {
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .foregroundColor(.blue)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(userViewModel.filteredUsers) { user in
                            Button(action: {
                                selectedUser = user
                            }) {
                                AdminUserRow(user: user)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if userViewModel.hasMore {
                            ProgressView()
                                .onAppear { userViewModel.fetchNextPage() }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
        }
        .sheet(item: $selectedUser) { user in
            AdminUserDetailView(user: user)
        }
    }
}

struct AdminUserRow: View {
    let user: UserAccount
    
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(user.avatarColor)
                .frame(width: 48, height: 48)
                .overlay(Text(user.avatarEmoji).font(.title3))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(user.firstName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if user.isAdmin {
                        Text("Admin")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                
                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("\(user.points) pts")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                    
                    Text("Joined \(formatted(date: user.accountCreatedDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
    
    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}


