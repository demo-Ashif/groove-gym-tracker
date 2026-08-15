import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

/// One buffered line.
@immutable
class LogRecord {
  const LogRecord({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
  });

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;

  @override
  String toString() =>
      '${time.toIso8601String()} ${level.name.toUpperCase().padRight(5)} '
      '[$tag] $message${error == null ? '' : ' | $error'}';
}

/// Release-safe logger with an in-memory ring buffer (ADR §17.1).
///
/// Console output is stripped in release builds — nothing is traceable from a
/// store binary — but the **buffer is kept in every build**, because the whole
/// point is being able to dump the last few hundred lines from Settings after
/// a real failure in a gym with no debugger attached.
///
/// Messages are truncated and are expected to be free of exercise names,
/// notes and photo paths: a report should say *where*, not *what you lifted*
/// (ADR §17.1).
abstract final class AppLogger {
  /// Hook for reporting errors in release builds. Wire to Sentry in
  /// `bootstrap()` once observability lands (ADR roadmap).
  static void Function(Object error, StackTrace? stackTrace)? onReleaseError;

  /// ADR §17.1: "the last 500 lines".
  static const bufferLimit = 500;
  static const _maxMessageLength = 500;

  static final Queue<LogRecord> _buffer = Queue<LogRecord>();

  /// Newest last. A copy, so a Settings screen can render it without holding
  /// a live reference to the buffer.
  static List<LogRecord> get history => List.unmodifiable(_buffer);

  static void clearHistory() => _buffer.clear();

  static void d(String message, {String tag = 'APP'}) =>
      _log(LogLevel.debug, message, tag: tag);

  static void i(String message, {String tag = 'APP'}) =>
      _log(LogLevel.info, message, tag: tag);

  static void w(String message, {String tag = 'APP'}) =>
      _log(LogLevel.warn, message, tag: tag);

  static void e(
    String message, {
    String tag = 'APP',
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      LogLevel.error,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
    if (kReleaseMode) onReleaseError?.call(error ?? message, stackTrace);
  }

  static void _log(
    LogLevel level,
    String message, {
    required String tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final truncated = message.length > _maxMessageLength
        ? '${message.substring(0, _maxMessageLength)}…'
        : message;

    _buffer.addLast(
      LogRecord(
        time: DateTime.now(),
        level: level,
        tag: tag,
        message: truncated,
        error: error?.toString(),
      ),
    );
    while (_buffer.length > bufferLimit) {
      _buffer.removeFirst();
    }

    if (kReleaseMode) return;
    developer.log(
      truncated,
      name: tag,
      level: switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      },
      error: error,
      stackTrace: stackTrace,
    );
  }
}
