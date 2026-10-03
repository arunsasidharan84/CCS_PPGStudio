import 'dart:convert';
import 'recording_import.dart';
import 'recording_settings.dart';
import 'ppg_ipfm_refinement.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../ffi_bindings.dart';
import '../models/ppg_models.dart';

class AnalysisRequest {
  final String ppgPath;
  final String? sigmotPath;
  final double sampleRate;

  AnalysisRequest({
    required this.ppgPath,
    this.sigmotPath,
    this.sampleRate = 50.0,
  });
}

class PPGAnalysisService {
  static String? findMatchingSigmot(String ppgPath) {
    final ppgFile = File(ppgPath);
    final dir = ppgFile.parent;
    final name = ppgFile.uri.pathSegments.last;

    if (name.contains('_ppg_data.csv')) {
      final sigmotName = name.replaceAll('_ppg_data.csv', '_sigmot_data.csv');
      final candidate = File('${dir.path}/$sigmotName');
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return null;
  }

  static String? findMatchingTemperature(String ppgPath) {
    final ppgFile = File(ppgPath);
    final dir = ppgFile.parent;
    final name = ppgFile.uri.pathSegments.last;

    if (name.contains('_ppg_data.csv')) {
      final tempName = name.replaceAll(
        '_ppg_data.csv',
        '_temperature_data.csv',
      );
      final candidate = File('${dir.path}/$tempName');
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return null;
  }

  /// Run session analysis in a background isolate for smooth 120fps UI
  static Future<SessionAnalysisResult> analyzeFile(
    String ppgPath, {
    String? sigmotPath,
    double sampleRate = 50.0,
    String? pipelineMode,
  }) async {
    final mode = pipelineMode ?? await RecordingSettings.pipelineMode();
    final resolvedSigmot = sigmotPath ?? findMatchingSigmot(ppgPath);

    final req = AnalysisRequest(
      ppgPath: ppgPath,
      sigmotPath: resolvedSigmot,
      sampleRate: sampleRate,
    );

    final base = await compute(_isolateAnalyze, req);
    if (mode == 'ipfm_kalman') {
      return PpgIpfmRefinement.refine(base);
    }
    return base;
  }

  /// Refines or switches pipeline mode in-memory
  static SessionAnalysisResult applyPipeline(
    SessionAnalysisResult base,
    String targetMode,
  ) {
    if (targetMode == 'ipfm_kalman') {
      return PpgIpfmRefinement.refine(base);
    }
    return base.copyWith(pipelineMode: 'standard');
  }

  static SessionAnalysisResult _isolateAnalyze(AnalysisRequest req) {
    final bindings = SensioNativeBindings.tryLoad();
    if (bindings == null) {
      throw Exception('Failed to load native sensio_ppg_core library.');
    }

    Directory? temporary;
    OrbitPpgRecording? orbit;
    var inputPath = req.ppgPath;
    String jsonStr;
    try {
      if (RegExp(
        r'\.(orb|signal)$',
        caseSensitive: false,
      ).hasMatch(inputPath)) {
        orbit = OrbitPpgRecording.parse(File(inputPath).readAsStringSync());
        temporary = Directory.systemTemp.createTempSync('ccs-ppg-orbit-');
        final csv = File('${temporary.path}/orbit_ppg_data.csv');
        orbit.writeCsv(csv);
        inputPath = csv.path;
      }
      jsonStr = bindings.processFile(
        inputPath,
        sigmotPath: orbit == null ? req.sigmotPath : null,
        sampleRate: req.sampleRate,
      );
    } finally {
      temporary?.deleteSync(recursive: true);
    }

    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid native response format');
    }

    final success = decoded['success'] as bool? ?? false;
    if (!success) {
      final err = decoded['error'] as String? ?? 'Unknown native error';
      throw Exception('Analysis failed: $err');
    }

    final data = decoded['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('No analysis data returned');
    }

    final result = SessionAnalysisResult.fromJson(data);
    if (orbit != null) {
      return result.copyWith(
        sessionStartDateTime: orbit.startedAt,
        startTimeOfDayS: orbit.startedAt == null
            ? 0
            : orbit.startedAt!.hour * 3600.0 +
                  orbit.startedAt!.minute * 60.0 +
                  orbit.startedAt!.second,
      );
    }
    if (result.sessionStartDateTime == null) {
      final startDt = extractSessionStartDateTime(
        req.ppgPath,
        result.startTimeOfDayS,
      );
      if (startDt != null) {
        return result.copyWith(sessionStartDateTime: startDt);
      }
    }

    return result;
  }

  /// Extract exact session start datetime from filename (e.g. 20260909_202452) or file metadata
  static DateTime? extractSessionStartDateTime(
    String ppgPath,
    double startTimeOfDayS,
  ) {
    final name = File(ppgPath).uri.pathSegments.last;
    final match = RegExp(
      r'(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})',
    ).firstMatch(name);
    if (match != null) {
      final y = int.parse(match.group(1)!);
      final mo = int.parse(match.group(2)!);
      final d = int.parse(match.group(3)!);
      final h = int.parse(match.group(4)!);
      final mi = int.parse(match.group(5)!);
      final s = int.parse(match.group(6)!);
      return DateTime(y, mo, d, h, mi, s);
    }

    return null;
  }
}
