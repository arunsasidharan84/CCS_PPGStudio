import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensio_ppg_app/core/services/comparison_label_store.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensio_ppg_app/core/reporting/analysis_report.dart';
import 'package:sensio_ppg_app/ui/screens/comparison_screen.dart';
import 'package:sensio_ppg_app/ui/screens/review_screen.dart';
import 'package:sensio_ppg_app/ui/theme.dart';
import 'responsive_ui_test.dart' show fixture;

Future<void> snapshot(WidgetTester tester, String name) async {
  if (Platform.environment['PPG_UI_QA'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('tmp/ui').create(recursive: true);
    await File('tmp/ui/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

ThemeData qaTheme() {
  final base = SensioTheme.darkTheme;
  if (Platform.environment['PPG_UI_FONT'] == null) return base;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'QA'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'QA'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'QA',
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    final path = Platform.environment['PPG_UI_FONT'];
    if (path == null) return;
    final font = FontLoader('QA')
      ..addFont(
        Future.value(ByteData.sublistView(await File(path).readAsBytes())),
      );
    await font.load();
    final icons = Platform.environment['PPG_ICON_FONT'];
    if (icons != null) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(ByteData.sublistView(await File(icons).readAsBytes())),
        );
      await loader.load();
    }
  });
  testWidgets(
    'Condition edits update the overview, persist and prevent ambiguous exports',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: qaTheme(),
          home: ComparisonScreen(
            first: ReportSession(
              'Standing pose',
              'standing.csv',
              fixture(),
              sourcePath: '/a.csv',
            ),
            second: ReportSession(
              'Bending pose',
              'bending.csv',
              fixture(),
              sourcePath: '/b.csv',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Condition names & selected regions'));
      await tester.pumpAndSettle();
      final nameA = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Condition A name',
      );
      await tester.ensureVisible(nameA);
      await tester.enterText(nameA, 'Bending pose');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '1-page visual PDF'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(nameA, 'Standing pose');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '1-page visual PDF'),
            )
            .onPressed,
        isNotNull,
      );
      expect(await ComparisonLabelStore.load('/a.csv'), 'Standing pose');
      expect(await ComparisonLabelStore.load('/b.csv'), 'Bending pose');
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('Comparison and review remain usable at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final base = fixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: qaTheme(),
          home: ComparisonScreen(
            first: ReportSession(
              'Standing pose',
              'StandingPose_ppg_data.csv',
              base,
            ),
            second: ReportSession(
              'Half-bending forward pose',
              'HalfBendingForwardPose_ppg_data.csv',
              base,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Recalculate regions'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recalculate regions'), findsOneWidget);
      await snapshot(tester, 'comparison-${size.width.toInt()}');
      await tester.pumpWidget(
        MaterialApp(
          theme: qaTheme(),
          home: ReviewScreen(original: base, current: base, edits: const []),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Include region'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Exclude region'), findsOneWidget);
      await snapshot(tester, 'review-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
}
