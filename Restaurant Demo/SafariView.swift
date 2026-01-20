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
    let onDismiss: () -> Void
    let onSuccess: () -> Void
    let onCancel: () -> Void

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
            print("[SafariView] safariViewControllerDidFinish called")
            print("[SafariView] Calling onDismiss callback")
            parent.onDismiss()
        }
        
        func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            print("[SafariView] Initial load completed: \(didLoadSuccessfully)")
        }
    }
}

// Simplified SafariView for attached menu items - cleaner experience without additional UI
struct SimplifiedSafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: UIViewControllerRepresentableContext<SimplifiedSafariView>) -> SFSafariViewController {
        let safariViewController = SFSafariViewController(url: url)
        safariViewController.delegate = context.coordinator
        // Configure for cleaner appearance
        safariViewController.preferredBarTintColor = UIColor.systemBackground
        safariViewController.preferredControlTintColor = UIColor.systemBlue
        return safariViewController
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SimplifiedSafariView>) {
        // No update needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let parent: SimplifiedSafariView
        
        init(_ parent: SimplifiedSafariView) {
            self.parent = parent
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            print("[SimplifiedSafariView] safariViewControllerDidFinish called")
            parent.onDismiss()
        }
    }
}
