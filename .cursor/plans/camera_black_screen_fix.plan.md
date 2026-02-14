# Fix intermittent black camera preview (flash works, no image)

## Symptom

Sometimes when opening the scanner, the user sees a black screen instead of the camera feed even though the camera is active (flash turns on). So the capture session is running but the preview layer is not showing the video.

## Likely cause

`CameraPreviewView` (UIViewRepresentable) adds the preview layer and sets its frame in `updateUIView`. SwiftUI can call `updateUIView` **before** the hosted UIView has a valid size (e.g. while the sheet is still animating or before layout). If `uiView.bounds` is zero at that time:

1. We set `previewLayer.frame = uiView.bounds` → **CGRect.zero**
2. We add the layer to the view
3. The async block runs and sets frame to bounds again → still zero
4. `updateUIView` is not guaranteed to run again when only the view’s bounds change

So the preview layer can stay at zero size and the user sees black even though the session is running.

## Fix (minimal)

Ensure the preview layer’s frame is updated whenever the host view is **laid out** (when it has real bounds), not only when SwiftUI calls `updateUIView`.

1. **Use a small host UIView subclass** that overrides `layoutSubviews` and:
   - Adds the preview layer to its layer if not already added (and sets `videoGravity` once).
   - Sets `previewLayer.frame = self.bounds` whenever the view has non-zero size.

2. **In `CameraPreviewView`:**
   - In `makeUIView`, create this host view, store the `cameraController` on it (e.g. via a stored property or coordinator), and return it.
   - In `updateUIView`, only pass the controller reference and call `setNeedsLayout()` so that when the view gets its bounds, `layoutSubviews` will run and set the layer frame.

This way the first time the view gets a non-zero bounds (after the sheet lays out), `layoutSubviews` runs and the preview layer gets the correct frame. No change to camera session, permissions, or detection logic.

## File and location

- [Restaurant Demo/Restaurant Demo/ReceiptScanView.swift](Restaurant Demo/Restaurant Demo/ReceiptScanView.swift)
- `CameraPreviewView`: `makeUIView` and `updateUIView` (around lines 2557–2584)
- Add a private `CameraPreviewHostView` class (UIView subclass) in the same file, and use it inside the representable.

## Implementation sketch

- Add a class:
  - `CameraPreviewHostView: UIView` with a weak or unowned reference to `CameraController`.
  - Override `layoutSubviews()`: if `previewLayer.superlayer == nil`, set `videoGravity`, add to `self.layer`; if `bounds != .zero` and `previewLayer.frame != bounds`, set `previewLayer.frame = bounds`; optionally set connection orientation on main.
- In `makeUIView`: instantiate `CameraPreviewHostView`, set its `cameraController` (or previewLayer), return it.
- In `updateUIView`: cast `uiView` to the host view, set the controller reference if needed, call `uiView.setNeedsLayout()` and optionally `uiView.layoutIfNeeded()` so layout runs and the layer frame is updated.

This keeps the rest of the camera and scanner logic unchanged.
