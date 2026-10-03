import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/models/ppg_models.dart';
import '../../core/reporting/chart_svg.dart';

class PoincareChart extends StatelessWidget {
  final PoincareData data;
  final ValueChanged<double>? onSelectBeatTimestamp;
  const PoincareChart({
    super.key,
    required this.data,
    this.onSelectBeatTimestamp,
  });
  @override
  Widget build(BuildContext context) {
    final geometry = PoincareGeometry.forData(data);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('Mean RR ${data.meanRr.toStringAsFixed(1)} ms'),
              Text(
                'SD1/SD2 ${data.sd2 > 0 ? (data.sd1 / data.sd2).toStringAsFixed(3) : "-"}',
              ),
              Text('${data.x.length} adjacent pairs'),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = math.min(
                constraints.maxWidth / 420,
                constraints.maxHeight / 400,
              );
              final width = 420 * scale, height = 400 * scale;
              return Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: GestureDetector(
                    onTapDown: onSelectBeatTimestamp == null
                        ? null
                        : (details) {
                            final p = details.localPosition / scale;
                            var best = double.infinity;
                            int? index;
                            for (
                              var i = 0;
                              i < math.min(data.x.length, data.y.length);
                              i++
                            ) {
                              final distance =
                                  (Offset(
                                            geometry.x(data.x[i]),
                                            geometry.y(data.y[i]),
                                          ) -
                                          p)
                                      .distance;
                              if (distance < best && distance * scale < 24) {
                                best = distance;
                                index = i;
                              }
                            }
                            if (index != null &&
                                index < data.timestamps.length) {
                              onSelectBeatTimestamp!(data.timestamps[index]);
                            }
                          },
                    child: SvgPicture.string(
                      ChartSvg.poincare(data, dark: true, bounds: geometry),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
