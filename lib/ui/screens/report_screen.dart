import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../core/reporting/analysis_report.dart';

Future<Uint8List> _generateReport(List<ReportSession> sessions) =>
    AnalysisReport.generate(sessions);

class ReportScreen extends StatefulWidget {
  final List<ReportSession> sessions;
  const ReportScreen({super.key, required this.sessions});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late final Future<Uint8List> _pdf = compute(_generateReport, widget.sessions);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.sessions.length == 2 ? 'Comparison report' : 'Session report',
      ),
    ),
    body: FutureBuilder<Uint8List>(
      future: _pdf,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Report could not be generated: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return PdfPreview(
          build: (_) async => snapshot.data!,
          pdfFileName: widget.sessions.length == 2
              ? 'CCS_PPG_comparison.pdf'
              : 'CCS_PPG_report.pdf',
          canChangePageFormat: false,
          canChangeOrientation: false,
          allowSharing: true,
          allowPrinting: true,
        );
      },
    ),
  );
}
