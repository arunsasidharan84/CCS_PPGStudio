import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensio_ppg_app/core/services/app_update_service.dart';
import 'package:sensio_ppg_app/core/services/session_review_service.dart';
import 'package:sensio_ppg_app/core/reporting/analysis_report.dart';
import 'responsive_ui_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Revert splits overlapping edits and preserves outside decisions', () {
    final edits = SessionReviewService.revert(
      [const ReviewEdit(0, 100, false), const ReviewEdit(25, 35, true)],
      20,
      40,
    );
    expect(edits.length, 2);
    expect(edits.map((e) => (e.start, e.end)), [(0.0, 20.0), (40.0, 100.0)]);
  });
  test(
    'Saved reviews are isolated by file identity and can be reset',
    () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('ppg-review-test');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File(
        '${dir.path}/signal.csv',
      ).writeAsString('original');
      await SessionReviewService.save(file.path, [
        const ReviewEdit(2, 4, false),
      ]);
      expect(
        (await SessionReviewService.load(file.path)).single.include,
        false,
      );
      await SessionReviewService.save(file.path, []);
      expect(await SessionReviewService.load(file.path), isEmpty);
      await SessionReviewService.save(file.path, [
        const ReviewEdit(2, 4, false),
      ]);
      await file.writeAsString('replacement recording');
      expect(await SessionReviewService.load(file.path), isEmpty);
    },
  );
  test('Version ordering compares numbers, not lexicographic strings', () {
    expect(AppUpdateService.isNewer('v1.10.0', '1.9.0'), true);
    expect(AppUpdateService.isNewer('v1.1.0', '1.1.0'), false);
    expect(AppUpdateService.isNewer('v1.0.9', '1.1.0'), false);
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: ${AppUpdateService.currentVersion}+'),
    );
  });
  test('Region recomputation and exclusion update exported metrics', () async {
    final base = fixture();
    final selected = await SessionReviewService.apply(
      base,
      start: 30,
      end: 150,
    );
    expect(selected.totalDurationS, 120);
    expect(selected.time.first, 0);
    expect(selected.hrv.timestamps.every((t) => t <= 120), true);
    final reviewed = await SessionReviewService.apply(
      base,
      edits: [const ReviewEdit(60, 120, false)],
    );
    expect(reviewed.coveragePct, closeTo(80, .1));
    expect(reviewed.peaksIndices.length, lessThan(base.peaksIndices.length));
    expect(reviewed.poincare.timestamps.any((t) => t >= 59 && t < 120), false);
  });
  test(
    'Experiment PDF is generated with selected regions and review metadata',
    () async {
      final base = fixture();
      final selected = await SessionReviewService.apply(
        base,
        start: 30,
        end: 150,
      );
      final bytes = await AnalysisReport.generate([
        ReportSession(
          'Baseline',
          'session-a.csv',
          selected,
          regionStartS: 30,
          regionEndS: 150,
          experimentTitle: 'Breathing experiment',
          reviewNotes: ['Exclude 60–90 s'],
        ),
        ReportSession(
          'Intervention',
          'session-b.csv',
          selected,
          regionStartS: 90,
          regionEndS: 210,
        ),
      ]);
      expect(bytes.take(4), [37, 80, 68, 70]);
      expect(bytes.length, greaterThan(10000));
      if (Platform.environment['PPG_REPORT_QA'] == '1') {
        await Directory('tmp/pdfs').create(recursive: true);
        await File('tmp/pdfs/experiment.pdf').writeAsBytes(bytes);
      }
    },
  );
}
