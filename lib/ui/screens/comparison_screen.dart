import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/models/ppg_models.dart';
import '../../core/reporting/analysis_report.dart';
import '../../core/reporting/chart_svg.dart';
import '../../core/services/ppg_analysis_service.dart';
import '../../core/services/session_review_service.dart';
import '../widgets/recording_picker.dart';
import '../widgets/region_selector.dart';
import 'report_screen.dart';

class ComparisonScreen extends StatefulWidget {
  final ReportSession first;
  final ReportSession? second;
  const ComparisonScreen({super.key, required this.first, this.second});
  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  late ReportSession? _second = widget.second;
  late SessionAnalysisResult _a = widget.first.result;
  SessionAnalysisResult? _b;
  late RangeValues _rangeA = RangeValues(0, _a.totalDurationS);
  RangeValues? _rangeB;
  bool _busy = false, _dirty = false;
  String? _error;
  String _domain = 'All';
  final _title = TextEditingController(text: 'Quick experiment');
  final _labelA = TextEditingController(text: 'Baseline');
  final _labelB = TextEditingController(text: 'Intervention');
  @override
  void initState() {
    super.initState();
    _b = _second?.result;
    if (_b != null) _rangeB = RangeValues(0, _b!.totalDurationS);
  }

  @override
  void dispose() {
    _title.dispose();
    _labelA.dispose();
    _labelB.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final path = await pickRecording(context);
    if (path == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var result = await PPGAnalysisService.analyzeFile(
        path,
        pipelineMode: 'standard',
      );
      final edits = await SessionReviewService.load(path);
      if (edits.isNotEmpty) {
        result = await SessionReviewService.apply(result, edits: edits);
      }
      if (mounted) {
        setState(() {
          _second = ReportSession(
            'B',
            File(path).uri.pathSegments.last,
            result,
            reviewNotes: edits
                .map(
                  (e) =>
                      '${e.include ? 'Include' : 'Exclude'} ${e.start}–${e.end} s',
                )
                .toList(),
          );
          _b = result;
          _rangeB = RangeValues(0, result.totalDurationS);
          _dirty = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open recording B: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_second == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Recalculate both selected signals with the same pipeline and no outside epochs.
      final a = await SessionReviewService.apply(
        widget.first.result,
        start: _rangeA.start,
        end: _rangeA.end,
      );
      final b = await SessionReviewService.apply(
        _second!.result,
        start: _rangeB!.start,
        end: _rangeB!.end,
      );
      if (mounted) {
        setState(() {
          _a = a;
          _b = b;
          _dirty = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not compare regions: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ReportSession _session(bool first) => ReportSession(
    (first ? _labelA : _labelB).text.trim().isEmpty
        ? (first ? 'A' : 'B')
        : (first ? _labelA : _labelB).text.trim(),
    first ? widget.first.filename : _second!.filename,
    first ? _a : _b!,
    regionStartS: first ? _rangeA.start : _rangeB!.start,
    regionEndS: first ? _rangeA.end : _rangeB!.end,
    experimentTitle: _title.text.trim(),
    reviewNotes: first ? widget.first.reviewNotes : _second!.reviewNotes,
  );
  Widget _region(bool first) {
    final session = first ? widget.first : _second;
    final range = first ? _rangeA : _rangeB;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              first ? 'A · Baseline' : 'B · Comparison',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: first ? _labelA : _labelB,
              decoration: const InputDecoration(
                labelText: 'Session label',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              session?.filename ?? 'Choose the second session to begin',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (session != null && range != null)
              RegionSelector(
                duration: session.result.totalDurationS,
                value: range,
                onChanged: (v) => setState(() {
                  if (first) {
                    _rangeA = v;
                  } else {
                    _rangeB = v;
                  }
                  _dirty = true;
                }),
              ),
            if (!first)
              OutlinedButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.folder_open),
                label: Text(
                  session == null ? 'Choose session B' : 'Replace session B',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    String key,
    Map<String, FeatureSummaryRow> am,
    Map<String, FeatureSummaryRow> bm,
  ) {
    final a = am[key]?.mean, b = bm[key]?.mean;
    final delta = a != null && b != null ? b - a : null;
    final pct = delta != null && a!.abs() > 1e-12
        ? delta / a.abs() * 100
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key.replaceAll('_', ' '),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text('A  ${AnalysisReport.number(a)}'),
                Text('B  ${AnalysisReport.number(b)}'),
                Text(
                  'Δ  ${AnalysisReport.number(delta)} ${AnalysisReport.unit(key)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Chip(
                  avatar: Icon(
                    delta == null || delta == 0
                        ? Icons.remove
                        : delta > 0
                        ? Icons.north_east
                        : Icons.south_east,
                    size: 18,
                  ),
                  label: Text('${AnalysisReport.number(pct)}%'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions() => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      FilledButton.icon(
        onPressed: _busy || _second == null ? null : _apply,
        icon: const Icon(Icons.compare_arrows),
        label: const Text('Compare selected regions'),
      ),
      OutlinedButton.icon(
        onPressed: _busy || _b == null || _dirty
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ReportScreen(sessions: [_session(true), _session(false)]),
                ),
              ),
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('Create experiment PDF'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final am = {for (final r in _a.summary) r.metric: r};
    final bm = {
      if (_b != null)
        for (final r in _b!.summary) r.metric: r,
    };
    final keys = {...am.keys, ...bm.keys}.toList()..sort();
    final domains = {
      'All',
      ...am.values.map((r) => r.domain),
      ...bm.values.map((r) => r.domain),
    };
    final ga = PoincareGeometry.forData(_a.poincare);
    final gb = _b == null ? ga : PoincareGeometry.forData(_b!.poincare);
    final bounds = PoincareGeometry(
      ga.low < gb.low ? ga.low : gb.low,
      ga.high > gb.high ? ga.high : gb.high,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Compare sessions')),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.all(12), child: _actions()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'From baseline to insight',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose two sessions, select an independent region in each, and create a shareable experiment report.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Experiment title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              AbsorbPointer(
                absorbing: _busy,
                child: LayoutBuilder(
                  builder: (context, c) => c.maxWidth < 760
                      ? Column(children: [_region(true), _region(false)])
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _region(true)),
                            Expanded(child: _region(false)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_dirty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Selection changed. Compare selected regions to refresh results and enable the report.',
                  ),
                ),
              if (_b != null && !_dirty) ...[
                const SizedBox(height: 24),
                Text(
                  'Experiment overview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        'A · ${_a.totalDurationS.toStringAsFixed(1)} s · ${_a.coveragePct.toStringAsFixed(1)}% accepted',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'B · ${_b!.totalDurationS.toStringAsFixed(1)} s · ${_b!.coveragePct.toStringAsFixed(1)}% accepted',
                      ),
                    ),
                  ],
                ),
                if ((_a.totalDurationS - _b!.totalDurationS).abs() > 1)
                  const Text(
                    'Selected durations differ. Consider matching durations for your experiment.',
                  ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final plots = [
                      for (final entry in [(_a, 'A'), (_b!, 'B')])
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SvgPicture.string(
                              ChartSvg.poincare(
                                entry.$1.poincare,
                                bounds: bounds,
                                dark: true,
                                title: 'Session ${entry.$2}',
                              ),
                              height: 290,
                            ),
                          ),
                        ),
                    ];
                    return c.maxWidth < 650
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: plots,
                          )
                        : Row(
                            children: plots
                                .map((p) => Expanded(child: p))
                                .toList(),
                          );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'What changed?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Δ = B − A. Direction describes the change; it does not indicate benefit or statistical significance. N/A means insufficient data.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in domains)
                      ChoiceChip(
                        label: Text(d),
                        selected: _domain == d,
                        onSelected: (_) => setState(() => _domain = d),
                      ),
                  ],
                ),
                if (keys.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No valid feature epochs in these regions. Select a longer region with accepted signal.',
                    ),
                  ),
                for (final k in keys.where(
                  (k) =>
                      _domain == 'All' ||
                      (am[k]?.domain ?? bm[k]?.domain) == _domain,
                ))
                  _metric(k, am, bm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
