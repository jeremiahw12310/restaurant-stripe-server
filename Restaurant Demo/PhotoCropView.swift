//
//  PhotoCropView.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/28/25.
//

import SwiftUI
import UIKit

struct PhotoCropView: View {
    @Binding var selectedImage: UIImage?
    let onCropComplete: (UIImage?) -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var disableSheetDismiss = true
    
    var body: some View {
        ZStack {
            // Adaptive background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Button("Cancel") {
                        disableSheetDismiss = false
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
                            .gesture(
                                SimultaneousGesture(
                                    DragGesture()
                                        .onChanged { value in
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        },
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = lastScale * value
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                        }
                                )
                            )
                        // Crop overlay
                        CropOverlay()
                    }
                    .frame(width: 280, height: 280)
                    .clipped()
                    // Prevent sheet drag-to-dismiss by disabling interactive dismiss
                    .interactiveDismissDisabled(true)
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
        let cropSize: CGFloat = 200
        let viewSize: CGFloat = 280
        let imageSize = image.size
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize / viewSize // always 1
        
        // Calculate the size of the image as displayed in the view (aspect fit)
        var displayedImageSize: CGSize
        if imageAspect > viewAspect {
            // Image is wider than view
            let width = viewSize
            let height = viewSize / imageAspect
            displayedImageSize = CGSize(width: width, height: height)
        } else {
            // Image is taller or square
            let width = viewSize * imageAspect
            let height = viewSize
            displayedImageSize = CGSize(width: width, height: height)
        }
        
        // Calculate the origin of the displayed image in the view
        let imageOrigin = CGPoint(
            x: (viewSize - displayedImageSize.width) / 2,
            y: (viewSize - displayedImageSize.height) / 2
        )
        
        // The center of the crop circle in the view (fixed at center)
        let cropCenterInView = CGPoint(x: viewSize / 2, y: viewSize / 2)
        
        // Calculate the crop rect in the view's coordinate system
        let cropRectInView = CGRect(
            x: cropCenterInView.x - cropSize / 2,
            y: cropCenterInView.y - cropSize / 2,
            width: cropSize,
            height: cropSize
        )
        
        // Calculate the scale factor from displayed image to original image
        let scaleToImage = imageSize.width / displayedImageSize.width
        
        // Calculate the offset in image coordinates
        let offsetInImage = CGPoint(
            x: -offset.width * scaleToImage / scale,
            y: -offset.height * scaleToImage / scale
        )
        
        // Map the crop rect from view space to image space
        let cropRectInImage = CGRect(
            x: (cropRectInView.origin.x - imageOrigin.x) * scaleToImage + offsetInImage.x,
            y: (cropRectInView.origin.y - imageOrigin.y) * scaleToImage + offsetInImage.y,
            width: cropRectInView.size.width * scaleToImage,
            height: cropRectInView.size.height * scaleToImage
        )
        
        // Ensure the crop rect is within the image bounds
        let clampedRect = CGRect(
            x: max(0, cropRectInImage.origin.x),
            y: max(0, cropRectInImage.origin.y),
            width: min(cropRectInImage.size.width, imageSize.width - max(0, cropRectInImage.origin.x)),
            height: min(cropRectInImage.size.height, imageSize.height - max(0, cropRectInImage.origin.y))
        )
        
        guard let cgImage = image.cgImage?.cropping(to: clampedRect.integral) else {
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
