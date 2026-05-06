import 'package:flightdeck/src/runner.dart';
import 'dart:io';

Future<void> main(List<String> args) async {
  final exitCode = await FlightDeckRunner().run(args);
  exit(exitCode);
}
