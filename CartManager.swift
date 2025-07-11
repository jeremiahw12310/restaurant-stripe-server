//
//  CartManager.swift
//  Restaurant Demo
//
//  Created by Jeremiah Wiseman on 6/27/25.
//
import Foundation
import Combine

// Represents a single item within the shopping cart.
struct CartItem: Identifiable, Equatable {
    let id = UUID()
    let menuItem: MenuItem
    var quantity: Int = 1
    var cookingStyle: String = "Boiled" // New: Boiled, Steamed, Pan-fried
}

// Manages the state of the user's shopping cart.
// This is an EnvironmentObject, accessible from any view in the app.
class CartManager: ObservableObject {
    @Published var items: [CartItem] = []
    @Published var showFlyingDumpling: Bool = false
    @Published var showFlyingBoba: Bool = false

    // A computed property to calculate the subtotal of all items in the cart.
    var subtotal: Double {
        items.reduce(0) { $0 + ($1.menuItem.price * Double($1.quantity)) }
    }
    
    // A computed property for the total quantity of items.
    var totalQuantity: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    /// Adds a menu item to the cart. If the item already exists with the same cooking style, it increases the quantity.
    func addToCart(item: MenuItem, cookingStyle: String = "Boiled", quantity: Int = 1) {
        if let index = items.firstIndex(where: { $0.menuItem.id == item.id && $0.cookingStyle == cookingStyle }) {
            items[index].quantity += quantity
        } else {
            items.append(CartItem(menuItem: item, quantity: quantity, cookingStyle: cookingStyle))
        }
    }
    
    /// Completely clears all items from the cart.
    func clearCart() {
        items.removeAll()
    }
    
    /// Updates the quantity of a specific item in the cart.
    func updateQuantity(for item: CartItem, quantity: Int) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].quantity = quantity
        }
    }
    
    /// Removes a specific item from the cart.
    func removeFromCart(_ item: CartItem) {
        items.removeAll { $0.id == item.id }
    }
    
    /// Calculates the total price including tax.
    var total: Double {
        subtotal * 1.09 // 9% tax
    }
}

