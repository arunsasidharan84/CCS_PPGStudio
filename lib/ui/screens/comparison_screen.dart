import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/ppg_models.dart';
import '../../core/reporting/analysis_report.dart';
import '../../core/reporting/comparison_presentation.dart';
import '../../core/services/comparison_label_store.dart';
import '../../core/services/ppg_analysis_service.dart';
import '../../core/services/session_review_service.dart';
import '../widgets/comparison_overview.dart';
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
  final _title = TextEditingController(),
      _labelA = TextEditingController(),
      _labelB = TextEditingController();
  Timer? _saveTimer;
  String _identity(ReportSession s) => s.sourcePath ?? s.filename;
  @override
  void initState() {
    super.initState();
    _labelA.text = AnalysisReport.conditionName(widget.first);
    _labelB.text = _second == null
        ? ''
        : AnalysisReport.conditionName(_second!);
    _b = _second?.result;
    if (_b != null) _rangeB = RangeValues(0, _b!.totalDurationS);
    _labelA.addListener(_namesChanged);
    _labelB.addListener(_namesChanged);
    _title.addListener(_refresh);
    _restoreLabels();
  }

  Future<void> _restoreLabels() async {
    final initialA = _labelA.text, initialB = _labelB.text;
    try {
      final a = await ComparisonLabelStore.load(_identity(widget.first));
      final b = _second == null
          ? null
          : await ComparisonLabelStore.load(_identity(_second!));
      if (!mounted) return;
      if (a != null && _labelA.text == initialA) _labelA.text = a;
      if (b != null && _labelB.text == initialB) _labelB.text = b;
    } catch (_) {
      /* Names remain editable when preferences are unavailable. */
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _namesChanged() {
    _refresh();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      _saveLabels();
    });
  }

  Future<void> _saveLabels() async {
    try {
      await ComparisonLabelStore.save(_identity(widget.first), _labelA.text);
      if (_second != null) {
        await ComparisonLabelStore.save(_identity(_second!), _labelB.text);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not remember condition names: $e');
      }
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _labelA.dispose();
    _labelB.dispose();
    _title.dispose();
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
      var result = await PPGAnalysisService.analyzeFile(
        path,
        pipelineMode: 'standard',
      );
      final edits = await SessionReviewService.load(path);
      if (edits.isNotEmpty) {
        result = await SessionReviewService.apply(result, edits: edits);
      }
      final name = await ComparisonLabelStore.load(path);
      if (!mounted) return;
      setState(() {
        _second = ReportSession(
          'B',
          File(path).uri.pathSegments.last,
          result,
          sourcePath: path,
          reviewNotes: edits
              .map(
                (e) =>
                    '${e.include ? 'Include' : 'Exclude'} ${e.start}–${e.end} s',
              )
              .toList(),
        );
        _labelB.text =
            name ?? ComparisonPresentation.inferCondition(_second!.filename);
        _b = result;
        _rangeB = RangeValues(0, result.totalDurationS);
        _dirty = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open condition B: $e');
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
      await _saveLabels();
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

  String get _nameA => _labelA.text.trim();
  String get _nameB => _labelB.text.trim();
  bool get _validNames =>
      _nameA.isNotEmpty &&
      _nameB.isNotEmpty &&
      _nameA.toLowerCase() != _nameB.toLowerCase();
  String get _experiment =>
      ComparisonPresentation.title(_nameA, _nameB, _title.text);
  ReportSession _session(bool first) => ReportSession(
    first ? _nameA : _nameB,
    first ? widget.first.filename : _second!.filename,
    first ? _a : _b!,
    sourcePath: first ? widget.first.sourcePath : _second!.sourcePath,
    regionStartS: first ? _rangeA.start : _rangeB!.start,
    regionEndS: first ? _rangeA.end : _rangeB!.end,
    experimentTitle: _experiment,
    reviewNotes: first ? widget.first.reviewNotes : _second!.reviewNotes,
  );
  Widget _region(bool first) {
    final s = first ? widget.first : _second, range = first ? _rangeA : _rangeB;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              first ? 'A · First condition' : 'B · Second condition',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: first ? _labelA : _labelB,
              decoration: InputDecoration(
                labelText: first ? 'Condition A name' : 'Condition B name',
                hintText: first ? 'Standing pose' : 'Half-bending forward pose',
                helperText: 'Use the pose or experimental condition',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s?.filename ?? 'Choose the second recording',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (s != null && range != null)
              RegionSelector(
                duration: s.result.totalDurationS,
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
                  s == null
                      ? 'Choose condition B recording'
                      : 'Replace condition B recording',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _b != null && !_dirty;
    return Scaffold(
      appBar: AppBar(title: const Text('Compare conditions')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy || _second == null ? null : _apply,
                icon: const Icon(Icons.compare_arrows),
                label: Text(
                  ready ? 'Recalculate regions' : 'Compare selected regions',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy || !ready || !_validNames
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReportScreen(
                            sessions: [_session(true), _session(false)],
                          ),
                        ),
                      ),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('1-page visual PDF'),
              ),
            ],
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _b == null ? 'Compare two conditions' : _experiment,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Name the conditions, compare the selected regions, and share a visual summary.',
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                key: ValueKey('configure-$_dirty-${_b != null}'),
                initiallyExpanded: !ready,
                title: const Text('Condition names & selected regions'),
                subtitle: Text(
                  _b == null
                      ? 'Set up your comparison'
                      : '$_nameA vs $_nameB · Tap to edit',
                ),
                children: [
                  TextField(
                    controller: _title,
                    decoration: InputDecoration(
                      labelText: 'Experiment title (optional)',
                      hintText: ComparisonPresentation.title(_nameA, _nameB),
                      border: const OutlineInputBorder(),
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
                ],
              ),
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
              if (_b != null && !_validNames)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Give both conditions distinct names before exporting.',
                  ),
                ),
              if (_dirty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Regions changed. Compare selected regions to refresh the summary.',
                  ),
                ),
              if (ready) ...[
                const SizedBox(height: 16),
                ComparisonOverview(sessions: [_session(true), _session(false)]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
