import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../core/reporting/analysis_report.dart';

Future<Uint8List> _generateReport((List<ReportSession>, bool) request) =>
    AnalysisReport.generate(request.$1, includeDetails: request.$2);

class ReportScreen extends StatefulWidget {
  final List<ReportSession> sessions;
  const ReportScreen({super.key, required this.sessions});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  bool _details = false;
  late Future<Uint8List> _pdf = compute(_generateReport, (
    widget.sessions,
    _details,
  ));
  late final TextEditingController _filename = TextEditingController(
    text: AnalysisReport.suggestedFilename(widget.sessions),
  );
  bool _customFilename = false;
  void _changeDetails(bool details) {
    setState(() {
      _details = details;
      if (!_customFilename) {
        _filename.text = AnalysisReport.suggestedFilename(
          widget.sessions,
          includeDetails: details,
        );
      }
      _pdf = compute(_generateReport, (widget.sessions, details));
    });
  }

  String get _safeFilename {
    var value = _filename.text.trim().replaceAll(
      RegExp(r'[/\\:*?"<>|\x00-\x1F]'),
      '-',
    );
    if (value.isEmpty) {
      value = AnalysisReport.suggestedFilename(
        widget.sessions,
        includeDetails: _details,
      );
    }
    return value.toLowerCase().endsWith('.pdf') ? value : '$value.pdf';
  }

  @override
  void dispose() {
    _filename.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Report preview')),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AnalysisReport.reportTitle(widget.sessions),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _filename,
                decoration: const InputDecoration(
                  labelText: 'PDF filename',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _customFilename = true),
              ),
              if (widget.sessions.length == 2)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include full metric appendix'),
                  subtitle: Text(
                    _details
                        ? 'Visual summary + detailed metrics and source notes'
                        : 'Default: one-page visual summary',
                  ),
                  value: _details,
                  onChanged: _changeDetails,
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Uint8List>(
            future: _pdf,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Report could not be generated: ${snapshot.error}',
                    ),
                  ),
                );
              }
              if (snapshot.connectionState != ConnectionState.done ||
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return PdfPreview(
                key: ValueKey(_details),
                build: (_) async => snapshot.data!,
                pdfFileName: _safeFilename,
                canChangePageFormat: false,
                canChangeOrientation: false,
                allowSharing: true,
                allowPrinting: true,
              );
            },
          ),
        ),
      ],
    ),
  );
}
