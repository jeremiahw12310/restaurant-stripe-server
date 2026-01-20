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
                var items: [HistoryItem] = []
                let group = DispatchGroup()
                for d in docs {
                    let data = d.data()
                    let referredId = data["referredUserId"] as? String
                    let statusRaw = (data["status"] as? String) ?? "pending"
                    let status = (statusRaw == "awarded") ? "Awarded" : "Pending"
                    if let rid = referredId, !rid.isEmpty {
                        group.enter()
                        db.collection("users").document(rid).getDocument { userDoc, _ in
                            let name = (userDoc?.data()?["firstName"] as? String) ?? "Friend"
                            items.append(HistoryItem(id: d.documentID, name: name, status: status, isOutbound: true, pointsTowards50: 0))
                            group.leave()
                        }
                    }
                }
                group.notify(queue: .main) {
                    self.outbound = items.sorted { $0.name < $1.name }
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
                var items: [HistoryItem] = []
                let group = DispatchGroup()
                for doc in docs {
                    let data = doc.data()
                    let referrerId = (data["referrerUserId"] as? String) ?? ""
                    let statusRaw = (data["status"] as? String) ?? "pending"
                    let status = (statusRaw == "awarded") ? "Awarded" : "Pending"
                    if !referrerId.isEmpty {
                        group.enter()
                        db.collection("users").document(referrerId).getDocument { userDoc, _ in
                            let name = (userDoc?.data()?["firstName"] as? String) ?? "Friend"
                            items.append(HistoryItem(id: doc.documentID, name: name, status: status, isOutbound: false, pointsTowards50: 0))
                            group.leave()
                        }
                    }
                }
                group.notify(queue: .main) {
                    self.inbound = items.sorted { $0.name < $1.name }
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








