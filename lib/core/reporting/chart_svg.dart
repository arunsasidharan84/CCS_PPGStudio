import 'dart:math' as math;
import '../models/ppg_models.dart';

String xmlText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

class PoincareGeometry {
  final double low;
  final double high;
  static const left = 62.0, top = 34.0, side = 310.0;
  const PoincareGeometry(this.low, this.high);
  factory PoincareGeometry.forData(PoincareData data) {
    final points = [...data.x, ...data.y].where((v) => v.isFinite).toList();
    if (points.isEmpty) return const PoincareGeometry(400, 1400);
    final lo = points.reduce(math.min);
    final hi = points.reduce(math.max);
    final padding = math.max(50.0, (hi - lo) * .12);
    return PoincareGeometry(math.max(0, lo - padding), hi + padding);
  }
  double x(double v) => left + (v - low) / (high - low) * side;
  double y(double v) => top + side - (v - low) / (high - low) * side;
}

class ChartSvg {
  static String poincare(
    PoincareData data, {
    bool dark = false,
    PoincareGeometry? bounds,
    String title = 'Poincare - successive intervals',
  }) {
    final g = bounds ?? PoincareGeometry.forData(data);
    final ink = dark ? '#dbeafe' : '#24364b';
    final grid = dark ? '#263548' : '#e2e8f0';
    final s = StringBuffer(
      '<svg xmlns="http://www.w3.org/2000/svg" width="420" height="400" viewBox="0 0 420 400">',
    );
    s.write(
      '<rect width="420" height="400" rx="12" fill="${dark ? '#0b1220' : '#ffffff'}"/>',
    );
    void text(
      double x,
      double y,
      String t, {
      int size = 11,
      String? color,
    }) => s.write(
      '<text x="$x" y="$y" font-family="Helvetica" font-size="$size" fill="${color ?? ink}">${xmlText(t)}</text>',
    );
    text(62, 19, title, size: 13);
    for (var i = 0; i <= 4; i++) {
      final v = g.low + (g.high - g.low) * i / 4;
      s.write(
        '<path d="M ${g.x(v)} 34 V 344 M 62 ${g.y(v)} H 372" stroke="$grid" stroke-width=".6"/>',
      );
      text(g.x(v) - 13, 361, v.toStringAsFixed(0));
      text(18, g.y(v) + 4, v.toStringAsFixed(0));
    }
    text(175, 382, 'RR[i] (ms)');
    s.write(
      '<text transform="translate(12 235) rotate(-90)" font-size="11" fill="$ink">RR[i+1] (ms)</text>',
    );
    s.write(
      '<path d="M 62 344 L 372 34" stroke="#94a3b8" stroke-dasharray="5 4"/>',
    );
    if (data.x.isEmpty) {
      text(82, 185, 'Insufficient adjacent accepted intervals');
    } else {
      // Gaussian smoothing of occupied bins, not a Gaussian confidence ellipse.
      const bins = 32;
      final density = List.filled(bins * bins, 0.0);
      for (var i = 0; i < math.min(data.x.length, data.y.length); i++) {
        final bx = ((data.x[i] - g.low) / (g.high - g.low) * bins).floor();
        final by = ((data.y[i] - g.low) / (g.high - g.low) * bins).floor();
        for (var dx = -2; dx <= 2; dx++) {
          for (var dy = -2; dy <= 2; dy++) {
            final x = bx + dx, y = by + dy;
            if (x >= 0 && x < bins && y >= 0 && y < bins) {
              density[y * bins + x] += math.exp(-(dx * dx + dy * dy) / 2.0);
            }
          }
        }
      }
      final maxD = density.reduce(math.max);
      if (maxD > 0) {
        for (var y = 0; y < bins; y++) {
          for (var x = 0; x < bins; x++) {
            final level = density[y * bins + x] / maxD;
            if (level < .035) continue;
            s.write(
              '<rect x="${62 + x * 310 / bins}" y="${34 + (bins - y - 1) * 310 / bins}" width="${310 / bins + .1}" height="${310 / bins + .1}" fill="#38bdf8" fill-opacity="${(.1 + .65 * level).toStringAsFixed(3)}"/>',
            );
          }
        }
      }
      // Bound SVG size for overnight recordings while preserving density of all pairs.
      final step = math.max(1, (data.x.length / 1800).ceil());
      for (var i = 0; i < math.min(data.x.length, data.y.length); i += step) {
        s.write(
          '<circle cx="${g.x(data.x[i])}" cy="${g.y(data.y[i])}" r="1.25" fill="$ink" fill-opacity=".5"/>',
        );
      }
      // One-standard-deviation ellipse; equal scales preserve its true angle.
      final path = StringBuffer();
      for (var i = 0; i <= 96; i++) {
        final angle = 2 * math.pi * i / 96;
        final long = data.sd2 * math.cos(angle) / math.sqrt2;
        final short = data.sd1 * math.sin(angle) / math.sqrt2;
        path.write(
          '${i == 0 ? 'M' : 'L'} ${g.x(data.meanRr + long - short)} ${g.y(data.meanRr + long + short)} ',
        );
      }
      s.write(
        '<path d="${path}Z" fill="none" stroke="#0284c7" stroke-width="1.3"/>',
      );
      void axis(double dx, double dy, String color) => s.write(
        '<path d="M ${g.x(data.meanRr - dx)} ${g.y(data.meanRr - dy)} L ${g.x(data.meanRr + dx)} ${g.y(data.meanRr + dy)}" stroke="$color" stroke-width="2.4"/>',
      );
      axis(data.sd1 / math.sqrt2, -data.sd1 / math.sqrt2, '#ef4444');
      axis(data.sd2 / math.sqrt2, data.sd2 / math.sqrt2, '#f59e0b');
      text(68, 49, 'SD1 ${data.sd1.toStringAsFixed(1)} ms', color: '#ef4444');
      text(68, 64, 'SD2 ${data.sd2.toStringAsFixed(1)} ms', color: '#d97706');
    }
    text(62, 397, 'Shading: relative point density | ellipse: 1 SD', size: 9);
    return '$s</svg>';
  }

  static String line(
    List<double> times,
    List<double> values,
    String title, {
    String color = '#0284c7',
    String unit = '',
    double? gapS,
  }) {
    final n = math.min(times.length, values.length);
    final finite = values.take(n).where((v) => v.isFinite).toList();
    final s = StringBuffer(
      '<svg xmlns="http://www.w3.org/2000/svg" width="720" height="180" viewBox="0 0 720 180"><rect width="720" height="180" fill="#ffffff"/>',
    );
    void text(double x, double y, String value, {int size = 11}) => s.write(
      '<text x="$x" y="$y" font-family="Helvetica" font-size="$size" fill="#334155">${xmlText(value)}</text>',
    );
    text(54, 17, title, size: 13);
    if (finite.isEmpty || n < 2) {
      text(54, 90, 'No valid data');
      return '$s</svg>';
    }
    var lo = finite.reduce(math.min), hi = finite.reduce(math.max);
    final pad = math.max((hi - lo) * .08, .01);
    lo -= pad;
    hi += pad;
    final t0 = times.first, span = math.max(times[n - 1] - t0, .001);
    double x(int i) => 54 + (times[i] - t0) / span * 650;
    double y(int i) => 144 - (values[i] - lo) / (hi - lo) * 115;
    for (var i = 0; i <= 2; i++) {
      final yy = 144 - i * 57.5;
      s.write('<path d="M54 $yy H704" stroke="#e2e8f0"/>');
      text(1, yy + 3, (lo + (hi - lo) * i / 2).toStringAsFixed(1));
    }
    // Envelope decimation retains extrema rather than hiding brief artifacts.
    final indices = <int>{0, n - 1};
    final stride = math.max(1, (n / 650).ceil());
    for (var a = 0; a < n; a += stride) {
      int? low, high;
      for (var j = a; j < math.min(a + stride, n); j++) {
        if (!values[j].isFinite) {
          indices.add(j);
          continue;
        }
        if (low == null || values[j] < values[low]) low = j;
        if (high == null || values[j] > values[high]) high = j;
      }
      if (low != null) indices.add(low);
      if (high != null) indices.add(high);
    }
    final sorted = indices.toList()..sort();
    final path = StringBuffer();
    var move = true;
    int? previous;
    for (final i in sorted) {
      if (!values[i].isFinite) {
        move = true;
        continue;
      }
      if (previous != null &&
          gapS != null &&
          times[i] - times[previous] > gapS) {
        move = true;
      }
      path.write(
        '${move ? 'M' : 'L'}${x(i).toStringAsFixed(2)} ${y(i).toStringAsFixed(2)} ',
      );
      move = false;
      previous = i;
    }
    s.write('<path d="$path" fill="none" stroke="$color" stroke-width="1"/>');
    text(54, 163, '${t0.toStringAsFixed(0)} s');
    text(636, 163, '${times[n - 1].toStringAsFixed(0)} s');
    text(
      310,
      177,
      'Elapsed time (s)${unit.isEmpty ? '' : ' | $unit'}',
      size: 10,
    );
    return '$s</svg>';
  }
}
