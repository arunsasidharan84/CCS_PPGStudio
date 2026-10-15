import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/ppg_models.dart';
import '../../core/services/session_review_service.dart';
import '../widgets/region_selector.dart';
import '../widgets/waveform_viewer.dart';

class ReviewOutcome {
  final SessionAnalysisResult result;
  final List<ReviewEdit> edits;
  const ReviewOutcome(this.result, this.edits);
}

class ReviewScreen extends StatefulWidget {
  final SessionAnalysisResult original, current;
  final List<ReviewEdit> edits;
  final String? path;
  const ReviewScreen({
    super.key,
    required this.original,
    required this.current,
    required this.edits,
    this.path,
  });
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late SessionAnalysisResult _result = widget.current;
  late List<ReviewEdit> _edits = List.of(widget.edits);
  final List<List<ReviewEdit>> _history = [];
  late RangeValues _range = RangeValues(
    0,
    math.min(30.0, _result.totalDurationS),
  );
  bool _busy = false;
  String? _error;
  Future<void> _apply(List<ReviewEdit> next, {bool undo = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = next.isEmpty
          ? widget.original
          : await SessionReviewService.apply(widget.original, edits: next);
      if (widget.path != null) {
        await SessionReviewService.save(widget.path!, next);
      }
      if (!mounted) return;
      setState(() {
        if (undo) {
          _history.removeLast();
        } else {
          _history.add(List.of(_edits));
        }
        _edits = next;
        _result = result;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Correction could not be saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _actions() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FilledButton.icon(
        onPressed: _busy
            ? null
            : () => _apply([
                ..._edits,
                ReviewEdit(_range.start, _range.end, true),
              ]),
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Include region'),
      ),
      OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => _apply([
                ..._edits,
                ReviewEdit(_range.start, _range.end, false),
              ]),
        icon: const Icon(Icons.block),
        label: const Text('Exclude region'),
      ),
      OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => _apply(
                SessionReviewService.revert(_edits, _range.start, _range.end),
              ),
        icon: const Icon(Icons.restore),
        label: const Text('Revert region'),
      ),
      TextButton.icon(
        onPressed: _busy || _history.isEmpty
            ? null
            : () => _apply(_history.last, undo: true),
        icon: const Icon(Icons.undo),
        label: const Text('Undo'),
      ),
      TextButton(
        onPressed: _busy || _edits.isEmpty ? null : () => _apply([]),
        child: const Text('Reset all'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy) {
        Navigator.pop(context, ReviewOutcome(_result, _edits));
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Review detections'),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.pop(context, ReviewOutcome(_result, _edits)),
            child: const Text('Done'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.all(12), child: _actions()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'You control what counts',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Select a region, then include or exclude its detections. Revert restores the app’s original decision in that region. Missing or structurally damaged samples remain unavailable.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              Chip(
                label: Text(
                  '${_result.coveragePct.toStringAsFixed(1)}% accepted',
                ),
              ),
              Chip(label: Text('${_result.peaksIndices.length} beats')),
              Chip(label: Text('${_edits.length} manual corrections')),
            ],
          ),
          const SizedBox(height: 12),
          AbsorbPointer(
            absorbing: _busy,
            child: RegionSelector(
              duration: _result.totalDurationS,
              value: _range,
              onChanged: (v) => setState(() => _range = v),
            ),
          ),
          SizedBox(
            height: 300,
            child: WaveformViewer(
              result: _result,
              currentStartS: _range.start,
              windowDurationS: _range.end - _range.start,
              onSeek: (s) {
                final width = _range.end - _range.start;
                final start = s.clamp(
                  0.0,
                  math.max(0.0, _result.totalDurationS - width),
                );
                setState(
                  () => _range = RangeValues(
                    start.toDouble(),
                    (start + width).toDouble(),
                  ),
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 20),
          Text(
            'Quality episodes · tap to review',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final segment in _result.segments)
            Card(
              child: ListTile(
                leading: Icon(
                  segment.isGood ? Icons.check_circle : Icons.info_outline,
                ),
                title: Text(
                  '${segment.onsetS.toStringAsFixed(1)}–${segment.endS.toStringAsFixed(1)} s · ${segment.isGood ? 'Included' : 'Excluded'}',
                ),
                subtitle: Text(segment.reason ?? segment.description),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy || segment.durationS <= 0
                    ? null
                    : () => setState(
                        () =>
                            _range = RangeValues(segment.onsetS, segment.endS),
                      ),
              ),
            ),
        ],
      ),
    ),
  );
}
