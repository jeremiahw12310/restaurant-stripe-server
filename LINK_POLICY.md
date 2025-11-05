### Link Policy — Community

Rule: Only the app’s whitelisted "Order Online" link is permitted. All other links are stripped at compose and rejected server‑side.

Whitelisting
- Single canonical URL: ORDER_ONLINE_URL (configured in app settings/secrets).
- Rendered in UI as a primary "Order Online" chip/button on posts.

Client enforcement
- Detect URLs in composer. If URL ≠ ORDER_ONLINE_URL → remove and notify user.
- Option to attach the Order Online chip explicitly; no generic link previews.

Server enforcement
- Validate post payload: allow `allowedLink` only when `type: "orderOnline"` and `url === ORDER_ONLINE_URL`.
- Strip any other `urls` if present; return 422 with validation error.

Rendering
- Show only the button/chip for Order Online. Never show generic external link previews.

Telemetry
- Track attempts to add non‑whitelisted links to understand user intent.







