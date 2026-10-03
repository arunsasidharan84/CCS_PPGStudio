import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Orbit stores PPG in E; T is a 250 Hz device sample counter.
/// Packet arrival timestamps are unsuitable for sample timing (BLE batching).
class OrbitPpgRecording {
  final List<double> seconds;
  final List<double> values;
  final DateTime? startedAt;
  final int malformedPackets;
  const OrbitPpgRecording(
    this.seconds,
    this.values,
    this.startedAt,
    this.malformedPackets,
  );

  static OrbitPpgRecording parse(String text) {
    final seconds = <double>[];
    final values = <double>[];
    DateTime? start;
    double? firstTick;
    double? previousTick;
    var offset = 0.0;
    var malformed = 0;
    List<double> numbers(dynamic value) => value is num
        ? [value.toDouble()]
        : value is List
        ? value.whereType<num>().map((n) => n.toDouble()).toList()
        : [];
    for (final line in const LineSplitter().convert(text)) {
      if (line.contains('MARK:')) continue;
      final timestamp = RegExp(
        r'timeStamp:\s*(\d{4}[-.]\d{2}[-.]\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?)',
      ).firstMatch(line);
      if (start == null && timestamp != null) {
        final raw = timestamp.group(1)!;
        start = DateTime.tryParse(
          raw.substring(0, 10).replaceAll('.', '-') + raw.substring(10),
        );
      }
      for (final object in RegExp(r'\{[^{}]*\}').allMatches(line)) {
        try {
          final json =
              jsonDecode(
                    object
                        .group(0)!
                        .replaceAllMapped(
                          RegExp(r'([\{,]\s*)([A-Za-z]+)(\s*:)'),
                          (m) => '${m[1]}"${m[2]}"${m[3]}',
                        ),
                  )
                  as Map<String, dynamic>;
          final e = numbers(json['E']);
          final ticks = numbers(json['T']);
          if (e.isEmpty) continue;
          // Matches Orbit_CCIApp: scalar E is one PPG sample; E arrays
          // contain four 250 Hz samples per 62.5 Hz PPG sample.
          for (var i = 0; i < e.length; i += e.length == 1 ? 1 : 4) {
            final chunk = e.sublist(i, math.min(i + 4, e.length));
            final value = chunk.reduce((a, b) => a + b) / chunk.length;
            if (!value.isFinite) {
              malformed++;
              continue;
            }
            final tick = ticks.isEmpty
                ? null
                : ticks[math.min(
                    e.length == 1 ? ticks.length - 1 : i + chunk.length - 1,
                    ticks.length - 1,
                  )];
            double time;
            if (tick != null) {
              firstTick ??= tick;
              if (previousTick != null && tick == previousTick) continue;
              if (previousTick != null && tick < previousTick) {
                // Device reset/wrap: preserve a discontinuity, never bridge it.
                offset =
                    (seconds.isEmpty ? 0 : seconds.last) +
                    1 -
                    (tick - firstTick) / 250;
              }
              time = (tick - firstTick) / 250 + offset;
              previousTick = tick;
            } else {
              time = seconds.isEmpty ? 0 : seconds.last + 1 / 62.5;
            }
            if (seconds.isNotEmpty && time <= seconds.last) continue;
            seconds.add(time);
            values.add(value);
          }
        } catch (_) {
          malformed++;
        }
      }
    }
    if (values.length < 125) {
      throw const FormatException(
        'No usable Orbit PPG stream (E channel) found. Select a raw or PPG recording.',
      );
    }
    return OrbitPpgRecording(seconds, values, start, malformed);
  }

  /// Temporary interchange file for the existing native analysis pipeline.
  void writeCsv(File file) {
    final out = StringBuffer('Timestamp,PPG\n');
    for (var i = 0; i < values.length; i++) {
      final micros = (seconds[i] * 1000000).round();
      final s = micros ~/ 1000000;
      String pad(int n, int width) => n.toString().padLeft(width, '0');
      out.writeln(
        '${pad((s ~/ 3600) % 24, 2)}:${pad((s ~/ 60) % 60, 2)}:${pad(s % 60, 2)}.${pad(micros % 1000000, 6)},${values[i]}',
      );
    }
    file.writeAsStringSync(out.toString());
  }
}

bool matchesRecordingPattern(String name, String pattern) {
  final expression = pattern
      .split('*')
      .map((p) => p.split('?').map(RegExp.escape).join('.'))
      .join('.*');
  return RegExp('^$expression\$', caseSensitive: false).hasMatch(name);
}
