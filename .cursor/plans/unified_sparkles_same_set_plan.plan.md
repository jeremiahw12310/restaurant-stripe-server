# Unified Sparkles: Same Set Fly Up, Float Everywhere, Then Organize Around Receipt

## Goal

- **One set of sparkles** for the whole flow: they fly up during preparing, then float **across the whole screen** (no line, no band), and when a receipt appears those **same** sparkles organize around it.
- No second set popping in when the preparing overlay fades; no “line” where sparkles stop.

## Current Behavior (to change)

- **PreparingSparkleOverlay** lives inside the preparing block. Sparkles rise, then float in a band. When the block is removed, the view and all its sparkles are destroyed.
- **AmbientSparkleOverlay** appears only when `!showPreparingOverlay`, with a **new** sparkle array that floats and then converges on the receipt.
- Result: two separate sets and a visible “new sparkles pop in” when preparing ends.

## Target Behavior

1. **Preparing:** Sparkles fly up from the bottom (staggered), then switch to **full-screen** floating (no band, no line)—they drift and wrap across the entire area.
2. **After fade-out:** The **same** sparkles keep floating across the screen (no reset, no new overlay).
3. **When a receipt is detected:** Those same sparkles transition to converging onto the quad edges, then edge drift (same “organize around receipt” behavior as today).
4. **When the receipt is lost:** Sparkles transition back to full-screen floating.

All with the **same** sparkle pool and the **same** overlay for the whole sheet session.

---

## Implementation Plan

**File:** [Restaurant Demo/Restaurant Demo/ReceiptScanView.swift](Restaurant Demo/Restaurant Demo/ReceiptScanView.swift)

### 1. One overlay for the whole session

- Add a **UnifiedSparkleOverlay** that is shown whenever the camera sheet is visible and there is no error: **both** during preparing and after.
- Place it in the ZStack as a **sibling** of the preparing overlay (not inside it), so it is not recreated when `showPreparingOverlay` goes false. Order:
  - Camera preview  
  - Preparing overlay (cream + “Preparing…” only) when `showPreparingOverlay`  
  - **UnifiedSparkleOverlay** when `cameraController.errorMessage == nil`  
  - Error overlay, then UI/ROI/glow etc.

- **UnifiedSparkleOverlay** inputs:
  - `containerSize: CGSize`
  - `quad: DetectedQuad?` — `nil` during preparing, then `cameraController.detectedReceiptQuad`
  - `previewLayer: AVCaptureVideoPreviewLayer` (for quad → layer coords when drawing around receipt)
  - `isPreparing: Bool` (e.g. `showPreparingOverlay`)
  - `phase: LiveScanPhase` (for sparkle color when locked/capturing, optional)

So the same overlay (and same `@State` sparkle array) is always there from first frame until sheet dismiss.

### 2. Single sparkle model with four modes

- Introduce one sparkle struct used only by UnifiedSparkleOverlay (or reuse/extend one of the existing ones and rename). Modes: **rising**, **floating**, **converging**, **edge**.
- Fields: position (x, y), targets (targetX, targetY), drift, size, opacity, blur, age, mode, wander params, edge drift, and for rising: e.g. `launchTicks` and a rise target Y so they can switch to floating after ~30 ticks or when `y <= targetY`.

### 3. Behavior by phase

- **When `isPreparing` is true**
  - Spawn at bottom (e.g. `y = h + 10...40`), mode **rising**, staggered (e.g. 1 per tick for first ~30 ticks).
  - **Rising:** move up (negative driftY), slight x wobble; after ~30 ticks or `y <= targetY` → switch to **floating** with small random drift.
  - **Floating:** full-screen only. Gentle drift + wobble; wrap x and y at edges (e.g. wrap so they never form a line). **No band, no clamp to a single Y.** Same full-screen float used after preparing and when no receipt.

- **When `isPreparing` is false and `quad == nil`**
  - Do nothing special: same sparkles keep **floating** (no reset, no new spawn wave). Optionally spawn a few more floating sparkles to keep count if some have aged out.

- **When `isPreparing` is false and `quad != nil`**
  - **Transition:** same as current AmbientSparkleOverlay: for each sparkle set target to a random point on the quad edge (using quad corners in layer coords), set mode to **converging**, and set edge drift from `outwardNormal`. No new sparkles “pop in”—these are the same sparkles that were floating.
  - **Converging / edge:** same lerp-to-target and edge drift logic as AmbientSparkleOverlay so they “organize around the receipt.”

- **When quad goes from non-nil to nil**
  - **Transition to float:** same as current `transitionToFloat()`: assign random targets in the full area, set mode **floating**, gentle drift, so the same sparkles go back to floating across the screen.

### 4. Spawning rules

- **During preparing:** only spawn at bottom in **rising** (staggered).
- **After preparing, no quad:** spawn in **floating** at random (x, y) to maintain pool size.
- **After preparing, quad present:** can spawn on quad edge (like current edge spawn) to keep count; existing sparkles are already converging/edge.

### 5. Remove old overlays

- **Preparing overlay:** remove `PreparingSparkleOverlay()` from inside it. Leave only cream background and “Preparing…” text.
- **AmbientSparkleOverlay:** remove the block that shows it when `!showPreparingOverlay`. Do not delete the struct yet if we want to reuse its convergence/edge/geometry helpers; those can be inlined or called from UnifiedSparkleOverlay.

### 6. Preserve timings

- No change to: minimum preparing display (1.2s), cream fade (0.8s), overlay removal (0.9s), or receipt detection delay (0.6s after fade-out). Only the sparkle source and behavior change.

---

## Summary

- **One overlay**, **one sparkle array**, for the whole sheet: **UnifiedSparkleOverlay** shown whenever there’s no error.
- Sparkles **fly up** (rising), then **float everywhere** (full screen, no line), then when a receipt appears **the same sparkles** organize around it (converging → edge).
- Preparing overlay = cream + text only; no sparkles inside it. No second sparkle overlay after fade-out.
