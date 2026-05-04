# EDU-AI App

Flutter application (mobile + web) for the EDU-AI learning platform. Targets iOS, Android, and the web; talks to the EDU-AI API backend over HTTPS. Built from a single Dart codebase using Flutter SDK 3.10+.

## Tech stack

- **Framework**: Flutter (Dart `^3.10.0`)
- **Targets**: iOS, Android, Web (desktop scaffolding present for macOS / Linux / Windows)
- **UI**: Material + Cupertino, `google_fonts`, `flutter_svg`
- **Storage**: Drift / SQLite (local persistence)
- **Web build**: served via nginx (multi-stage Docker build)

## Project structure

```
lib/
  app.dart           # root MaterialApp / theming
  main.dart          # entry point
  routing/           # navigation / route definitions
  pages/             # full-screen pages
  features/          # feature modules (lesson player, etc.)
  widgets/           # shared UI components
  models/            # domain models / DTOs
  data/              # repositories, API clients, local DB
  core/              # core services (env, logging, ...)
  utils/             # utility helpers
android/             # Android platform project
ios/                 # iOS platform project
macos/ linux/ windows/   # desktop platform projects
assets/              # images, fonts, JSON fixtures
docs/                # internal docs
Dockerfile           # multi-stage build for Flutter Web → nginx
nginx.conf           # nginx config used by the production image
run.sh               # interactive helper to launch iOS / Android sim
run_ios.sh           # one-shot iOS Simulator launcher
run_android.sh       # one-shot Android Emulator launcher
```

## Prerequisites

- Flutter SDK `>= 3.10` (`flutter --version`)
- Xcode (iOS), Android Studio + SDK (Android)
- Chrome (Flutter Web debugging)
- For Docker builds: Docker 24+

## Local development

```bash
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:8000   # web
flutter run -d ios                                                  # iOS simulator
flutter run -d android                                              # Android emulator
```

Helper scripts:

```bash
./run.sh           # interactive: pick iOS / Android / both
./run_ios.sh       # iOS only
./run_android.sh   # Android only
```

## Run with Docker (web build)

Builds the Flutter web bundle and serves it with nginx. The API base URL is baked in at build time via `--dart-define`.

```bash
# Build image
docker build \
  --build-arg API_URL=https://app-api.edu-ai.eu \
  -t eduai-app:latest .

# Run (nginx listens on $PORT, defaulting to 80)
docker run --rm -it \
  -p 8080:80 \
  -e PORT=80 \
  eduai-app:latest
```

Open [http://localhost:8080](http://localhost:8080).

For local dev against a local API:

```bash
docker build --build-arg API_URL=http://host.docker.internal:8000 -t eduai-app:dev .
docker run --rm -p 8080:80 -e PORT=80 eduai-app:dev
```

## Build outputs

| Command                                  | Output                          |
|------------------------------------------|---------------------------------|
| `flutter build web --release`            | `build/web/`                    |
| `flutter build apk --release`            | `build/app/outputs/flutter-apk` |
| `flutter build appbundle --release`      | `build/app/outputs/bundle`      |
| `flutter build ios --release`            | iOS archive (use Xcode to sign) |

Pass runtime config with `--dart-define=API_URL=...`.

## Useful commands

| Command                       | Purpose                       |
|-------------------------------|-------------------------------|
| `flutter pub get`             | Fetch packages                |
| `flutter pub upgrade`         | Upgrade packages              |
| `flutter analyze`             | Static analysis               |
| `flutter test`                | Run unit / widget tests       |
| `flutter clean`               | Remove build artefacts        |

## Related

- **EDU-AI-asistent-API** — Laravel backend (separate repository)
- **EDU-AI-asistent-ADM** — Next.js admin (separate repository)

## License

See `LICENSE`.
