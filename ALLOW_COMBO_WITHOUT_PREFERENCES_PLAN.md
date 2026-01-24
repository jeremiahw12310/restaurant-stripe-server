# Plan: Allow Combo Generation Without Dietary Preferences

## Current State Analysis

### ✅ What Already Works

1. **Backend Support** (already implemented):
   - `backend/server.js` and `backend-deploy/server.js` normalize dietary preferences with defaults
   - The `/generate-combo` endpoint accepts optional `dietaryPreferences` (only requires `userName`)
   - Backend handles missing preferences gracefully by creating normalized defaults:
     ```javascript
     const normalizedDietaryPreferences = {
       likesSpicyFood: false,
       dislikesSpicyFood: false,
       hasPeanutAllergy: false,
       isVegetarian: false,
       hasLactoseIntolerance: false,
       doesntEatPork: false,
       tastePreferences: '',
       hasCompletedPreferences: false,
       ...(dietaryPreferences || {})
     };
     ```

2. **Frontend Models** (already implemented):
   - `PersonalizedComboModels.swift` supports optional `dietaryPreferences: DietaryPreferences?`
   - `PersonalizedComboService.swift` accepts optional dietary preferences parameter
   - Models are designed to handle nil/empty preferences

### ❌ Current Blocking Issue

**Location**: `MenuViewViewModel.swift` lines 31-35

```swift
guard userVM.hasCompletedPreferences else {
    print("❌ User hasn't completed preferences")
    error = "Please complete your dietary preferences first"
    return
}
```

This guard statement prevents combo generation if the user hasn't explicitly completed their dietary preferences flow.

## Proposed Solution

### Change 1: Remove Guard Check in MenuViewViewModel

**File**: `Restaurant Demo/MenuViewViewModel.swift`

**Current behavior**:
- Blocks combo generation if `hasCompletedPreferences` is false
- Shows error message requiring preferences to be completed

**New behavior**:
- Allow combo generation regardless of `hasCompletedPreferences` status
- Pass dietary preferences (or nil/empty defaults) to backend
- Backend will handle normalization

**Implementation**:
1. Remove the guard statement (lines 31-35)
2. Modify dietary preferences handling to work with incomplete preferences
3. Pass dietary preferences object with current values (even if defaults) or nil

### Change 2: Update Dietary Preferences Handling

**File**: `Restaurant Demo/MenuViewViewModel.swift` (around line 45-54)

**Current behavior**:
- Always creates `DietaryPreferences` object from `userVM` properties
- Assumes preferences are set

**New behavior**:
- Create `DietaryPreferences` with current user values (which may be defaults)
- Include `hasCompletedPreferences: false` when user hasn't completed flow
- Backend will normalize appropriately and indicate user hasn't completed preferences

**Implementation**:
```swift
// Create dietary preferences with current values (may be defaults)
let dietaryPreferences = DietaryPreferences(
    likesSpicyFood: userVM.likesSpicyFood,
    dislikesSpicyFood: userVM.dislikesSpicyFood,
    hasPeanutAllergy: userVM.hasPeanutAllergy,
    isVegetarian: userVM.isVegetarian,
    hasLactoseIntolerance: userVM.hasLactoseIntolerance,
    doesntEatPork: userVM.doesntEatPork,
    tastePreferences: userVM.tastePreferences,
    hasCompletedPreferences: userVM.hasCompletedPreferences
)
```

### Backend Behavior (Already Implemented ✅)

When `hasCompletedPreferences: false`:
- Backend AI prompt includes: "The customer has not provided detailed dietary preferences yet, so do not assume allergy information."
- Dietary restrictions validation still runs but assumes no restrictions if not specified
- Combo generation proceeds normally with general recommendations

## Implementation Steps

1. **Remove the guard check** in `MenuViewViewModel.swift`
   - Delete lines 31-35 that block combo generation
   - Remove error assignment for missing preferences

2. **Ensure dietary preferences are always passed**
   - Keep the existing `DietaryPreferences` initialization (already correct)
   - This ensures backend receives preferences object (with defaults if needed)

3. **Test scenarios**:
   - ✅ User with no preferences set → Generate combo
   - ✅ User with partial preferences → Generate combo
   - ✅ User with completed preferences → Generate combo (existing flow)
   - ✅ Backend receives normalized preferences correctly
   - ✅ AI prompt reflects preference completion status

## Expected User Experience

### Before
- User taps "Personalized Combo" button
- ❌ Error: "Please complete your dietary preferences first"
- User must navigate to preferences, complete them, then return

### After
- User taps "Personalized Combo" button
- ✅ Combo generation proceeds immediately
- Interstitial video plays
- Combo is generated with general recommendations (not personalized yet)
- User can still complete preferences later for future personalization

## Benefits

1. **Lower barrier to entry**: Users can try the feature immediately
2. **Better onboarding**: Users discover combo generation without friction
3. **Incremental engagement**: Users can complete preferences later when motivated
4. **Backend already supports this**: No backend changes needed

## Potential Considerations

1. **User communication**: Should we show a subtle hint that preferences improve recommendations?
   - Consider adding a small banner: "Complete your preferences for better personalized combos"
   - Could be shown in combo result view or as an optional prompt

2. **Analytics**: Track combo generation with/without preferences
   - Monitor if users complete preferences after trying combos
   - Measure engagement improvement

3. **Backend prompt quality**: 
   - Current backend handles this well with `preferencesStatusText`
   - AI will generate general combos when preferences aren't set

## Files to Modify

1. `Restaurant Demo/MenuViewViewModel.swift`
   - Remove guard check (lines 31-35)
   - Ensure dietary preferences object is passed correctly

## Testing Checklist

- [ ] New user (no preferences) can generate combo
- [ ] User with partial preferences can generate combo
- [ ] User with completed preferences still works (regression test)
- [ ] Backend receives correct preference data
- [ ] AI generates appropriate combos based on preference status
- [ ] No crashes or errors in combo generation flow
- [ ] Interstitial video still plays correctly
- [ ] Combo result view displays correctly
