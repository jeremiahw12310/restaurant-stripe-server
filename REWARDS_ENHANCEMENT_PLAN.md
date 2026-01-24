# 🎁 Rewards Enhancement Plan: Toppings & Cooking Methods

## Overview
This plan outlines the implementation of additional customization options for reward redemptions:
1. **Drink Rewards (Milk Tea, Fruit Tea, Lemonade)**: Add toppings selection after drink selection
2. **12-Piece Dumpling Reward**: Add half-and-half selection (2 items) and cooking method selection

---

## 📋 Current System Analysis

### Existing Flow
1. User selects a reward from the rewards list
2. `RewardDetailView` shows reward details and "Redeem" button
3. User confirms redemption
4. `RewardItemSelectionView` shows eligible items (if reward has `eligibleCategoryId`)
5. User selects an item (optional)
6. Redemption is processed with `selectedItemId` and `selectedItemName`
7. Cashier views the redemption code and sees the selected item name

### Current Data Model
- **Backend (`/redeem-reward`)**: Accepts `selectedItemId`, `selectedItemName`
- **Firestore (`redeemedRewards`)**: Stores `selectedItemId`, `selectedItemName`
- **Cashier View**: Displays `selectedItemName` if available

### Reference Implementation
- **`HalfAndHalfView.swift`**: Shows how to select 2 dumpling flavors and cooking method
- **`MenuViewModel.toppingsCategory`**: Property that identifies the toppings category
- **Cooking Methods**: `["Boiled", "Steamed", "Pan-fried"]` (from `HalfAndHalfView`)

---

## 🎯 Requirements Breakdown

### 1. Drink Rewards with Toppings (Milk Tea, Fruit Tea, Lemonade)

**Rewards Affected:**
- "Milk Tea" (450 pts, `eligibleCategoryId: "Milk Tea"`)
- "Fruit Tea" (450 pts, `eligibleCategoryId: "Fruit Tea"`)
- "Lemonade" (450 pts, `eligibleCategoryId: "Lemonade"`)

**User Flow:**
1. User selects reward → Confirms redemption
2. User selects a drink from eligible items (existing flow)
3. **NEW**: User selects one topping from the "Toppings" category
4. Redemption proceeds with both drink and topping selections
5. Cashier sees: "[Drink Name] with [Topping Name]"

**Implementation Details:**
- After drink selection, show a second selection screen for toppings
- Fetch toppings from the category marked with `isToppingCategory = true`
- Store both `selectedItemId` (drink) and `selectedToppingId` (topping)
- Display format: "Drink Name with Topping Name"

### 2. 12-Piece Dumpling Reward with Half-and-Half & Cooking Method

**Reward Affected:**
- "12-Piece Dumplings" (1500 pts, `rewardTierId: "tier_12piece_1500"`)

**User Flow:**
1. User selects reward → Confirms redemption
2. **NEW**: User selects first dumpling flavor (from Dumplings category)
3. **NEW**: User selects second dumpling flavor (from Dumplings category, different from first)
4. **NEW**: User selects cooking method (Boiled, Steamed, Pan-fried)
5. Redemption proceeds with all selections
6. Cashier sees: "Half and Half: [Flavor 1] + [Flavor 2] ([Cooking Method])"

**Implementation Details:**
- Show a multi-step selection interface similar to `HalfAndHalfView`
- Store `selectedItemId` (flavor 1), `selectedItemId2` (flavor 2), `cookingMethod`
- Display format: "Half and Half: Flavor 1 + Flavor 2 (Cooking Method)"
- Reuse cooking method enum: `["Boiled", "Steamed", "Pan-fried"]`

---

## 🏗️ Architecture Changes

### Data Model Updates

#### Backend (`server.js` - `/redeem-reward` endpoint)
```javascript
// New fields to accept
const { 
  selectedItemId,      // Existing
  selectedItemName,    // Existing
  selectedToppingId,   // NEW: For drink rewards
  selectedToppingName, // NEW: For drink rewards
  selectedItemId2,     // NEW: For half-and-half (second dumpling)
  selectedItemName2,   // NEW: For half-and-half (second dumpling)
  cookingMethod        // NEW: For dumpling rewards ("Boiled", "Steamed", "Pan-fried")
} = req.body;
```

#### Firestore (`redeemedRewards` collection)
```javascript
// New fields to store
{
  selectedItemId: String?,
  selectedItemName: String?,
  selectedToppingId: String?,      // NEW
  selectedToppingName: String?,    // NEW
  selectedItemId2: String?,        // NEW
  selectedItemName2: String?,      // NEW
  cookingMethod: String?           // NEW: "Boiled" | "Steamed" | "Pan-fried"
}
```

#### Swift Models (`RewardRedemptionModels.swift`)
```swift
struct RewardRedemptionRequest: Codable {
  // ... existing fields
  let selectedToppingId: String?      // NEW
  let selectedToppingName: String?    // NEW
  let selectedItemId2: String?        // NEW
  let selectedItemName2: String?      // NEW
  let cookingMethod: String?          // NEW
}

struct RedeemedReward: Identifiable, Codable {
  // ... existing fields
  let selectedToppingId: String?      // NEW
  let selectedToppingName: String?    // NEW
  let selectedItemId2: String?        // NEW
  let selectedItemName2: String?      // NEW
  let cookingMethod: String?          // NEW
}

struct RewardRedemptionResponse: Codable {
  // ... existing fields
  let selectedToppingName: String?    // NEW
  let selectedItemName2: String?      // NEW
  let cookingMethod: String?          // NEW
}
```

### UI Flow Updates

#### 1. Enhanced Reward Selection Flow

**For Drink Rewards:**
```
RewardDetailView
  ↓ (User taps Redeem)
RedemptionConfirmationDialog
  ↓ (User confirms)
RewardItemSelectionView (Drink Selection)
  ↓ (User selects drink)
RewardToppingSelectionView (NEW: Topping Selection)
  ↓ (User selects topping)
Redemption processed
```

**For 12-Piece Dumpling Reward:**
```
RewardDetailView
  ↓ (User taps Redeem)
RedemptionConfirmationDialog
  ↓ (User confirms)
RewardHalfAndHalfSelectionView (NEW: Dumpling + Cooking Method Selection)
  ↓ (User selects flavors + method)
Redemption processed
```

### New Swift Views

#### 1. `RewardToppingSelectionView.swift`
- Similar structure to `RewardItemSelectionView`
- Fetches items from the toppings category (`MenuViewModel.toppingsCategory`)
- Allows selecting one topping
- Calls callback with topping selection

#### 2. `RewardHalfAndHalfSelectionView.swift`
- Similar structure to `HalfAndHalfView`
- Fetches dumpling items from "Dumplings" category
- Allows selecting two different dumpling flavors
- Includes cooking method picker (Boiled, Steamed, Pan-fried)
- Calls callback with both selections + cooking method

### Updated Views

#### `RewardsComponents.swift` - `RewardDetailView`
- Update redemption flow to handle multi-step selection:
  - Detect if reward requires toppings (Milk Tea, Fruit Tea, Lemonade)
  - Detect if reward requires half-and-half (12-Piece Dumplings)
  - Show appropriate selection views in sequence

#### `AdminRewardsScanView.swift`
- Update display logic to show:
  - For drink rewards: "[Drink] with [Topping]" if topping selected
  - For dumpling rewards: "Half and Half: [Flavor 1] + [Flavor 2] ([Method])" if applicable

---

## 📝 Implementation Steps

### Phase 1: Backend Updates
1. ✅ Update `/redeem-reward` endpoint to accept new fields
2. ✅ Update Firestore document structure to store new fields
3. ✅ Update `/admin/rewards/validate` endpoint to return new fields
4. ✅ Update `/admin/rewards/consume` endpoint (if needed)

### Phase 2: Swift Models
1. ✅ Update `RewardRedemptionRequest` model
2. ✅ Update `RedeemedReward` model
3. ✅ Update `RewardRedemptionResponse` model
4. ✅ Add enum for cooking methods

### Phase 3: UI Components
1. ✅ Create `RewardToppingSelectionView.swift`
2. ✅ Create `RewardHalfAndHalfSelectionView.swift`
3. ✅ Update `RewardDetailView` flow logic
4. ✅ Update `RewardRedemptionService` to handle new fields

### Phase 4: Cashier Display
1. ✅ Update `AdminRewardsScanView` to display new information
2. ✅ Format display strings for different reward types

### Phase 5: Testing
1. ✅ Test drink reward with toppings selection
2. ✅ Test 12-piece dumpling with half-and-half and cooking method
3. ✅ Test cashier view displays correctly
4. ✅ Test edge cases (missing selections, etc.)

---

## 🎨 UI/UX Considerations

### Topping Selection Screen
- Similar design to `RewardItemSelectionView`
- Header: "Choose Your Topping"
- Subtitle: "Select one topping for your [Drink Type]"
- Grid layout of topping items
- Continue button (topping required for these rewards)

### Half-and-Half Selection Screen
- Similar design to `HalfAndHalfView`
- Header: "Choose Your Dumplings"
- Two flavor selection sections
- Cooking method picker (segmented control)
- Continue button (all selections required)

### Cashier Display Format
- **Drink with Topping**: "Mango Fruit Tea with Tapioca Pearls"
- **Half and Half**: "Half and Half: Pork & Chive + Shrimp & Pork (Pan-fried)"
- **Regular Item**: "Pork & Chive Dumplings" (existing behavior)

---

## 🔄 Migration Considerations

- Existing redeemed rewards will have `null` for new fields (backward compatible)
- Cashier view should handle missing new fields gracefully
- Display logic should check for new fields before displaying enhanced information

---

## ✅ Success Criteria

1. ✅ Drink rewards (Milk Tea, Fruit Tea, Lemonade) show toppings selection after drink selection
2. ✅ Topping selection is required and saved with redemption
3. ✅ 12-Piece Dumpling reward shows half-and-half selection screen
4. ✅ Cooking method selection is saved with redemption
5. ✅ Cashier view displays all selections clearly
6. ✅ Backward compatibility maintained for existing redemptions

---

## 📚 Files to Modify

### Backend
- `server.js` (main server)
- `backend/server.js` (dev server)
- `backend-deploy/server.js` (production server)

### Swift Client
- `Restaurant Demo/RewardRedemptionModels.swift`
- `Restaurant Demo/RewardRedemptionService.swift`
- `Restaurant Demo/RewardsComponents.swift`
- `Restaurant Demo/RewardItemSelectionView.swift`
- `Restaurant Demo/AdminRewardsScanView.swift`
- `Restaurant Demo/RewardToppingSelectionView.swift` (NEW)
- `Restaurant Demo/RewardHalfAndHalfSelectionView.swift` (NEW)

---

## 🔍 Open Questions / Decisions Needed

1. **Topping Selection**: Should topping selection be required or optional?
   - **Decision**: Required for Milk Tea, Fruit Tea, and Lemonade rewards (as stated in description)

2. **Display Format**: How should multiple selections be formatted for cashier?
   - **Decision**: "Drink with Topping" format for drinks, "Half and Half: Flavor 1 + Flavor 2 (Method)" for dumplings

3. **Error Handling**: What happens if toppings category doesn't exist or is empty?
   - **Decision**: Show error message and allow user to continue without topping (fallback to generic reward)

4. **Cooking Method Default**: Should there be a default cooking method for dumplings?
   - **Decision**: "Steamed" as default (matching `HalfAndHalfView`)

---

## 🚀 Next Steps

Once this plan is approved, we'll proceed with implementation in the order outlined above, starting with backend updates and then moving to UI components.