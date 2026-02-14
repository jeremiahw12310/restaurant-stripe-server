# Sparkles fly higher and scatter during preparing

## Goal

During preparing, sparkles should fly **higher** (not stop around 35% up from the bottom) and then **scatter** across the screen. Minimal code changes.

## Cause

- Transition to floating happens when `launchTicks >= 30` **or** `y <= riseTargetY`.
- With current rise speed (`driftY` about -11 to -7.2), in 30 frames sparkles move ~220–330 pt up, so they often hit the **30-tick limit** before reaching the target and switch to float while still in the lower third (~35% up from bottom).
- `riseTargetY` is `h * 0.28...0.50` (28%–50% from top), so even when the target is used, they only rise to mid/upper-mid.

## Changes (all in `UnifiedSparkleOverlay`, ReceiptScanView.swift)

1. **Raise the target band**  
   In `spawnRisingSparkle`, change:
   - `riseTargetY: CGFloat.random(in: h * 0.28...h * 0.50)`  
   to:
   - `riseTargetY: CGFloat.random(in: h * 0.12...h * 0.38)`  
   So sparkles are aimed at the **upper** part of the screen (12%–38% from top) and visibly fly higher.

2. **Slightly faster rise**  
   In `spawnRisingSparkle`, change:
   - `driftY: CGFloat.random(in: -11.0...(-7.2))`  
   to:
   - `driftY: CGFloat.random(in: -12.5...(-9.0))`  
   So they climb a bit faster and are more likely to reach the higher target.

3. **Give them a bit more time to reach the higher target**  
   In the rising case, change:
   - `if s.launchTicks >= 30 || s.y <= s.riseTargetY`  
   to:
   - `if s.launchTicks >= 42 || s.y <= s.riseTargetY`  
   So they can keep rising for a few more frames and reach the upper area before switching to float and scattering.

No other logic changes. Floating and scatter behavior stay as they are.
