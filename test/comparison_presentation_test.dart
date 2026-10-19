import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensio_ppg_app/core/models/ppg_models.dart';
import 'package:sensio_ppg_app/core/reporting/analysis_report.dart';
import 'package:sensio_ppg_app/core/reporting/chart_svg.dart';
import 'package:sensio_ppg_app/core/reporting/comparison_presentation.dart';
import 'package:sensio_ppg_app/core/services/comparison_label_store.dart';
import 'responsive_ui_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Names derive from meaningful filenames without inventing interventions',
    () {
      expect(
        ComparisonPresentation.inferCondition('StandingPose_ppg_data.csv'),
        'Standing Pose',
      );
      expect(
        ComparisonPresentation.inferCondition(
          'session_12_20261019_084821_ppg_data.csv',
        ),
        'Session 12',
      );
      expect(
        ComparisonPresentation.condition(
          'Session A',
          'StandingPose_ppg_data.csv',
        ),
        'Standing Pose',
      );
      expect(
        ComparisonPresentation.condition('Standing pose', 'session_12.csv'),
        'Standing pose',
      );
    },
  );
  test('Condition names persist independently for each recording', () async {
    SharedPreferences.setMockInitialValues({});
    await ComparisonLabelStore.save('/a/session.csv', 'Standing pose');
    await ComparisonLabelStore.save(
      '/b/session.csv',
      'Half-bending forward pose',
    );
    expect(await ComparisonLabelStore.load('/a/session.csv'), 'Standing pose');
    expect(
      await ComparisonLabelStore.load('/b/session.csv'),
      'Half-bending forward pose',
    );
    await ComparisonLabelStore.save('/a/session.csv', '');
    expect(await ComparisonLabelStore.load('/a/session.csv'), isNull);
  });
  test('Filename identifies conditions, date, regions and export scope', () {
    final a = ReportSession(
      'Standing pose',
      'a.csv',
      fixture().copyWith(sessionStartDateTime: DateTime(2026, 10, 19)),
      regionStartS: 12.25,
      regionEndS: 92.5,
    );
    final b = ReportSession('Half-bending forward pose', 'b.csv', fixture());
    final name = AnalysisReport.suggestedFilename([a, b]);
    expect(
      name,
      '2026-10-19_Standing-pose_vs_Half-bending-forward-pose_A-12.25-92.50s_B-full_summary.pdf',
    );
    expect(
      AnalysisReport.suggestedFilename([a, b], includeDetails: true),
      endsWith('with-details.pdf'),
    );
    expect(ComparisonPresentation.slug('../../pose:*?'), 'pose');
  });
  test(
    'Missing epochs are not rendered as zero and percent changes use points',
    () {
      final base = fixture();
      final empty = base.copyWith(summary: []);
      final m = ComparisonMetric.highlights.first;
      expect(m.value(empty), isNull);
      expect(m.delta(base, empty), isNull);
      expect(m.change(base, empty), 'Change unavailable');
      final svg = ChartSvg.pairedMetric(m, base, empty);
      expect(svg, contains('N/A'));
      expect(svg, contains('Change unavailable'));
      expect(
        ComparisonMetric.highlights[3].change(base, base),
        contains('percentage points'),
      );
    },
  );
  test('Quality and sparse-epoch cautions use the actual data', () {
    final b = fixture().copyWith(
      summary: [
        FeatureSummaryRow(
          domain: 'Time',
          metric: 'MeanHR',
          mean: 83.65,
          sd: 0,
          median: 83.65,
          iqr: 0,
          min: 83.65,
          max: 83.65,
          count: 1,
        ),
      ],
    );
    expect(
      ComparisonPresentation.cautions(fixture(), b).join(' '),
      contains('one valid epoch'),
    );
  });
}
