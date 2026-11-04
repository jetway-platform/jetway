# Contributing

Thanks for your interest in contributing to Jetway! This guide covers development setup, code structure, and pull request guidelines.

---

## Prerequisites

- Dart SDK ≥ 3.0
- Flutter ≥ 3.10
- Code editor with Dart support (VS Code or IntelliJ)

---

## Development Setup

```bash
# Clone the repository
git clone https://github.com/jetway-platform/jetway.git
cd jetway-cli

# Install dependencies
dart pub get

# Run the CLI in development
dart run bin/jetway.dart --help
dart run bin/jetway.dart deploy --help
```

---

## Code Structure

Key entry points across the codebase:

| File | Purpose |
| --- | --- |
| `lib/src/runner.dart` | Registers CLI commands |
| `lib/src/commands/` | Top-level command implementations |
| `lib/src/services/` | Platform API integrations (App Store Connect, Google Play, Flutter build) |
| `lib/src/models/config.dart` | `jetway.yaml` parsing and validation logic |
| `lib/src/utils/` | Project detection and terminal prompt utilities |

---

## Adding a New Command

1. Create `lib/src/commands/<name>_command.dart`.
2. Extend `Command<int>` from `package:args`.
3. Implement `name`, `description`, and `run()`. Return `0` on success, `1` on error.
4. Register the command in `lib/src/runner.dart` with `..addCommand(MyNewCommand(_logger))`.

---

## Adding a New Config Field

1. Add the field to the relevant model in `lib/src/models/config.dart` (`IosConfig`, `AndroidConfig`, or `AppConfig`).
2. Parse the field in the `fromYaml()` factory.
3. Add a resolved getter if the field supports environment variable fallbacks.
4. Update `jetway.yaml.example` with the new field.

---

## Running Tests

```bash
# Run all tests
dart test

# Run a specific test file
dart test test/config_test.dart
```

---

## Code Style

Jetway follows standard Dart guidelines:

- `dart format .` — auto-format all files
- `dart analyze` — check for lint errors

---

## Submitting a Pull Request

1. Fork the repository and create a feature branch from `master`:
   ```bash
   git checkout -b feature/my-feature
   ```
2. Write tests for any new behavior.
3. Run formatting, lint, and tests:
   ```bash
   dart format .
   dart analyze
   dart test
   ```
4. Commit with descriptive messages.
5. Open a PR against `master`.
