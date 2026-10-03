import 'dart:math' as math;

/// IPFM-style beat-series cleaning for wearable PPG recordings.
///
/// Ported from the validated implementation in Orbit_CCIApp.
///
/// WHAT IT DOES:
///
/// 1. Spurious Beat Removal: drops beats creating an implausibly short interval
///    (< 60% of local median period), typically caused by motion spikes or dicrotic
///    notch false triggers.
/// 2. Confidence-Gated Segmentation: breaks the pulse series where missed beats
///    cannot be inferred with high confidence. A gap is only trusted when the implied
///    beat count is small (<= 4) and within 0.25 of an integer ratio.
/// 3. Trusted Gap Imputation & Real Interval Isolation:
///    - [rrAllMs] contains all intervals including filled gaps for robust rate tracking.
///    - [rrRealMs] strictly contains intervals between two REAL consecutive beats.
///      Imputed beats never enter [rrRealMs], preventing artificial deflation of
///      variability metrics (RMSSD, SDNN, SD1).
class IpfmCardiacResult {
  const IpfmCardiacResult({
    required this.rrRealMs,
    required this.rrAllMs,
    required this.hrBpmRobust,
    required this.beatsRemoved,
    required this.beatsInserted,
    required this.chainBreaks,
    required this.segments,
  });

  /// Intervals between consecutive REAL beats, within segments.
  /// Feed HRV variability analysis from this.
  final List<double> rrRealMs;

  /// All intervals including those created by gap filling.
  /// Use for rate and coverage, not for variability.
  final List<double> rrAllMs;

  /// Median of the per-interval instantaneous rate over [rrAllMs].
  final double? hrBpmRobust;

  final int beatsRemoved;
  final int beatsInserted;
  final int chainBreaks;
  final int segments;

  bool get isUsable => rrRealMs.length >= 3;

  Map<String, double> get diagnostics => {
    'ipfm_beats_removed': beatsRemoved.toDouble(),
    'ipfm_beats_inserted': beatsInserted.toDouble(),
    'ipfm_chain_breaks': chainBreaks.toDouble(),
    'ipfm_segments': segments.toDouble(),
    'ipfm_rr_real_count': rrRealMs.length.toDouble(),
    'ipfm_rr_all_count': rrAllMs.length.toDouble(),
  };
}

class IpfmCardiac {
  IpfmCardiac._();

  /// Interval shorter than this fraction of the local median is treated as a
  /// spurious extra beat.
  static const double shortRatio = 0.60;

  /// A multi-beat gap is only counted when its implied count is within this of
  /// an integer.
  static const double ambiguityTolerance = 0.25;

  /// Largest gap, in beats, we are willing to count through.
  static const int maxGapBeats = 4;

  /// A single ordinary interval is always trusted inside this ratio band.
  static const double singleBeatLow = 0.60;
  static const double singleBeatHigh = 1.45;

  static const int _maxRemovalIterations = 20;

  /// Clean a raw peak-to-peak interval series (milliseconds, in time order).
  static IpfmCardiacResult process(List<double> rawPpiMs) {
    final intervals = rawPpiMs
        .where((v) => v.isFinite && v > 0)
        .toList(growable: false);
    if (intervals.length < 3) {
      return IpfmCardiacResult(
        rrRealMs: List<double>.from(intervals),
        rrAllMs: List<double>.from(intervals),
        hrBpmRobust: _medianRate(intervals),
        beatsRemoved: 0,
        beatsInserted: 0,
        chainBreaks: 0,
        segments: 1,
      );
    }

    // Reconstruct beat times from intervals.
    var beats = <double>[0.0];
    for (final v in intervals) {
      beats.add(beats.last + v);
    }

    final removed = _removeSpurious(beats);
    beats = removed.beats;

    final segments = _segment(beats);

    final rrReal = <double>[];
    final rrAll = <double>[];
    var inserted = 0;

    for (final seg in segments) {
      if (seg.length < 2) continue;
      final period = _median(_diff(seg));
      for (int i = 0; i < seg.length - 1; i++) {
        final dt = seg[i + 1] - seg[i];
        final ratio = period > 0 ? dt / period : 1.0;
        var n = ratio.round();
        if (n < 1) n = 1;
        if (n > maxGapBeats) n = maxGapBeats;
        if (n == 1) {
          rrReal.add(dt);
          rrAll.add(dt);
        } else {
          // Place missing beats at local rate for rate tracking only.
          final part = dt / n;
          for (int k = 0; k < n; k++) {
            rrAll.add(part);
          }
          inserted += n - 1;
        }
      }
    }

    return IpfmCardiacResult(
      rrRealMs: rrReal,
      rrAllMs: rrAll,
      hrBpmRobust: _medianRate(rrAll),
      beatsRemoved: removed.count,
      beatsInserted: inserted,
      chainBreaks: math.max(0, segments.length - 1),
      segments: segments.length,
    );
  }

  static ({List<double> beats, int count}) _removeSpurious(List<double> input) {
    final beats = List<double>.from(input);
    var count = 0;
    for (int iter = 0; iter < _maxRemovalIterations; iter++) {
      if (beats.length < 4) break;
      final intervals = _diff(beats);
      final period = _median(intervals);
      if (!period.isFinite || period <= 0) break;

      var minIdx = 0;
      for (int i = 1; i < intervals.length; i++) {
        if (intervals[i] < intervals[minIdx]) minIdx = i;
      }
      if (intervals[minIdx] >= shortRatio * period) break;

      // Drop whichever beat leaves the joined interval closest to local period.
      int dropIdx = minIdx + 1;
      double bestCost = double.infinity;
      if (minIdx > 0) {
        final cost = ((beats[minIdx + 1] - beats[minIdx - 1]) - period).abs();
        if (cost < bestCost) {
          bestCost = cost;
          dropIdx = minIdx;
        }
      }
      if (minIdx + 2 < beats.length) {
        final cost = ((beats[minIdx + 2] - beats[minIdx]) - period).abs();
        if (cost < bestCost) {
          bestCost = cost;
          dropIdx = minIdx + 1;
        }
      }
      beats.removeAt(dropIdx);
      count++;
    }
    return (beats: beats, count: count);
  }

  static List<List<double>> _segment(List<double> beats) {
    if (beats.length < 2) return [beats];
    final intervals = _diff(beats);
    final period = _median(intervals);
    if (!period.isFinite || period <= 0) return [beats];

    final segments = <List<double>>[];
    var current = <double>[beats.first];
    for (int i = 0; i < intervals.length; i++) {
      final ratio = intervals[i] / period;
      final n = ratio.round();
      final confident = (ratio >= singleBeatLow && ratio <= singleBeatHigh)
          ? true
          : (n >= 1 &&
                n <= maxGapBeats &&
                (ratio - n).abs() <= ambiguityTolerance);
      if (confident) {
        current.add(beats[i + 1]);
      } else {
        segments.add(current);
        current = <double>[beats[i + 1]];
      }
    }
    segments.add(current);
    return segments;
  }

  static List<double> _diff(List<double> a) {
    final out = <double>[];
    for (int i = 0; i < a.length - 1; i++) {
      out.add(a[i + 1] - a[i]);
    }
    return out;
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return double.nan;
    final s = List<double>.from(values)..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : 0.5 * (s[n ~/ 2 - 1] + s[n ~/ 2]);
  }

  static double? _medianRate(List<double> rrMs) {
    final rates = rrMs
        .where((v) => v.isFinite && v >= 330.0 && v <= 2000.0)
        .map((v) => 60000.0 / v)
        .toList();
    if (rates.length < 2) return null;
    final m = _median(rates);
    return m.isFinite ? m.clamp(40.0, 180.0) : null;
  }
}
