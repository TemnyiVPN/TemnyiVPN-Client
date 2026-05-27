import 'dart:ffi';
import 'dart:io' show Platform, pid;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

class WindowsInterferenceProcess {
  const WindowsInterferenceProcess({
    required this.pid,
    required this.executableName,
    required this.displayName,
    required this.reason,
  });

  final int pid;
  final String executableName;
  final String displayName;
  final String reason;

  String get label => '$displayName ($executableName, PID $pid)';
}

class WindowsInterferenceFailure {
  const WindowsInterferenceFailure({
    required this.process,
    required this.message,
  });

  final WindowsInterferenceProcess process;
  final String message;
}

class WindowsInterferenceActionResult {
  const WindowsInterferenceActionResult({
    required this.affected,
    required this.failures,
  });

  final List<WindowsInterferenceProcess> affected;
  final List<WindowsInterferenceFailure> failures;

  bool get hasFailures => failures.isNotEmpty;
}

class WindowsInterferenceService {
  static const MethodChannel _windowsRuntimeChannel = MethodChannel(
    'entropy_vpn/windows_runtime',
  );

  _WindowsProcessApi? _api;

  Future<List<WindowsInterferenceProcess>> scan() async {
    if (!Platform.isWindows) {
      return const <WindowsInterferenceProcess>[];
    }
    final api = _windowsApi;
    final matches = <WindowsInterferenceProcess>[];
    for (final process in api.enumerateProcesses()) {
      if (process.pid == pid) {
        continue;
      }
      final rule = _WindowsInterferenceRule.match(process.executableName);
      if (rule == null) {
        continue;
      }
      matches.add(
        WindowsInterferenceProcess(
          pid: process.pid,
          executableName: process.executableName,
          displayName: rule.displayName,
          reason: rule.reason,
        ),
      );
    }
    matches.sort((a, b) {
      final byName = a.displayName.compareTo(b.displayName);
      if (byName != 0) {
        return byName;
      }
      return a.pid.compareTo(b.pid);
    });
    return matches;
  }

  Future<WindowsInterferenceActionResult> terminateDetectedProcesses() async {
    final processes = await scan();
    final affected = <WindowsInterferenceProcess>[];
    final failures = <WindowsInterferenceFailure>[];
    if (!Platform.isWindows || processes.isEmpty) {
      return WindowsInterferenceActionResult(
        affected: affected,
        failures: failures,
      );
    }

    final result = await _runPrivilegedAction('terminate', processes);
    return result;
  }

  Future<WindowsInterferenceActionResult> _runPrivilegedAction(
    String action,
    List<WindowsInterferenceProcess> processes,
  ) async {
    final affected = <WindowsInterferenceProcess>[];
    final failures = <WindowsInterferenceFailure>[];
    if (!Platform.isWindows || processes.isEmpty) {
      return WindowsInterferenceActionResult(
        affected: affected,
        failures: failures,
      );
    }

    try {
      final rawResult = await _windowsRuntimeChannel.invokeMethod<Object?>(
        'manageInterferenceProcesses',
        <String, Object?>{
          'action': action,
          'pids': processes.map((process) => process.pid).toList(),
        },
      );
      if (rawResult is! Map) {
        throw StateError('Native Windows runtime returned an invalid result.');
      }
      final result = rawResult.cast<Object?, Object?>();
      if (result['ok'] != true) {
        final error = result['error']?.toString();
        throw StateError(
          error == null || error.isEmpty
              ? 'TemnyiVPN service could not manage the selected processes.'
              : error,
        );
      }

      final affectedPids = _intSet(result['affectedPids']);
      final failedPids = _intSet(result['failedPids']);
      final serviceError = result['error']?.toString();
      for (final process in processes) {
        if (affectedPids.contains(process.pid)) {
          affected.add(process);
        } else if (failedPids.contains(process.pid)) {
          failures.add(
            WindowsInterferenceFailure(
              process: process,
              message: serviceError == null || serviceError.isEmpty
                  ? 'The privileged service could not access this process.'
                  : serviceError,
            ),
          );
        }
      }
      return WindowsInterferenceActionResult(
        affected: affected,
        failures: failures,
      );
    } on MissingPluginException {
      for (final process in processes) {
        failures.add(
          WindowsInterferenceFailure(
            process: process,
            message:
                'The installed TemnyiVPN service is outdated. Reinstall the latest setup first.',
          ),
        );
      }
    } catch (error) {
      for (final process in processes) {
        failures.add(
          WindowsInterferenceFailure(
            process: process,
            message: _friendlyError(error),
          ),
        );
      }
    }

    return WindowsInterferenceActionResult(
      affected: affected,
      failures: failures,
    );
  }

  static Set<int> _intSet(Object? value) {
    if (value is! Iterable) {
      return const <int>{};
    }
    return value
        .whereType<num>()
        .map((item) => item.toInt())
        .where((item) => item > 0)
        .toSet();
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('Win32 5') || text.contains('Access is denied')) {
      return 'Administrator access is required. Reinstall or repair TemnyiVPN so the privileged service can handle this action.';
    }
    return text.startsWith('StateError: ') ? text.substring(12) : text;
  }

  _WindowsProcessApi get _windowsApi {
    return _api ??= _WindowsProcessApi();
  }
}

class _WindowsInterferenceRule {
  const _WindowsInterferenceRule({
    required this.displayName,
    required this.reason,
    this.exactExecutables = const <String>{},
    this.nameFragments = const <String>{},
  });

  final String displayName;
  final String reason;
  final Set<String> exactExecutables;
  final Set<String> nameFragments;

  static const List<_WindowsInterferenceRule>
  _rules = <_WindowsInterferenceRule>[
    _WindowsInterferenceRule(
      displayName: 'zapret',
      reason:
          'Filters traffic through WinDivert and can conflict with VPN routing.',
      exactExecutables: <String>{
        'zapret.exe',
        'winws.exe',
        'nfqws.exe',
        'tpws.exe',
      },
      nameFragments: <String>{'zapret', 'winws', 'nfqws', 'tpws'},
    ),
    _WindowsInterferenceRule(
      displayName: 'GoodbyeDPI',
      reason: 'Modifies TCP traffic and can make VPN connections unstable.',
      exactExecutables: <String>{'goodbyedpi.exe', 'goodbyedpi_gui.exe'},
      nameFragments: <String>{'goodbyedpi'},
    ),
    _WindowsInterferenceRule(
      displayName: 'ByeDPI',
      reason: 'Runs a DPI bypass proxy that can interfere with VPN traffic.',
      exactExecutables: <String>{'byedpi.exe', 'ciadpi.exe'},
      nameFragments: <String>{'byedpi', 'ciadpi'},
    ),
    _WindowsInterferenceRule(
      displayName: 'PowerTunnel',
      reason:
          'Runs a local traffic bypass proxy that can conflict with VPN mode.',
      exactExecutables: <String>{'powertunnel.exe', 'power-tunnel.exe'},
      nameFragments: <String>{'powertunnel', 'power-tunnel'},
    ),
    _WindowsInterferenceRule(
      displayName: 'GreenTunnel',
      reason:
          'Runs a local traffic bypass proxy that can conflict with VPN mode.',
      exactExecutables: <String>{'greentunnel.exe'},
      nameFragments: <String>{'greentunnel'},
    ),
  ];

  static _WindowsInterferenceRule? match(String executableName) {
    final normalized = executableName.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final rule in _rules) {
      if (rule.exactExecutables.contains(normalized)) {
        return rule;
      }
    }
    for (final rule in _rules) {
      for (final fragment in rule.nameFragments) {
        if (normalized.contains(fragment)) {
          return rule;
        }
      }
    }
    return null;
  }
}

class _WindowsProcessInfo {
  const _WindowsProcessInfo({required this.pid, required this.executableName});

  final int pid;
  final String executableName;
}

final class _ProcessEntry32W extends Struct {
  @Uint32()
  external int dwSize;

  @Uint32()
  external int cntUsage;

  @Uint32()
  external int th32ProcessID;

  @IntPtr()
  external int th32DefaultHeapID;

  @Uint32()
  external int th32ModuleID;

  @Uint32()
  external int cntThreads;

  @Uint32()
  external int th32ParentProcessID;

  @Int32()
  external int pcPriClassBase;

  @Uint32()
  external int dwFlags;

  @Array(260)
  external Array<Uint16> szExeFile;
}

typedef _CreateToolhelp32SnapshotNative = IntPtr Function(Uint32, Uint32);
typedef _CreateToolhelp32SnapshotDart = int Function(int, int);
typedef _Process32Native = Int32 Function(IntPtr, Pointer<_ProcessEntry32W>);
typedef _Process32Dart = int Function(int, Pointer<_ProcessEntry32W>);
typedef _OpenProcessNative = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenProcessDart = int Function(int, int, int);
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);
typedef _TerminateProcessNative = Int32 Function(IntPtr, Uint32);
typedef _TerminateProcessDart = int Function(int, int);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();
typedef _NtProcessNative = Int32 Function(IntPtr);
typedef _NtProcessDart = int Function(int);

class _WindowsProcessApi {
  _WindowsProcessApi()
    : _kernel32 = DynamicLibrary.open('kernel32.dll'),
      _ntdll = DynamicLibrary.open('ntdll.dll') {
    _createToolhelp32Snapshot = _kernel32
        .lookupFunction<
          _CreateToolhelp32SnapshotNative,
          _CreateToolhelp32SnapshotDart
        >('CreateToolhelp32Snapshot');
    _process32First = _kernel32
        .lookupFunction<_Process32Native, _Process32Dart>('Process32FirstW');
    _process32Next = _kernel32.lookupFunction<_Process32Native, _Process32Dart>(
      'Process32NextW',
    );
    _openProcess = _kernel32
        .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
    _closeHandle = _kernel32
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
    _terminateProcess = _kernel32
        .lookupFunction<_TerminateProcessNative, _TerminateProcessDart>(
          'TerminateProcess',
        );
    _getLastError = _kernel32
        .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
    _ntSuspendProcess = _lookupNtProcess('NtSuspendProcess');
    _ntResumeProcess = _lookupNtProcess('NtResumeProcess');
  }

  static const int _th32csSnapProcess = 0x00000002;
  static const int _invalidHandleValue = -1;
  static const int _processTerminate = 0x0001;
  static const int _processSuspendResume = 0x0800;

  final DynamicLibrary _kernel32;
  final DynamicLibrary _ntdll;
  late final _CreateToolhelp32SnapshotDart _createToolhelp32Snapshot;
  late final _Process32Dart _process32First;
  late final _Process32Dart _process32Next;
  late final _OpenProcessDart _openProcess;
  late final _CloseHandleDart _closeHandle;
  late final _TerminateProcessDart _terminateProcess;
  late final _GetLastErrorDart _getLastError;
  late final _NtProcessDart? _ntSuspendProcess;
  late final _NtProcessDart? _ntResumeProcess;

  List<_WindowsProcessInfo> enumerateProcesses() {
    final snapshot = _createToolhelp32Snapshot(_th32csSnapProcess, 0);
    if (snapshot == _invalidHandleValue) {
      throw StateError(
        'Could not enumerate Windows processes (${_lastWin32Error()}).',
      );
    }

    final entry = calloc<_ProcessEntry32W>();
    final processes = <_WindowsProcessInfo>[];
    try {
      entry.ref.dwSize = sizeOf<_ProcessEntry32W>();
      if (_process32First(snapshot, entry) == 0) {
        return processes;
      }

      while (true) {
        final executableName = _readUtf16Array(entry.ref.szExeFile);
        if (executableName.isNotEmpty) {
          processes.add(
            _WindowsProcessInfo(
              pid: entry.ref.th32ProcessID,
              executableName: executableName,
            ),
          );
        }
        entry.ref.dwSize = sizeOf<_ProcessEntry32W>();
        if (_process32Next(snapshot, entry) == 0) {
          break;
        }
      }
      return processes;
    } finally {
      calloc.free(entry);
      _closeHandle(snapshot);
    }
  }

  String? terminateProcess(int processId) {
    final handle = _openProcess(_processTerminate, 0, processId);
    if (handle == 0) {
      return 'OpenProcess failed: ${_lastWin32Error()}';
    }
    try {
      if (_terminateProcess(handle, 0) == 0) {
        return 'TerminateProcess failed: ${_lastWin32Error()}';
      }
      return null;
    } finally {
      _closeHandle(handle);
    }
  }

  String? suspendProcess(int processId) {
    final suspend = _ntSuspendProcess;
    if (suspend == null) {
      return 'NtSuspendProcess is unavailable on this Windows build.';
    }
    return _withSuspendResumeHandle(processId, (handle) {
      final status = suspend(handle);
      if (status != 0) {
        return 'NtSuspendProcess failed: NTSTATUS 0x${_hex32(status)}';
      }
      return null;
    });
  }

  String? resumeProcess(int processId) {
    final resume = _ntResumeProcess;
    if (resume == null) {
      return 'NtResumeProcess is unavailable on this Windows build.';
    }
    return _withSuspendResumeHandle(processId, (handle) {
      final status = resume(handle);
      if (status != 0) {
        return 'NtResumeProcess failed: NTSTATUS 0x${_hex32(status)}';
      }
      return null;
    });
  }

  _NtProcessDart? _lookupNtProcess(String name) {
    try {
      return _ntdll.lookupFunction<_NtProcessNative, _NtProcessDart>(name);
    } catch (_) {
      return null;
    }
  }

  String? _withSuspendResumeHandle(
    int processId,
    String? Function(int handle) action,
  ) {
    final handle = _openProcess(_processSuspendResume, 0, processId);
    if (handle == 0) {
      return 'OpenProcess failed: ${_lastWin32Error()}';
    }
    try {
      return action(handle);
    } finally {
      _closeHandle(handle);
    }
  }

  String _lastWin32Error() => 'Win32 ${_getLastError()}';

  static String _readUtf16Array(Array<Uint16> chars) {
    final units = <int>[];
    for (var i = 0; i < 260; i += 1) {
      final unit = chars[i];
      if (unit == 0) {
        break;
      }
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }

  static String _hex32(int value) {
    return (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  }
}
