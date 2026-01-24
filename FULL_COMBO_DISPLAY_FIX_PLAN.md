# Fix Full Combo Display Name for Half-and-Half

## Problem

When Full Combo is redeemed with half-and-half dumplings, a drink, and a topping, the display shows:
- **Current**: "Chicken & Coriander (Pan-fried) + Curry Chicken with Boba Jelly"
- **Expected**: "Half and Half: Chicken & Coriander + Curry Chicken (Pan-fried) + [Drink Name] with Boba Jelly"

## Root Cause

The display logic has two issues:

1. **Order of checks**: The `buildDisplayName` function checks for Full Combo first, but when it's half-and-half Full Combo:
   - `selectedItemName` = first dumpling (Chicken & Coriander)
   - `selectedItemName2` = second dumpling (Curry Chicken) - NOT the drink
   - The Full Combo check assumes `selectedItemName2` is the drink, so it incorrectly formats it

2. **Data model limitation**: For half-and-half Full Combo, we can't store the drink because:
   - `selectedItem2` is used for the second dumpling flavor
   - There's no separate field for the drink item
   - The drink (`comboDrinkItem`) is lost during redemption

## Solution

### 1. Fix Display Logic Order

The display logic should check for Full Combo with half-and-half BEFORE checking for regular Full Combo.

**Detection logic**:
- If `rewardTitle == "Full Combo"` AND `selectedItemName2` exists AND `selectedToppingName` exists
- This indicates it's Full Combo with items selected
- But we need to distinguish: is `selectedItemName2` the drink (single dumpling) or second dumpling (half-and-half)?

**Better approach**: Check if it looks like half-and-half first:
- If `rewardTitle == "Full Combo"` AND `selectedItemName` exists AND `selectedItemName2` exists AND `cookingMethod` exists AND `selectedToppingName` exists
- This could be either:
  - Single dumpling + drink + topping (selectedItem2 = drink)
  - Half-and-half + drink + topping (selectedItem2 = second dumpling, drink is missing)

**Problem**: We can't distinguish between these two cases with current data model.

### 2. Add Backend Field for Drink (Recommended)

Add a new field to store the drink item separately:
- `selectedDrinkItemId` / `selectedDrinkItemName` - for Full Combo drink

This allows:
- `selectedItem` / `selectedItemName` = first dumpling (or single dumpling)
- `selectedItem2` / `selectedItemName2` = second dumpling (for half-and-half) OR drink (for single dumpling)
- `selectedDrinkItem` / `selectedDrinkItemName` = drink (for Full Combo)

### 3. Temporary Fix (Without Backend Changes)

For now, we can improve the display logic by:
1. Checking if it's Full Combo with half-and-half pattern
2. If `selectedItemName2` looks like a dumpling name (not a drink), treat it as half-and-half
3. Format as "Half and Half: [Flavor1] + [Flavor2] ([Method]) + [Drink] with [Topping]"
4. Note: Drink name will be missing until backend field is added

**Better temporary solution**: Store drink name in a way that can be retrieved. But we can't modify backend easily.

### 4. Alternative: Store Drink in Description or Note Field

We could store the drink name in the `rewardDescription` or add it to a note, but this is hacky.

## Implementation Plan

### Option A: Backend Field (Best Solution)

1. **Backend Changes** (`server.js`):
   - Add `selectedDrinkItemId` and `selectedDrinkItemName` to redemption request
   - Store these fields in Firestore `redeemedRewards` collection
   - Return these fields in validation and consumption endpoints

2. **Frontend Changes**:
   - Update `RewardRedemptionRequest` to include drink item fields
   - Update `RedeemedReward` model to include drink item fields
   - Update redemption service to send drink item
   - Update display logic to use drink item field

### Option B: Temporary Fix (Quick Solution)

1. **Frontend Only**:
   - Update `buildDisplayName` to detect half-and-half Full Combo
   - Format as "Half and Half: [Flavor1] + [Flavor2] ([Method]) + [Drink] with [Topping]"
   - For drink, show "[Drink Category]" as placeholder until backend field is added
   - Or: Don't show drink name for half-and-half Full Combo until backend supports it

2. **Detection Logic**:
   ```swift
   // Check for Full Combo with half-and-half
   if reward.rewardTitle == "Full Combo" && 
      reward.selectedItemName != nil && 
      reward.selectedItemName2 != nil && 
      reward.cookingMethod != nil && 
      reward.selectedToppingName != nil {
       // This is Full Combo with selections
       // If selectedItemName2 looks like a dumpling (contains common dumpling words),
       // treat as half-and-half
       // Otherwise, treat as single dumpling + drink
   }
   ```

## Recommended Approach

**Short term**: Implement Option B with improved detection logic and note that drink name is missing for half-and-half.

**Long term**: Implement Option A to add proper backend support for drink item in Full Combo.

## Files to Modify

1. **AdminRewardsScanView.swift** - `buildDisplayName()` function
2. **RewardsComponents.swift** - Display name logic in `redeemReward()`
3. **server.js** (if doing Option A) - Add drink item fields
4. **RewardRedemptionModels.swift** (if doing Option A) - Add drink item to models
