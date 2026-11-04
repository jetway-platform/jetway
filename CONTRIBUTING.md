# Contributing

Thanks for your interest in contributing to FlightDeck! This guide covers how to set up the project for development, the code structure to be aware of, and how to submit changes.

---

## Prerequisites

- Dart SDK ≥ 3.0
- Flutter ≥ 3.10 (for integration testing against a real Flutter project)
- A code editor with the Dart plugin (VS Code or IntelliJ)

---

## Development Setup

```bash
# Clone the repo
git clone https://github.com/AbdLim/flightdeck-cli.git
cd flightdeck-cli

# Install dependencies
dart pub get

# Run the CLI in development (without installing)
dart run bin/flightdeck.dart --help
dart run bin/flightdeck.dart deploy --help
```

---

## Code Structure

Key entry points across the codebase:

| File | Purpose |
|------|---------|
| `lib/src/runner.dart` | Registers commands — start here when adding a new command |
| `lib/src/commands/` | One file per top-level command |
| `lib/src/services/` | Platform-specific API wrappers (Apple, Google Play, Flutter build) |
| `lib/src/models/config.dart` | All `flightdeck.yaml` parsing logic |

---

## Adding a New Command

1. Create `lib/src/commands/<name>_command.dart`
2. Extend `Command<int>` from `package:args`
3. Implement `name`, `description`, and `run()` (return `0` for success, `1` for error)
4. Register it in `lib/src/runner.dart` with `..addCommand(MyNewCommand(_logger))`

**Minimal example:**

```dart
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

class DoctorCommand extends Command<int> {
  @override
  final String name = 'doctor';

  @override
  final String description = 'Check all prerequisites are installed.';

  final Logger _logger;
  DoctorCommand(this._logger);

  @override
  Future<int> run() async {
    _logger.info('Running FlightDeck doctor...');
    // ... checks ...
    return 0;
  }
}
```

---

## Adding a New Config Field

1. Add the field to the relevant model in `lib/src/models/config.dart` (`IosConfig`, `AndroidConfig`, or `AppConfig`)
2. Parse it in the `fromYaml()` factory
3. Add a `resolved*` getter if the field can also be set via an environment variable
4. Update `flightdeck.yaml.example` with the new field (commented out if optional)

---

## Tests

```bash
# Run all tests
dart test

# Run a specific test file
dart test test/config_test.dart

# Run with verbose output
dart test --reporter expanded
```

Tests live in `test/`. Run tests with `dart test`.

**Test naming convention:**

```dart
group('FlightDeckConfig', () {
  test('throws when flightdeck.yaml is missing', () { ... });
  test('parses ios section correctly', () { ... });
});
```

---

## Code Style

FlightDeck follows the standard [Dart style guide](https://dart.dev/guides/language/effective-dart/style).

- `dart format .` — auto-format all files
- `dart analyze` — check for lint errors (uses `lints` package rules)

Both are enforced in CI. Run them locally before submitting a PR:

```bash
dart format .
dart analyze
```

---

## Submitting a Pull Request

1. **Fork** the repository and create a feature branch from `main`:
   ```bash
   git checkout -b feature/doctor-command
   ```

2. **Write tests** for any new behaviour

3. **Run the checks:**
   ```bash
   dart format .
   dart analyze
   dart test
   ```

4. **Commit** with a clear message:
   ```
   feat: add flightdeck doctor command
   fix: handle missing .ipa file after build
   docs: update CREDENTIALS guide for new ASC UI
   ```

5. **Open a PR** against `main` with a description of what changed and why

---

## Reporting Issues

Please include:
- FlightDeck version (`flightdeck --version`)
- Dart/Flutter version (`dart --version`, `flutter --version`)
- The command you ran (redact any credentials)
- The full error output (run with `--verbose` for extra detail)
