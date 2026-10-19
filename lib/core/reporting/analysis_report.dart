import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/ppg_models.dart';
import 'chart_svg.dart';
import 'comparison_presentation.dart';

class ReportSession {
  final String label;
  final String filename;
  final SessionAnalysisResult result;
  final double? regionStartS, regionEndS;
  final String? experimentTitle;
  final List<String> reviewNotes;
  final String? sourcePath, provenanceNote;
  const ReportSession(
    this.label,
    this.filename,
    this.result, {
    this.regionStartS,
    this.regionEndS,
    this.experimentTitle,
    this.reviewNotes = const [],
    this.sourcePath,
    this.provenanceNote,
  });
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

  static String conditionName(ReportSession s) =>
      ComparisonPresentation.condition(s.label, s.filename);
  static String reportTitle(List<ReportSession> sessions) =>
      sessions.length == 2
      ? ComparisonPresentation.title(
          conditionName(sessions[0]),
          conditionName(sessions[1]),
          sessions.first.experimentTitle,
        )
      : conditionName(sessions.first);
  static String suggestedFilename(
    List<ReportSession> sessions, {
    bool includeDetails = false,
  }) {
    final date = sessions.first.result.sessionStartDateTime ?? DateTime.now();
    if (sessions.length == 1) {
      return '${date.toIso8601String().substring(0, 10)}_${ComparisonPresentation.slug(conditionName(sessions.first))}_report.pdf';
    }
    String region(ReportSession s) => s.regionStartS == null
        ? 'full'
        : '${s.regionStartS!.toStringAsFixed(2)}-${s.regionEndS!.toStringAsFixed(2)}s';
    return ComparisonPresentation.filename(
      conditionName(sessions[0]),
      conditionName(sessions[1]),
      date,
      details: includeDetails,
      regions: 'A-${region(sessions[0])}_B-${region(sessions[1])}',
    );
  }

  static Future<Uint8List> generate(
    List<ReportSession> sessions, {
    bool includeDetails = false,
  }) async {
    if (sessions.isEmpty || sessions.length > 2) {
      throw ArgumentError('Select one or two sessions.');
    }
    if (sessions.length == 2) {
      return _comparison(sessions, includeDetails: includeDetails);
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
          ? (sessions.first.experimentTitle?.isNotEmpty == true
                ? sessions.first.experimentTitle!
                : 'Two recordings. One clear comparison.')
          : 'Your recording at a glance',
      [
        note(
          'Generated ${DateTime.now().toIso8601String().substring(0, 16)}. Scope: explicitly listed session regions. Feature epochs are recalculated within each selected region.',
        ),
        for (final session in sessions) ...[
          pw.SizedBox(height: 12),
          heading(session.label),
          note(session.filename),
          note(
            session.regionStartS == null
                ? 'Scope: full recording'
                : 'Source region: ${session.regionStartS!.toStringAsFixed(2)} to ${session.regionEndS!.toStringAsFixed(2)} seconds (elapsed). Charts use time relative to this region.',
          ),
          if (session.reviewNotes.isNotEmpty)
            note('Manual review: ${session.reviewNotes.join('; ')}'),
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
                session.result.totalWindowCount == 0
                    ? 'Recalculated from reviewed signal mask'
                    : '${session.result.acceptedWindowCount} / ${session.result.totalWindowCount}',
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
            'Signal quality across the reported region',
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

  static Future<Uint8List> _comparison(
    List<ReportSession> sessions, {
    bool includeDetails = false,
  }) async {
    final a = sessions[0], b = sessions[1];
    final names = sessions.map(conditionName).toList();
    final doc = pw.Document(
      title: clean(reportTitle(sessions)),
      author: 'CCS PPGStudio',
    );
    final ca = PdfColor.fromHex(ComparisonPresentation.colorA),
        cb = PdfColor.fromHex(ComparisonPresentation.colorB);
    final muted = PdfColor.fromHex('#526478'),
        pale = PdfColor.fromHex('#F3F6FA');
    pw.Widget text(
      String value, {
      double size = 9,
      PdfColor? color,
      bool bold = false,
    }) => pw.Text(
      clean(value),
      style: pw.TextStyle(
        fontSize: size,
        color: color ?? navy,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    );
    pw.Widget section(String label, String caption) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          text(label, size: 12, bold: true),
          text(caption, size: 8, color: muted),
        ],
      ),
    );
    String scope(ReportSession s) => s.regionStartS == null
        ? 'Full recording'
        : '${number(s.regionStartS)} - ${number(s.regionEndS)} s';
    pw.Widget condition(int index) {
      final s = sessions[index], r = s.result;
      final n = ComparisonMetric.highlights.first.count(r);
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: pale,
          border: pw.Border.all(color: index == 0 ? ca : cb, width: .8),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            text(
              '${index == 0 ? 'A' : 'B'}  ${names[index]}',
              size: 13,
              color: index == 0 ? ca : cb,
              bold: true,
            ),
            pw.SizedBox(height: 5),
            text(
              '${s.provenanceNote == null ? r.totalDurationS.toStringAsFixed(1) : '~${r.totalDurationS.toStringAsFixed(0)}'} s  |  ${r.coveragePct.toStringAsFixed(1)}% accepted  |  ${r.peaksIndices.length} beats',
              size: 8,
            ),
            pw.SizedBox(height: 3),
            text(
              '$n valid HR epoch${n == 1 ? '' : 's'}  |  ${scope(s)}',
              size: 8,
              color: muted,
            ),
          ],
        ),
      );
    }

    pw.Widget metric(ComparisonMetric m) => pw.Container(
      height: 91,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: .5),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          text('${m.title} (${m.unit})', size: 9, bold: true),
          pw.Expanded(
            child: pw.SvgImage(
              svg: ChartSvg.pairedMetric(m, a.result, b.result),
            ),
          ),
          text(
            'Valid epochs  A ${m.count(a.result)}  /  B ${m.count(b.result)}',
            size: 7,
            color: muted,
          ),
        ],
      ),
    );
    final cautions = ComparisonPresentation.cautions(a.result, b.result);
    final geometryAvailable =
        a.result.poincare.x.isNotEmpty || b.result.poincare.x.isNotEmpty;
    final ga = PoincareGeometry.forData(a.result.poincare),
        gb = PoincareGeometry.forData(b.result.poincare);
    final bounds = PoincareGeometry(
      math.min(ga.low, gb.low),
      math.max(ga.high, gb.high),
    );
    final title = reportTitle(sessions);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                text(
                  'CCS PPGSTUDIO / CONDITION COMPARISON',
                  size: 8,
                  color: muted,
                  bold: true,
                ),
                text('VISUAL SUMMARY', size: 8, color: muted),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.SizedBox(
              height: 42,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.centerLeft,
                child: text(title, size: 23, bold: true),
              ),
            ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: condition(0)),
                pw.SizedBox(width: 10),
                pw.Expanded(child: condition(1)),
              ],
            ),
            pw.SizedBox(height: 9),
            pw.Container(
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: cautions.isEmpty ? pale : PdfColor.fromHex('#FFF4DF'),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: text(
                cautions.isEmpty
                    ? 'Read as a descriptive comparison. A change is not proof of an experimental effect.'
                    : cautions.take(2).join(' '),
                size: 8.5,
              ),
            ),
            section(
              'Six measures at a glance',
              'Teal = A   Purple = B   Change = B - A',
            ),
            for (var i = 0; i < ComparisonMetric.highlights.length; i += 2)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 7),
                child: pw.Row(
                  children: [
                    pw.Expanded(child: metric(ComparisonMetric.highlights[i])),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: metric(ComparisonMetric.highlights[i + 1]),
                    ),
                  ],
                ),
              ),
            if (geometryAvailable) ...[
              section('Pulse geometry', 'Same axes for both conditions'),
              pw.SizedBox(
                width: PdfPageFormat.a4.width - 56,
                height: 150,
                child: pw.Row(
                  children: [
                    for (var i = 0; i < 2; i++)
                      pw.Expanded(
                        child: pw.SvgImage(
                          svg: ChartSvg.poincareCompact(
                            sessions[i].result.poincare,
                            bounds,
                            clean('${i == 0 ? 'A' : 'B'} - ${names[i]}'),
                            i == 0
                                ? ComparisonPresentation.colorA
                                : ComparisonPresentation.colorB,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ] else ...[
              section('Accepted signal coverage', 'Original exported values'),
              for (var i = 0; i < 2; i++)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Row(
                    children: [
                      pw.SizedBox(
                        width: 18,
                        child: text(i == 0 ? 'A' : 'B', bold: true),
                      ),
                      pw.Expanded(
                        child: pw.Stack(
                          children: [
                            pw.Container(height: 12, color: pale),
                            pw.Container(
                              height: 12,
                              width:
                                  420 *
                                  sessions[i].result.coveragePct.clamp(0, 100) /
                                  100,
                              color: i == 0 ? ca : cb,
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(
                        width: 45,
                        child: text(
                          '${sessions[i].result.coveragePct.toStringAsFixed(1)}%',
                          size: 9,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            for (var i = 0; i < 2; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: text(
                  '${i == 0 ? 'A' : 'B'}: ${sessions[i].filename} | ${scope(sessions[i])} | ${sessions[i].provenanceNote != null ? 'review not recorded in source PDF' : '${sessions[i].reviewNotes.length} manual corrections'}',
                  size: 7,
                  color: muted,
                ),
              ),
            if (sessions.any((s) => s.provenanceNote != null))
              text(
                sessions
                    .map((s) => s.provenanceNote)
                    .whereType<String>()
                    .toSet()
                    .join(' '),
                size: 7,
                color: muted,
              ),
            text(
              'PPG pulse variability; descriptive only. Bars show epoch means on a shared scale per metric. Geometry pools selected intervals. Counts are overlapping epochs. Full metrics ${includeDetails ? 'follow in the appendix' : 'are available in the optional appendix'}.',
              size: 7,
              color: muted,
            ),
            pw.SizedBox(height: 4),
            text(
              'Generated ${DateTime.now().toIso8601String().substring(0, 16)} | ${includeDetails ? 'Summary + detail appendix' : '1-page summary'}',
              size: 7,
              color: muted,
            ),
          ],
        ),
      ),
    );
    if (includeDetails) {
      final am = {for (final r in a.result.summary) r.metric: r},
          bm = {for (final r in b.result.summary) r.metric: r};
      final keys = {...am.keys, ...bm.keys}.toList()..sort();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          header: (_) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: text('Full metrics / $title', size: 14, bold: true),
          ),
          footer: (c) => text(
            'CCS PPGStudio | ${c.pageNumber} / ${c.pagesCount}',
            size: 8,
            color: muted,
          ),
          build: (_) => [
            text(
              'A: ${names[0]}    B: ${names[1]}. N = valid epochs. No statistical significance test is implied.',
              size: 9,
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: ['Metric / unit', 'A', 'B', 'Change', 'N A/B'],
              data: [
                for (final k in keys)
                  [
                    '$k (${unit(k)})',
                    number(am[k]?.mean),
                    number(bm[k]?.mean),
                    am[k] != null && bm[k] != null
                        ? number(bm[k]!.mean - am[k]!.mean)
                        : 'N/A',
                    '${am[k]?.count ?? 0}/${bm[k]?.count ?? 0}',
                  ],
              ],
              headerDecoration: pw.BoxDecoration(color: navy),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.all(4),
              border: null,
              oddRowDecoration: pw.BoxDecoration(color: pale),
            ),
            pw.SizedBox(height: 12),
            for (final note in cautions)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: text(note, size: 8),
              ),
            for (var i = 0; i < 2; i++) ...[
              pw.SizedBox(height: 10),
              text('${names[i]} / source and review', bold: true),
              text(sessions[i].filename, size: 8),
              text(
                'Pipeline: ${sessions[i].result.pipelineMode}. Region: ${scope(sessions[i])}. Start: ${sessions[i].result.sessionStartDateTime?.toIso8601String() ?? 'unknown'}.',
                size: 8,
              ),
              for (final note in sessions[i].reviewNotes) text(note, size: 8),
            ],
          ],
        ),
      );
    }
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
