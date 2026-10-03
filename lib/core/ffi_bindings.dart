import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// FFI bindings to native `libsensio_ppg_core`
class SensioNativeBindings {
  SensioNativeBindings._(DynamicLibrary lib)
    : _getVersion = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'sensio_get_version',
          ),
      _processFile = lib
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Double),
            Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, double)
          >('sensio_process_file'),
      _freeString = lib
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('sensio_free_string');

  final Pointer<Utf8> Function() _getVersion;
  final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, double)
  _processFile;
  final void Function(Pointer<Utf8>) _freeString;

  static Object? lastLoadError;

  static SensioNativeBindings? tryLoad() {
    lastLoadError = null;

    if (Platform.isAndroid) {
      try {
        final lib = DynamicLibrary.open('libsensio_ppg_core.so');
        return SensioNativeBindings._(lib);
      } catch (e) {
        lastLoadError = e;
        try {
          return SensioNativeBindings._(DynamicLibrary.process());
        } catch (_) {}
      }
      return null;
    }

    if (Platform.isIOS) {
      final iosPaths = [
        'libsensio_ppg_core.framework/libsensio_ppg_core',
        'Frameworks/libsensio_ppg_core.framework/libsensio_ppg_core',
        'libsensio_ppg_core.dylib',
      ];
      for (final p in iosPaths) {
        try {
          final lib = DynamicLibrary.open(p);
          return SensioNativeBindings._(lib);
        } catch (e) {
          lastLoadError = 'Path "$p": $e';
        }
      }
      try {
        return SensioNativeBindings._(DynamicLibrary.process());
      } catch (e) {
        lastLoadError = 'process(): $e (also tried $iosPaths)';
      }
      return null;
    }

    if (Platform.isMacOS) {
      final exe = File(Platform.resolvedExecutable);
      final exeDir = exe.parent.path;
      final bundleFrameworksPath = '${exe.parent.parent.path}/Frameworks/libsensio_ppg_core.dylib';
      final current = Directory.current.path;
      final paths = [
        bundleFrameworksPath,
        '$exeDir/Frameworks/libsensio_ppg_core.dylib',
        '$exeDir/libsensio_ppg_core.dylib',
        '@rpath/libsensio_ppg_core.dylib',
        '@executable_path/../Frameworks/libsensio_ppg_core.dylib',
        '@loader_path/../Frameworks/libsensio_ppg_core.dylib',
        'libsensio_ppg_core.dylib',
        '$current/macos/Frameworks/libsensio_ppg_core.dylib',
        '$current/bin/libsensio_ppg_core.dylib',
        '$current/rust/target/release/libsensio_ppg_core.dylib',
        '$current/rust/target/aarch64-apple-darwin/release/libsensio_ppg_core.dylib',
        '$current/rust/target/x86_64-apple-darwin/release/libsensio_ppg_core.dylib',
        'macos/Frameworks/libsensio_ppg_core.dylib',
        'bin/libsensio_ppg_core.dylib',
        'rust/target/release/libsensio_ppg_core.dylib',
        '../rust/target/release/libsensio_ppg_core.dylib',
      ];

      final loadErrors = <String>[];
      for (final p in paths) {
        try {
          if (p.startsWith('@') || !p.contains('/') || File(p).existsSync()) {
            final lib = DynamicLibrary.open(p);
            return SensioNativeBindings._(lib);
          }
        } catch (e) {
          loadErrors.add('Path "$p": $e');
        }
      }

      lastLoadError = loadErrors.isEmpty
          ? 'Native library libsensio_ppg_core.dylib not found in any search path.'
          : loadErrors.join('\n');
      return null;
    }

    if (Platform.isLinux) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final paths = [
        '$exeDir/libsensio_ppg_core.so',
        '$exeDir/lib/libsensio_ppg_core.so',
        'libsensio_ppg_core.so',
        'bin/libsensio_ppg_core.so',
        'rust/target/release/libsensio_ppg_core.so',
        '../rust/target/release/libsensio_ppg_core.so',
      ];
      for (final p in paths) {
        try {
          if (!p.contains('/') || File(p).existsSync()) {
            return SensioNativeBindings._(DynamicLibrary.open(p));
          }
        } catch (e) {
          lastLoadError = 'Path "$p": $e';
        }
      }
      try {
        return SensioNativeBindings._(DynamicLibrary.open('libsensio_ppg_core.so'));
      } catch (e) {
        lastLoadError = 'open(libsensio_ppg_core.so): $e';
      }
      return null;
    }

    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final paths = [
        '$exeDir\\sensio_ppg_core.dll',
        'sensio_ppg_core.dll',
        'bin\\sensio_ppg_core.dll',
        'rust\\target\\release\\sensio_ppg_core.dll',
        '..\\rust\\target\\release\\sensio_ppg_core.dll',
      ];
      for (final p in paths) {
        try {
          if (!p.contains('\\') || File(p).existsSync()) {
            return SensioNativeBindings._(DynamicLibrary.open(p));
          }
        } catch (e) {
          lastLoadError = 'Path "$p": $e';
        }
      }
      try {
        return SensioNativeBindings._(DynamicLibrary.open('sensio_ppg_core.dll'));
      } catch (e) {
        lastLoadError = 'open(sensio_ppg_core.dll): $e';
      }
      return null;
    }

    return null;
  }

  String getVersion() {
    final ptr = _getVersion();
    if (ptr == nullptr) return 'unknown';
    return ptr.toDartString();
  }

  String processFile(
    String ppgPath, {
    String? sigmotPath,
    double sampleRate = 50.0,
  }) {
    final ppgPtr = ppgPath.toNativeUtf8();
    final sigmotPtr = sigmotPath != null ? sigmotPath.toNativeUtf8() : nullptr;

    try {
      final resPtr = _processFile(ppgPtr, sigmotPtr, sampleRate);
      if (resPtr == nullptr) {
        throw Exception('Native process_file returned null pointer');
      }
      try {
        return resPtr.toDartString();
      } finally {
        _freeString(resPtr);
      }
    } finally {
      calloc.free(ppgPtr);
      if (sigmotPtr != nullptr) {
        calloc.free(sigmotPtr);
      }
    }
  }
}
