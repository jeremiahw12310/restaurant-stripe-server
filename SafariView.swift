//
//  SafariView.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/27/25.
//
import SwiftUI
import SafariServices

//A helper to wrap SFSafariViewController so it can be used in SwiftUI.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void = {}

    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        let safariViewController = SFSafariViewController(url: url)
        safariViewController.delegate = context.coordinator
        return safariViewController
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {
        // No update needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let parent: SafariView
        
        init(_ parent: SafariView) {
            self.parent = parent
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            parent.onDismiss()
        }
    }
}
