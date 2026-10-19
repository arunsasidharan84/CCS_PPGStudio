import 'dart:math' as math;
import '../models/ppg_models.dart';

/// Shared labels, scales and availability rules for screen and PDF comparisons.
class ComparisonMetric {
  final String key, title, unit;
  const ComparisonMetric(this.key, this.title, this.unit);
  static const highlights = [
    ComparisonMetric('MeanHR', 'Heart rate', 'bpm'),
    ComparisonMetric('RMSSD', 'Short-term variability · RMSSD', 'ms'),
    ComparisonMetric('SDNN', 'Overall variability · SDNN', 'ms'),
    ComparisonMetric('pNN50', 'Successive differences · pNN50', '%'),
    ComparisonMetric('SD1', 'Short-axis dispersion · SD1', 'ms'),
    ComparisonMetric('SD2', 'Long-axis dispersion · SD2', 'ms'),
  ];
  double? value(SessionAnalysisResult result) {
    final row = result.summary.where((r) => r.metric == key).firstOrNull;
    return row == null || row.count <= 0 || !row.mean.isFinite
        ? null
        : row.mean;
  }

  int count(SessionAnalysisResult result) =>
      result.summary
          .where((r) => r.metric == key && r.mean.isFinite)
          .firstOrNull
          ?.count ??
      0;
  double? delta(SessionAnalysisResult a, SessionAnalysisResult b) =>
      value(a) == null || value(b) == null ? null : value(b)! - value(a)!;
  static String number(double? v) => v == null || !v.isFinite
      ? 'N/A'
      : v.toStringAsFixed(v.abs() >= 1000 ? 1 : 2);
  String change(SessionAnalysisResult a, SessionAnalysisResult b) {
    final d = delta(a, b);
    return d == null
        ? 'Change unavailable'
        : '${d > 0 ? '+' : ''}${number(d)} ${unit == '%' ? 'percentage points' : unit}';
  }
}

class ComparisonPresentation {
  static const colorA = '#007F86', colorB = '#7754B8';
  static String inferCondition(String filename) {
    var name = filename
        .split(RegExp(r'[/\\]'))
        .last
        .replaceFirst(RegExp(r'\.[^.]+$'), '');
    final session = RegExp(
      r'^session[_ -]*(\d+)[_ -]+\d{8}',
      caseSensitive: false,
    ).firstMatch(name);
    if (session != null) return 'Session ${session.group(1)}';
    name = name.replaceAll(
      RegExp(r'_?ppg_?data$|_?ppg$|_?data$', caseSensitive: false),
      '',
    );
    name = name
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .trim();
    return name.isEmpty ? 'Unnamed condition' : name;
  }

  static bool genericLabel(String label) => RegExp(
    r'^(A|B|Session [AB]|Recording)$',
    caseSensitive: false,
  ).hasMatch(label.trim());
  static String condition(String label, String filename) =>
      label.trim().isEmpty || genericLabel(label)
      ? inferCondition(filename)
      : label.trim();
  static String title(String a, String b, [String? custom]) =>
      custom == null || custom.trim().isEmpty || custom == 'Quick experiment'
      ? '$a vs $b'
      : custom.trim();
  static String slug(String label) {
    final s = label
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'condition' : s.substring(0, math.min(48, s.length));
  }

  static String filename(
    String a,
    String b,
    DateTime date, {
    bool details = false,
    String? regions,
  }) =>
      '${date.toIso8601String().substring(0, 10)}_${slug(a)}_vs_${slug(b)}${regions == null ? '' : '_$regions'}_${details ? 'with-details' : 'summary'}.pdf';
  static List<String> cautions(
    SessionAnalysisResult a,
    SessionAnalysisResult b,
  ) => [
    if (math.min(a.coveragePct, b.coveragePct) < 50 ||
        (a.coveragePct - b.coveragePct).abs() >= 20)
      'Unequal signal quality: ${a.coveragePct.toStringAsFixed(1)}% vs ${b.coveragePct.toStringAsFixed(1)}% accepted. Review signal quality before interpreting changes.',
    if (ComparisonMetric.highlights.any(
      (m) =>
          (m.count(a) > 0 && m.count(a) < 2) ||
          (m.count(b) > 0 && m.count(b) < 2),
    ))
      'Some estimates use only one valid epoch. Epoch counts describe data availability, not independent repeats.',
    if ((a.totalDurationS - b.totalDurationS).abs() > 1)
      'Selected durations differ (${a.totalDurationS.toStringAsFixed(0)} s vs ${b.totalDurationS.toStringAsFixed(0)} s).',
    if (a.pipelineMode != b.pipelineMode)
      'The sessions use different analysis pipelines.',
  ];
}
