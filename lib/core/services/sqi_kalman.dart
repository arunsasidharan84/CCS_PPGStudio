import 'dart:math' as math;

/// SQI-weighted scalar Kalman smoothing for continuous physiological features.
///
/// Ported from the validated implementation in Orbit_CCIApp.
///
/// MECHANISM:
/// A random-walk state-space filter whose measurement noise variance is scaled
/// inversely by Signal Quality Index: R_k = R_0 / SQI_k.
/// When the signal is clean (SQI -> 1), the measurement is trusted.
/// When a motion artifact, sensor detachment, or transient noise occurs (SQI -> 0),
/// R_k becomes large, Kalman gain K -> 0, and the filter relies on its process
/// model (autonomic inertia) to predict through the disturbance rather than
/// ingesting garbage outliers or producing NaN gaps.
class SqiKalman1D {
  SqiKalman1D({
    this.processVar = defaultProcessVar,
    this.minSqi = defaultMinSqi,
    this.batchObsVar,
    this.shrinkOnMissing = true,
    double? initialValue,
    double? initialCovariance,
  }) : _x = initialValue,
       _p = initialCovariance ?? 0.0;

  static const double defaultProcessVar = 0.1;
  static const double defaultMinSqi = 0.05;

  final double processVar;
  final double minSqi;
  final double? batchObsVar;
  final bool shrinkOnMissing;

  double? _x;
  double _p;

  int _n = 0;
  double _mean = 0.0;
  double _m2 = 0.0;

  bool get isInitialized => _x != null;
  double? get value => _x;
  double get covariance => _p;
  int get observationCount => _n;

  double get obsVar {
    final fixed = batchObsVar;
    if (fixed != null) return math.max(fixed, 1e-6);
    if (_n < 2) return 1.0;
    return math.max(_m2 / _n, 1e-6);
  }

  /// Feed one observation [z] with associated quality [sqi] in [0, 1].
  double step(double z, double sqi) {
    final hasObs = z.isFinite;
    if (hasObs) {
      _n++;
      final d = z - _mean;
      _mean += d / _n;
      _m2 += d * (z - _mean);
    }

    if (_x == null) {
      if (!hasObs) return double.nan;
      _x = z;
      _p = obsVar;
    }

    _p += processVar;
    final s = (sqi.isFinite ? sqi : 0.0).clamp(minSqi, 1.0).toDouble();
    final r = obsVar / s;
    final gain = _p / (_p + r);
    if (hasObs) {
      _x = _x! + gain * (z - _x!);
    }
    if (hasObs || shrinkOnMissing) {
      _p = (1.0 - gain) * _p;
    }
    return _x!;
  }

  void reset() {
    _x = null;
    _p = 0.0;
    _n = 0;
    _mean = 0.0;
    _m2 = 0.0;
  }
}

/// Bank of [SqiKalman1D] filters keyed by metric name.
class SqiKalmanBank {
  SqiKalmanBank({
    this.processVar = SqiKalman1D.defaultProcessVar,
    this.suffix = '__kf',
  });

  final double processVar;
  final String suffix;
  final Map<String, SqiKalman1D> _filters = {};

  int get filterCount => _filters.length;

  Map<String, double> smooth(
    Map<String, double> features, {
    required double? Function(String featureName) sqiFor,
    double defaultSqi = 0.5,
  }) {
    final out = <String, double>{};
    features.forEach((name, value) {
      final filter = _filters.putIfAbsent(
        name,
        () => SqiKalman1D(processVar: processVar),
      );
      final sqi = sqiFor(name) ?? defaultSqi;
      final smoothed = filter.step(value, sqi);
      if (smoothed.isFinite) out['$name$suffix'] = smoothed;
    });
    return out;
  }

  void reset() {
    _filters.clear();
  }
}
