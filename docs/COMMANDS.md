# CLI Command Reference

Full reference for every `flightdeck` command and flag.

---

## Global Flags

These flags can be used with any command:

| Flag | Description |
|------|-------------|
| `--version` | Print the FlightDeck version and exit |
| `--verbose`, `-v` | Enable verbose/debug output |
| `--help`, `-h` | Show help for a command |

---

## `flightdeck init`

Interactive setup wizard. Creates `flightdeck.yaml` in your Flutter project root.

```bash
flightdeck init
```

**What it does:**
1. Verifies the current directory is a Flutter project (`pubspec.yaml` with `flutter:`)
2. Detects the app name from `pubspec.yaml`
3. Prompts for iOS and Android configuration interactively
4. Writes `flightdeck.yaml`
5. Prints `.gitignore` recommendations for protecting secrets

**Notes:**
- Prompts to overwrite if `flightdeck.yaml` already exists
- All prompts have defaults — press Enter to accept

---

## `flightdeck setup`

Re-run the guided credential wizard on an **existing** `flightdeck.yaml` — useful when credentials expire or you need to add a new platform without running `init` again from scratch.

```bash
flightdeck setup [options]
```

| Flag / Option | Short | Default | Description |
|---------------|-------|---------|-------------|
| `--platform` | `-p` | `all` | `ios`, `android`, or `all` |

**What it does:**
1. Reads your existing `flightdeck.yaml` (fails if not found — run `flightdeck init` first)
2. Runs the browser-assisted, API-backed wizard for the selected platform(s)
3. Merges updated credentials back into `flightdeck.yaml` without overwriting unrelated sections

**Examples:**

```bash
# Refresh iOS credentials only (e.g. after rotating your .p8 key)
flightdeck setup --platform ios

# Refresh Android service account
flightdeck setup --platform android

# Re-run both
flightdeck setup
```

---

## `flightdeck deploy`

Build **and** upload your Flutter app to App Store Connect and/or Google Play.

```bash
flightdeck deploy [options]
```

| Flag / Option | Short | Default | Description |
|---------------|-------|---------|-------------|
| `--platform` | `-p` | `all` | `ios`, `android`, or `all` |
| `--track` | `-t` | from config | `internal`, `alpha`, `beta`, `production` |
| `--build-number` | `-b` | from pubspec | Override the build number |
| `--release-notes` | — | — | Release notes string (shown in Play Console) |
| `--skip-build` | — | false | Skip building; upload a previously built artifact |
| `--skip-validate` | — | false | Skip IPA validation step (iOS only) |
| `--verbose` | `-v` | false | Show full `flutter build` output |
| `--config` | — | `./flightdeck.yaml` | Path to a custom config file |

**Examples:**

```bash
# Deploy both platforms
flightdeck deploy

# Deploy to iOS TestFlight only
flightdeck deploy --platform ios

# Deploy Android to the beta track with release notes
flightdeck deploy --platform android --track beta --release-notes "Bug fixes and performance improvements"

# Override build number
flightdeck deploy --build-number 42

# Upload a pre-built artifact (skip flutter build)
flightdeck deploy --skip-build

# Show verbose flutter build output
flightdeck deploy --verbose
```

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Build, upload, or config error |
| `64` | Invalid usage (bad flags) |

---

## `flightdeck build`

Build release artifacts **without uploading** them. Useful for inspecting the output or testing the build step in isolation.

```bash
flightdeck build [options]
```

| Flag / Option | Short | Default | Description |
|---------------|-------|---------|-------------|
| `--platform` | `-p` | `all` | `ios`, `android`, or `all` |
| `--build-number` | `-b` | from pubspec | Override the build number |
| `--verbose` | `-v` | false | Show full build output |

**Examples:**

```bash
# Build both platforms
flightdeck build

# Build iOS IPA only
flightdeck build --platform ios

# Build Android AAB with a specific build number
flightdeck build --platform android --build-number 55
```

**Output paths:**
- iOS IPA: `build/ios/ipa/<AppName>.ipa`
- Android AAB: `build/app/outputs/bundle/release/app-release.aab`
- Android APK: `build/app/outputs/flutter-apk/app-release.apk`

---

## `flightdeck certs`

Manage Apple certificates and provisioning profiles. macOS only.

### `flightdeck certs sync`

Refresh provisioning profiles from Apple and reset the Xcode cache.

```bash
flightdeck certs sync
```

What it does:
1. Calls `xcrun altool --list-provisioning-profiles` with your ASC API key
2. Checks the macOS Keychain for valid distribution signing identities
3. Resets Xcode's provisioning profile cache

### `flightdeck certs check`

List currently installed valid code signing identities from the macOS Keychain.

```bash
flightdeck certs check
```

### `flightdeck certs list`

List all `.mobileprovision` files installed locally, with their name and expiry date.

```bash
flightdeck certs list
```

---

## `flightdeck env`

Manage FlightDeck's known environment variables. Reads from and writes to a `.env` file in your current directory.

### `flightdeck env set`

Set an environment variable in `.env`:

```bash
flightdeck env set KEY VALUE

# Examples:
flightdeck env set APP_STORE_API_KEY_ID ABC123
flightdeck env set ANDROID_KEYSTORE_PASSWORD mypassword
```

Warns if `.env` is not in your `.gitignore`.

### `flightdeck env get`

Read a variable (masked — shows last 4 characters only):

```bash
flightdeck env get APP_STORE_API_KEY_ID
# APP_STORE_API_KEY_ID = ****C123
```

### `flightdeck env list`

Show all 6 known FlightDeck variables and their set/unset status:

```bash
flightdeck env list
```

### `flightdeck env check`

Check that all required variables are set. Exits with code `1` if any are missing:

```bash
flightdeck env check
```

**Known variables:**

| Variable | Used for |
|----------|----------|
| `APP_STORE_API_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_API_ISSUER_ID` | App Store Connect Issuer ID |
| `APP_STORE_API_KEY_PATH` | Path to `.p8` key file |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | Path to Play service account JSON |
| `ANDROID_KEYSTORE_PASSWORD` | Android keystore password |
| `ANDROID_KEY_PASSWORD` | Android key password |
