# Credentials Setup

This guide walks through obtaining and configuring all credentials required to deploy with FlightDeck.

---

## iOS — App Store Connect API Key

FlightDeck uses the **App Store Connect API** for authentication (no Apple ID username/password needed). You need three values: a Key ID, an Issuer ID, and a `.p8` private key file.

### Step 1: Generate an API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** → **Integrations** → **App Store Connect API**
2. Click **Generate API Key** (or the `+` button)
3. Give it a name (e.g. `FlightDeck CI`)
4. Set the role to **App Manager** (minimum required for uploads)
5. Click **Generate**

### Step 2: Download the Key

1. Download the `.p8` file immediately — **Apple only shows it once**
2. Note your **Key ID** (e.g. `ABC123DEF4`) — visible in the key list
3. Note your **Issuer ID** (e.g. `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) — shown at the top of the API keys page

### Step 3: Find Your Team ID

1. Go to [developer.apple.com/account](https://developer.apple.com/account)
2. Your Team ID is shown in the top-right (e.g. `ABCD1234EF`)

### Step 4: Set the Credentials

Copy your `.p8` file to the `keys/` directory of your Flutter project:

```bash
mkdir -p keys
cp ~/Downloads/AuthKey_ABC123DEF4.p8 keys/
```

Then set them in FlightDeck:

```bash
flightdeck env set APP_STORE_API_KEY_ID     ABC123DEF4
flightdeck env set APP_STORE_API_ISSUER_ID  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
flightdeck env set APP_STORE_API_KEY_PATH   ./keys/AuthKey_ABC123DEF4.p8
```

Or set them in `flightdeck.yaml`:

```yaml
ios:
  team_id: "ABCD1234EF"
  api_key_id: "ABC123DEF4"
  api_issuer_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  api_key_path: "./keys/AuthKey_ABC123DEF4.p8"
```

---

## iOS — Certificates & Provisioning Profiles

Your machine needs a valid **Apple Distribution certificate** in the macOS Keychain and a matching **provisioning profile**.

### Check what's installed

```bash
flightdeck certs check   # lists valid signing identities
flightdeck certs list    # lists installed provisioning profiles
```

### Sync from Apple

```bash
flightdeck certs sync
```

This fetches the latest profiles from Apple and resets Xcode's cache.

### Manual Certificate Setup (if needed)

1. In **Xcode** → **Settings** → **Accounts**, add your Apple ID
2. Select your team and click **Manage Certificates**
3. Click `+` → **Apple Distribution** to create a new certificate
4. Xcode will install it to your Keychain automatically

---

## Android — Signing Keystore

A release keystore is required to sign Android builds. If you already have one, skip to [Step 2](#step-2-reference-it-in-flightdeckyaml).

### Step 1: Generate a Keystore

```bash
keytool -genkey -v \
  -keystore keys/release.keystore \
  -alias release \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

You'll be prompted for a keystore password, key password, and identity details. **Keep these passwords safe** — you cannot re-sign old APKs with a different key.

### Step 2: Reference It in `flightdeck.yaml`

```yaml
android:
  keystore: "./keys/release.keystore"
  key_alias: "release"
```

### Step 3: Set Passwords as Environment Variables

```bash
flightdeck env set ANDROID_KEYSTORE_PASSWORD your_keystore_password
flightdeck env set ANDROID_KEY_PASSWORD      your_key_password
```

> **Never commit keystore passwords to source control.**

---

## Android — Google Play Service Account

FlightDeck uses the **Google Play Android Publisher API** to upload and promote builds. This requires a service account with the right permissions.

### Step 1: Link Google Play to a Google Cloud Project

1. Go to [Google Play Console](https://play.google.com/console) → **Setup** → **API access**
2. Click **Link to an existing Google Cloud project** (or create a new one)
3. Follow the prompts to link

### Step 2: Create a Service Account

1. In [Google Cloud Console](https://console.cloud.google.com) → **IAM & Admin** → **Service Accounts**
2. Click **Create Service Account**
3. Give it a name (e.g. `flightdeck-deploy`)
4. Skip the optional role grant at the Cloud level (permissions are granted in Play Console next)
5. Click **Done**
6. Click the service account → **Keys** → **Add Key** → **Create new key** → **JSON**
7. Download the JSON key file

### Step 3: Grant Play Console Access

1. Back in [Play Console](https://play.google.com/console) → **Setup** → **API access**
2. Find your new service account in the list → click **Grant access**
3. Set the role to **Release Manager** (required for uploading and promoting builds)
4. Click **Apply**

### Step 4: Set the Credential

```bash
mkdir -p keys
cp ~/Downloads/flightdeck-deploy-xxxxx.json keys/play-service-account.json

flightdeck env set GOOGLE_PLAY_SERVICE_ACCOUNT ./keys/play-service-account.json
```

Or in `flightdeck.yaml`:

```yaml
android:
  service_account: "./keys/play-service-account.json"
```

---

## Verify Everything

```bash
flightdeck env check
```

Expected output:
```
✓ APP_STORE_API_KEY_ID
✓ APP_STORE_API_ISSUER_ID
✓ APP_STORE_API_KEY_PATH
✓ GOOGLE_PLAY_SERVICE_ACCOUNT
✓ ANDROID_KEYSTORE_PASSWORD
✓ ANDROID_KEY_PASSWORD

✔ All environment variables are configured.
```

---

## Keeping Secrets Safe

Add this to your `.gitignore`:

```gitignore
keys/
.env
*.p8
*.keystore
*.jks
```

For CI/CD, see [CI_CD.md](CI_CD.md) for how to pass secrets as GitHub Actions secrets.
