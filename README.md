# Jetway

> Deploy Flutter apps to the App Store and Google Play — one command.

Jetway is a Dart CLI tool that automates the release pipeline for Flutter apps: building release artifacts, uploading to TestFlight, and pushing to Google Play tracks.

```bash
jetway deploy
```

---

## Installation

Requires Dart SDK ≥ 3.0 and Flutter ≥ 3.10.

```bash
dart pub global activate jetway
```

Add the pub cache bin to your PATH if needed:

```bash
export PATH="$PATH":"$HOME/.pub-cache/bin"
```

---

## Quick Start

1. **Initialize your project:**

```bash
cd your-flutter-app
jetway init
```

This runs an interactive wizard and generates `jetway.yaml`.

2. **Configure credentials** (see [Credentials](#credentials) below).

3. **Deploy:**

```bash
jetway deploy                      # both platforms
jetway deploy --platform ios       # iOS only
jetway deploy --platform android   # Android only
```

---

## Commands

### `jetway init`

Guided setup wizard. Creates `jetway.yaml` in your project root with auto-detected bundle IDs and package names.

### `jetway setup`

Re-run guided credential setup on an existing `jetway.yaml`:

```bash
jetway setup --platform ios
jetway setup --platform android
```

### `jetway deploy`

Build and upload to App Store Connect and/or Google Play.

| Flag | Default | Description |
| --- | --- | --- |
| `--platform` | `all` | `ios`, `android`, or `all` |
| `--track` | from config | `internal`, `alpha`, `beta`, `production` |
| `--build-number` | from pubspec | Override the build number |
| `--release-notes` | — | Release notes string |
| `--skip-build` | false | Upload pre-built artifacts without building |
| `--skip-validate` | false | Skip IPA validation (iOS) |
| `--verbose` | false | Show full process output |

### `jetway build`

Build release artifacts without uploading:

```bash
jetway build --platform ios
jetway build --platform android
```

### `jetway certs`

Manage Apple signing identities and provisioning cache (macOS only):

```bash
jetway certs sync    # Verify API credentials & refresh Xcode cache
jetway certs check   # List valid signing identities
jetway certs list    # List installed provisioning profiles
```

### `jetway env`

Manage secrets and environment variables:

```bash
jetway env set APP_STORE_API_KEY_ID ABC123DEF4
jetway env get APP_STORE_API_KEY_ID
jetway env list
jetway env check     # Verify all required vars are set
```

---

## Configuration

Jetway reads from `jetway.yaml` in your project root. See [`jetway.yaml.example`](jetway.yaml.example) for the complete reference.

```yaml
app:
  name: "My App"
  bundle_id: "com.example.myapp"
  package_name: "com.example.myapp"

ios:
  team_id: "ABCD1234EF"
  profile: distribution
  testflight_group: "Internal Testers"
  api_key_id: "ABC123DEF4"
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

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → Users and Access → Integrations → API
2. Create a key with **App Manager** role
3. Download the `.p8` file
4. Note your **Key ID** and **Issuer ID**

Set in `jetway.yaml`, in `.env`, or as environment variables:

```bash
export APP_STORE_API_KEY_ID=ABC123DEF4
export APP_STORE_API_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export APP_STORE_API_KEY_PATH=./keys/AuthKey.p8
```

### Android — Google Play Service Account

1. Go to [Google Play Console](https://play.google.com/console) → Setup → API access
2. Link to a Google Cloud project
3. Create a Service Account with **Release Manager** role
4. Download the JSON key file

Set in `jetway.yaml`, in `.env`, or as environment variables:

```bash
export GOOGLE_PLAY_SERVICE_ACCOUNT=./keys/play-service-account.json
export ANDROID_KEYSTORE_PASSWORD=your_keystore_password
export ANDROID_KEY_PASSWORD=your_key_password
```

### Protecting Secrets

Add keys and environment files to your `.gitignore`:

```gitignore
keys/
.env
*.p8
*.keystore
*.jks
```

---

## CI/CD — GitHub Actions

A starter workflow is included at `.github/workflows/deploy.yml`.

**Required GitHub Secrets:**

| Secret | Description |
| --- | --- |
| `APP_STORE_API_KEY_ID` | App Store Connect Key ID |
| `APP_STORE_API_ISSUER_ID` | App Store Connect Issuer ID |
| `APP_STORE_API_KEY_CONTENT` | Base64-encoded `.p8` file content |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Google Play service account JSON |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded keystore file |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Key password |

Encode files for secrets:

```bash
base64 -i AuthKey.p8 | pbcopy
base64 -i release.keystore | pbcopy
```

---

## License

MIT
