Traccar Manager - Main Screen Test Checklist

Smoke
i- App launches to web content without blank screen.
i- Loader appears before first page load; no crash.
i- Light/dark theme background matches system brightness.

URL + navigation
i- Default server URL loads when no saved URL.
- Change server URL via error screen and reload succeeds.
i- External links open in the system browser (not inside the app).
- OAuth-style authorize link launches externally and returns via app link.
- Deep link with scheme org.traccar.manager routes to the correct in-app path.
- Push notification with eventId opens /event/{id}.
- Back button behavior:
  - Goes back within webview when not at root/login.
  - Exits app when at root or /login.

Auth + tokens
i- Login message saves token.
i- Authentication message sends stored login token to web.
- Authenticated message completes notification setup (no timeout).
i- Logout clears stored token.
- Notification token is injected to web after login.
- Notification token refresh is delivered to web without reload.

Push notifications
- Foreground push triggers handleNativeNotification and shows snackbar text.
- Background tap opens event page.
- Initial push (cold start) routes to event page.

Downloads + share
i- Excel report downloads via JS hook and opens share sheet.
i- Direct downloadable links (xlsx/kml/csv/gpx) are fetched with auth and shared.

Permissions
xi- Camera permission request from web prompts native permission and grants/denies correctly.
i- Location permission request for geolocation prompts native permission and respects choice.

Error handling + recovery
- Web content process termination triggers reload and recovers.
xi- Main-frame load error shows error screen with message.
- Error screen retry clears error and reloads.

App links + redirects
- Redirect URIs are rewritten to org.traccar.manager and back to server path.
- Non-matching scheme URLs still open externally.
