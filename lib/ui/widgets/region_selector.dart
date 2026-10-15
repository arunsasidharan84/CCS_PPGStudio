import 'package:flutter/material.dart';

/// Touch-sized range handles plus exact numeric entry for experiment boundaries.
class RegionSelector extends StatelessWidget {
  final double duration;
  final RangeValues value;
  final ValueChanged<RangeValues> onChanged;
  const RegionSelector({
    super.key,
    required this.duration,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              '${value.start.toStringAsFixed(1)}–${value.end.toStringAsFixed(1)} s · ${(value.end - value.start).toStringAsFixed(1)} s selected',
            ),
          ),
          TextButton(
            onPressed: () => onChanged(RangeValues(0, duration)),
            child: const Text('Full session'),
          ),
        ],
      ),
      if (duration > 0)
        RangeSlider(
          min: 0,
          max: duration,
          values: value,
          labels: RangeLabels(
            '${value.start.toStringAsFixed(1)} s',
            '${value.end.toStringAsFixed(1)} s',
          ),
          onChanged: (v) {
            if (v.end - v.start >= .1) onChanged(v);
          },
        ),
      Row(
        children: [
          for (final start in [true, false])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextFormField(
                  key: ValueKey('$start:${start ? value.start : value.end}'),
                  initialValue: (start ? value.start : value.end)
                      .toStringAsFixed(2),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: start ? 'Start (seconds)' : 'End (seconds)',
                    border: const OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (text) {
                    final n = double.tryParse(text);
                    if (n == null || !n.isFinite || n < 0 || n > duration) {
                      return;
                    }
                    if (start && n < value.end) {
                      onChanged(RangeValues(n, value.end));
                    }
                    if (!start && n > value.start) {
                      onChanged(RangeValues(value.start, n));
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
