import 'dart:io';

class CacheCleanupResult {
  const CacheCleanupResult({
    required this.deletedPaths,
    required this.failedPaths,
  });

  final List<String> deletedPaths;
  final List<String> failedPaths;

  int get deletedCount => deletedPaths.length;
  bool get hasFailures => failedPaths.isNotEmpty;
}

class CacheCleanupService {
  Future<CacheCleanupResult> clearVpnCache() async {
    final deleted = <String>[];
    final failed = <String>[];
    final targets = <FileSystemEntity>[];

    void addDirectory(String? base, String child) {
      if (base == null || base.trim().isEmpty) {
        return;
      }
      targets.add(Directory(_joinPath(base, child)));
    }

    addDirectory(Platform.environment['LOCALAPPDATA'], 'EntropyVPN');
    addDirectory(Platform.environment['LOCALAPPDATA'], 'TemnyiVPN');
    addDirectory(Platform.environment['APPDATA'], 'EntropyVPN');
    addDirectory(Platform.environment['APPDATA'], 'TemnyiVPN');
    addDirectory(Platform.environment['PROGRAMDATA'], 'EntropyVPN');
    addDirectory(Platform.environment['PROGRAMDATA'], 'TemnyiVPN');

    final tempRoot = Directory.systemTemp;
    try {
      if (await tempRoot.exists()) {
        await for (final entity in tempRoot.list(followLinks: false)) {
          final name = _basename(entity.path).toLowerCase();
          if (name.startsWith('entropy_vpn_') ||
              name.startsWith('temnyivpn_') ||
              name.startsWith('temnyi_vpn_')) {
            targets.add(entity);
          }
        }
      }
    } on FileSystemException catch (error) {
      failed.add('${tempRoot.path}: ${error.message}');
    }

    final seen = <String>{};
    for (final target in targets) {
      final path = target.absolute.path;
      final key = path.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }
      try {
        if (await target.exists()) {
          await target.delete(recursive: true);
          deleted.add(path);
        }
      } on FileSystemException catch (error) {
        failed.add('$path: ${error.message}');
      }
    }

    return CacheCleanupResult(
      deletedPaths: List<String>.unmodifiable(deleted),
      failedPaths: List<String>.unmodifiable(failed),
    );
  }

  String _joinPath(String base, String child) {
    final normalized = base.endsWith(r'\') || base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$normalized${Platform.pathSeparator}$child';
  }

  String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }
}
