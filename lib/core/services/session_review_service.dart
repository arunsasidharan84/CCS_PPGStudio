import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ffi_bindings.dart';
import '../models/ppg_models.dart';

class ReviewEdit {
  final double start, end;
  final bool include;
  const ReviewEdit(this.start, this.end, this.include);
  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'include': include,
  };
}

class SessionReviewService {
  static Future<String> _key(String path) async {
    final stat = await File(path).stat();
    return 'review:v1:$path:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  }

  static Future<List<ReviewEdit>> load(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _key(path));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (e) => ReviewEdit(
            (e['start'] as num).toDouble(),
            (e['end'] as num).toDouble(),
            e['include'] as bool,
          ),
        )
        .toList();
  }

  static Future<void> save(String path, List<ReviewEdit> edits) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      await _key(path),
      jsonEncode(edits.map((e) => e.toJson()).toList()),
    );
  }

  /// Revert removes overlapping overrides only inside the selected region.
  static List<ReviewEdit> revert(
    List<ReviewEdit> edits,
    double start,
    double end,
  ) => [
    for (final e in edits)
      if (e.end <= start || e.start >= end)
        e
      else ...[
        if (e.start < start) ReviewEdit(e.start, start, e.include),
        if (e.end > end) ReviewEdit(end, e.end, e.include),
      ],
  ];
  static Future<SessionAnalysisResult> apply(
    SessionAnalysisResult base, {
    List<ReviewEdit> edits = const [],
    double start = 0,
    double? end,
  }) async {
    final result = await compute(_recalculate, (
      base,
      edits,
      start,
      end ?? base.totalDurationS,
    ));
    return result.copyWith(
      sessionStartDateTime: base.sessionStartDateTime?.add(
        Duration(microseconds: (start * 1e6).round()),
      ),
      startTimeOfDayS: base.startTimeOfDayS + start,
      // Recompute standard features directly; do not smooth across rejected gaps.
      pipelineMode: 'standard',
    );
  }
}

SessionAnalysisResult _recalculate(
  (SessionAnalysisResult, List<ReviewEdit>, double, double) request,
) {
  final (base, edits, start, end) = request;
  List<double?> finite(List<double> values) =>
      values.map((v) => v.isFinite ? v : null).toList();
  final bindings = SensioNativeBindings.tryLoad();
  if (bindings == null) throw StateError('Native analysis engine unavailable');
  final raw = bindings.reviewSignal(
    jsonEncode({
      'time': base.time,
      'filtered': finite(base.filtered),
      'norm_ppg': finite(base.normPpg),
      'usable_mask': base.usableMask,
      'pulse_mask': base.pulseMask,
      'quality_trace': finite(base.qualityTrace),
      'sigmot_trace': finite(base.sigmotTrace),
      'peaks_indices': base.peaksIndices,
      'sample_rate': base.sampleRate,
      'start': start,
      'end': end,
      'overrides': edits.map((e) => e.toJson()).toList(),
      'epoch_times': base.hrv.timestamps,
      'ancillary': {
        for (final key in ['Skin_Temperature', 'Activity_Motion'])
          if (base.hrv.metrics.containsKey(key))
            key: finite(base.hrv.metrics[key]!),
      },
    }),
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  if (decoded['success'] != true) throw StateError(decoded['error'] as String);
  return SessionAnalysisResult.fromJson(
    decoded['data'] as Map<String, dynamic>,
  );
}
