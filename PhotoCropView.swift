//
//  PhotoCropView.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/28/25.
//

import SwiftUI

struct PhotoCropView: View {
    @Binding var selectedImage: UIImage?
    let onCropComplete: (UIImage?) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Adaptive background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Text("Crop Photo")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button("Save") {
                        saveCroppedImage()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                Spacer()
                
                // Image with crop overlay
                if let image = selectedImage {
                    ZStack {
                        // Image
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                        
                        // Crop overlay
                        CropOverlay()
                    }
                    .frame(width: 280, height: 280)
                    .clipped()
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                print("🖱️ Drag gesture: \(value.translation)")
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                                print("🖱️ Drag ended, offset: \(offset)")
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                print("🔍 Magnification gesture: \(value)")
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                print("🔍 Magnification ended, scale: \(scale)")
                            }
                    )
                } else {
                    Text("No image selected")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Instructions
                VStack(spacing: 8) {
                    Text("Drag to move • Pinch to zoom")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("Position your face in the center")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            // Reset transformations
            scale = 1.0
            offset = .zero
            lastOffset = .zero
            lastScale = 1.0
            print("📱 PhotoCropView appeared")
        }
    }
    
    private func saveCroppedImage() {
        guard let originalImage = selectedImage else {
            print("❌ No image to crop")
            dismiss()
            return
        }
        
        print("✂️ Cropping image with scale: \(scale), offset: \(offset)")
        
        // Create a cropped version of the image
        let croppedImage = cropImage(originalImage)
        onCropComplete(croppedImage)
        dismiss()
    }
    
    private func cropImage(_ image: UIImage) -> UIImage {
        // Calculate the cropping rect in the image's coordinate space
        let cropSize: CGFloat = 200
        let viewSize: CGFloat = 280
        let scaleRatio = image.size.width / viewSize
        let scaledCropSize = cropSize * scaleRatio / scale
        let x = ((viewSize / 2) - offset.width - (cropSize / 2)) * scaleRatio / scale
        let y = ((viewSize / 2) - offset.height - (cropSize / 2)) * scaleRatio / scale
        let cropRect = CGRect(x: x, y: y, width: scaledCropSize, height: scaledCropSize)
        
        print("📐 Crop rect: \(cropRect)")
        
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            print("❌ Failed to crop image")
            return image
        }
        let cropped = UIImage(cgImage: cgImage)
        // Mask to circle
        UIGraphicsBeginImageContextWithOptions(cropped.size, false, 0.0)
        let path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: cropped.size))
        path.addClip()
        cropped.draw(in: CGRect(origin: .zero, size: cropped.size))
        let final = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        print("✅ Image cropped successfully")
        return final ?? cropped
    }
}

struct CropOverlay: View {
    var body: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.5)
                .mask(
                    Rectangle()
                        .overlay(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 200, height: 200)
                                .blendMode(.destinationOut)
                        )
                )
            
            // Crop circle outline
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 200, height: 200)
        }
        .allowsHitTesting(false) // Don't intercept gestures
    }
}
