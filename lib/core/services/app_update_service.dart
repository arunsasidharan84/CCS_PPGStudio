import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

class AppUpdateService {
  static const currentVersion = '1.2.0';
  static const repository = 'arunsasidharan84/CCS_PPGStudio';
  static bool isNewer(String candidate, String current) {
    List<int> parts(String v) => v
        .replaceFirst(RegExp(r'^v'), '')
        .split('+')
        .first
        .split('.')
        .map((v) => int.tryParse(v) ?? 0)
        .toList();
    final a = parts(candidate), b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static String get assetName => Platform.isMacOS
      ? 'CCSPPGStudio-macos.zip'
      : Platform.isWindows
      ? 'CCSPPGStudio-Windows.zip'
      : 'CCSPPGStudio-Linux-x64.tar.gz';
  static Future<Map<String, dynamic>> check() async {
    final bytes = await _get(
      'https://api.github.com/repos/$repository/releases/latest',
    );
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (data['draft'] == true || data['prerelease'] == true) {
      throw StateError('No stable release available');
    }
    return data;
  }

  static Future<List<int>> _get(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'CCS-PPGStudio/$currentVersion');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException('Download returned HTTP ${response.statusCode}');
      }
      return await response.fold<List<int>>([], (a, b) => a..addAll(b));
    } finally {
      client.close();
    }
  }

  static Future<File> download(
    Map<String, dynamic> release,
    void Function(double) progress,
  ) async {
    final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
    final asset = assets.where((a) => a['name'] == assetName).firstOrNull;
    final sums = assets.where((a) => a['name'] == 'SHA256SUMS').firstOrNull;
    if (asset == null || sums == null) {
      throw StateError(
        'This release has no verified package for this platform',
      );
    }
    String trustedUrl(Map<String, dynamic> a) {
      final url = a['browser_download_url'] as String;
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          !uri.path.startsWith('/$repository/releases/download/')) {
        throw StateError('Unexpected release download URL');
      }
      return url;
    }

    final manifest = utf8.decode(await _get(trustedUrl(sums)));
    final line = manifest
        .split('\n')
        .where((s) => s.trim().endsWith('  $assetName'))
        .firstOrNull;
    if (line == null) throw StateError('Package checksum is missing');
    final expected = line.split(RegExp(r'\s+')).first;
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expected)) {
      throw StateError('Invalid package checksum');
    }
    final folder = await Directory.systemTemp.createTemp('ccs-ppg-update-');
    final file = File('${folder.path}/$assetName');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final response = await (await client.getUrl(
        Uri.parse(trustedUrl(asset)),
      )).close();
      if (response.statusCode != 200) {
        throw HttpException('Package download failed');
      }
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          sink.add(chunk);
          received += chunk.length;
          if (response.contentLength > 0) {
            progress((received / response.contentLength).clamp(0, 1));
          }
        }
      } finally {
        await sink.close();
      }
      final actual = await sha256.bind(file.openRead()).first;
      if (actual.toString() != expected.toLowerCase()) {
        throw StateError('Checksum mismatch. Update was not installed.');
      }
      progress(1);
      return file;
    } catch (_) {
      await folder.delete(recursive: true);
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Stage a verified archive, then replace with a backup after the app exits.
  static Future<void> install(File archive) async {
    final staging = await Directory('${archive.parent.path}/staging').create();
    final exe = File(Platform.resolvedExecutable);
    if (Platform.isWindows) {
      final prepare = File('${archive.parent.path}/prepare.ps1');
      await prepare.writeAsString(r'''param([string]$Archive,[string]$Staging)
$ErrorActionPreference = 'Stop'
Expand-Archive -LiteralPath $Archive -DestinationPath $Staging
''');
      final extraction = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        prepare.path,
        archive.path,
        staging.path,
      ]);
      if (extraction.exitCode != 0 ||
          !await File(
            '${staging.path}/${exe.uri.pathSegments.last}',
          ).exists()) {
        throw StateError('Could not stage the Windows update');
      }
      final probe = File('${exe.parent.parent.path}/.ccs-update-probe-$pid');
      await probe.writeAsString('');
      await probe.delete();
      final script = File('${archive.parent.path}/install.ps1');
      await script.writeAsString(r'''
param([string]$Archive,[string]$Target,[string]$Staging,[int]$AppPid,[string]$Executable)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath (Join-Path $Staging $Executable))) { throw 'Invalid update package' }
Wait-Process -Id $AppPid -ErrorAction SilentlyContinue
$Backup = "$Target.previous-$(Get-Date -Format yyyyMMddHHmmss)"
if (Test-Path -LiteralPath $Backup) { throw 'Previous backup exists; resolve it before updating' }
Move-Item -LiteralPath $Target -Destination $Backup
try { Move-Item -LiteralPath $Staging -Destination $Target } catch { Move-Item -LiteralPath $Backup -Destination $Target; throw }
Start-Process -FilePath (Join-Path $Target $Executable)
''');
      await Process.start('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        archive.path,
        exe.parent.path,
        staging.path,
        '$pid',
        exe.uri.pathSegments.last,
      ], mode: ProcessStartMode.detached);
    } else {
      String target, staged, launch;
      if (Platform.isMacOS) {
        var dir = exe.parent;
        while (!dir.path.endsWith('.app') && dir.parent.path != dir.path) {
          dir = dir.parent;
        }
        if (!dir.path.endsWith('.app')) {
          throw StateError('Install updates from a packaged desktop app');
        }
        target = dir.path;
        final extraction = await Process.run('/usr/bin/ditto', [
          '-x',
          '-k',
          archive.path,
          staging.path,
        ]);
        if (extraction.exitCode != 0) {
          throw StateError('Could not extract macOS update');
        }
        staged = '${staging.path}/CCS PPG Studio.app';
        if (!await File('$staged/Contents/MacOS/sensio_ppg_app').exists() &&
            !await Directory('$staged/Contents/MacOS').exists()) {
          throw StateError('Invalid macOS package');
        }
        final signature = await Process.run('/usr/bin/codesign', [
          '--verify',
          '--deep',
          '--strict',
          staged,
        ]);
        if (signature.exitCode != 0) {
          throw StateError('Update code signature is invalid');
        }
        launch = 'open';
      } else {
        target = exe.parent.path;
        final extraction = await Process.run('tar', [
          '-xzf',
          archive.path,
          '-C',
          staging.path,
        ]);
        if (extraction.exitCode != 0) {
          throw StateError('Could not extract Linux update');
        }
        staged = '${staging.path}/CCSPPGStudio';
        if (!await File('$staged/${exe.uri.pathSegments.last}').exists()) {
          throw StateError('Invalid Linux package');
        }
        launch = exe.uri.pathSegments.last;
      }
      // Verify parent permissions before asking the running app to exit.
      final probe = File(
        '${Directory(target).parent.path}/.ccs-update-probe-$pid',
      );
      await probe.writeAsString('');
      await probe.delete();

      final script = File('${archive.parent.path}/install.sh');
      await script.writeAsString(r'''#!/bin/sh
set -eu
app_pid="$1"; target="$2"; staged="$3"; launch="$4"
while kill -0 "$app_pid" 2>/dev/null; do sleep 1; done
backup="$target.previous-$(date +%Y%m%d%H%M%S)"
mv "$target" "$backup"
if ! mv "$staged" "$target"; then mv "$backup" "$target"; exit 1; fi
if [ "$launch" = open ]; then /usr/bin/open "$target"; else "$target/$launch" >/dev/null 2>&1 & fi
''');
      await Process.start('/bin/sh', [
        script.path,
        '$pid',
        target,
        staged,
        launch,
      ], mode: ProcessStartMode.detached);
    }
    exit(0);
  }
}
