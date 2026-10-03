import 'dart:math' as math;
import '../models/ppg_models.dart';
import 'ipfm_cardiac.dart';
import 'sqi_kalman.dart';

/// Applies Physiology-Informed IPFM Beat Cleaning and SQI-Weighted Kalman Smoothing
/// to a [SessionAnalysisResult].
class PpgIpfmRefinement {
  static SessionAnalysisResult refine(SessionAnalysisResult original) {
    if (original.peaksIndices.length < 3) {
      return original.copyWith(pipelineMode: 'ipfm_kalman');
    }

    // 1. Extract raw peak-to-peak intervals in milliseconds
    final rawPpiMs = <double>[];
    final peakTimes = <double>[];
    for (var i = 0; i < original.peaksIndices.length; i++) {
      final idx = original.peaksIndices[i];
      if (idx < original.time.length) {
        peakTimes.add(original.time[idx]);
      }
    }
    for (var i = 0; i < peakTimes.length - 1; i++) {
      rawPpiMs.add((peakTimes[i + 1] - peakTimes[i]) * 1000.0);
    }

    // 2. IPFM Beat Cleaning (spurious removal, confidence segmentation, gap filling)
    final ipfm = IpfmCardiac.process(rawPpiMs);

    // 3. Recalculate Poincare geometry from clean real intervals (rrRealMs)
    final poincare = _computePoincare(ipfm.rrRealMs);

    // 4. SQI-weighted Kalman smoothing across time-resolved feature trajectories
    final hrv = _smoothHrvMetrics(original, ipfm);

    // 5. Recompute Summary Statistics
    final summary = _computeRefinedSummary(original, hrv, ipfm, poincare);

    return original.copyWith(
      hrv: hrv,
      poincare: poincare,
      summary: summary,
      pipelineMode: 'ipfm_kalman',
      ipfmDiagnostics: ipfm.diagnostics,
    );
  }

  static PoincareData _computePoincare(List<double> rrRealMs) {
    final x = <double>[];
    final y = <double>[];
    final timestamps = <double>[];

    for (var i = 0; i < rrRealMs.length - 1; i++) {
      final left = rrRealMs[i];
      final right = rrRealMs[i + 1];
      if (left < 350.0 || left > 1600.0 || right < 350.0 || right > 1600.0) {
        continue;
      }
      if ((right - left).abs() > left * 0.25) continue;
      x.add(left);
      y.add(right);
      timestamps.add(i.toDouble());
    }

    if (x.length < 2) {
      return PoincareData(
        x: x,
        y: y,
        timestamps: timestamps,
        meanRr: x.isEmpty ? 0.0 : x.first,
        sd1: 0.0,
        sd2: 0.0,
        ellipseX: [],
        ellipseY: [],
      );
    }

    final meanRr =
        (x.reduce((a, b) => a + b) + y.reduce((a, b) => a + b)) /
        (2 * x.length);

    final diffXy = <double>[];
    final sumXy = <double>[];
    for (var i = 0; i < x.length; i++) {
      diffXy.add(x[i] - y[i]);
      sumXy.add(x[i] + y[i]);
    }

    final mDiff = diffXy.reduce((a, b) => a + b) / diffXy.length;
    final mSum = sumXy.reduce((a, b) => a + b) / sumXy.length;

    final varDiff =
        diffXy
            .map((v) => math.pow(v - mDiff, 2).toDouble())
            .reduce((a, b) => a + b) /
        math.max(1, diffXy.length - 1);
    final varSum =
        sumXy
            .map((v) => math.pow(v - mSum, 2).toDouble())
            .reduce((a, b) => a + b) /
        math.max(1, sumXy.length - 1);

    final sd1 = math.sqrt(varDiff) / math.sqrt2;
    final sd2 = math.sqrt(varSum) / math.sqrt2;

    final ellipseX = <double>[];
    final ellipseY = <double>[];
    for (var i = 0; i <= 96; i++) {
      final angle = 2 * math.pi * i / 96;
      final long = sd2 * math.cos(angle) / math.sqrt2;
      final short = sd1 * math.sin(angle) / math.sqrt2;
      ellipseX.add(meanRr + long - short);
      ellipseY.add(meanRr + long + short);
    }

    return PoincareData(
      x: x,
      y: y,
      timestamps: timestamps,
      meanRr: meanRr,
      sd1: sd1,
      sd2: sd2,
      ellipseX: ellipseX,
      ellipseY: ellipseY,
    );
  }

  static TimeResolvedHrvResult _smoothHrvMetrics(
    SessionAnalysisResult original,
    IpfmCardiacResult ipfm,
  ) {
    final timestamps = original.hrv.timestamps;
    final rawMetrics = original.hrv.metrics;
    if (timestamps.isEmpty || rawMetrics.isEmpty) return original.hrv;

    final windowS = original.hrv.windowS;
    final halfWin = windowS / 2.0;

    // Precalculate local SQI per window from quality and sigmot traces
    final windowSqis = <double>[];
    for (final t in timestamps) {
      final tStart = math.max(0.0, t - halfWin);
      final tEnd = t + halfWin;

      var qSum = 0.0;
      var mSum = 0.0;
      var count = 0;

      final startSample = (tStart * original.sampleRate).round();
      final endSample = math.min(
        original.time.length,
        (tEnd * original.sampleRate).round(),
      );

      for (var i = startSample; i < endSample; i++) {
        if (i < original.qualityTrace.length) {
          qSum += original.qualityTrace[i];
          count++;
        }
        if (i < original.sigmotTrace.length) {
          mSum += original.sigmotTrace[i];
        }
      }

      final avgQ = count > 0 ? qSum / count : 0.5;
      final avgM = count > 0 ? mSum / count : 0.0;
      // Motion penalty: significant motion reduces trust
      final motionPenalty = (avgM / 50.0).clamp(0.0, 0.8);
      final effectiveSqi = (avgQ * (1.0 - motionPenalty)).clamp(0.05, 1.0);
      windowSqis.add(effectiveSqi);
    }

    final smoothedMetrics = <String, List<double>>{};

    rawMetrics.forEach((metricName, values) {
      final filter = SqiKalman1D(
        processVar: metricName == 'MeanHR' ? 0.05 : 0.10,
        minSqi: 0.05,
      );

      final smoothed = <double>[];
      for (var i = 0; i < values.length; i++) {
        final val = values[i];
        final sqi = i < windowSqis.length ? windowSqis[i] : 0.5;
        final res = filter.step(val, sqi);
        smoothed.add(res.isFinite ? res : val);
      }
      smoothedMetrics[metricName] = smoothed;
    });

    return TimeResolvedHrvResult(
      timestamps: timestamps,
      windowS: windowS,
      stepS: original.hrv.stepS,
      metrics: smoothedMetrics,
    );
  }

  static List<FeatureSummaryRow> _computeRefinedSummary(
    SessionAnalysisResult original,
    TimeResolvedHrvResult hrv,
    IpfmCardiacResult ipfm,
    PoincareData poincare,
  ) {
    final rows = <FeatureSummaryRow>[];

    // Compute updated stats for each HRV metric
    hrv.metrics.forEach((metricName, values) {
      final valid = values.where((v) => v.isFinite && !v.isNaN).toList()
        ..sort();
      if (valid.isEmpty) return;

      final n = valid.length;
      final mean = valid.reduce((a, b) => a + b) / n;
      final variance =
          valid.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
          math.max(1, n - 1);
      final sd = math.sqrt(variance);

      final median = n.isOdd
          ? valid[n ~/ 2]
          : 0.5 * (valid[n ~/ 2 - 1] + valid[n ~/ 2]);
      final q1 = valid[(n * 0.25).floor()];
      final q3 = valid[(n * 0.75).floor()];
      final iqr = q3 - q1;

      // Find original domain if available
      var domain = 'General';
      for (final r in original.summary) {
        if (r.metric == metricName) {
          domain = r.domain;
          break;
        }
      }

      rows.add(
        FeatureSummaryRow(
          domain: domain,
          metric: metricName,
          mean: mean,
          sd: sd,
          median: median,
          iqr: iqr,
          min: valid.first,
          max: valid.last,
          count: n,
        ),
      );
    });

    // Add IPFM Diagnostics
    final diag = ipfm.diagnostics;
    diag.forEach((k, v) {
      final displayName = k
          .replaceAll('ipfm_', 'IPFM_')
          .split('_')
          .map(
            (w) => w.length > 1
                ? '${w[0].toUpperCase()}${w.substring(1)}'
                : w.toUpperCase(),
          )
          .join('_');
      rows.add(
        FeatureSummaryRow(
          domain: 'Diagnostics',
          metric: displayName,
          mean: v,
          sd: 0.0,
          median: v,
          iqr: 0.0,
          min: v,
          max: v,
          count: 1,
        ),
      );
    });

    if (ipfm.hrBpmRobust != null) {
      rows.add(
        FeatureSummaryRow(
          domain: 'Diagnostics',
          metric: 'IPFM_Robust_HR',
          mean: ipfm.hrBpmRobust!,
          sd: 0.0,
          median: ipfm.hrBpmRobust!,
          iqr: 0.0,
          min: ipfm.hrBpmRobust!,
          max: ipfm.hrBpmRobust!,
          count: 1,
        ),
      );
    }

    return rows;
  }
}
