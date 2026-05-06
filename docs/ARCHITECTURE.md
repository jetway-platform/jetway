# Architecture

FlightDeck is a **Dart CLI tool** that automates the Flutter app release pipeline — build, sign, and upload to both the App Store and Google Play — from a single command.

---

## Project Structure

```
flightdeck/
├── bin/
│   └── flightdeck.dart          # Binary entry point
├── lib/src/
│   ├── runner.dart              # CommandRunner bootstrap; registers all commands
│   ├── commands/
│   │   ├── init_command.dart    # `flightdeck init`   — interactive setup wizard
│   │   ├── deploy_command.dart  # `flightdeck deploy` — full build + upload pipeline
│   │   ├── build_command.dart   # `flightdeck build`  — build-only, no upload
│   │   ├── certs_command.dart   # `flightdeck certs`  — Apple cert management
│   │   └── env_command.dart     # `flightdeck env`    — secrets / .env file helper
│   ├── services/
│   │   ├── flutter_build_service.dart       # Invokes `flutter build` subprocess
│   │   ├── app_store_connect_service.dart   # Apple ASC REST API + xcrun altool
│   │   └── google_play_service.dart         # Google Play Android Publisher API v3
│   └── models/
│       └── config.dart          # Parses & validates flightdeck.yaml
├── docs/                        # Developer documentation (you are here)
├── flightdeck.yaml.example      # Annotated config template
└── pubspec.yaml
```

---

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                       flightdeck (CLI)                          │
│                                                                 │
│  bin/flightdeck.dart ──► FlightDeckRunner                       │
│                               │                                 │
│         ┌─────────────────────┼──────────────────────┐          │
│         ▼                     ▼                      ▼          │
│    InitCommand          DeployCommand           BuildCommand     │
│    CertsCommand         EnvCommand                              │
│                               │                                 │
│         ┌─────────────────────┼────────────────┐                │
│         ▼                     ▼                ▼                │
│  FlutterBuildService  AppStoreConnect    GooglePlayService       │
│  (flutter build)       Service           (googleapis SDK)       │
│                        (xcrun altool)                           │
│                               │                                 │
│         ┌─────────────────────┴────────────────┐                │
│         ▼                                      ▼                │
│  App Store Connect API           Google Play Publisher API      │
└─────────────────────────────────────────────────────────────────┘

       FlightDeckConfig (models/config.dart) is shared by all commands
```

---

## Deploy Request Lifecycle

```
flightdeck deploy
      │
      ▼
1. FlightDeckRunner.run()
      │  parses args, dispatches to DeployCommand
      ▼
2. FlightDeckConfig.fromFile()
      │  reads + validates flightdeck.yaml
      │  resolves credentials (yaml value → env var)
      ▼
3. FlutterBuildService.validate()  →  pubGet()
      │  checks `flutter` is on PATH, pubspec.yaml exists
      ▼
4. FlutterBuildService.buildIos()
      │  flutter build ipa --release --export-method=app-store
      │  locates .ipa at  build/ios/ipa/
      ▼
5. FlutterBuildService.buildAndroid()
      │  flutter build appbundle --release
      │  locates .aab at  build/app/outputs/bundle/release/
      ▼
6. AppStoreConnectService
      │  a. Generate ES256 JWT from .p8 key (19 min TTL)
      │  b. xcrun altool --validate-app  (catches signing issues early)
      │  c. xcrun altool --upload-app
      │  d. ASC REST API: getAppId → getLatestBuild → addBuildToTestFlightGroup
      ▼
7. GooglePlayService
      │  a. OAuth2 via service account → AuthClient
      │  b. edits.insert()          — open Play Store edit session
      │  c. edits.bundles.upload()  — stream AAB to Play
      │  d. edits.tracks.update()   — assign to track
      │  e. edits.commit()          — make upload visible in Play Console
      ▼
8. Print summary (elapsed time, ASC link, Play Console link)
```

---

## Credential Resolution

Both `IosConfig` and `AndroidConfig` use `resolved*` getters that apply this priority:

```
flightdeck.yaml value  →  environment variable  →  "" (validation fails)
```

This means credentials can come from the YAML file (local dev) or environment variables (CI/CD) without any code changes.

---

## Error Handling

Each layer has a typed exception:

| Exception | Thrown by |
|-----------|-----------|
| `FlightDeckConfigException` | `config.dart` — missing/invalid config |
| `FlightDeckBuildException` | `flutter_build_service.dart` — flutter subprocess failed |
| `AppStoreConnectException` | `app_store_connect_service.dart` — API/upload error |
| `GooglePlayException` | `google_play_service.dart` — API/upload error |

All are caught in `DeployCommand.run()` and logged before exiting with code `1`.

---

## Key Dependencies

| Package | Role |
|---------|------|
| `args` | CLI argument parsing and sub-command dispatch |
| `mason_logger` | Styled terminal output (info / success / warn / error) |
| `yaml` | Parsing `flightdeck.yaml` |
| `dart_jsonwebtoken` | ES256 JWT for App Store Connect API auth |
| `googleapis` + `googleapis_auth` | Google Play Android Publisher API v3 client |
| `http` | REST calls to ASC API |
| `dotenv` | `.env` file support |
| `path` | Cross-platform path utilities |
| `archive` | IPA zip/packaging utilities |
