import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Generates and renders a QR code image for a string payload.
/// Intended for short payloads (e.g., an 8-digit reward code).
struct RewardQRCodeView: View {
    let text: String
    var foregroundColor: UIColor = .black
    var backgroundColor: UIColor = .white
    var correctionLevel: String = "M" // L, M, Q, H

    var body: some View {
        if let image = QRCodeRenderer.shared.uiImage(
            text: text,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            correctionLevel: correctionLevel
        ) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("QR code")
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    Image(systemName: "qrcode")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                )
                .accessibilityLabel("QR code unavailable")
        }
    }
}

private final class QRCodeRenderer {
    static let shared = QRCodeRenderer()

    private struct CacheKey: Hashable {
        let text: String
        let fgRGBA: UInt32
        let bgRGBA: UInt32
        let correctionLevel: String
    }

    private let context = CIContext(options: [
        .useSoftwareRenderer: false
    ])
    private let cache = NSCache<WrappedKey, UIImage>()

    func uiImage(text: String, foregroundColor: UIColor, backgroundColor: UIColor, correctionLevel: String) -> UIImage? {
        let fg = foregroundColor.rgba32
        let bg = backgroundColor.rgba32
        let key = CacheKey(text: text, fgRGBA: fg, bgRGBA: bg, correctionLevel: correctionLevel)

        if let cached = cache.object(forKey: WrappedKey(key)) {
            return cached
        }

        guard let data = text.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up sharply. QR codes look best with nearest-neighbor scaling.
        let scale: CGFloat = 12
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Colorize the QR code.
        let colorFilter = CIFilter.falseColor()
        colorFilter.inputImage = scaled
        colorFilter.color0 = CIColor(color: foregroundColor)
        colorFilter.color1 = CIColor(color: backgroundColor)

        guard let colored = colorFilter.outputImage else { return nil }
        guard let cgImage = context.createCGImage(colored, from: colored.extent) else { return nil }

        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: WrappedKey(key))
        return image
    }
}

private final class WrappedKey: NSObject {
    let key: AnyHashable
    init<T: Hashable>(_ key: T) { self.key = AnyHashable(key) }
    override var hash: Int { key.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? WrappedKey else { return false }
        return key == other.key
    }
}

private extension UIColor {
    var rgba32: UInt32 {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let rr = UInt32((r * 255).rounded())
        let gg = UInt32((g * 255).rounded())
        let bb = UInt32((b * 255).rounded())
        let aa = UInt32((a * 255).rounded())
        return (rr << 24) | (gg << 16) | (bb << 8) | aa
    }
}

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Simple QR renderer for displaying a large, crisp QR code in SwiftUI.
/// Named uniquely to avoid clashing with the referral QR components.
struct RewardRedemptionQRCodeView: View {
    let text: String
    var foregroundColor: UIColor = .black
    var backgroundColor: UIColor = .white

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if let image = makeUIImage(from: text) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .accessibilityLabel("QR code")
            } else {
                // Fallback: never block UI if QR generation fails
                Text("Unable to generate QR")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }

    private func makeUIImage(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        // Colorize
        let colored = outputImage.applyingFilter(
            "CIFalseColor",
            parameters: [
                "inputColor0": CIColor(color: foregroundColor),
                "inputColor1": CIColor(color: backgroundColor)
            ]
        )

        guard let cgImage = context.createCGImage(colored, from: colored.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}


