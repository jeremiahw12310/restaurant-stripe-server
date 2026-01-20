import SwiftUI
import Kingfisher

struct CategoryRow: View {
    let category: MenuCategory
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var menuVM: MenuViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Optional PNG icon per category - use cached image if available
            if let iconString = effectiveIconString(for: category),
               let url = resolveIconURL(iconString) {
                let urlString = url.absoluteString
                
                // Use cached image if available, otherwise fall back to Kingfisher
                if let cachedImage = menuVM.cachedCategoryIcons[urlString] {
                    // Cached image - instant display!
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 57, height: 57)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    // Fallback to Kingfisher for uncached images
                    KFImage(url)
                        .resizable()
                        .placeholder { 
                            ProgressView()
                                .frame(width: 57, height: 57)
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 57, height: 57)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            Text(category.id)
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case let c where c.contains("appetizer"): return "leaf.fill"
        case let c where c.contains("main"): return "fork.knife"
        case let c where c.contains("dessert"): return "birthday.cake.fill"
        case let c where c.contains("drink"): return "cup.and.saucer.fill"
        case let c where c.contains("soup"): return "drop.fill"
        case let c where c.contains("salad"): return "leaf.circle.fill"
        case let c where c.contains("pizza"): return "circle.grid.3x3.fill"
        case let c where c.contains("tea"): return "cup.and.saucer.fill"
        case let c where c.contains("coffee"): return "cup.and.saucer.fill"
        case let c where c.contains("sauce"): return "drop.fill"
        case let c where c.contains("lemonade"): return "drop.fill"
        case let c where c.contains("coke"): return "drop.fill"
        default: return "circle.fill"
        }
    }

    private func effectiveIconString(for category: MenuCategory) -> String? {
        // Admin-controlled text-only category rendering (overrides uploaded icon + built-in defaults)
        if category.hideIcon { return nil }

        // Prefer icon set on the category document
        if !category.icon.isEmpty { return category.icon }
        let key = category.id.lowercased()
        if key == "dumplings" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/Subject.png?alt=media"
        } else if key == "soups" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/wontonsoup-2.png?alt=media"
        } else if key == "appetizers" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/eda.png?alt=media"
        } else if key == "coke products" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/coke.png?alt=media"
        } else if key == "sauces" {
            return "https://firebasestorage.googleapis.com/v0/b/dumplinghouseapp.firebasestorage.app/o/peanut.png?alt=media"
        }
        return nil
    }
    
    private func resolveIconURL(_ icon: String) -> URL? {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("gs://") {
            let components = trimmed.replacingOccurrences(of: "gs://", with: "").components(separatedBy: "/")
            if components.count >= 2 {
                let bucketName = components[0]
                let filePath = components.dropFirst().joined(separator: "/")
                // Encode object name for /o/<object> where slashes must be %2F
                let partiallyEncoded = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
                let encodedPath = partiallyEncoded.replacingOccurrences(of: "/", with: "%2F")
                // Try both Firebase endpoints
                let candidates = [
                    "https://firebasestorage.googleapis.com/v0/b/\(bucketName)/o/\(encodedPath)?alt=media",
                    "https://storage.googleapis.com/\(bucketName)/\(filePath)"
                ]
                for candidate in candidates {
                    if let url = URL(string: candidate) {
                        return url
                    }
                }
            }
        } else if trimmed.hasPrefix("http") {
            return URL(string: trimmed)
        }
        return nil
    }
} 