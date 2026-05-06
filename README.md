# 🛫 FlightDeck

> Deploy Flutter apps to the App Store and Google Play — one command.

FlightDeck is a Dart CLI tool that handles the entire release pipeline for Flutter apps: building signed release artifacts, uploading to TestFlight, and pushing to Google Play — without ever opening Xcode or Android Studio.

```bash
flightdeck deploy
```

---

## Installation

Requires Dart SDK ≥ 3.0 and Flutter ≥ 3.10.

```bash
dart pub global activate flightdeck
```

Add the pub cache bin to your PATH if needed:

```bash
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

---

## Quick start

**1. Initialize your project:**

```bash
cd your-flutter-app
flightdeck init
```

This runs an interactive wizard and generates `flightdeck.yaml`.

**2. Configure credentials** (see [Credentials](#credentials) below).

**3. Deploy:**

```bash
flightdeck deploy                      # both platforms
flightdeck deploy --platform ios       # iOS only
flightdeck deploy --platform android   # Android only
```

---

## Commands

### `flightdeck init`

Interactive setup wizard. Creates `flightdeck.yaml` in your project root.

### `flightdeck deploy`

Build and upload to App Store Connect and/or Google Play.

| Flag              | Default      | Description                               |
| ----------------- | ------------ | ----------------------------------------- |
| `--platform`      | `all`        | `ios`, `android`, or `all`                |
| `--track`         | from config  | `internal`, `alpha`, `beta`, `production` |
| `--build-number`  | from pubspec | Override the build number                 |
| `--release-notes` | —            | Release notes string                      |
| `--skip-build`    | false        | Upload pre-built artifacts                |
| `--skip-validate` | false        | Skip IPA validation (iOS)                 |
| `--verbose`       | false        | Show full build output                    |

### `flightdeck build`

Build release artifacts without uploading.

```bash
flightdeck build --platform ios
```

### `flightdeck certs`

Manage Apple certificates and provisioning profiles.

```bash
flightdeck certs sync    # Refresh from Apple
flightdeck certs check   # Check installed certs
flightdeck certs list    # List provisioning profiles
```

### `flightdeck env`

Manage secrets and environment variables.

```bash
flightdeck env set APP_STORE_API_KEY_ID ABC123
flightdeck env list
flightdeck env check     # Verify all required vars are set
```

---

## Configuration

FlightDeck reads from `flightdeck.yaml` in your project root. See [`flightdeck.yaml.example`](flightdeck.yaml.example) for all options.

```yaml
app:
    name: "My App"
    bundle_id: "com.yourcompany.myapp"
    package_name: "com.yourcompany.myapp"

ios:
    team_id: "ABCD1234EF"
    profile: distribution
    testflight_group: "Internal Testers"
    api_key_id: "ABC123"
    api_issuer_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    api_key_path: "./keys/AuthKey.p8"

android:
    keystore: "./keys/release.keystore"
    track: internal
    artifact: aab
    service_account: "./keys/play-service-account.json"
```

---

## Credentials

### iOS — App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → Users and Access → Keys
2. Create a key with **App Manager** role
3. Download the `.p8` file
4. Note your **Key ID** and **Issuer ID**

Set in `flightdeck.yaml` or as environment variables:

```bash
export APP_STORE_API_KEY_ID=ABC123
export APP_STORE_API_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export APP_STORE_API_KEY_PATH=./keys/AuthKey_ABC123.p8
```

### Android — Google Play Service Account

1. Go to [Google Play Console](https://play.google.com/console) → Setup → API access
2. Link to a Google Cloud project
3. Create a Service Account with **Release Manager** role
4. Download the JSON key file

Set in `flightdeck.yaml` or as environment variable:

```bash
export GOOGLE_PLAY_SERVICE_ACCOUNT=./keys/play-service-account.json
export ANDROID_KEYSTORE_PASSWORD=your_keystore_password
export ANDROID_KEY_PASSWORD=your_key_password
```

### Keep secrets safe

```gitignore
# .gitignore
keys/
.env
*.p8
*.keystore
*.jks
```

---

## CI/CD — GitHub Actions

A ready-made workflow is included at `.github/workflows/deploy.yml`.

**Required GitHub Secrets:**

| Secret                             | Description                       |
| ---------------------------------- | --------------------------------- |
| `APP_STORE_API_KEY_ID`             | App Store Connect Key ID          |
| `APP_STORE_API_ISSUER_ID`          | App Store Connect Issuer ID       |
| `APP_STORE_API_KEY_CONTENT`        | Base64-encoded `.p8` file content |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Google Play service account JSON  |
| `ANDROID_KEYSTORE_BASE64`          | Base64-encoded keystore file      |
| `ANDROID_KEYSTORE_PASSWORD`        | Keystore password                 |
| `ANDROID_KEY_PASSWORD`             | Key password                      |

Encode files for secrets:

```bash
base64 -i AuthKey.p8 | pbcopy           # copies to clipboard
base64 -i release.keystore | pbcopy
```

---

## Roadmap

- [ ] `flightdeck certs rotate` — rotate expiring certificates
- [ ] `flightdeck release notes` — pull from CHANGELOG.md automatically
- [ ] Slack/Discord notifications on deploy success
- [ ] Staged rollout support for production
- [ ] Multi-environment support (staging/production configs)
- [ ] `flightdeck doctor` — check all prerequisites

---

## License

MIT
