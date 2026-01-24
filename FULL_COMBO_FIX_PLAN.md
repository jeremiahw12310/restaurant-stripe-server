# Fix Full Combo Drink Selection and Half-and-Half Support

## Issues Identified

1. **Drink Items Not Loading**: `RewardComboDrinkItemSelectionView` is trying to find items by matching menu category IDs (e.g., "Milk Tea"), but drink items are stored in reward tiers, not menu categories. The tier IDs are:
   - `tier_drinks_fruit_tea_450` for Fruit Tea
   - `tier_drinks_milk_tea_450` for Milk Tea  
   - `tier_drinks_lemonade_450` for Lemonade or Soda
   - `tier_drinks_coffee_450` for Coffee

2. **Half-and-Half Not Working**: The Full Combo flow currently disables half-and-half selection. Need to add support for it.

## Solution

### 1. Fix Drink Item Selection

**Problem**: `RewardComboDrinkItemSelectionView` uses `menuVM.menuCategories.first(where: { $0.id == drinkCategory })` which won't find items because:
- Menu categories might have different IDs
- Items are stored in reward tiers, not menu categories

**Fix**: Update `RewardComboDrinkItemSelectionView` to:
- Map drink category names to tier IDs
- Use `RewardRedemptionService.fetchEligibleItems()` with the tier ID (same as `RewardItemSelectionView` does)
- Remove dependency on `menuVM.menuCategories`

**File to Modify**: `Restaurant Demo/RewardComboDrinkItemSelectionView.swift`

### 2. Add Half-and-Half Support for Full Combo

**Problem**: Full Combo flow disables half-and-half in dumpling selection.

**Fix**: 
- Allow half-and-half selection for Full Combo
- When half-and-half is selected, store both flavors
- After half-and-half selection, proceed to drink category selection (skip cooking method since half-and-half already includes it)
- Update redemption to handle half-and-half for Full Combo

**Files to Modify**:
- `Restaurant Demo/RewardsComponents.swift` - Enable half-and-half and handle flow
- Update display logic to show half-and-half for Full Combo

## Implementation Details

### Drink Category to Tier ID Mapping

```swift
private func tierIdForCategory(_ category: String) -> String? {
    switch category {
    case "Fruit Tea": return "tier_drinks_fruit_tea_450"
    case "Milk Tea": return "tier_drinks_milk_tea_450"
    case "Lemonade": return "tier_drinks_lemonade_450"
    case "Soda": return "tier_drinks_lemonade_450" // Same tier as Lemonade
    default: return nil
    }
}
```

### Half-and-Half Flow for Full Combo

Current flow (single dumpling):
1. Select dumpling → Select cooking method → Select drink category → ...

New flow (half-and-half):
1. Select dumpling → Select half-and-half → Select flavors + cooking method → Select drink category → ...

The half-and-half selection view already handles cooking method, so we skip the separate cooking method step.

## Files to Modify

1. **RewardComboDrinkItemSelectionView.swift**
   - Replace menu category lookup with reward tier lookup
   - Use `RewardRedemptionService.fetchEligibleItems()` with tier ID
   - Remove `@EnvironmentObject var menuVM: MenuViewModel` dependency

2. **RewardsComponents.swift**
   - Enable half-and-half button for Full Combo
   - Handle half-and-half selection flow (skip cooking method step)
   - Update redemption to pass both dumpling items for half-and-half

3. **AdminRewardsScanView.swift** (if needed)
   - Ensure display name handles half-and-half for Full Combo
