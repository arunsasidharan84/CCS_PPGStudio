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
                  itemBuilder: (_, i) {
                    final fName = File(paths[i]).uri.pathSegments.last;
                    final parent = File(paths[i]).parent.path;
                    final isOrbit = RegExp(r'\.(orb|signal)$', caseSensitive: false).hasMatch(fName);
                    String sub = 'Orbit PPG Recording';
                    if (!isOrbit) {
                      final hasSigmot = File('$parent/${fName.replaceAll("_ppg_data.csv", "_sigmot_data.csv")}').existsSync();
                      final hasTemp = File('$parent/${fName.replaceAll("_ppg_data.csv", "_temperature_data.csv")}').existsSync();
                      sub = 'SensIO • Sigmot: ${hasSigmot ? "✓" : "—"} | Temp: ${hasTemp ? "✓" : "—"}';
                    }
                    return ListTile(
                      title: Text(fName),
                      subtitle: Text(sub, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      onTap: () => Navigator.pop(ctx, paths[i]),
                    );
                  },
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
          ? 'Select Orbit PPG (.orb, .signal)'
          : 'Select SensIO PPG file (and optional Sigmot/Temp files)',
      type: FileType.custom,
      allowedExtensions: mode == 'orbit' ? ['orb', 'signal'] : ['csv'],
      allowMultiple: mode == 'sensio',
    );
  } catch (_) {
    result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: mode == 'sensio',
    );
  }

  if (result == null || result.files.isEmpty) return null;

  final files = result.files.where((f) => f.path != null).toList();
  if (files.isEmpty) return null;

  // If multiple files selected, find the primary PPG file
  String? ppgPath;
  final companionPaths = <String>[];

  for (final f in files) {
    final p = f.path!;
    final name = File(p).uri.pathSegments.last;
    if (mode == 'orbit') {
      if (RegExp(r'\.(orb|signal)$', caseSensitive: false).hasMatch(name)) {
        ppgPath = p;
        break;
      }
    } else {
      if (matchesRecordingPattern(name, pattern)) {
        ppgPath = p;
      } else if (name.endsWith('_sigmot_data.csv') ||
          name.endsWith('_temperature_data.csv')) {
        companionPaths.add(p);
      }
    }
  }

  // If no file strictly matched the PPG pattern, check if user picked a companion file alone
  if (ppgPath == null) {
    final firstPath = files.first.path!;
    final firstName = File(firstPath).uri.pathSegments.last;

    if (firstName.endsWith('_sigmot_data.csv') ||
        firstName.endsWith('_temperature_data.csv')) {
      final candidatePpgName = firstName.replaceAll(
        RegExp(r'_(sigmot|temperature)_data\.csv$'),
        '_ppg_data.csv',
      );
      final candidatePpg = File('${File(firstPath).parent.path}/$candidatePpgName');
      if (candidatePpg.existsSync()) {
        ppgPath = candidatePpg.path;
      } else {
        throw FormatException(
          'Selected "$firstName" is a companion file. Please select the matching PPG file: "$candidatePpgName".',
        );
      }
    } else {
      final valid = mode == 'orbit'
          ? RegExp(r'\.(orb|signal)$', caseSensitive: false).hasMatch(firstName)
          : matchesRecordingPattern(firstName, pattern);
      if (!valid) {
        throw FormatException(
          mode == 'orbit'
              ? 'Select an .orb or .signal recording.'
              : 'The file "$firstName" does not match $pattern. You can change this filter in Settings.',
        );
      }
      ppgPath = firstPath;
    }
  }

  // Copy any selected companion files to the same directory as the PPG file
  final ppgDir = File(ppgPath).parent.path;
  for (final cp in companionPaths) {
    final cName = File(cp).uri.pathSegments.last;
    final target = File('$ppgDir/$cName');
    if (target.path != cp && !target.existsSync()) {
      try {
        await File(cp).copy(target.path);
      } catch (_) {}
    }
  }

  // If on mobile/isolated environment and companion files are still missing, prompt user
  if (context.mounted && mode == 'sensio') {
    await _promptAndImportMissingCompanions(context, ppgPath);
  }

  return ppgPath;
}

Future<void> _promptAndImportMissingCompanions(
  BuildContext context,
  String ppgPath,
) async {
  final ppgFile = File(ppgPath);
  final dir = ppgFile.parent.path;
  final name = ppgFile.uri.pathSegments.last;
  if (!name.contains('_ppg_data.csv')) return;

  final expectedSigmot = name.replaceAll('_ppg_data.csv', '_sigmot_data.csv');
  final expectedTemp = name.replaceAll('_ppg_data.csv', '_temperature_data.csv');

  final hasSigmot = File('$dir/$expectedSigmot').existsSync();
  final hasTemp = File('$dir/$expectedTemp').existsSync();

  if (hasSigmot && hasTemp) return;

  final missingList = <String>[];
  if (!hasSigmot) missingList.add('Sigmot / Motion');
  if (!hasTemp) missingList.add('Temperature');

  final shouldPick = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('SensIO Companion Files'),
      content: Text(
        'Selected PPG:\n$name\n\n'
        'Companion files (${missingList.join(', ')}) were not found in the same folder.\n\n'
        'Would you like to select them for motion and temperature tracking?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Analyze PPG Only'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Select Companion Files'),
        ),
      ],
    ),
  );

  if (shouldPick != true) return;

  try {
    final companions = await FilePicker.pickFiles(
      dialogTitle: 'Select matching Sigmot and Temperature CSVs',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      allowMultiple: true,
    );

    if (companions == null || companions.files.isEmpty) return;

    for (final f in companions.files) {
      if (f.path == null) continue;
      final cName = File(f.path!).uri.pathSegments.last;
      if (cName.endsWith('_sigmot_data.csv') ||
          cName.endsWith('_temperature_data.csv')) {
        final target = File('$dir/$cName');
        await File(f.path!).copy(target.path);
      }
    }
  } catch (_) {}
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
