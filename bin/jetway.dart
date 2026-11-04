import 'dart:io';
import 'package:jetway/src/runner.dart';

Future<void> main(List<String> args) async {
  final exitCode = await JetwayRunner().run(args);
  exit(exitCode);
}
