import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/services/app_update_service.dart';

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  Map<String, dynamic>? _release;
  File? _archive;
  bool _busy = false;
  double? _progress;
  String? _error;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final release = await AppUpdateService.check();
      if (mounted) setState(() => _release = release);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not check for updates: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final archive = await AppUpdateService.download(_release!, (v) {
        if (mounted) setState(() => _progress = v);
      });
      if (mounted) setState(() => _archive = archive);
    } catch (e) {
      if (mounted) setState(() => _error = 'Download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppUpdateService.install(_archive!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not install update: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final newer =
        _release != null &&
        AppUpdateService.isNewer(
          _release!['tag_name'] as String,
          AppUpdateService.currentVersion,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('App updates')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.system_update_alt, size: 56),
              const SizedBox(height: 20),
              Text(
                'CCS PPGStudio ${AppUpdateService.currentVersion}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (_release != null)
                Text(
                  newer
                      ? 'Version ${_release!['tag_name']} is available'
                      : 'You have the latest stable version',
                ),
              if (_release != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: SelectableText(
                    _release!['body'] as String? ?? 'No release notes',
                  ),
                ),
              if (_busy) LinearProgressIndicator(value: _progress),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_archive != null)
                const Text(
                  'Package verified. Finish your current work before restarting. The previous installation is retained as a .previous backup.',
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _check,
                    child: const Text('Check again'),
                  ),
                  if (newer && _archive == null)
                    FilledButton.icon(
                      onPressed: _busy ? null : _download,
                      icon: const Icon(Icons.download),
                      label: const Text('Download update'),
                    ),
                  if (_archive != null)
                    FilledButton.icon(
                      onPressed: _busy ? null : _install,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Install and restart'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
