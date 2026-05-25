import 'package:lib5/lib5.dart';
// ignore: implementation_imports
import 'package:lib5/src/node/logger/base.dart';

class S5MessengerLogger extends Logger {
  final String prefix;
  final bool showVerbose;

  S5MessengerLogger({
    this.prefix = '',
    this.showVerbose = false,
  });

  String _format(String level, String message, String color) {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    
    // ANSI Colors
    const reset = '\x1B[0m';
    
    return "$timeStr $color[${level.padRight(5)}]$reset $prefix $message";
  }

  @override
  void info(String s) {
    print(_format("INFO", s, '\x1B[32m')); // Green
  }

  @override
  void warn(String s) {
    print(_format("WARN", s, '\x1B[33m')); // Yellow
  }

  @override
  void error(String s) {
    print(_format("ERROR", s, '\x1B[31m')); // Red
  }

  @override
  void verbose(String s) {
    if (!showVerbose) return;
    print(_format("VERB", s, '\x1B[34m')); // Blue
  }

  @override
  void catched(e, st, [context]) {
    error("Caught Exception: $e\n$st");
  }
}
