# Cookie and Similar Technologies Statement

*Effective from: 20 May 2026*

> This Statement complements the [Privacy Policy](/privacy/en). In the event of discrepancy with the [Czech original](/cookies), the Czech version prevails.

## 1. What are cookies and similar technologies

1.1 **Cookies** are small text files stored by the browser. The EDU AI assistant Application, as a single-page application, does not use standard HTTP cookies in the browser. We use "similar technologies":

- **Local Storage** and **Session Storage** — domain-scoped key/value storage (e.g., selected language).
- **IndexedDB** — structured in-browser database for offline progress, lessons, quizzes and user data.
- **Cache Storage / Service Worker** — caching of static Application files (HTML, JS, CSS, fonts) for faster loading and offline use.
- **Session tokens** — short-lived login identifiers stored in secure browser storage.

1.2 On mobile (iOS, Android) the equivalents are:

- **SQLite database** (Drift) — user progress, bookmarks, courses, statistics.
- **Encrypted keystore** (Keychain on iOS, Keystore on Android via `flutter_secure_storage`) — authentication token.
- **SharedPreferences / NSUserDefaults** — user settings.

## 2. Our approach

2.1 The Application does **not** use:

- tracking cookies,
- advertising cookies,
- third-party profiling cookies,
- behavioural targeting,
- analytics tools sharing with marketing networks,
- cross-site tracking or fingerprinting.

2.2 The Application uses **only strictly necessary** technologies.

## 3. Legal basis

3.1 Strictly necessary cookies and similar technologies do not require user consent under § 89(3) of Act No. 127/2005 Coll. on Electronic Communications (transposing ePrivacy Directive 2002/58/EC).

3.2 Should we introduce technologies requiring consent in the future, we would request it via a transparent consent banner.

## 4. Overview of technologies used

### 4.1 Web version (browser)

| Name / key | Storage type | Purpose | Retention |
|---|---|---|---|
| locale | Local Storage | UI language | Persistent (until cleared) |
| theme | Local Storage | Colour theme | Persistent |
| session_meta | Local Storage | Session metadata | Session, per inactivity setting |
| auth_token | Local Storage (web) / Secure storage (mobile) | Bearer auth token | Until logout or expiry |
| eduai_db | IndexedDB | Local DB (Drift): courses, lessons, progress, bookmarks, quizzes, statistics, FSRS cards | Persistent (until cleared or uninstalled) |
| flutter-cache | Cache Storage | Static App files for offline use | Updated on deployment |
| cf-* (Cloudflare) | Third-party cookies (technical) | DDoS / bot protection | 30 min – 1 year |

### 4.2 Mobile (iOS, Android)

| Name | Storage type | Purpose | Retention |
|---|---|---|---|
| app_database.sqlite | SQLite (Drift) | User data: courses, lessons, progress, bookmarks, statistics, FSRS cards, chat sessions | Persistent (until uninstall / data clear) |
| auth_token | Keychain (iOS) / Keystore (Android) | Bearer auth token | Until logout or expiry |
| SharedPreferences / NSUserDefaults | OS settings | Language, theme, configs | Persistent |
| FCM token | Firebase storage | Push notifications | Until logout or opt-out |

### 4.3 Public pages (terms, privacy, about, …)

These pages **do not use any cookies** nor store any information beyond ordinary browser HTTP cache.

## 5. Retention

5.1 Strictly necessary technologies are stored for the time necessary for their purpose — session duration or account lifetime.

5.2 You may remove local data at any time:

- in the Application: *Profile → Settings → Log out / Delete account*,
- in the browser: clear site data (Site Data / IndexedDB / Local Storage),
- on mobile OS: clear app data in system settings or uninstall.

## 6. How to manage or reject

6.1 Most browsers can block cookies and similar technologies. Rejecting strictly necessary technologies may cause the Application to malfunction.

6.2 Browser settings:

- [Google Chrome](https://support.google.com/chrome/answer/95647)
- [Mozilla Firefox](https://support.mozilla.org/en-US/kb/enable-and-disable-cookies-website-preferences)
- [Apple Safari](https://support.apple.com/guide/safari/sfri11471/mac)
- [Microsoft Edge](https://support.microsoft.com/en-us/microsoft-edge)

6.3 Push notifications disabled in OS settings.

## 7. Third parties

7.1 Third-party services (see [Privacy Policy](/privacy/en)):

- Cloudflare — content delivery and DDoS protection
- Amazon Web Services (AWS) — hosting
- Firebase (Google) — push notifications, Google Sign-In
- Apple / Microsoft — only on Apple/Microsoft Sign-In

7.2 None stores marketing or analytics cookies in the Application.

## 8. Changes

8.1 We may modify this Statement. Current version at [app.edu-ai.eu/cookies](https://app.edu-ai.eu/cookies).

8.2 Material changes notified at least 30 days in advance.

## 9. Contact

Questions about this Statement: [gdpr@edu-ai.eu](mailto:gdpr@edu-ai.eu) or contacts in the [Privacy Policy](/privacy/en).
