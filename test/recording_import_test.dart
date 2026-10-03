import 'package:flutter_test/flutter_test.dart';
import 'package:sensio_ppg_app/core/services/recording_import.dart';

void main() {
  test('SensIO wildcard filter is case insensitive and anchored', () {
    expect(
      matchesRecordingPattern('session_PPG_DATA.CSV', '*_ppg_data.csv'),
      isTrue,
    );
    expect(
      matchesRecordingPattern('session_sigmot_data.csv', '*_ppg_data.csv'),
      isFalse,
    );
    expect(
      matchesRecordingPattern('session_ppg_data.csv.bak', '*_ppg_data.csv'),
      isFalse,
    );
  });
  test('Orbit E channel uses device ticks and preserves missing packets', () {
    final text = List.generate(
      150,
      (i) =>
          'timeStamp: 2026-10-02T08:21:30.123; {"A":[1,2,3,4],"E":${1000 + i},"T":${4 * i + (i >= 80 ? 40 : 0)}}',
    ).join('\n');
    final data = OrbitPpgRecording.parse(text);
    expect(data.values.length, 150);
    expect(data.startedAt, DateTime(2026, 10, 2, 8, 21, 30, 123));
    expect(data.seconds[1] - data.seconds[0], closeTo(.016, 1e-8));
    expect(data.seconds[80] - data.seconds[79], closeTo(.176, 1e-8));
    expect(data.values.first, 1000);
  });
  test('EEG-only file cannot masquerade as PPG', () {
    expect(
      () => OrbitPpgRecording.parse('{"A":[1,2,3,4]}'),
      throwsFormatException,
    );
  });
}
