---
name: ""
overview: ""
todos: []
isProject: false
---

# Sparkles Float Higher + Receipt Detection Delay

## Summary

1. **Preparing sparkles float higher** – Move the center band and launch target Y so sparkles rise and hover in the upper half of the screen.
2. **Receipt detection starts 0.60s after fade-out** – Keep the Vision receipt pipeline off until 0.60 seconds after the preparing overlay is removed, then enable it.

---

## 1. Sparkles float higher

**File:** [Restaurant Demo/Restaurant Demo/ReceiptScanView.swift](Restaurant Demo/Restaurant Demo/ReceiptScanView.swift)

**Location:** `PreparingSparkleOverlay.tickRising(containerSize:)` (around lines 1825–1828 and 1901).

- **Center band** (where sparkles hover in float phase):
  - Today: `centerBandMidY = h * 0.52`, `centerBandHalfHeight = h * 0.16` → band from 36% to 68% of height.
  - Change to: `centerBandMidY = h * 0.36`, keep `centerBandHalfHeight = h * 0.16` → band from 20% to 52% of height (higher on screen).
- **Launch target Y** (where sparkles are sent when spawning):
  - Today: `targetY = CGFloat.random(in: h * 0.44...h * 0.66)`.
  - Change to: `targetY = CGFloat.random(in: h * 0.28...h * 0.50)` so they aim into the higher band.

No other logic changes; same launch-then-float behavior, just higher on screen.

---

## 2. Receipt detection delay (0.60s after fade-out)

**Fade-out completion:** In `CameraViewWithOverlay`, `showPreparingOverlay = false` is set inside `DispatchQueue.main.asyncAfter(deadline: .now() + 0.9)` (after the cream fade animation). That moment is “fade-out complete.”

**Requirement:** Start running receipt detection only **0.60 seconds after** that moment.

### 2a. CameraController: gate Vision on a flag

**File:** [Restaurant Demo/Restaurant Demo/ReceiptScanView.swift](Restaurant Demo/Restaurant Demo/ReceiptScanView.swift)

- Add a property (e.g. with other live-scan state, around 2339):
  - `var isReceiptDetectionEnabled = false`
- In `captureOutput(_:didOutput:from:)`, after the existing `guard isAutoScanEnabled` / `guard !hasTriggeredAutoCapture` and after the auto-torch block, add:
  - `guard isReceiptDetectionEnabled else { return }`
  So when the flag is false we do not run the Vision pipeline or update `detectedReceiptQuad`.
- In `stopSession()`, set `isReceiptDetectionEnabled = false` so the next time the sheet opens, detection stays off until the view turns it on again.

### 2b. CameraViewWithOverlay: enable detection 0.60s after fade-out

**File:** Same file, in the block where the preparing overlay is dismissed (around 1378–1380).

- When setting `showPreparingOverlay = false` (inside the existing `asyncAfter(deadline: .now() + 0.9)`), also schedule:
  - `DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { cameraController.isReceiptDetectionEnabled = true }`
  So detection turns on 0.60 seconds after the overlay is removed.

No change to when the overlay appears or when the camera feed is shown; only the moment when receipt detection starts is delayed.

---

## 3. Resulting timeline

- **t = 0:** Sheet opens, preparing overlay visible, sparkles launch and float **higher**.
- **t = 1.2s (or when camera ready):** Cream fade starts.
- **t ≈ 2.0s:** Fade ends, `showPreparingOverlay = false`; camera feed and ambient sparkles visible; receipt detection still off.
- **t ≈ 2.6s:** `isReceiptDetectionEnabled = true`; receipt detection starts (e.g. “Finding receipt…” and quad/glow when a receipt is found).

---

## 4. Files to touch

- [Restaurant Demo/Restaurant Demo/ReceiptScanView.swift](Restaurant Demo/Restaurant Demo/ReceiptScanView.swift) only: PreparingSparkleOverlay constants, CameraController flag + guard + stopSession, and the 0.6s delayed enable in the overlay dismiss block.

