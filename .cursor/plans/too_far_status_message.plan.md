# Show "Hold phone closer" when receipt is too far

## Goal

When Vision detects a receipt (rectangle around it) but the receipt is **too far** (small in the frame) so text is hard to read, show a status message asking the user to hold the phone closer to the receipt. Minimal change.

## Current behavior

- Status text is set in `CameraController` in the block that runs when we publish a quad (`detectedReceiptQuad = publishQuad`).
- There is already a "too close" case: `quadSmall = max(bb.width, bb.height) < 0.40` and `isBrightLowContrast && quadSmall` → "Too close — back up a little".
- When the quad is small but the scene is **not** bright low-contrast, that usually means the receipt is **too far** (small in frame, Vision can still see edges but text is hard to read).

## Change

**File:** [Restaurant Demo/Restaurant Demo/ReceiptScanView.swift](Restaurant Demo/Restaurant Demo/ReceiptScanView.swift)

**Location:** The `DispatchQueue.main.async { ... }` block that sets `detectedReceiptQuad = publishQuad` and calls `applyStatusText` (around lines 3583–3601).

**Logic:** After the existing "Too close" branch, add a branch for "too far":

- Keep: `if isBrightLowContrast && quadSmall { applyStatusText("Too close — back up a little") }`
- Add: `else if quadSmall { applyStatusText("Hold phone closer to receipt") }`  
  So when the quad is small (receipt fills &lt; ~40% of frame) and we’re not in the "too close" case, show the new message.
- Leave all later branches (Point at a receipt, Center just one receipt, Hold steady) as-is; they’ll run when `quadSmall` is false.

No new constants or thresholds; reuse existing `quadSmall` (`max(bb.width, bb.height) < 0.40`). No change to capture logic or Vision pipeline.
