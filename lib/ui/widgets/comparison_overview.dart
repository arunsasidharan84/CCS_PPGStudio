import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/reporting/analysis_report.dart';
import '../../core/reporting/chart_svg.dart';
import '../../core/reporting/comparison_presentation.dart';

class ComparisonOverview extends StatefulWidget {
  final List<ReportSession> sessions;
  const ComparisonOverview({super.key, required this.sessions});
  @override
  State<ComparisonOverview> createState() => _ComparisonOverviewState();
}

class _ComparisonOverviewState extends State<ComparisonOverview> {
  String _domain = 'All';
  static const colors = [Color(0xFF27C5C8), Color(0xFFB69AF6)];
  Widget _condition(int i) {
    final s = widget.sessions[i], r = s.result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${i == 0 ? 'A' : 'B'} · ${AnalysisReport.conditionName(s)}',
              style: TextStyle(
                color: colors[i],
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${r.coveragePct.toStringAsFixed(1)}% accepted · ${r.totalDurationS.toStringAsFixed(1)} s · ${r.peaksIndices.length} beats',
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: r.coveragePct.clamp(0, 100) / 100,
              color: colors[i],
              backgroundColor: colors[i].withValues(alpha: .12),
              minHeight: 6,
            ),
            const SizedBox(height: 8),
            Text(
              '${ComparisonMetric.highlights.first.count(r)} valid heart-rate epochs',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(ComparisonMetric m) {
    final a = widget.sessions[0].result, b = widget.sessions[1].result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${m.title} (${m.unit})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Semantics(
              label:
                  '${m.title}. ${AnalysisReport.conditionName(widget.sessions[0])}: ${ComparisonMetric.number(m.value(a))} ${m.unit}. ${AnalysisReport.conditionName(widget.sessions[1])}: ${ComparisonMetric.number(m.value(b))} ${m.unit}. ${m.change(a, b)}.',
              child: SvgPicture.string(
                ChartSvg.pairedMetric(m, a, b, dark: true),
                height: 100,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
            Text(
              'Valid epochs: A ${m.count(a)} · B ${m.count(b)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.sessions[0].result, b = widget.sessions[1].result;
    final cautions = ComparisonPresentation.cautions(a, b);
    final am = {for (final r in a.summary) r.metric: r},
        bm = {for (final r in b.summary) r.metric: r};
    final keys = {...am.keys, ...bm.keys}.toList()..sort();
    final domains = {
      'All',
      ...am.values.map((r) => r.domain),
      ...bm.values.map((r) => r.domain),
    };
    final ga = PoincareGeometry.forData(a.poincare),
        gb = PoincareGeometry.forData(b.poincare);
    final bounds = PoincareGeometry(
      ga.low < gb.low ? ga.low : gb.low,
      ga.high > gb.high ? ga.high : gb.high,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 650
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_condition(0), _condition(1)],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _condition(0)),
                    Expanded(child: _condition(1)),
                  ],
                ),
        ),
        if (cautions.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF392E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF8B6B32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Read the signal quality first',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD69A),
                  ),
                ),
                for (final note in cautions)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(note),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Six measures at a glance',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text(
          'Teal = A · Purple = B. Bars show epoch means on a shared scale per measure. Change = B − A; direction does not indicate benefit.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth >= 1000
                ? 3
                : c.maxWidth >= 600
                ? 2
                : 1;
            final width = (c.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in ComparisonMetric.highlights)
                  SizedBox(width: width, child: _metric(m)),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Pulse geometry'),
          subtitle: const Text('Side-by-side plots with identical axes'),
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final plots = [
                  for (var i = 0; i < 2; i++)
                    SvgPicture.string(
                      ChartSvg.poincare(
                        widget.sessions[i].result.poincare,
                        bounds: bounds,
                        dark: true,
                        title: AnalysisReport.conditionName(widget.sessions[i]),
                      ),
                      height: 260,
                    ),
                ];
                return c.maxWidth < 650
                    ? Column(children: plots)
                    : Row(
                        children: plots.map((p) => Expanded(child: p)).toList(),
                      );
              },
            ),
          ],
        ),
        ExpansionTile(
          title: Text('All measures (${keys.length})'),
          subtitle: const Text('Details, changes and valid epoch counts'),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in domains)
                  ChoiceChip(
                    label: Text(d),
                    selected: _domain == d,
                    onSelected: (_) => setState(() => _domain = d),
                  ),
              ],
            ),
            for (final k in keys.where(
              (k) =>
                  _domain == 'All' ||
                  (am[k]?.domain ?? bm[k]?.domain) == _domain,
            ))
              ListTile(
                title: Text(k.replaceAll('_', ' ')),
                subtitle: Text(
                  'A ${AnalysisReport.number(am[k]?.mean)}  ·  B ${AnalysisReport.number(bm[k]?.mean)} ${AnalysisReport.unit(k)}\nValid epochs: ${am[k]?.count ?? 0} / ${bm[k]?.count ?? 0}',
                ),
                trailing: Text(
                  am[k] != null && bm[k] != null
                      ? 'Δ ${AnalysisReport.number(bm[k]!.mean - am[k]!.mean)}'
                      : 'N/A',
                ),
                isThreeLine: true,
              ),
            if (keys.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No valid feature epochs in these regions.'),
              ),
          ],
        ),
      ],
    );
  }
}
