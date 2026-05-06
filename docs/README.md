# FlightDeck Documentation

Welcome to the FlightDeck developer docs.

---

## Contents

| Doc | Description |
|-----|-------------|
| [GETTING_STARTED.md](GETTING_STARTED.md) | Prerequisites, installation, first deploy |
| [COMMANDS.md](COMMANDS.md) | Full CLI reference: all commands, flags, and examples |
| [CONFIGURATION.md](CONFIGURATION.md) | Every `flightdeck.yaml` field explained |
| [CREDENTIALS.md](CREDENTIALS.md) | Step-by-step: App Store Connect API key, keystore, Play service account |
| [CI_CD.md](CI_CD.md) | GitHub Actions workflow, secrets setup, matrix jobs |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Project structure, component diagram, deploy lifecycle |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Dev setup, adding commands, tests, PR workflow |

---

## Quick Start (TL;DR)

```bash
# 1. Install
dart pub global activate flightdeck

# 2. Set up your Flutter project
cd your-flutter-app
flightdeck init

# 3. Add credentials
flightdeck env set APP_STORE_API_KEY_ID     <your-key-id>
flightdeck env set APP_STORE_API_ISSUER_ID  <your-issuer-id>
flightdeck env set APP_STORE_API_KEY_PATH   ./keys/AuthKey.p8
flightdeck env set GOOGLE_PLAY_SERVICE_ACCOUNT ./keys/play-service-account.json
flightdeck env set ANDROID_KEYSTORE_PASSWORD   <your-password>
flightdeck env set ANDROID_KEY_PASSWORD        <your-key-password>

# 4. Deploy
flightdeck deploy
```

See [GETTING_STARTED.md](GETTING_STARTED.md) for the full walkthrough.
