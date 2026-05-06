# Configuration Reference

FlightDeck is configured via `flightdeck.yaml` in your Flutter project root. Run `flightdeck init` to generate it interactively, or create it manually using this reference.

---

## Full Example

```yaml
# flightdeck.yaml

app:
  name: "My Flutter App"
  bundle_id: "com.yourcompany.myapp"
  package_name: "com.yourcompany.myapp"
  # version: "1.2.0"   # Optional: overrides pubspec.yaml version string

ios:
  team_id: "ABCD1234EF"
  profile: distribution
  testflight_group: "Internal Testers"
  scheme: "Runner"
  api_key_id: "ABC123DEF4"
  api_issuer_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  api_key_path: "./keys/AuthKey_ABC123.p8"

android:
  keystore: "./keys/release.keystore"
  key_alias: "release"
  track: internal
  artifact: aab
  service_account: "./keys/play-service-account.json"
  # keystore_password: ""  # prefer ANDROID_KEYSTORE_PASSWORD env var
  # key_password: ""       # prefer ANDROID_KEY_PASSWORD env var
```

---

## `app` Section *(required)*

Core app identity shared across platforms.

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | string | ✅ | Human-readable app name (used in CLI output) |
| `bundle_id` | string | ✅ | iOS Bundle Identifier (e.g. `com.yourcompany.myapp`) |
| `package_name` | string | ✅ | Android package name (usually same as `bundle_id`) |
| `version` | string | — | Version string override. If omitted, read from `pubspec.yaml` |

---

## `ios` Section *(required for iOS deploy)*

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `team_id` | string | ✅ | Apple Developer Team ID (10-char alphanumeric) |
| `profile` | string | — | Signing profile type. One of: `distribution` (default), `adhoc`, `development` |
| `testflight_group` | string | — | Name of a TestFlight beta group to add the build to after upload |
| `scheme` | string | — | Xcode scheme to build. Defaults to `Runner` |
| `api_key_id` | string | ✅* | App Store Connect API Key ID. Can use `APP_STORE_API_KEY_ID` env var instead |
| `api_issuer_id` | string | ✅* | App Store Connect Issuer UUID. Can use `APP_STORE_API_ISSUER_ID` env var instead |
| `api_key_path` | string | ✅* | Path to the `.p8` private key file. Can use `APP_STORE_API_KEY_PATH` env var instead |
| `export_options_plist` | string | — | Optional path to a custom `ExportOptions.plist` for advanced signing setups |

> ✅* All three API key fields are required **unless** all three corresponding environment variables are set.

### Profile → Export Method Mapping

| `profile` value | `flutter build ipa` export method |
|-----------------|-----------------------------------|
| `distribution` | `app-store` |
| `adhoc` | `ad-hoc` |
| `development` | `development` |

---

## `android` Section *(required for Android deploy)*

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `keystore` | string | ✅ | Path to the `.keystore` or `.jks` signing file |
| `key_alias` | string | — | Key alias within the keystore (defaults to `release`) |
| `keystore_password` | string | — | Keystore password. **Prefer** `ANDROID_KEYSTORE_PASSWORD` env var |
| `key_password` | string | — | Key password. **Prefer** `ANDROID_KEY_PASSWORD` env var |
| `track` | string | — | Google Play release track. One of: `internal` (default), `alpha`, `beta`, `production` |
| `artifact` | string | — | Build output type. One of: `aab` (default, recommended), `apk` |
| `service_account` | string | ✅* | Path to the Google Play service account JSON file. Can use `GOOGLE_PLAY_SERVICE_ACCOUNT` env var instead |

> ✅* Required unless the `GOOGLE_PLAY_SERVICE_ACCOUNT` env var is set.

### Track Comparison

| Track | Audience | When to use |
|-------|----------|-------------|
| `internal` | Internal testers only (max 100 users) | Every build, fast review |
| `alpha` | Closed group of testers | Wider internal testing |
| `beta` | Open testing / public opt-in | Pre-production validation |
| `production` | All users | Full release |

---

## Environment Variables

All sensitive values can be provided as environment variables instead of (or in addition to) `flightdeck.yaml` values. The YAML value takes precedence if both are set.

| Variable | Replaces |
|----------|----------|
| `APP_STORE_API_KEY_ID` | `ios.api_key_id` |
| `APP_STORE_API_ISSUER_ID` | `ios.api_issuer_id` |
| `APP_STORE_API_KEY_PATH` | `ios.api_key_path` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | `android.service_account` |
| `ANDROID_KEYSTORE_PASSWORD` | `android.keystore_password` |
| `ANDROID_KEY_PASSWORD` | `android.key_password` |

Use `flightdeck env set KEY VALUE` to save them to a local `.env` file, or set them directly in your shell / CI environment.

---

## Config File Location

By default, FlightDeck looks for `flightdeck.yaml` in the current working directory. You can override this with `--config`:

```bash
flightdeck deploy --config path/to/custom.yaml
```

---

## Recommended `.gitignore` Additions

Never commit credentials or key files:

```gitignore
# FlightDeck secrets
keys/
.env
*.p8
*.keystore
*.jks
```
