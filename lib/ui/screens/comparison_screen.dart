import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/reporting/analysis_report.dart';
import '../../core/reporting/chart_svg.dart';
import '../../core/services/ppg_analysis_service.dart';
import '../widgets/recording_picker.dart';
import 'report_screen.dart';

class ComparisonScreen extends StatefulWidget {
  final ReportSession first;
  const ComparisonScreen({super.key, required this.first});
  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  ReportSession? _second;
  bool _busy = false;
  String? _error;
  final _labelA = TextEditingController(text: 'Baseline');
  final _labelB = TextEditingController(text: 'Comparison');
  @override
  void dispose() {
    _labelA.dispose();
    _labelB.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final path = await pickRecording(context);
      if (path == null || !mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final result = await PPGAnalysisService.analyzeFile(path);
      if (mounted) {
        setState(
          () => _second = ReportSession(
            'Comparison',
            File(path).uri.pathSegments.last,
            result,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _compareWithAlternativePipeline() {
    final a = widget.first.result;
    final isAStandard = a.pipelineMode != 'ipfm_kalman';
    final targetMode = isAStandard ? 'ipfm_kalman' : 'standard';
    final b = PPGAnalysisService.applyPipeline(a, targetMode);
    setState(() {
      _labelA.text = isAStandard
          ? 'Standard (Refractory SQI)'
          : 'IPFM + Kalman Refined';
      _labelB.text = isAStandard
          ? 'IPFM + Kalman Refined'
          : 'Standard (Refractory SQI)';
      _second = ReportSession(
        _labelB.text,
        '${widget.first.filename} [${isAStandard ? "IPFM+Kalman" : "Standard"}]',
        b,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.first.result;
    final b = _second?.result;
    final am = {for (final row in a.summary) row.metric: row};
    final bm = {
      if (b != null)
        for (final row in b.summary) row.metric: row,
    };
    final keys = {...am.keys, ...bm.keys}.toList()..sort();
    final ga = PoincareGeometry.forData(a.poincare);
    final gb = b == null ? ga : PoincareGeometry.forData(b.poincare);
    final bounds = PoincareGeometry(
      ga.low < gb.low ? ga.low : gb.low,
      ga.high > gb.high ? ga.high : gb.high,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare recordings'),
        actions: [
          IconButton(
            tooltip: 'Comparison PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: b == null || _busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportScreen(
                        sessions: [
                          ReportSession(
                            _labelA.text.trim().isEmpty
                                ? 'A'
                                : _labelA.text.trim(),
                            widget.first.filename,
                            a,
                          ),
                          ReportSession(
                            _labelB.text.trim().isEmpty
                                ? 'B'
                                : _labelB.text.trim(),
                            _second!.filename,
                            b,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Compare full recordings. Review coverage and duration alongside metric changes.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelA,
            decoration: InputDecoration(
              labelText: 'Recording A label',
              helperText: widget.first.filename,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelB,
            decoration: InputDecoration(
              labelText: 'Recording B label',
              helperText: _second?.filename ?? 'Choose a second recording',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.folder_open),
                label: Text(
                  _busy
                      ? 'Analyzing second recording...'
                      : 'Choose recording B',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _compareWithAlternativePipeline,
                icon: const Icon(Icons.compare_arrows),
                label: Text(
                  widget.first.result.pipelineMode == 'ipfm_kalman'
                      ? 'Compare with Standard Pipeline'
                      : 'Compare with IPFM+Kalman Pipeline',
                ),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          if (b != null) ...[
            const SizedBox(height: 16),
            Text(
              'Coverage A: ${a.coveragePct.toStringAsFixed(1)}%  |  B: ${b.coveragePct.toStringAsFixed(1)}%',
            ),
            Text(
              'Duration A: ${(a.totalDurationS / 60).toStringAsFixed(1)} min  |  B: ${(b.totalDurationS / 60).toStringAsFixed(1)} min',
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final plots = [
                  SvgPicture.string(
                    ChartSvg.poincare(
                      a.poincare,
                      bounds: bounds,
                      dark: true,
                      title: 'Recording A',
                    ),
                    height: 330,
                  ),
                  SvgPicture.string(
                    ChartSvg.poincare(
                      b.poincare,
                      bounds: bounds,
                      dark: true,
                      title: 'Recording B',
                    ),
                    height: 330,
                  ),
                ];
                return constraints.maxWidth < 650
                    ? Column(children: plots)
                    : Row(
                        children: plots.map((p) => Expanded(child: p)).toList(),
                      );
              },
            ),
            const Text(
              'Feature means and change (B - A)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Text(
              'A higher value is not necessarily better. N/A means the feature was unavailable.',
            ),
            for (final key in keys)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        key.replaceAll('_', ' '),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          Text('A: ${AnalysisReport.number(am[key]?.mean)}'),
                          Text('B: ${AnalysisReport.number(bm[key]?.mean)}'),
                          Text(
                            'Delta: ${am[key] != null && bm[key] != null ? AnalysisReport.number(bm[key]!.mean - am[key]!.mean) : 'N/A'}',
                          ),
                          Text(AnalysisReport.unit(key)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
