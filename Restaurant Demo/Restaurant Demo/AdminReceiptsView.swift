import SwiftUI

struct AdminReceiptsView: View {
    @StateObject private var viewModel = AdminReceiptsViewModel()
    @State private var isConfirmingDelete = false
    @State private var receiptPendingDelete: AdminReceipt?
    @State private var selectedReceiptId: String?
    
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
        .sheet(isPresented: Binding(
            get: { selectedReceiptId != nil },
            set: { if !$0 { selectedReceiptId = nil } }
        )) {
            if let id = selectedReceiptId {
                AdminReceiptDetailView(
                    receiptId: id,
                    viewModel: viewModel,
                    onDismiss: { selectedReceiptId = nil }
                )
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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedReceiptId = receipt.id
                            }
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

// MARK: - Admin Receipt Detail (tap from list; shows full info + image when within 48h)
struct AdminReceiptDetailView: View {
    let receiptId: String
    @ObservedObject var viewModel: AdminReceiptsViewModel
    let onDismiss: () -> Void
    
    @State private var detail: AdminReceiptDetail?
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Loading receipt...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let d = detail {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            receiptInfoSection(d)
                            if d.imageUrl != nil && !d.imageExpired {
                                imageSection(url: d.imageUrl!)
                            } else {
                                imageExpiredSection
                            }
                            if hasVisibilityFlags(d) {
                                visibilitySection(d)
                            }
                        }
                        .padding(20)
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(viewModel.errorMessage ?? "Receipt not found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.94).ignoresSafeArea())
            .navigationTitle("Receipt Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .onAppear {
            Task {
                isLoading = true
                detail = await viewModel.fetchReceiptDetail(receiptId: receiptId)
                isLoading = false
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil && detail == nil && !isLoading },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { onDismiss() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    private func receiptInfoSection(_ d: AdminReceiptDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            detailRow("Order", d.orderNumber.map { "#\($0)" } ?? "—")
            detailRow("Date", d.orderDate ?? "—")
            detailRow("Time", d.orderTime ?? "—")
            if let total = d.orderTotal {
                detailRow("Total", String(format: "$%.2f", total))
            }
            detailRow("Customer", d.userName ?? d.userId.map { "User \($0.prefix(8))…" } ?? "—")
            if let phone = d.userPhone, !phone.isEmpty {
                detailRow("Phone", phone)
            }
            if let points = d.pointsAwarded {
                detailRow("Points awarded", "\(points)")
            }
            if let ts = d.timestamp {
                detailRow("Scanned", Self.format(ts))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white).shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2))
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
    }
    
    private func imageSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receipt image")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    Text("Could not load image")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                @unknown default:
                    EmptyView()
                }
            }
            Text("Images are removed after 48 hours.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white).shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2))
    }
    
    private var imageExpiredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receipt image")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "photo.badge.clock")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Receipt image no longer available (removed after 48 hours).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white).shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2))
    }
    
    private func hasVisibilityFlags(_ d: AdminReceiptDetail) -> Bool {
        d.totalVisibleAndClear != nil || d.orderNumberVisibleAndClear != nil || d.keyFieldsTampered == true || d.tamperingReason != nil
    }
    
    private func visibilitySection(_ d: AdminReceiptDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Validation flags")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            if let v = d.totalVisibleAndClear { detailRow("Total visible", v ? "Yes" : "No") }
            if let v = d.orderNumberVisibleAndClear { detailRow("Order # visible", v ? "Yes" : "No") }
            if let v = d.dateVisibleAndClear { detailRow("Date visible", v ? "Yes" : "No") }
            if let v = d.timeVisibleAndClear { detailRow("Time visible", v ? "Yes" : "No") }
            if d.keyFieldsTampered == true {
                detailRow("Tampering", d.tamperingReason ?? "Detected")
            }
            if d.orderNumberInBlackBox == true { detailRow("Order # source", "Black box") }
            if d.paidOnlineReceipt == true { detailRow("Paid online", "Yes") }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white).shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2))
    }
    
    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}


