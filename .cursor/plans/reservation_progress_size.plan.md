# Reservation Progress Indicator – Making It More Prominent

## Current State

The progress indicator lives in the **navigation bar** (principal toolbar area) with:

| Element | Current | Notes |
|---------|---------|-------|
| Title | 17pt semibold | "Reserve a Table" |
| Step text | 12pt medium | "Step 1 of 4" |
| Progress bar | 3pt height, 100pt max width | Thin gold bar |

The nav bar principal area is constrained by iOS (typically ~44pt height). The current design fits within that space but reads as small, especially the step label and the thin bar.

---

## Why It Feels Small

1. **Step label** – 12pt is small for secondary UI; "Step 1 of 4" competes with the 17pt title.
2. **Progress bar** – 3pt height and 100pt width are subtle; on retina displays they can look faint.
3. **Cramped layout** – Everything is squeezed into the narrow principal area.

---

## Options to Make It More Prominent

### Option A: Enlarge Within the Nav Bar

Increase sizes while staying in the principal area:

- **Step text**: 12pt → 15pt (or 14pt)
- **Progress bar height**: 3pt → 5pt
- **Progress bar width**: 100pt → 140pt (or use `.frame(maxWidth: .infinity)` if the principal allows)

**Pros:** No structural change; still compact.  
**Cons:** Nav bar principal may clip or feel crowded on smaller devices.

---

### Option B: Progress Strip Below the Nav Bar

Add a slim strip between the nav bar and the ScrollView dedicated to progress:

- Keep the nav bar for "Reserve a Table" + Cancel only (default `navigationTitle`).
- Below it, a full-width strip (~36–44pt tall) with:
  - "Step 1 of 4" at 15pt
  - Progress bar at 5–6pt height, full width
  - Optional: step name (When / Party / Contact / Confirm) in smaller text

**Pros:** More room for larger type and bar; clear separation from content.  
**Cons:** Slightly more vertical space than the current nav-bar-only layout.

---

### Option C: Hybrid – Bigger Text, Thicker Bar (Stay in Nav Bar)

- **Step text**: 12pt → 14pt, **weight .semibold**, and `Theme.primaryGold` instead of `Theme.modernSecondary`
- **Progress bar**: 3pt → 5pt height, width 120pt
- Add a light shadow or glow to the filled portion

**Pros:** Noticeable improvement without layout changes.  
**Cons:** May still feel constrained in the principal area.

---

### Option D: Inline With Step Content (Top of ScrollView)

Move progress out of the nav bar and into the scrollable content:

- Nav bar: title only (standard).
- First element in the ScrollView: a compact progress card (same idea as the old design but slimmer – bar + "Step 1 of 4" or step circles).

**Pros:** More space for progress; can be larger and more readable.  
**Cons:** Progress scrolls away with content; we’re partially reverting the previous change.

---

## Recommendation

**Option B (Progress strip below nav bar)** gives the best balance:

- Nav bar stays simple (title + Cancel).
- Progress gets its own strip with larger text (15pt) and a thicker bar (5–6pt).
- Clear hierarchy and better readability without a heavy multi-step card.
- Only a small, predictable amount of extra vertical space.

**Alternative:** If you prefer not to add the strip, **Option C** is the safest in-place upgrade.

---

## Implementation Summary (Option B)

1. Restore `.navigationTitle("Reserve a Table")` and remove the custom principal toolbar content.
2. Add a fixed `VStack` above the ScrollView:
   - "Step X of 4" at 15pt semibold, gold or primary text color.
   - Full-width progress bar, 5pt height, gold gradient fill.
3. Optional: show the current step name ("When", "Party", etc.) as 13pt secondary text.

---

## Implementation Summary (Option C – In-place)

1. In the principal toolbar `VStack`:
   - Step text: `.font(.system(size: 14, weight: .semibold))` and `.foregroundColor(Theme.primaryGold)`.
   - Progress bar: `.frame(height: 5)` and `.frame(maxWidth: 120)`.
2. Optional: add `.shadow(color: Theme.primaryGold.opacity(0.3), radius: 2)` to the filled bar.
