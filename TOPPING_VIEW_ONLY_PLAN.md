# Plan: Disable Topping Item Selection When Viewing Topping Options

## Problem
When a user clicks a drink item and then clicks "View Topping Options", they can tap on the topping items in the category view, which opens another ItemDetailView. This is confusing because they're just browsing options, not selecting them to add to their drink.

## Current Flow
1. User clicks drink item → `ItemDetailView` opens
2. User clicks "View Topping Options" button → `showToppingCategorySheet = true`
3. Sheet opens with `CategoryDetailView` showing toppings category
4. `CategoryDetailView` uses `MenuItemGridView` to display items
5. `MenuItemGridView` has buttons that set `selectedItem`, which opens another `ItemDetailView`
6. This creates confusion - users think they're selecting toppings but they're just viewing

## Solution

### Approach: Add View-Only Mode
Add a parameter to disable item selection when viewing topping options from a drink item detail view.

### Implementation Steps

1. **Update `CategoryDetailView`**
   - Add optional parameter: `isViewOnly: Bool = false`
   - Pass this parameter to `MenuItemGridView`

2. **Update `MenuItemGridView`**
   - Add optional parameter: `disableItemSelection: Bool = false`
   - Conditionally disable button action when `disableItemSelection == true`
   - Optionally add visual feedback (reduced opacity or disabled appearance)

3. **Update `ItemDetailView`**
   - When opening toppings category sheet, pass `isViewOnly: true` to `CategoryDetailView`

4. **Visual Feedback (Optional)**
   - Consider adding a subtle indicator that items are view-only
   - Could use reduced opacity or a "view only" badge
   - Or simply disable interaction without visual change (cleaner)

### Code Changes

#### CategoryDetailView.swift
- Add `let isViewOnly: Bool` parameter (default: false)
- Pass to MenuItemGridView: `MenuItemGridView(..., disableItemSelection: isViewOnly)`

#### MenuItemGridView.swift
- Add `let disableItemSelection: Bool` parameter (default: false)
- Conditionally disable button: `if !disableItemSelection { ... }` around the button action
- Optionally add `.disabled(disableItemSelection)` modifier

#### ItemDetailView.swift
- When creating CategoryDetailView in sheet, pass `isViewOnly: true`

### Alternative Approaches Considered

1. **Separate View Component**: Create a read-only version of MenuItemGridView
   - More code duplication
   - Less flexible

2. **Modal Presentation Style**: Change how the sheet is presented
   - Doesn't solve the core issue of item selection

3. **Navigation Stack**: Use navigation instead of sheet
   - Changes UX flow significantly
   - May not be desired

### Benefits
- Minimal code changes
- Maintains existing architecture
- Easy to extend to other view-only scenarios
- Clear separation of concerns

### Testing Checklist
- [ ] Verify topping items are not tappable when viewing from drink detail
- [ ] Verify normal category browsing still works (items are tappable)
- [ ] Verify admin tools still work in view-only mode (if applicable)
- [ ] Test on different screen sizes
- [ ] Verify visual feedback (if implemented)
