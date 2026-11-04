# Getting Started

Welcome to FlightDeck development. This guide gets you from a fresh clone to running the CLI locally in a few minutes.

---

## Prerequisites

| Requirement | Minimum Version | Check |
|-------------|----------------|-------|
| Dart SDK | 3.0.0 | `dart --version` |
| Flutter | 3.10.0 | `flutter --version` |
| Xcode + CLI Tools *(iOS only)* | 14+ | `xcode-select -p` |
| Xcode Command Line Tools | — | `xcrun --version` |
| macOS *(iOS builds)* | 12+ | — |

> **Note:** Android-only deploys can be done on any OS with the Dart SDK. iOS builds require macOS with Xcode.

---

## 1. Clone the Repository

```bash
git clone https://github.com/yourusername/flightdeck.git
cd flightdeck
```

---

## 2. Install Dependencies

```bash
dart pub get
```

---

## 3. Run Locally (Without Installing)

You can run the CLI directly from the repo root using `dart run`:

```bash
dart run bin/flightdeck.dart --version
dart run bin/flightdeck.dart --help
dart run bin/flightdeck.dart deploy --help
```

---

## 4. Install Globally (Recommended)

This installs `flightdeck` to your Dart pub-cache bin directory so it's available as a regular command:

```bash
dart pub global activate --source path .
```

Make sure the pub-cache bin is on your `PATH`:

```bash
# Add to your shell config (~/.zshrc or ~/.bashrc)
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

Verify:

```bash
flightdeck --version
# flightdeck v0.2.5
```

---

## 5. Run the Guided Setup Wizard

Navigate to an existing Flutter project root and run `flightdeck init`:

```bash
cd your-flutter-app/
flightdeck init
```

The interactive wizard will:
1. Auto-detect your app name from `pubspec.yaml`
2. **Open App Store Connect in your browser** — you paste back just 3 values (Key ID, Issuer ID, .p8 path)
3. **Verify credentials immediately** against the API — no silent failures
4. **Fetch your apps** and let you select from a numbered list — no copying Bundle IDs manually
5. **Fetch your TestFlight groups** and let you select — no manual typing
6. **Open Google Play Console in your browser** for Android — same guided flow
7. Optionally **generate an Android keystore** via `keytool` if you don't have one
8. Write `flightdeck.yaml` with everything filled in

> **If you ever need to rotate credentials or add a new platform later:**
> ```bash
> flightdeck setup --platform ios      # iOS only
> flightdeck setup --platform android  # Android only
> ```
> This re-runs just that platform's wizard and merges back into `flightdeck.yaml`.

---

## 6. Deploy

---

## 7. Deploy

```bash
flightdeck deploy                      # both platforms
flightdeck deploy --platform ios       # iOS only
flightdeck deploy --platform android   # Android only
```

---

## Running Tests

```bash
dart test
```

Tests live in the `test/` directory. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidance on writing new tests.

---

## Next Steps

- [COMMANDS.md](COMMANDS.md) — full CLI reference
- [CONFIGURATION.md](CONFIGURATION.md) — every `flightdeck.yaml` option explained
- [CREDENTIALS.md](CREDENTIALS.md) — step-by-step iOS & Android credential setup
- [CI_CD.md](CI_CD.md) — setting up GitHub Actions
