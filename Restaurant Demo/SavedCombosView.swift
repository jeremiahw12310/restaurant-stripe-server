import SwiftUI
import Kingfisher

struct SavedCombosView: View {
    @State private var saved: [SavedComboRecord] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedCombo: PersonalizedCombo? = nil
    @EnvironmentObject var menuVM: MenuViewModel

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let error = error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                }
            } else if saved.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .foregroundColor(.secondary)
                    Text("No saved combos yet")
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(saved) { record in
                        HStack(spacing: 12) {
                            // Thumbnail from first item if resolvable
                            SavedComboThumbnail(record: record)
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Combo • \(record.items.count) items")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                // Preview the first couple items
                                Text(itemsPreview(for: record))
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                // One-line AI message preview
                                Text(record.aiResponse)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { openRecord(record) }
                        .padding(.vertical, 6)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.insetGrouped)
                .toolbar {
                    EditButton()
                }
            }
        }
        .sheet(item: $selectedCombo) { combo in
            PersonalizedComboResultView(
                combo: combo,
                onOrder: {
                    NotificationCenter.default.post(name: Notification.Name("openOrderFromSaved"), object: nil)
                },
                onBack: { selectedCombo = nil }
            )
            .environmentObject(menuVM)
        }
        .onAppear(perform: load)
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let key = "savedCombos"
        guard let raw = UserDefaults.standard.array(forKey: key) as? [Data] else {
            saved = []
            return
        }
        let decoder = JSONDecoder()
        var records: [SavedComboRecord] = []
        for data in raw {
            if let rec = try? decoder.decode(SavedComboRecord.self, from: data) {
                records.append(rec)
            }
        }
        saved = records
    }

    private func openRecord(_ record: SavedComboRecord) {
        // Resolve item names to MenuItem objects
        let resolvedItems: [MenuItem] = record.items.compactMap { name in
            menuVM.allMenuItems.first { $0.id == name }
        }
        guard !resolvedItems.isEmpty else { return }
        let total = record.totalPrice ?? resolvedItems.reduce(0) { $0 + $1.price }
        selectedCombo = PersonalizedCombo(items: resolvedItems, aiResponse: record.aiResponse, totalPrice: total)
    }

    private func itemsPreview(for record: SavedComboRecord) -> String {
        let maxShown = 2
        let shown = record.items.prefix(maxShown)
        let remainder = max(0, record.items.count - shown.count)
        if remainder > 0 {
            return shown.joined(separator: ", ") + " +\(remainder) more"
        } else {
            return shown.joined(separator: ", ")
        }
    }

    private func delete(at offsets: IndexSet) {
        var current = saved
        current.remove(atOffsets: offsets)
        saved = current
        // Persist
        let key = "savedCombos"
        let encoder = JSONEncoder()
        let encoded = current.compactMap { try? encoder.encode($0) }
        UserDefaults.standard.set(encoded, forKey: key)
    }
}

struct SavedComboRecord: Codable, Identifiable {
    let id = UUID()
    let items: [String]
    let aiResponse: String
    let totalPrice: Double?
    let savedAt: Date
}

// MARK: - Thumbnail helper
private struct SavedComboThumbnail: View {
    let record: SavedComboRecord
    @EnvironmentObject var menuVM: MenuViewModel
    
    var body: some View {
        if let firstName = record.items.first, let menuItem = menuVM.allMenuItems.first(where: { $0.id == firstName }), let url = menuItem.resolvedImageURL {
            KFImage(url)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .background(Color(.systemGray5))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.secondary)
            }
        }
    }
}


