# Remove Sparkle Line – Seamless Fly-Up Then Float

## Problem

In the preparing overlay, sparkles fly up then switch to float. In float phase we currently **hard-clamp** Y when a sparkle is outside the band:

```swift
if s.y < minY - 30 {
    s.y = minY - 30
    s.driftY = abs(s.driftY)
}
if s.y > maxY + 30 {
    s.y = maxY + 30
    s.driftY = -abs(s.driftY)
}
```

Every sparkle that enters float above the band gets snapped to the **same** Y (`minY - 30`), so they form a visible **line**. When they eventually drift into the band they look like they “pop in.” There should be no line; sparkles should simply fly up and then float around at the same timings.

## Fix

**File:** [Restaurant Demo/Restaurant Demo/ReceiptScanView.swift](Restaurant Demo/Restaurant Demo/ReceiptScanView.swift)  
**Location:** `PreparingSparkleOverlay.tickRising(containerSize:)`, inside the `case .float:` block (around lines 1871–1883).

- **Remove the hard Y clamp** that sets `s.y = minY - 30` or `s.y = maxY + 30`. Do not snap sparkles to a single line.
- **Keep** the soft drift nudge: when `s.y < minY` add a bit to `driftY`, when `s.y > maxY` subtract a bit, and clamp `driftY` to ±0.18. That keeps sparkles drifting toward the band without forming a line.
- **Keep** the existing X wrap (`s.x < -20` / `s.x > w + 20`) so horizontal motion still wraps.

Result: sparkles keep their natural spread when they transition from launch to float; they’re only gently nudged toward the band and never forced onto one Y, so there’s no line and no pop-in—just fly up then float around at the same timings as before.
