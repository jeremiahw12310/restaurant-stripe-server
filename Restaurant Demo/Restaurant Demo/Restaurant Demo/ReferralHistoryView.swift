import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ReferralHistoryView: View {
    struct HistoryItem: Identifiable {
        let id: String
        let name: String
        let status: String // "Pending" | "Awarded"
        let isOutbound: Bool
        let pointsTowards50: Int
        let createdAt: Date?
    }
    
    @State private var outbound: [HistoryItem] = []
    @State private var inbound: [HistoryItem] = []
    @State private var outboundListener: ListenerRegistration? = nil
    @State private var inboundListener: ListenerRegistration? = nil
    
    var body: some View {
        List {
            if !inbound.isEmpty {
                Section(header: Text("Received")) {
                    ForEach(inbound) { item in
                        HistoryRow(item: item)
                    }
                }
            }
            Section(header: Text("Sent")) {
                if outbound.isEmpty {
                    Text("No sent invites yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(outbound) { item in
                        HistoryRow(item: item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Connections")
        .onAppear(perform: startListeners)
        .onDisappear {
            outboundListener?.remove(); outboundListener = nil
            inboundListener?.remove(); inboundListener = nil
        }
    }
    
    private func startListeners() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        
        // Outbound
        outboundListener?.remove()
        outboundListener = db.collection("referrals")
            .whereField("referrerUserId", isEqualTo: uid)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else {
                    self.outbound = []
                    return
                }
                // IMPORTANT: Do not read users/{uid} for other users here (blocked by Firestore rules).
                // Use denormalized names and progress stored on the referral doc.
                let items: [HistoryItem] = docs.map { d in
                    let data = d.data()
                    let statusRaw = (data["status"] as? String) ?? "pending"
                    let status = (statusRaw == "awarded") ? "Awarded" : "Pending"
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                    let rawName = (data["referredFirstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let name = rawName.isEmpty ? "Friend" : rawName
                    // Read pointsTowards50 from referral doc (maintained by Cloud Function)
                    let ptsRaw = (data["pointsTowards50"] as? NSNumber)?.intValue ?? (data["pointsTowards50"] as? Int) ?? 0
                    let pointsTowards50 = min(max(ptsRaw, 0), 50) // Clamp to 0-50
                    return HistoryItem(id: d.documentID, name: name, status: status, isOutbound: true, pointsTowards50: pointsTowards50, createdAt: createdAt)
                }
                DispatchQueue.main.async {
                    self.outbound = items.sorted { item1, item2 in
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
        
        // Inbound
        inboundListener?.remove()
        inboundListener = db.collection("referrals")
            .whereField("referredUserId", isEqualTo: uid)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents, !docs.isEmpty else {
                    self.inbound = []
                    return
                }
                // IMPORTANT: Do not read users/{uid} for other users here (blocked by Firestore rules).
                // Use denormalized names and progress stored on the referral doc.
                let items: [HistoryItem] = docs.map { doc in
                    let data = doc.data()
                    let statusRaw = (data["status"] as? String) ?? "pending"
                    let status = (statusRaw == "awarded") ? "Awarded" : "Pending"
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                    let rawName = (data["referrerFirstName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let name = rawName.isEmpty ? "Friend" : rawName
                    // Read pointsTowards50 from referral doc (maintained by Cloud Function)
                    let ptsRaw = (data["pointsTowards50"] as? NSNumber)?.intValue ?? (data["pointsTowards50"] as? Int) ?? 0
                    let pointsTowards50 = min(max(ptsRaw, 0), 50) // Clamp to 0-50
                    return HistoryItem(id: doc.documentID, name: name, status: status, isOutbound: false, pointsTowards50: pointsTowards50, createdAt: createdAt)
                }
                DispatchQueue.main.async {
                    self.inbound = items.sorted { item1, item2 in
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
    }
}

fileprivate struct HistoryRow: View {
    let item: ReferralHistoryView.HistoryItem
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill((item.isOutbound ? Color.green : Color.orange).opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(item.name.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "F").uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(item.isOutbound ? .green : .orange)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    (Text(item.isOutbound ? "You referred " : "Referred by ") + Text(item.name).fontWeight(.semibold))
                    Spacer()
                    statusBadge(item.status)
                }
                if let date = item.createdAt {
                    Text(date, style: .date)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.isOutbound ? "You referred" : "Referred by") \(item.name), status \(item.status)"))
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
}








