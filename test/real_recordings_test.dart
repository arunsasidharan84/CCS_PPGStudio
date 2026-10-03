// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensio_ppg_app/core/services/ppg_analysis_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Analyze real SensIO, .orb, and .signal recordings', () async {
    final files = [
      '/Users/arunsasidharan/EEGdata/SenseIO/RingData_20260906_onwards/VM_session_14_20260922_064717_ppg_data.csv',
      '/Users/arunsasidharan/EEGdata/NeuroYukti/P001_P1782881959843_Reading_2026-07-02T06-32-15.834276.orb',
      '/Users/arunsasidharan/EEGdata/Neurostellar/NeurostellarTeamRecordings/Dhanushya/extracted_0b9793aa-f04d-4479-8edb-442779c0b8b2_raw/ppg_signal.signal',
    ];

    for (final path in files) {
      if (!File(path).existsSync()) {
        print('Skipping non-existent file: $path');
        continue;
      }
      final sw = Stopwatch()..start();
      final res = await PPGAnalysisService.analyzeFile(path);
      expect(res.totalDurationS, greaterThan(0));
      expect(res.coveragePct, greaterThanOrEqualTo(0));
      expect(res.summary, isNotEmpty);
      print(
        'SUCCESS on ${File(path).uri.pathSegments.last} in ${sw.elapsedMilliseconds} ms: '
        'duration=${res.totalDurationS.toStringAsFixed(1)}s, '
        'coverage=${res.coveragePct.toStringAsFixed(1)}%, '
        'peaks=${res.peaksIndices.length}, '
        'poincare=${res.poincare.x.length} pairs, '
        'summary=${res.summary.length} metrics',
      );
    }
  });

  test('Compare Standard vs IPFM+Kalman refinement on real ring data', () async {
    const path =
        '/Users/arunsasidharan/EEGdata/SenseIO/RingData_20260906_onwards/VM_session_14_20260922_064717_ppg_data.csv';
    if (!File(path).existsSync()) return;

    final standard = await PPGAnalysisService.analyzeFile(
      path,
      pipelineMode: 'standard',
    );
    final ipfmKalman = await PPGAnalysisService.analyzeFile(
      path,
      pipelineMode: 'ipfm_kalman',
    );

    expect(standard.pipelineMode, 'standard');
    expect(ipfmKalman.pipelineMode, 'ipfm_kalman');
    expect(ipfmKalman.ipfmDiagnostics, isNotNull);

    final diag = ipfmKalman.ipfmDiagnostics!;
    print('--- Ring Data A/B Comparison: Standard vs IPFM+Kalman ---');
    print('Standard peaks count: ${standard.peaksIndices.length}');
    print(
      'Poincare pairs - Standard: ${standard.poincare.x.length}, IPFM: ${ipfmKalman.poincare.x.length}',
    );
    print(
      'Poincare SD1 - Standard: ${standard.poincare.sd1.toStringAsFixed(2)} ms, IPFM: ${ipfmKalman.poincare.sd1.toStringAsFixed(2)} ms',
    );
    print(
      'Poincare SD2 - Standard: ${standard.poincare.sd2.toStringAsFixed(2)} ms, IPFM: ${ipfmKalman.poincare.sd2.toStringAsFixed(2)} ms',
    );
    print('IPFM Beats Removed (spurious): ${diag['ipfm_beats_removed']}');
    print('IPFM Beats Inserted (trusted gaps): ${diag['ipfm_beats_inserted']}');
    print('IPFM Chain Breaks: ${diag['ipfm_chain_breaks']}');
    print('IPFM Continuous Segments: ${diag['ipfm_segments']}');

    // Kalman smoothed HR trajectories should have no non-finite or empty values
    final rawHr = standard.hrv.metrics['MeanHR'] ?? [];
    final kalmanHr = ipfmKalman.hrv.metrics['MeanHR'] ?? [];
    print(
      'MeanHR valid epochs: raw=${rawHr.where((v) => v.isFinite).length}/${rawHr.length}, kalman=${kalmanHr.where((v) => v.isFinite).length}/${kalmanHr.length}',
    );
    expect(kalmanHr.length, rawHr.length);
  });
}
