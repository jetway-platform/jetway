import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;

class CliPrompt {
  final Logger logger;

  CliPrompt(this.logger);

  String prompt(String label, String defaultValue) {
    if (defaultValue.isNotEmpty) {
      stdout.write('  $label [$defaultValue]: ');
    } else {
      stdout.write('  $label: ');
    }
    final input = stdin.readLineSync()?.trim() ?? '';
    return input.isEmpty ? defaultValue : input;
  }

  String promptRequired(String label, [String? defaultValue]) {
    while (true) {
      if (defaultValue != null && defaultValue.isNotEmpty) {
        stdout.write('  $label [$defaultValue]: ');
      } else {
        stdout.write('  $label: ');
      }
      final input = stdin.readLineSync()?.trim() ?? '';
      if (input.isNotEmpty) return input;
      if (defaultValue != null && defaultValue.isNotEmpty) return defaultValue;
      logger.warn('  This field is required.');
    }
  }

  String promptPath(String label, String defaultValue) {
    final raw = prompt(label, defaultValue);
    if (raw.startsWith('~/')) {
      return path.join(Platform.environment['HOME'] ?? '', raw.substring(2));
    }
    return raw;
  }

  T selectFromList<T>(
    String label,
    List<T> items, {
    required String Function(T) display,
  }) {
    logger.info('  $label:\n');
    for (var i = 0; i < items.length; i++) {
      logger.info('    ${i + 1}) ${display(items[i])}');
    }
    logger.info('');

    while (true) {
      stdout.write('  Enter number [1]: ');
      final input = stdin.readLineSync()?.trim() ?? '';
      final index = input.isEmpty ? 1 : int.tryParse(input);
      if (index != null && index >= 1 && index <= items.length) {
        return items[index - 1];
      }
      logger.warn('  Please enter a number between 1 and ${items.length}.');
    }
  }

  Future<void> openUrl(String url) async {
    logger.info('  Opening: $url');
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('start', [url], runInShell: true);
      }
    } catch (_) {
      // Browser launch is best-effort.
    }
  }
}
