import 'dart:io';
import 'dart:math' as math;
import '../widgets/recording_picker.dart';
import '../../core/reporting/analysis_report.dart';
import 'report_screen.dart';
import 'comparison_screen.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';
import '../../core/services/ppg_analysis_service.dart';
import '../../core/utils/time_formatter.dart';
import '../widgets/timeline_ribbon.dart';
import '../widgets/waveform_viewer.dart';
import '../widgets/poincare_chart.dart';
import '../widgets/hrv_trends_chart.dart';
import '../widgets/summary_table.dart';
import '../widgets/csv_explorer_widget.dart';
import '../../core/services/csv_export_service.dart';
import '../../core/services/window_analysis_service.dart';

class HomeScreen extends StatefulWidget {
  final SessionAnalysisResult? initialResult;
  final String? initialPath;
  const HomeScreen({super.key, this.initialResult, this.initialPath});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? _selectedPpgPath;
  String? _detectedSigmotPath;
  bool _isAnalyzing = false;
  String? _errorMessage;
  SessionAnalysisResult? _analysisResult;

  double _currentStartS = 0.0;
  double _windowDurationS = 30.0; // 30s default zoom
  bool _showClockTime = false; // Toggle between elapsed time and clock time

  // Sub-window analysis state
  double? _analysisWindowStartS;
  double? _analysisWindowEndS;
  FilteredWindowStats? _windowStats;
  int _hrvSubTab = 0; // 0: Poincaré Plot, 1: 15s Epoch Trends (mobile portrait)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _analysisResult = widget.initialResult;
    _selectedPpgPath = widget.initialPath;
    if (_analysisResult != null) {
      _analysisWindowStartS = 0;
      _analysisWindowEndS = _analysisResult!.totalDurationS;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final ppgPath = await pickRecording(context);
      if (!mounted || ppgPath == null) return;
      {
        final sigmotPath = PPGAnalysisService.findMatchingSigmot(ppgPath);
        setState(() {
          _selectedPpgPath = ppgPath;
          _detectedSigmotPath = sigmotPath;
          _errorMessage = null;
        });
        _runAnalysis();
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Error opening file picker: $e\n\nYou can also enter the absolute path directly.';
      });
    }
  }

  Future<void> _showManualPathDialog() async {
    final controller = TextEditingController(text: _selectedPpgPath ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SensioTheme.surface,
        title: const Text(
          'Open PPG Recording by Path',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a SensIO CSV, Orbit .orb or .signal path:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                hintText: '/path/to/session_ppg_data.csv',
                hintStyle: TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Color(0xFF0F172A),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SensioTheme.accent,
            ),
            onPressed: () {
              final path = controller.text.trim();
              Navigator.pop(ctx);
              if (path.isNotEmpty) {
                final file = File(path);
                if (file.existsSync()) {
                  final sigmotPath = PPGAnalysisService.findMatchingSigmot(
                    path,
                  );
                  setState(() {
                    _selectedPpgPath = path;
                    _detectedSigmotPath = sigmotPath;
                    _errorMessage = null;
                  });
                  _runAnalysis();
                } else {
                  setState(() {
                    _errorMessage = 'File does not exist: $path';
                  });
                }
              }
            },
            child: const Text(
              'Load & Analyze',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _quickExportCsv({required bool isTimeSeries}) async {
    if (_analysisResult == null) return;
    try {
      final baseName = _selectedPpgPath != null
          ? _selectedPpgPath!.split('/').last.replaceAll('_ppg_data.csv', '')
          : 'sensio_session';

      final defaultFileName = isTimeSeries
          ? '${baseName}_hrv_timeseries.csv'
          : '${baseName}_hrv_summary.csv';

      final content = isTimeSeries
          ? CsvExportService.generateTimeSeriesCsv(_analysisResult!)
          : CsvExportService.generateSummaryCsv(_analysisResult!);

      final fallbackDir = _selectedPpgPath?.substring(
        0,
        _selectedPpgPath!.lastIndexOf('/'),
      );

      final saved = await CsvExportService.saveCsv(
        defaultFileName: defaultFileName,
        csvContent: content,
        fallbackDirectory: fallbackDir,
      );

      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SensioTheme.accent,
            content: Text(
              'Exported: $saved',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SensioTheme.rejectNoise,
            content: Text('Export failed: $e'),
          ),
        );
      }
    }
  }

  Future<void> _runAnalysis() async {
    if (_selectedPpgPath == null) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final result = await PPGAnalysisService.analyzeFile(
        _selectedPpgPath!,
        sigmotPath: _detectedSigmotPath,
        sampleRate: 50.0,
      );

      setState(() {
        _analysisResult = result;
        _isAnalyzing = false;
        _currentStartS = 0.0;
        _analysisWindowStartS = 0.0;
        _analysisWindowEndS = result.totalDurationS;
        _windowStats = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isAnalyzing = false;
      });
    }
  }

  void _onAnalysisWindowChanged(double startS, double endS) {
    if (_analysisResult == null) return;
    setState(() {
      _analysisWindowStartS = startS;
      _analysisWindowEndS = endS;
      final isFull =
          startS <= 0.5 && endS >= (_analysisResult!.totalDurationS - 0.5);
      if (isFull) {
        _windowStats = null;
      } else {
        _windowStats = WindowAnalysisService.computeSubWindow(
          _analysisResult!,
          startS,
          endS,
        );
      }
    });
  }

  void _onResetAnalysisWindow() {
    if (_analysisResult == null) return;
    setState(() {
      _analysisWindowStartS = 0.0;
      _analysisWindowEndS = _analysisResult!.totalDurationS;
      _windowStats = null;
    });
  }

  void _onSeek(double newStartS) {
    if (_analysisResult == null) return;
    setState(() {
      _currentStartS = newStartS.clamp(
        0.0,
        (_analysisResult!.totalDurationS - _windowDurationS).clamp(
          0.0,
          _analysisResult!.totalDurationS,
        ),
      );
    });
  }

  void _onSelectBeatTimestamp(double ts) {
    if (_analysisResult == null) return;
    setState(() {
      _currentStartS = (ts - _windowDurationS / 2.0).clamp(
        0.0,
        (_analysisResult!.totalDurationS - _windowDurationS).clamp(
          0.0,
          _analysisResult!.totalDurationS,
        ),
      );
      _tabController.animateTo(0); // Jump to Waveform tab for individual beat
    });
  }

  void _onSyncWaveformFromTrend(double ts) {
    if (_analysisResult == null) return;
    setState(() {
      _currentStartS = (ts - _windowDurationS / 2.0).clamp(
        0.0,
        (_analysisResult!.totalDurationS - _windowDurationS).clamp(
          0.0,
          _analysisResult!.totalDurationS,
        ),
      );
      // Stay on HRV Dynamics tab while inspecting
    });
  }

  void _onJumpToWaveform(double ts) {
    if (_analysisResult == null) return;
    setState(() {
      _currentStartS = (ts - _windowDurationS / 2.0).clamp(
        0.0,
        (_analysisResult!.totalDurationS - _windowDurationS).clamp(
          0.0,
          _analysisResult!.totalDurationS,
        ),
      );
      _tabController.animateTo(0); // Explicitly requested tab jump
    });
  }

  ReportSession get _reportSession => ReportSession(
    'Session A',
    _selectedPpgPath == null
        ? 'Recording'
        : File(_selectedPpgPath!).uri.pathSegments.last,
    _analysisResult!,
  );

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                compact ? 'CCS PPGStudio' : 'Sensio PPG Analysis Studio',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_analysisResult?.pipelineMode == 'ipfm_kalman') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(60),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blueAccent, width: 0.8),
                ),
                child: const Text(
                  'IPFM+KF',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.lightBlueAccent,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open recording',
            icon: const Icon(Icons.folder_open),
            onPressed: _isAnalyzing ? null : _pickFile,
          ),
          PopupMenuButton<String>(
            tooltip: 'Reports, export and settings',
            onSelected: (value) async {
              if (value == 'settings') {
                await showRecordingSettings(
                  context,
                  onSettingsChanged: () {
                    if (_selectedPpgPath != null) _runAnalysis();
                  },
                );
              } else if (value == 'toggle_pipeline') {
                if (_analysisResult == null) return;
                final nextMode = _analysisResult!.pipelineMode == 'ipfm_kalman'
                    ? 'standard'
                    : 'ipfm_kalman';
                setState(() {
                  _analysisResult = PPGAnalysisService.applyPipeline(
                    _analysisResult!,
                    nextMode,
                  );
                });
              } else if (value == 'clock') {
                setState(() => _showClockTime = !_showClockTime);
              } else if (value == 'pdf') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportScreen(sessions: [_reportSession]),
                  ),
                );
              } else if (value == 'compare') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ComparisonScreen(first: _reportSession),
                  ),
                );
              } else if (value == 'timeseries' || value == 'summary') {
                await _quickExportCsv(isTimeSeries: value == 'timeseries');
              }
            },
            itemBuilder: (_) => [
              if (_analysisResult != null) ...[
                PopupMenuItem(
                  value: 'toggle_pipeline',
                  child: Text(
                    _analysisResult!.pipelineMode == 'ipfm_kalman'
                        ? 'Switch to Standard Pipeline'
                        : 'Switch to IPFM+Kalman Pipeline',
                  ),
                ),
                const PopupMenuItem(
                  value: 'pdf',
                  child: Text('Create PDF report'),
                ),
                const PopupMenuItem(
                  value: 'compare',
                  child: Text('Compare two recordings'),
                ),
                const PopupMenuItem(
                  value: 'timeseries',
                  child: Text('Export feature time series CSV'),
                ),
                const PopupMenuItem(
                  value: 'summary',
                  child: Text('Export summary CSV'),
                ),
                PopupMenuItem(
                  value: 'clock',
                  child: Text(
                    _showClockTime ? 'Show elapsed time' : 'Show clock time',
                  ),
                ),
              ],
              const PopupMenuItem(
                value: 'settings',
                child: Text('Recording settings'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isAnalyzing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: SensioTheme.accent),
            SizedBox(height: 16),
            Text(
              'Processing high-efficiency Rust DSP & HRV Engine...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: SensioTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SensioTheme.badArtifact),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: SensioTheme.badArtifact,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SensioTheme.accent,
                    ),
                    onPressed: _pickFile,
                    child: const Text(
                      'Select Another File',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                    onPressed: _showManualPathDialog,
                    child: const Text('Enter Path Directly'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_analysisResult == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights,
              size: 64,
              color: SensioTheme.border.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            const Text(
              'No PPG Session Loaded',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Open a SensIO CSV or Orbit PPG recording',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SensioTheme.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.folder_open),
                  label: const Text(
                    'Open recording',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _pickFile,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: SensioTheme.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Enter Path Directly'),
                  onPressed: _showManualPathDialog,
                ),
              ],
            ),
          ],
        ),
      );
    }

    final size = MediaQuery.sizeOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumHeight = size.width < 600 ? 690.0 : 620.0;
        return SingleChildScrollView(
          child: SizedBox(
            height: math.max(constraints.maxHeight, minimumHeight),
            child: Column(
              children: [
                // KPI Quick Summary Bar
                if (size.width < 900)
                  ExpansionTile(
                    title: Text(
                      _selectedPpgPath == null
                          ? 'Recording overview'
                          : File(_selectedPpgPath!).uri.pathSegments.last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${_analysisResult!.coveragePct.toStringAsFixed(1)}% accepted · ${(_analysisResult!.totalDurationS / 60).toStringAsFixed(0)} min · Tap for details',
                    ),
                    children: [
                      SizedBox(
                        height: 170,
                        child: SingleChildScrollView(child: _buildKpiBar()),
                      ),
                    ],
                  )
                else
                  _buildKpiBar(),

                // Tab Navigation
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tabs: [
                    Tab(icon: null, text: 'Waveform'),
                    Tab(icon: null, text: 'HRV Dynamics'),
                    Tab(
                      icon: null,
                      text: _windowStats != null
                          ? 'Clinical Summary (Window)'
                          : 'Clinical Summary',
                    ),
                    Tab(icon: null, text: 'CSV Explorer'),
                  ],
                ),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildWaveformTab(),
                      _buildHrvDynamicsTab(),
                      _buildSummaryTab(),
                      _buildCsvExplorerTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpiBar() {
    final res = _analysisResult!;
    final isWindowActive = _windowStats != null;
    final rows = _windowStats?.summary ?? res.summary;
    final summary = {for (final r in rows) r.metric: r};

    final coverage = _windowStats?.coveragePct ?? res.coveragePct;
    final beats = _windowStats?.detectedBeats ?? res.peaksIndices.length;

    final meanHr = summary['MeanHR']?.mean ?? double.nan;
    final sdnn = summary['SDNN']?.mean ?? double.nan;
    final rmssd = summary['RMSSD']?.mean ?? double.nan;
    final mqi = summary['Morphology_Quality']?.mean ?? double.nan;
    final skinTemp = summary['Skin_Temperature']?.mean ?? double.nan;
    final actMotion = summary['Activity_Motion']?.mean ?? double.nan;

    final dateLabel = TimeFormatter.formatSessionDate(res.sessionStartDateTime);
    final spanLabel = TimeFormatter.formatSessionSpan(
      res.sessionStartDateTime,
      res.totalDurationS,
    );
    final sessionStartLabel = TimeFormatter.formatSeconds(
      0,
      clockTime: res.sessionStartDateTime != null,
      sessionStart: res.sessionStartDateTime,
      t0SecondsOfDay: res.startTimeOfDayS,
      includeDate: false,
    );
    final sessionEndLabel = TimeFormatter.formatSeconds(
      res.totalDurationS,
      clockTime: res.sessionStartDateTime != null,
      sessionStart: res.sessionStartDateTime,
      t0SecondsOfDay: res.startTimeOfDayS,
      includeDate: false,
    );
    final sessionDurationHours = res.totalDurationS / 3600;
    final sessionDurationText = sessionDurationHours >= 1
        ? '${sessionDurationHours.toStringAsFixed(1)}h'
        : '${(res.totalDurationS / 60).round()}m';

    final windowStartLabel = TimeFormatter.formatSeconds(
      _analysisWindowStartS ?? 0.0,
      clockTime: _showClockTime,
      sessionStart: res.sessionStartDateTime,
      t0SecondsOfDay: res.startTimeOfDayS,
      includeDate: false,
    );
    final windowEndLabel = TimeFormatter.formatSeconds(
      _analysisWindowEndS ?? res.totalDurationS,
      clockTime: _showClockTime,
      sessionStart: res.sessionStartDateTime,
      t0SecondsOfDay: res.startTimeOfDayS,
      includeDate: false,
    );
    final winDurS =
        ((_analysisWindowEndS ?? res.totalDurationS) -
                (_analysisWindowStartS ?? 0.0))
            .clamp(0.0, res.totalDurationS);
    final winDurHours = winDurS / 3600.0;
    final winDurText = winDurHours >= 1.0
        ? '${winDurHours.toStringAsFixed(1)}h'
        : '${(winDurS / 60.0).round()}m';

    final kpiWidgets = [
      _kpiItem(
        isWindowActive ? 'Window Coverage' : 'Pulse Coverage',
        '${coverage.toStringAsFixed(1)}%',
        SensioTheme.goodPulse,
      ),
      _kpiItem(
        isWindowActive ? 'Window Beats' : 'Detected Beats',
        '$beats',
        SensioTheme.accent,
      ),
      _kpiItem(
        'Mean HR',
        meanHr.isFinite ? '${meanHr.toStringAsFixed(1)} BPM' : '-',
        Colors.white,
      ),
      _kpiItem(
        'Mean SDNN',
        sdnn.isFinite ? '${sdnn.toStringAsFixed(1)} ms' : '-',
        SensioTheme.ppgSignal,
      ),
      _kpiItem(
        'Mean RMSSD',
        rmssd.isFinite ? '${rmssd.toStringAsFixed(1)} ms' : '-',
        SensioTheme.accent,
      ),
      if (skinTemp.isFinite)
        _kpiItem(
          'Skin Temp',
          '${skinTemp.toStringAsFixed(2)} °C',
          const Color(0xFF38BDF8),
        ),
      if (actMotion.isFinite)
        _kpiItem(
          'Mean Activity',
          actMotion.toStringAsFixed(1),
          SensioTheme.sigmotSignal,
        ),
      _kpiItem(
        'Morphology Quality',
        mqi.isFinite ? mqi.toStringAsFixed(2) : '-',
        const Color(0xFFF472B6),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;
        final size = MediaQuery.sizeOf(context);
        final compactLandscape =
            size.shortestSide < 600 && size.width > size.height;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Session Date & Time Span Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              decoration: BoxDecoration(
                color: SensioTheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: SensioTheme.border.withValues(alpha: 0.3),
                ),
              ),
              child: isNarrow && !compactLandscape
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 13,
                              color: SensioTheme.accent,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                dateLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isWindowActive) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: SensioTheme.accent.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: SensioTheme.accent.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.filter_alt,
                                      size: 10,
                                      color: SensioTheme.accent,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      'Win: $winDurText',
                                      style: const TextStyle(
                                        color: SensioTheme.accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: _onResetAnalysisWindow,
                                      child: const Icon(
                                        Icons.close,
                                        size: 11,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else
                              Text(
                                'Duration $sessionDurationText',
                                style: const TextStyle(
                                  color: SensioTheme.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 13,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '$sessionStartLabel  →  $sessionEndLabel',
                                maxLines: 2,
                                softWrap: true,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 15,
                          color: SensioTheme.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dateLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.schedule,
                          size: 15,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            spanLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isWindowActive) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: SensioTheme.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: SensioTheme.accent.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.filter_alt,
                                  size: 12,
                                  color: SensioTheme.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Window: $windowStartLabel → $windowEndLabel ($winDurText)',
                                  style: const TextStyle(
                                    color: SensioTheme.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: _onResetAnalysisWindow,
                                  child: const Icon(
                                    Icons.close,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),

            // KPI Badges
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              decoration: BoxDecoration(
                color: SensioTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SensioTheme.border.withValues(alpha: 0.3),
                ),
              ),
              child: isNarrow && !compactLandscape
                  ? Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceAround,
                      children: kpiWidgets,
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: kpiWidgets
                            .map(
                              (w) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: w,
                              ),
                            )
                            .toList(),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _kpiItem(String label, String val, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildWaveformTab() {
    final res = _analysisResult!;
    final t0 = res.startTimeOfDayS > 0
        ? res.startTimeOfDayS
        : (res.time.isNotEmpty ? res.time.first : 0.0);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gapless Quality Strip Header & Ribbon
          Row(
            children: [
              const Expanded(
                child: Text(
                  'GAPLESS QUALITY EPISODES',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Zoom Level Presets
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Zoom: ',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  ...[15.0, 30.0, 60.0, 120.0, 300.0].map((dur) {
                    final label = dur >= 60.0
                        ? '${(dur / 60).round()}m'
                        : '${dur.round()}s';
                    final isSel = _windowDurationS == dur;
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => setState(() => _windowDurationS = dur),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isSel
                                ? SensioTheme.accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSel
                                  ? SensioTheme.accent
                                  : SensioTheme.border.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isSel ? Colors.black : Colors.white70,
                              fontSize: 10,
                              fontWeight: isSel
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Interactive Gapless Ribbon
          TimelineRibbon(
            segments: res.segments,
            totalDurationS: res.totalDurationS,
            currentStartS: _currentStartS,
            windowDurationS: _windowDurationS,
            onSeek: _onSeek,
            showClockTime: _showClockTime,
            t0SecondsOfDay: t0,
            sessionStart: res.sessionStartDateTime,
            analysisStartS: _analysisWindowStartS ?? 0.0,
            analysisEndS: _analysisWindowEndS ?? res.totalDurationS,
            onAnalysisWindowChanged: _onAnalysisWindowChanged,
            onResetAnalysisWindow: _onResetAnalysisWindow,
          ),
          const SizedBox(height: 8),

          // High-Resolution 50 Hz Waveform Canvas
          Expanded(
            child: WaveformViewer(
              result: res,
              currentStartS: _currentStartS,
              windowDurationS: _windowDurationS,
              onSeek: _onSeek,
              showClockTime: _showClockTime,
              t0SecondsOfDay: t0,
              sessionStart: res.sessionStartDateTime,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHrvDynamicsTab() {
    final res = _analysisResult!;
    final t0 = res.startTimeOfDayS > 0
        ? res.startTimeOfDayS
        : (res.time.isNotEmpty ? res.time.first : 0.0);
    final poincareData = _windowStats?.poincare ?? res.poincare;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isPhonePortrait = constraints.maxWidth < 600;
          final isLandscape =
              constraints.maxHeight < 500 &&
              constraints.maxWidth > constraints.maxHeight;
          final isWide = constraints.maxWidth > 850 || isLandscape;

          Widget poincare() => PoincareChart(
            data: poincareData,
            onSelectBeatTimestamp: _onSelectBeatTimestamp,
          );

          Widget trends() => HrvTrendsChart(
            hrvResult: res.hrv,
            onSelectTimestamp: _onSyncWaveformFromTrend,
            onJumpToWaveform: _onJumpToWaveform,
            showClockTime: _showClockTime,
            t0SecondsOfDay: t0,
            sessionStart: res.sessionStartDateTime,
          );

          if (isPhonePortrait) {
            return Column(
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.scatter_plot, size: 16),
                      label: Text('Poincaré Plot'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.timeline, size: 16),
                      label: Text('HRV Trends'),
                    ),
                  ],
                  selected: {_hrvSubTab},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _hrvSubTab = selection.first),
                ),
                const SizedBox(height: 10),
                Expanded(child: _hrvSubTab == 0 ? poincare() : trends()),
              ],
            );
          }

          if (isWide) {
            return Row(
              children: [
                Expanded(flex: 5, child: poincare()),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: trends()),
              ],
            );
          } else {
            return SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 380, child: poincare()),
                  const SizedBox(height: 16),
                  SizedBox(height: 480, child: trends()),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildSummaryTab() {
    final res = _analysisResult!;
    final rows = _windowStats?.summary ?? res.summary;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SummaryTable(rows: rows),
    );
  }

  Widget _buildCsvExplorerTab() {
    final res = _analysisResult!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: CsvExplorerWidget(result: res, sourceFilePath: _selectedPpgPath),
    );
  }
}
