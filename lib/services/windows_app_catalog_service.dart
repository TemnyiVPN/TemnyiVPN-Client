import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/split_tunnel.dart';

class WindowsAppCatalogService {
  static const MethodChannel _androidControlChannel = MethodChannel(
    'entropy_vpn/control',
  );
  static const MethodChannel _windowsAppCatalogChannel = MethodChannel(
    'entropy_vpn/windows_app_catalog',
  );

  List<SplitTunnelApp>? _cachedApplications;
  Future<List<SplitTunnelApp>>? _loadingApplications;

  Future<List<SplitTunnelApp>> loadApplications({bool refresh = false}) {
    final cachedApplications = _cachedApplications;
    if (!refresh && cachedApplications != null) {
      return Future<List<SplitTunnelApp>>.value(cachedApplications);
    }

    final loadingApplications = _loadingApplications;
    if (loadingApplications != null) {
      return loadingApplications;
    }

    final future = _loadApplications()
        .then((applications) {
          final cached = List<SplitTunnelApp>.unmodifiable(applications);
          _cachedApplications = cached;
          return cached;
        })
        .whenComplete(() {
          _loadingApplications = null;
        });
    _loadingApplications = future;
    return future;
  }

  Future<List<SplitTunnelApp>> _loadApplications() async {
    if (Platform.isAndroid) {
      return _loadAndroidApplications();
    }

    if (!Platform.isWindows) {
      return const <SplitTunnelApp>[];
    }

    final apps = <SplitTunnelApp>[
      ...await _loadWindowsApplicationsNative(),
      ...await _loadWindowsGameApplications(),
    ];
    return _dedupeAndSort(apps);
  }

  Future<List<SplitTunnelApp>> _loadWindowsApplicationsNative() async {
    try {
      final rawItems = await _windowsAppCatalogChannel
          .invokeListMethod<dynamic>('listApplications');
      return _decodeApplications(rawItems ?? const <dynamic>[]);
    } on MissingPluginException {
      return const <SplitTunnelApp>[];
    } on PlatformException {
      return const <SplitTunnelApp>[];
    }
  }

  Future<List<SplitTunnelApp>> _loadAndroidApplications() async {
    try {
      final rawItems = await _androidControlChannel.invokeListMethod<dynamic>(
        'listInstalledApps',
      );
      return _decodeApplications(rawItems ?? const <dynamic>[]);
    } catch (_) {
      return const <SplitTunnelApp>[];
    }
  }

  Future<List<SplitTunnelApp>> _loadWindowsGameApplications() async {
    final apps = <SplitTunnelApp>[];
    apps.addAll(await _loadSteamGames());
    apps.addAll(await _loadEpicGames());
    apps.addAll(await _loadKnownGameFolders());
    return _dedupeAndSort(apps);
  }

  Future<List<SplitTunnelApp>> _loadSteamGames() async {
    final steamRoots = <String>{};
    final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
    final programFiles = Platform.environment['ProgramFiles'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (programFilesX86 != null) {
      steamRoots.add(_join(programFilesX86, 'Steam'));
    }
    if (programFiles != null) {
      steamRoots.add(_join(programFiles, 'Steam'));
    }
    if (localAppData != null) {
      steamRoots.add(_join(localAppData, 'Steam'));
    }

    final apps = <SplitTunnelApp>[];
    for (final steamRoot in steamRoots) {
      final steamApps = Directory(_join(steamRoot, 'steamapps'));
      if (!await steamApps.exists()) {
        continue;
      }
      final libraries = <String>{steamApps.path};
      final libraryFile = File(_join(steamApps.path, 'libraryfolders.vdf'));
      try {
        if (await libraryFile.exists()) {
          final raw = await libraryFile.readAsString();
          for (final path in _extractQuotedValues(raw, 'path')) {
            libraries.add(_join(path.replaceAll(r'\\', r'\'), 'steamapps'));
          }
        }
      } on FileSystemException {}

      for (final library in libraries) {
        apps.addAll(await _loadSteamLibraryGames(Directory(library)));
      }
    }
    return apps;
  }

  Future<List<SplitTunnelApp>> _loadSteamLibraryGames(
    Directory steamApps,
  ) async {
    final apps = <SplitTunnelApp>[];
    try {
      if (!await steamApps.exists()) {
        return const <SplitTunnelApp>[];
      }
      await for (final entity in steamApps.list(followLinks: false)) {
        if (entity is! File ||
            !_basename(entity.path).startsWith('appmanifest_')) {
          continue;
        }
        final raw = await entity.readAsString();
        final name = _firstQuotedValue(raw, 'name');
        final installDir = _firstQuotedValue(raw, 'installdir');
        if (installDir == null || installDir.trim().isEmpty) {
          continue;
        }
        final gameDir = Directory(
          _join(_join(steamApps.path, 'common'), installDir),
        );
        final exe = await _findBestGameExecutable(
          gameDir,
          gameName: name ?? installDir,
        );
        if (exe != null) {
          apps.add(
            SplitTunnelApp.fromPath(name: name ?? installDir, path: exe.path),
          );
        }
      }
    } on FileSystemException {}
    return apps;
  }

  Future<List<SplitTunnelApp>> _loadEpicGames() async {
    final programData = Platform.environment['PROGRAMDATA'];
    if (programData == null) {
      return const <SplitTunnelApp>[];
    }
    final manifests = Directory(
      _join(programData, 'Epic/EpicGamesLauncher/Data/Manifests'),
    );
    final apps = <SplitTunnelApp>[];
    try {
      if (!await manifests.exists()) {
        return const <SplitTunnelApp>[];
      }
      await for (final entity in manifests.list(followLinks: false)) {
        if (entity is! File ||
            !_basename(entity.path).toLowerCase().endsWith('.item')) {
          continue;
        }
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) {
          continue;
        }
        final installLocation = decoded['InstallLocation']?.toString();
        final displayName = decoded['DisplayName']?.toString();
        final launchExecutable = decoded['LaunchExecutable']?.toString();
        if (installLocation == null || installLocation.trim().isEmpty) {
          continue;
        }
        File? exe;
        if (launchExecutable != null && launchExecutable.trim().isNotEmpty) {
          final launchFile = File(_join(installLocation, launchExecutable));
          if (await launchFile.exists()) {
            exe = launchFile;
          }
        }
        exe ??= await _findBestGameExecutable(
          Directory(installLocation),
          gameName: displayName ?? _basename(installLocation),
        );
        if (exe != null) {
          apps.add(
            SplitTunnelApp.fromPath(
              name: displayName ?? _basenameWithoutExtension(exe.path),
              path: exe.path,
            ),
          );
        }
      }
    } on FileSystemException {
    } on FormatException {}
    return apps;
  }

  Future<List<SplitTunnelApp>> _loadKnownGameFolders() async {
    final roots = <String>{};
    for (final envName in <String>['ProgramFiles', 'ProgramFiles(x86)']) {
      final value = Platform.environment[envName];
      if (value == null || value.trim().isEmpty) {
        continue;
      }
      roots
        ..add(_join(value, 'Steam/steamapps/common'))
        ..add(_join(value, 'Epic Games'))
        ..add(_join(value, 'GOG Galaxy/Games'))
        ..add(_join(value, 'EA Games'))
        ..add(_join(value, 'Ubisoft/Ubisoft Game Launcher/games'))
        ..add(_join(value, 'Origin Games'));
    }

    final apps = <SplitTunnelApp>[];
    for (final root in roots) {
      final directory = Directory(root);
      try {
        if (!await directory.exists()) {
          continue;
        }
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is! Directory) {
            continue;
          }
          final exe = await _findBestGameExecutable(
            entity,
            gameName: _basename(entity.path),
            maxDepth: 2,
          );
          if (exe != null) {
            apps.add(
              SplitTunnelApp.fromPath(
                name: _humanizeGameName(_basename(entity.path)),
                path: exe.path,
              ),
            );
          }
        }
      } on FileSystemException {}
    }
    return apps;
  }

  Future<File?> _findBestGameExecutable(
    Directory root, {
    required String gameName,
    int maxDepth = 3,
  }) async {
    try {
      if (!await root.exists()) {
        return null;
      }
      final candidates = <File>[];
      await _collectExecutables(root, candidates, maxDepth: maxDepth);
      if (candidates.isEmpty) {
        return null;
      }
      candidates.sort((left, right) {
        final leftScore = _gameExecutableScore(left.path, gameName);
        final rightScore = _gameExecutableScore(right.path, gameName);
        if (leftScore != rightScore) {
          return rightScore.compareTo(leftScore);
        }
        return left.path.length.compareTo(right.path.length);
      });
      return candidates.first;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _collectExecutables(
    Directory root,
    List<File> output, {
    required int maxDepth,
    int depth = 0,
  }) async {
    if (depth > maxDepth) {
      return;
    }
    await for (final entity in root.list(followLinks: false)) {
      final name = _basename(entity.path).toLowerCase();
      if (entity is File && name.endsWith('.exe')) {
        if (!_isLikelyHelperExecutable(name)) {
          output.add(entity);
        }
      } else if (entity is Directory && !_isIgnoredGameDirectory(name)) {
        await _collectExecutables(
          entity,
          output,
          maxDepth: maxDepth,
          depth: depth + 1,
        );
      }
    }
  }

  int _gameExecutableScore(String path, String gameName) {
    final name = _basenameWithoutExtension(path).toLowerCase();
    final normalizedGame = _normalizeGameName(gameName);
    var score = 0;
    if (name == normalizedGame) {
      score += 100;
    }
    if (normalizedGame.isNotEmpty && name.contains(normalizedGame)) {
      score += 60;
    }
    if (name.contains('win64') || name.contains('shipping')) {
      score += 20;
    }
    if (name.contains('launcher') ||
        name.contains('crash') ||
        name.contains('setup')) {
      score -= 50;
    }
    if (name == 'hl2' && normalizedGame.contains('garry')) {
      score += 80;
    }
    if (name.contains('fortniteclient-win64-shipping')) {
      score += 120;
    }
    return score;
  }

  bool _isLikelyHelperExecutable(String name) {
    return name.contains('crash') ||
        name.contains('redist') ||
        name.contains('setup') ||
        name.contains('installer') ||
        name.contains('unins') ||
        name.contains('unitycrashhandler') ||
        name.contains('cefprocess') ||
        name.contains('helper') ||
        name.contains('bootstrap');
  }

  bool _isIgnoredGameDirectory(String name) {
    return name == '_commonredist' ||
        name == 'redist' ||
        name == 'redistributables' ||
        name == 'engine' ||
        name == 'binaries/thirdparty';
  }

  String? _firstQuotedValue(String raw, String key) {
    final pattern = RegExp(
      '"${RegExp.escape(key)}"\\s+"([^"]*)"',
      caseSensitive: false,
    );
    return pattern.firstMatch(raw)?.group(1);
  }

  Iterable<String> _extractQuotedValues(String raw, String key) {
    final pattern = RegExp(
      '"${RegExp.escape(key)}"\\s+"([^"]*)"',
      caseSensitive: false,
    );
    return pattern.allMatches(raw).map((match) => match.group(1) ?? '');
  }

  List<SplitTunnelApp> _decodeApplications(dynamic decoded) {
    final rawItems = decoded is List
        ? decoded
        : decoded is Map
        ? <dynamic>[decoded]
        : const <dynamic>[];
    final apps = <SplitTunnelApp>[];

    for (final item in rawItems) {
      if (item is! Map) {
        continue;
      }
      final name = item['name']?.toString() ?? '';
      final path = item['path']?.toString() ?? '';
      final app = SplitTunnelApp.fromPath(name: name, path: path);
      if (app.path.isEmpty) {
        continue;
      }
      apps.add(app);
    }

    return _dedupeAndSort(apps);
  }

  List<SplitTunnelApp> _dedupeAndSort(Iterable<SplitTunnelApp> input) {
    final apps = <SplitTunnelApp>[];
    final seen = <String>{};
    for (final app in input) {
      final normalized = app.normalized;
      if (normalized.path.isEmpty || !seen.add(normalized.id)) {
        continue;
      }
      apps.add(normalized);
    }
    apps.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return apps;
  }

  String _join(String left, String right) {
    if (left.endsWith(r'\') || left.endsWith('/')) {
      return '$left$right'.replaceAll('/', Platform.pathSeparator);
    }
    return '$left${Platform.pathSeparator}$right'.replaceAll(
      '/',
      Platform.pathSeparator,
    );
  }

  String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  String _basenameWithoutExtension(String path) {
    final name = _basename(path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  String _normalizeGameName(String value) {
    return _basenameWithoutExtension(
      value,
    ).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  String _humanizeGameName(String value) {
    return value.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
