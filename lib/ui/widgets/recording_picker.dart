import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/services/recording_import.dart';
import '../../core/services/recording_settings.dart';

Future<String?> pickRecording(BuildContext context) async {
  final pattern = await RecordingSettings.pattern();
  if (!context.mounted) return null;
  final mode = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Open recording'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'sensio'),
          child: ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('SensIO recording'),
            subtitle: Text(pattern),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'orbit'),
          child: const ListTile(
            leading: Icon(Icons.sensors),
            title: Text('Orbit recording'),
            subtitle: Text('.orb or .signal - PPG channel only'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'folder'),
          child: const ListTile(
            leading: Icon(Icons.folder_open),
            title: Text('Search a folder'),
            subtitle: Text('List matching SensIO and Orbit files'),
          ),
        ),
      ],
    ),
  );
  if (mode == null) return null;
  if (Platform.isMacOS) await FilePicker.skipEntitlementsChecks();
  if (mode == 'folder') {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return null;
    final paths = <String>[];
    await for (final entity in Directory(dir).list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (matchesRecordingPattern(name, pattern) ||
          RegExp(r'\.(orb|signal)$', caseSensitive: false).hasMatch(name)) {
        paths.add(entity.path);
      }
    }
    paths.sort();
    if (!context.mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${paths.length} matching recordings'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: paths.isEmpty
              ? const Text(
                  'No matching files. Change the SensIO pattern in Settings or select another folder.',
                )
              : ListView.builder(
                  itemCount: paths.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(File(paths[i]).uri.pathSegments.last),
                    onTap: () => Navigator.pop(ctx, paths[i]),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
  FilePickerResult? result;
  try {
    result = await FilePicker.pickFiles(
      dialogTitle: mode == 'orbit'
          ? 'Orbit PPG (.orb, .signal)'
          : 'SensIO ($pattern)',
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid
          ? null
          : mode == 'orbit'
          ? ['orb', 'signal']
          : ['csv'],
    );
  } catch (_) {
    result = await FilePicker.pickFiles(type: FileType.any);
  }
  final path = result?.files.single.path;
  if (path == null) return null;
  final name = File(path).uri.pathSegments.last;
  final valid = mode == 'orbit'
      ? RegExp(r'\.(orb|signal)$', caseSensitive: false).hasMatch(name)
      : matchesRecordingPattern(name, pattern);
  if (!valid) {
    throw FormatException(
      mode == 'orbit'
          ? 'Select an .orb or .signal recording.'
          : 'The file does not match $pattern. You can change this filter in Settings.',
    );
  }
  return path;
}

Future<void> showRecordingSettings(
  BuildContext context, {
  VoidCallback? onSettingsChanged,
}) async {
  final controller = TextEditingController(
    text: await RecordingSettings.pattern(),
  );
  var currentMode = await RecordingSettings.pipelineMode();
  if (!context.mounted) {
    controller.dispose();
    return;
  }
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: const Text('Recording & Analysis Settings'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'SensIO filename filter',
                    helperText: 'Use * for any text, ? for one character.',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'PPG Analysis Pipeline Mode:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                RadioGroup<String>(
                  groupValue: currentMode,
                  onChanged: (v) => update(() => currentMode = v ?? 'standard'),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        title: const Text(
                          'Standard (Refractory SQI)',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Direct peak intervals with strict window gating',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: 'standard',
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<String>(
                        title: const Text(
                          'Quality-Aware IPFM + Kalman Refinement',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Removes spurious beats, segments ambiguous gaps, and smooths metrics by 1/SQI',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: 'ipfm_kalman',
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Default pattern: *_ppg_data.csv. Orbit import extracts PPG (E channel) using hardware tick counter T.',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final pattern = controller.text.trim();
              if (pattern.isEmpty ||
                  !pattern.toLowerCase().endsWith('.csv') ||
                  pattern.contains('/') ||
                  pattern.contains('\\')) {
                update(
                  () => error = 'Enter a filename pattern ending in .csv.',
                );
                return;
              }
              await RecordingSettings.savePattern(pattern);
              await RecordingSettings.savePipelineMode(currentMode);
              if (ctx.mounted) Navigator.pop(ctx);
              onSettingsChanged?.call();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}
