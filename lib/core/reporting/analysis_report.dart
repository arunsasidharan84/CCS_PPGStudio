import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/ppg_models.dart';
import 'chart_svg.dart';

class ReportSession {
  final String label;
  final String filename;
  final SessionAnalysisResult result;
  const ReportSession(this.label, this.filename, this.result);
}

class AnalysisReport {
  static final navy = PdfColor.fromHex('#10233F');
  static final blue = PdfColor.fromHex('#0284C7');
  static String number(double? v) => v == null || !v.isFinite
      ? 'N/A'
      : v.abs() >= 1000
      ? v.toStringAsFixed(1)
      : v.abs() < .01 && v != 0
      ? v.toStringAsExponential(2)
      : v.toStringAsFixed(2);
  static String unit(String metric) {
    if (metric == 'MeanHR') return 'bpm';
    if (['MeanNN', 'SDNN', 'RMSSD', 'SD1', 'SD2'].contains(metric)) return 'ms';
    if (['LF', 'HF', 'VLF', 'Total_Power'].contains(metric)) return 'ms^2';
    if (metric.startsWith('pNN')) return '%';
    if (metric == 'Skin_Temperature') return 'deg C';
    if (metric == 'Activity_Motion') return 'count';
    return 'ratio / a.u.';
  }

  static String clean(String text) => text
      .replaceAll('±', '+/-')
      .replaceAll('°', 'deg ')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'[^\x20-\x7E\n]'), '');

  static Future<Uint8List> generate(List<ReportSession> sessions) async {
    if (sessions.isEmpty || sessions.length > 2) {
      throw ArgumentError('Select one or two sessions.');
    }
    final doc = pw.Document(
      title: sessions.length == 2
          ? 'PPG comparison report'
          : 'PPG session report',
      author: 'CCS PPGStudio',
    );
    final comparison = sessions.length == 2;
    pw.Widget heading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Text(
        clean(text),
        style: pw.TextStyle(
          fontSize: 19,
          color: navy,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
    pw.Widget note(String text) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Text(
        clean(text),
        style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
      ),
    );
    pw.Widget chart(String svg, {double height = 160}) => pw.SizedBox(
      height: height,
      child: pw.SvgImage(svg: svg, fit: pw.BoxFit.contain),
    );
    void page(String title, List<pw.Widget> body) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
          header: (_) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 16),
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: blue, width: 2)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'CCS PPGStudio',
                  style: pw.TextStyle(
                    color: navy,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  comparison ? 'SESSION COMPARISON' : 'SESSION ANALYSIS',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
          footer: (ctx) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'PPG-derived pulse variability | Research report',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                '${ctx.pageNumber} / ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
          build: (_) => [heading(title), ...body],
        ),
      );
    }

    pw.Widget table(List<String> headers, List<List<String>> rows) =>
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: pw.BoxDecoration(color: navy),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
          cellPadding: const pw.EdgeInsets.all(6),
          border: null,
        );

    page(
      comparison
          ? 'Two recordings. One clear comparison.'
          : 'Your recording at a glance',
      [
        note(
          'Generated ${DateTime.now().toIso8601String().substring(0, 16)}. Scope: full recordings. App display zoom or selection does not trim this report.',
        ),
        for (final session in sessions) ...[
          pw.SizedBox(height: 12),
          heading(session.label),
          note(session.filename),
          table(
            ['Session', 'Value'],
            [
              [
                'Recording start',
                session.result.sessionStartDateTime?.toIso8601String() ??
                    'Unknown - elapsed time only',
              ],
              [
                'Duration',
                '${(session.result.totalDurationS / 60).toStringAsFixed(1)} minutes',
              ],
              ['Analysis sample rate', '${session.result.sampleRate} Hz'],
              [
                'Pipeline mode',
                session.result.pipelineMode == 'ipfm_kalman'
                    ? 'Quality-Aware IPFM + Kalman Refinement'
                    : 'Standard Refractory SQI',
              ],
              if (session.result.ipfmDiagnostics != null) ...[
                [
                  'IPFM beats removed / filled',
                  '${session.result.ipfmDiagnostics!['ipfm_beats_removed']?.toInt() ?? 0} spurious / ${session.result.ipfmDiagnostics!['ipfm_beats_inserted']?.toInt() ?? 0} gap-filled',
                ],
                [
                  'IPFM continuous segments',
                  '${session.result.ipfmDiagnostics!['ipfm_segments']?.toInt() ?? 0} segments (${session.result.ipfmDiagnostics!['ipfm_chain_breaks']?.toInt() ?? 0} breaks)',
                ],
              ],
              ['Accepted signal', '${number(session.result.coveragePct)}%'],
              ['Accepted beats', '${session.result.peaksIndices.length}'],
              [
                'Accepted quality windows',
                '${session.result.acceptedWindowCount} / ${session.result.totalWindowCount}',
              ],
              [
                'Feature epochs',
                '${session.result.hrv.windowS.toStringAsFixed(0)} s, step ${session.result.hrv.stepS.toStringAsFixed(0)} s',
              ],
            ],
          ),
        ],
        note(
          'Quality screening excludes unreliable signal before pulse variability analysis. Missing values are shown as N/A. These are PPG-derived intervals, not ECG-confirmed normal-to-normal intervals. Changes may reflect recording quality, duration, activity and sensor conditions.',
        ),
      ],
    );

    if (comparison) {
      final a = {for (final r in sessions[0].result.summary) r.metric: r};
      final b = {for (final r in sessions[1].result.summary) r.metric: r};
      final keys = {...a.keys, ...b.keys}.toList()..sort();
      final domains = keys.map((k) => a[k]?.domain ?? b[k]!.domain).toSet();
      for (final domain in domains) {
        final metrics = keys
            .where((k) => (a[k]?.domain ?? b[k]!.domain) == domain)
            .toList();
        page('$domain - comparison', [
          note(
            'A: ${sessions[0].label}. B: ${sessions[1].label}. Values are means of available epochs; delta = B - A. Percent change uses abs(A) and is N/A when A is zero. Colors encode relative magnitude within each metric, not health or statistical significance.',
          ),
          table(
            ['Metric / unit', 'A', 'B', 'Delta', 'Change %'],
            [
              for (final k in metrics)
                [
                  '$k\n${unit(k)}',
                  number(a[k]?.mean),
                  number(b[k]?.mean),
                  a[k] != null && b[k] != null
                      ? number(b[k]!.mean - a[k]!.mean)
                      : 'N/A',
                  a[k] != null && b[k] != null && a[k]!.mean.abs() > 1e-12
                      ? number(
                          100 * (b[k]!.mean - a[k]!.mean) / a[k]!.mean.abs(),
                        )
                      : 'N/A',
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          for (var start = 0; start < metrics.length; start += 5)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Row(
                children: [
                  for (final k in metrics.skip(start).take(5))
                    pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: pw.Column(
                          children: [
                            pw.Text(
                              k,
                              style: const pw.TextStyle(fontSize: 8),
                              textAlign: pw.TextAlign.center,
                            ),
                            for (final v in [a[k]?.mean, b[k]?.mean])
                              pw.Container(
                                width: double.infinity,
                                padding: const pw.EdgeInsets.all(7),
                                decoration: pw.BoxDecoration(
                                  color: v == null || !v.isFinite
                                      ? PdfColors.grey200
                                      : (a[k]?.mean == b[k]?.mean
                                            ? PdfColors.blue100
                                            : v ==
                                                  math.max(
                                                    a[k]?.mean ?? v,
                                                    b[k]?.mean ?? v,
                                                  )
                                            ? navy
                                            : PdfColors.blue50),
                                ),
                                child: pw.Text(
                                  number(v),
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    color:
                                        v != null &&
                                            v.isFinite &&
                                            a[k]?.mean != b[k]?.mean &&
                                            v ==
                                                math.max(
                                                  a[k]?.mean ?? v,
                                                  b[k]?.mean ?? v,
                                                )
                                        ? PdfColors.white
                                        : navy,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ]);
      }
    }

    final bounds = sessions
        .map((s) => PoincareGeometry.forData(s.result.poincare))
        .toList();
    final shared = PoincareGeometry(
      bounds.map((g) => g.low).reduce(math.min),
      bounds.map((g) => g.high).reduce(math.max),
    );
    for (final session in sessions) {
      final r = session.result;
      page('${session.label} - pulse geometry', [
        chart(ChartSvg.poincare(r.poincare, bounds: shared), height: 345),
        note(
          'SD1 describes short-term dispersion; SD2 describes long-term dispersion. Red and amber lines show the respective one-SD axes. Density is smoothed across occupied bins. Both comparison sessions use identical axis limits. ${r.poincare.x.length} adjacent accepted interval pairs.',
        ),
        chart(
          ChartSvg.line(
            r.time,
            r.qualityTrace,
            'Signal quality across the full recording',
            unit: '0-1 score',
          ),
          height: 145,
        ),
      ]);
      // Show the longest accepted episode plus an explicit rejected example.
      final good = r.segments.where((s) => s.isGood).toList()
        ..sort((a, b) => b.durationS.compareTo(a.durationS));
      final bad = r.segments.where((s) => !s.isGood).toList()
        ..sort((a, b) => b.durationS.compareTo(a.durationS));
      page('${session.label} - waveform review', [
        for (final entry in [
          (good, 'Accepted signal'),
          (bad, 'Rejected / uncertain signal'),
        ]) ...[
          if (entry.$1.isNotEmpty) ...[
            note(
              '${entry.$2}: excerpt from the longest matching episode. ${entry.$1.first.reason ?? ''}',
            ),
            chart(_waveform(r, entry.$1.first.onsetS, entry.$2), height: 170),
          ] else
            note('${entry.$2}: no matching episode.'),
        ],
        chart(
          ChartSvg.line(
            r.hrv.timestamps,
            r.hrv.metrics['MeanHR'] ?? [],
            'Heart rate',
            unit: 'bpm',
          ),
          height: 150,
        ),
      ]);
      final domains = r.summary.map((row) => row.domain).toSet();
      for (final domain in domains) {
        page('${session.label} - $domain statistics', [
          note(
            'All available features. N counts valid epochs; overlapping epochs are not independent observations. Frequency-domain estimates use ${r.hrv.windowS.toStringAsFixed(0)}-second windows; VLF and longer-term components require longer recordings for reliable interpretation.',
          ),
          table(
            ['Metric / unit', 'Mean +/- SD', 'Median / IQR', 'Min / Max', 'N'],
            [
              for (final row in r.summary.where((row) => row.domain == domain))
                [
                  '${row.metric}\n${unit(row.metric)}',
                  '${number(row.mean)} +/- ${number(row.sd)}',
                  '${number(row.median)} / ${number(row.iqr)}',
                  '${number(row.min)} / ${number(row.max)}',
                  '${row.count}',
                ],
            ],
          ),
        ]);
      }
      final keys = r.hrv.metrics.keys.toList();
      for (var i = 0; i < keys.length; i += 4) {
        page('${session.label} - feature trajectories', [
          for (final key in keys.skip(i).take(4))
            chart(
              ChartSvg.line(
                r.hrv.timestamps,
                r.hrv.metrics[key]!,
                key.replaceAll('_', ' '),
                unit: unit(key),
              ),
              height: 153,
            ),
        ]);
      }
    }
    page('Methods and reading this report', [
      note(
        'The pipeline resamples PPG onto a uniform grid, applies zero-phase bandpass filtering, rejects structural defects and scores overlapping quality windows. Accepted pulses are used for interval statistics. Poincare pairs require consecutive valid intervals; rejected gaps must not create new neighbors.',
      ),
      note(
        'Quality-Aware IPFM & Kalman Mode: Uses Integral Pulse Frequency Modulation (IPFM) beat cleaning to remove spurious motion beats (< 60% of local median), breaks ambiguous gaps, and infers trusted micro-dropouts (<= 4 beats) without deflating variability (rrRealMs). Scalar SQI-weighted Kalman filtering scales observation variance by 1/SQI, allowing continuous feature tracking through transient artifacts.',
      ),
      note(
        'Comparison is descriptive, not a significance test. It includes all available metrics; absent channels remain N/A. Large changes should be reviewed alongside accepted-signal coverage and waveform examples. No universal normal ranges are applied across differing ages, activities, recording lengths and sensor types.',
      ),
      note(
        'References: Charlton et al. (2022), Detecting beats in the photoplethysmogram: benchmarking open-source algorithms. Physiological Measurement 43, 085007. doi:10.1088/1361-6579/ac826d.',
      ),
      note(
        'Elgendi et al. (2013), Systolic peak detection in acceleration photoplethysmograms. PLoS ONE 8, e76585. doi:10.1371/journal.pone.0076585.',
      ),
      note(
        'Charlton et al. (2025), The MSPTDfast photoplethysmography beat detection algorithm: design, benchmarking, and open-source distribution. doi:10.1088/1361-6579/adb89e. Consulted for detector evaluation and quality assessment; this application is not an implementation of MSPTDfast.',
      ),
    ]);
    return doc.save();
  }

  static String _waveform(SessionAnalysisResult r, double start, String title) {
    final indices = <int>[];
    for (var i = 0; i < r.time.length; i++) {
      if (r.time[i] >= start && r.time[i] <= start + 30) indices.add(i);
    }
    return ChartSvg.line(
      indices.map((i) => r.time[i]).toList(),
      indices.map((i) => r.normPpg[i]).toList(),
      title,
      unit: 'normalized PPG',
    );
  }
}
