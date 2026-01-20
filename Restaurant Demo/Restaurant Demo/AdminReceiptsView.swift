import SwiftUI

struct AdminReceiptsView: View {
    @StateObject private var viewModel = AdminReceiptsViewModel()
    @State private var isConfirmingDelete = false
    @State private var receiptPendingDelete: AdminReceipt?
    
    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Color(red: 0.98, green: 0.96, blue: 0.94).ignoresSafeArea())
        .onAppear {
            Task {
                await viewModel.loadInitial()
            }
        }
        .alert("Error", isPresented: Binding<Bool>(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Receipt Deleted", isPresented: Binding<Bool>(
            get: { viewModel.successMessage != nil },
            set: { _ in viewModel.successMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.successMessage ?? "")
        }
        .confirmationDialog(
            "Delete this receipt so it can be scanned again?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Receipt", role: .destructive) {
                if let receipt = receiptPendingDelete {
                    viewModel.deleteReceipt(receipt)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let receipt = receiptPendingDelete {
                Text(deleteDescription(for: receipt))
            }
        }
    }
    
    private var header: some View {
        HStack {
            Text("Scanned Receipts")
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            Button(action: {
                viewModel.refresh()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    private var content: some View {
        Group {
            if viewModel.isLoading && viewModel.receipts.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading receipts...")
                        .scaleEffect(1.1)
                    Spacer()
                }
            } else if viewModel.receipts.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No scanned receipts yet")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("Receipts will appear here after customers scan them.")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.8))
                    Spacer()
                }
                .padding(.horizontal, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.receipts) { receipt in
                            AdminReceiptRow(
                                receipt: receipt,
                                onDeleteTapped: {
                                    receiptPendingDelete = receipt
                                    isConfirmingDelete = true
                                }
                            )
                            .onAppear {
                                viewModel.loadMoreIfNeeded(currentReceipt: receipt)
                            }
                        }
                        
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }
    
    private func deleteDescription(for receipt: AdminReceipt) -> String {
        var parts: [String] = []
        if let order = receipt.orderNumber {
            parts.append("Order #\(order)")
        }
        if let date = receipt.orderDate {
            parts.append("on \(date)")
        }
        if let name = receipt.userName {
            parts.append("for \(name)")
        }
        let info = parts.isEmpty ? "this receipt" : parts.joined(separator: " ")
        return "\(info).\n\nDeleting does not remove any points already issued. The customer will be able to scan this receipt again."
    }
}

struct AdminReceiptRow: View {
    let receipt: AdminReceipt
    let onDeleteTapped: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let order = receipt.orderNumber {
                        Text("#\(order)")
                            .font(.headline)
                    } else {
                        Text("Unknown Order")
                            .font(.headline)
                    }
                    if let date = receipt.orderDate {
                        Text(date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let name = receipt.userName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                } else if let userId = receipt.userId {
                    Text("User: \(userId.prefix(8))…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let phone = receipt.userPhone, !phone.isEmpty {
                    Text(phone)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let ts = receipt.timestamp {
                    Text(Self.format(date: ts))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: onDeleteTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Delete")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red.opacity(0.1))
                )
                .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
    
    private static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}


