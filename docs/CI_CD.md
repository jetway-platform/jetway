# CI/CD with GitHub Actions

FlightDeck ships with a ready-made GitHub Actions workflow that runs `flightdeck deploy` on every push to your release branch.

---

## Workflow File

The workflow lives at `.github/workflows/deploy.yml` in your repository. It:

1. Checks out the code
2. Sets up the Dart SDK and Flutter
3. Installs FlightDeck from the pub cache
4. Decodes base64-encoded secrets (keystore, `.p8` key) back to files
5. Runs `flightdeck deploy`

---

## Required GitHub Secrets

Go to your repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

### iOS Secrets

| Secret | Value |
|--------|-------|
| `APP_STORE_API_KEY_ID` | App Store Connect API Key ID (e.g. `ABC123DEF4`) |
| `APP_STORE_API_ISSUER_ID` | App Store Connect Issuer ID (UUID) |
| `APP_STORE_API_KEY_CONTENT` | **Base64-encoded** content of the `.p8` file |

### Android Secrets

| Secret | Value |
|--------|-------|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | **Full JSON content** of the service account key file |
| `ANDROID_KEYSTORE_BASE64` | **Base64-encoded** `.keystore` or `.jks` file |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Key password |

---

## Encoding Files for Secrets

GitHub Secrets only accept text. Binary files (the keystore and `.p8` key) must be base64-encoded:

```bash
# macOS — copies to clipboard
base64 -i keys/AuthKey_ABC123.p8      | pbcopy
base64 -i keys/release.keystore       | pbcopy

# Linux
base64 -w 0 keys/AuthKey_ABC123.p8    | xclip -selection clipboard
base64 -w 0 keys/release.keystore     | xclip -selection clipboard
```

Paste the result as the secret value. The workflow decodes it back to a file at runtime.

---

## Example Workflow

```yaml
# .github/workflows/deploy.yml

name: FlightDeck Deploy

on:
  push:
    branches:
      - release

jobs:
  deploy:
    runs-on: macos-latest   # macos required for iOS builds

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'

      - name: Set up Dart
        uses: dart-lang/setup-dart@v1

      - name: Install FlightDeck
        run: dart pub global activate flightdeck

      - name: Decode iOS API Key
        run: |
          mkdir -p keys
          echo "${{ secrets.APP_STORE_API_KEY_CONTENT }}" | base64 --decode > keys/AuthKey.p8

      - name: Decode Android Keystore
        run: |
          echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 --decode > keys/release.keystore

      - name: Decode Google Play Service Account
        run: |
          echo '${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON }}' > keys/play-service-account.json

      - name: Deploy
        run: flightdeck deploy
        env:
          APP_STORE_API_KEY_ID:      ${{ secrets.APP_STORE_API_KEY_ID }}
          APP_STORE_API_ISSUER_ID:   ${{ secrets.APP_STORE_API_ISSUER_ID }}
          APP_STORE_API_KEY_PATH:    ./keys/AuthKey.p8
          GOOGLE_PLAY_SERVICE_ACCOUNT: ./keys/play-service-account.json
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_PASSWORD:      ${{ secrets.ANDROID_KEY_PASSWORD }}
```

---

## Platform-Specific Deployments

Deploy to only one platform on a given branch:

```yaml
# iOS only on release branch
- name: Deploy iOS
  run: flightdeck deploy --platform ios

# Android only on a separate job
- name: Deploy Android
  run: flightdeck deploy --platform android
```

Or use separate jobs for parallelism:

```yaml
jobs:
  deploy-ios:
    runs-on: macos-latest
    steps:
      # ... setup ...
      - run: flightdeck deploy --platform ios

  deploy-android:
    runs-on: ubuntu-latest   # Android builds don't require macOS
    steps:
      # ... setup ...
      - run: flightdeck deploy --platform android
```

> **Note:** iOS builds require `macos-latest`. Android-only builds can run on `ubuntu-latest` (faster and cheaper).

---

## Triggering Deploys

### On push to a branch

```yaml
on:
  push:
    branches:
      - release
      - main
```

### On a Git tag

```yaml
on:
  push:
    tags:
      - 'v*'   # matches v1.0.0, v2.3.1, etc.
```

### Manual trigger

```yaml
on:
  workflow_dispatch:
    inputs:
      platform:
        description: 'Platform to deploy'
        required: true
        default: 'all'
        type: choice
        options: [all, ios, android]
```

Then in the deploy step:

```yaml
- run: flightdeck deploy --platform ${{ inputs.platform }}
```

---

## Troubleshooting CI Failures

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `IPA upload failed` | `.p8` file incorrectly decoded | Check the base64 encoding step; ensure no line breaks in the secret |
| `Google Play service account not found` | Wrong path to JSON | Verify the decode step writes to the path referenced in env |
| `Android keystore not found` | Keystore not decoded | Check the decode step and the `android.keystore` path in `flightdeck.yaml` |
| `flutter: command not found` | Flutter setup step failed | Ensure `subosito/flutter-action` runs before FlightDeck |
| `flightdeck: command not found` | Pub cache not on PATH | Add `export PATH="$PATH":"$HOME/.pub-cache/bin"` before the deploy step |
