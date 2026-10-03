import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensio_ppg_app/core/models/ppg_models.dart';
import 'package:sensio_ppg_app/ui/screens/home_screen.dart';
import 'package:sensio_ppg_app/ui/theme.dart';
import 'package:sensio_ppg_app/ui/widgets/hrv_trends_chart.dart';
import 'package:sensio_ppg_app/ui/widgets/summary_table.dart';

SessionAnalysisResult fixture() {
  final metrics = {
    for (final name in ClinicalDictionary.dictionary.keys)
      name: List.generate(17, (i) => 60 + 5 * math.sin(i / 2)),
  };
  return SessionAnalysisResult.fromJson({
    'total_duration_s': 300.0,
    'sample_rate': 50.0,
    'coverage_pct': 100.0,
    'time': List.generate(15001, (i) => i / 50),
    'norm_ppg': List.generate(15001, (i) => math.sin(i * math.pi * 2 / 50)),
    'filtered': List.generate(15001, (i) => math.sin(i * math.pi * 2 / 50)),
    'usable_mask': List.filled(15001, true),
    'pulse_mask': List.filled(15001, true),
    'quality_trace': List.filled(15001, .9),
    'sigmot_trace': List.filled(15001, 0.0),
    'peaks_indices': List.generate(299, (i) => (i + 1) * 50),
    'gapless_segments': [
      {
        'id': 0,
        'onset_s': 0.0,
        'duration_s': 300.0,
        'end_s': 300.0,
        'is_good': true,
        'description': 'GOOD',
      },
    ],
    'hrv': {
      'timestamps': List.generate(17, (i) => 30.0 + i * 15),
      'window_s': 60.0,
      'step_s': 15.0,
      'metrics': metrics,
    },
    'poincare': {
      'x': [950.0, 1000.0, 1020.0, 970.0],
      'y': [1000.0, 1020.0, 970.0, 980.0],
      'timestamps': [1.0, 2.0, 3.0, 4.0],
      'mean_rr': 990.0,
      'sd1': 28.0,
      'sd2': 41.0,
    },
    'summary': [
      for (final name in metrics.keys)
        {
          'domain': name.startsWith('Morph') || name.startsWith('APG')
              ? 'Morphology'
              : 'Time',
          'metric': name,
          'mean': 61.99,
          'sd': 3.94,
          'median': 60.73,
          'iqr': 5.0,
          'min': 39.47,
          'max': 85.60,
          'count': 17,
        },
    ],
  });
}

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('All loaded tabs stay usable at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: SensioTheme.darkTheme,
          home: HomeScreen(
            initialResult: fixture(),
            initialPath: '/recordings/example_ppg_data.csv',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(FloatingActionButton), findsNothing);
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      for (var index = 1; index < 4; index++) {
        tabBar.controller!.animateTo(index);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Tab $index at $size');
      }
    });
  }
  testWidgets('Mobile selectors show searchable, full-width metric list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: SensioTheme.darkTheme,
        home: Scaffold(body: HrvTrendsChart(hrvResult: fixture().hrv)),
      ),
    );
    await tester.tap(find.text('Overlay · right axis'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Skin');
    await tester.pumpAndSettle();
    expect(find.text('Skin Temperature'), findsOneWidget);
    await tester.tap(find.text('Skin Temperature'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
