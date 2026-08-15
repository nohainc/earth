# EARTH Flutter client

This is the shared Flutter client for Web, iOS, and macOS. It reads canonical state from the server-authoritative API rather than calculating balances or market outcomes locally.

```bash
flutter pub get
flutter run -d chrome
```

To test the real production API and remote Cloudflare state from a local Flutter browser session:

```bash
flutter run -d chrome --dart-define=EARTH_API_URL=https://earthuc.com
```

The web client uses credentialed browser requests for this remote mode, so the
Worker's HttpOnly session cookie is sent during sign-in and subsequent API
calls. The production application uses the same-origin default at `/app`.

The production Worker serves the compiled Flutter application at `/app`. The public landing page is available at `/landing`, while `/` redirects to the landing page. The Flutter application begins at its identity screen before loading the authenticated command center.

Authentication uses the Worker API endpoints `/api/auth/register`, `/api/auth/login`, `/api/auth/me`, and `/api/auth/logout`. Sessions are HttpOnly, Secure, seven-day cookies; the client never stores passwords or session tokens in application state.
