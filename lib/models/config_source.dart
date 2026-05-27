import 'vpn_profile.dart';

enum ConfigSourceKind { config, subscription }

enum ProfileSelectionMode { manual, fastest }

const int defaultSubscriptionAutoUpdateMinutes = 60;
const int minSubscriptionAutoUpdateMinutes = 15;
const int maxSubscriptionAutoUpdateMinutes = 24 * 60;
const int subscriptionAutoUpdateStepMinutes = 15;
const Duration tcpPingLatencyFreshness = Duration(minutes: 30);

class TcpPingProfileLatency {
  const TcpPingProfileLatency({
    required this.profileKey,
    this.latencyMs,
    this.measuredAt,
    this.failureCount = 0,
    this.lastError,
  });

  final String profileKey;
  final int? latencyMs;
  final DateTime? measuredAt;
  final int failureCount;
  final String? lastError;

  bool get hasLatency => latencyMs != null && latencyMs! > 0;
  bool get isFailure => !hasLatency && failureCount > 0;

  bool isStale([DateTime? now]) {
    final measured = measuredAt;
    if (measured == null) {
      return hasLatency;
    }
    final elapsed = (now ?? DateTime.now()).difference(measured);
    return elapsed.isNegative || elapsed >= tcpPingLatencyFreshness;
  }

  bool isFreshSuccess([DateTime? now]) => hasLatency && !isStale(now);

  TcpPingProfileLatency copyWith({
    String? profileKey,
    int? latencyMs,
    bool clearLatency = false,
    DateTime? measuredAt,
    bool clearMeasuredAt = false,
    int? failureCount,
    String? lastError,
    bool clearLastError = false,
  }) {
    return TcpPingProfileLatency(
      profileKey: profileKey ?? this.profileKey,
      latencyMs: clearLatency ? null : (latencyMs ?? this.latencyMs),
      measuredAt: clearMeasuredAt ? null : (measuredAt ?? this.measuredAt),
      failureCount: failureCount ?? this.failureCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileKey': profileKey,
      'latencyMs': latencyMs,
      'measuredAt': measuredAt?.toIso8601String(),
      'failureCount': failureCount,
      'lastError': _parseOptionalString(lastError),
    };
  }

  factory TcpPingProfileLatency.fromJson(Map<String, dynamic> json) {
    return TcpPingProfileLatency(
      profileKey: _parseOptionalString(json['profileKey']) ?? '',
      latencyMs: _parseOptionalPositiveInt(json['latencyMs']),
      measuredAt: _parseDateTime(json['measuredAt'] as String?),
      failureCount: _parseNonNegativeInt(json['failureCount']),
      lastError: _parseOptionalString(json['lastError']),
    );
  }
}

class SubscriptionTrafficUsage {
  const SubscriptionTrafficUsage({
    required this.uploadBytes,
    required this.downloadBytes,
    this.totalBytes,
    this.expiresAt,
  });

  final int uploadBytes;
  final int downloadBytes;
  final int? totalBytes;
  final DateTime? expiresAt;

  int get usedBytes => uploadBytes + downloadBytes;
  bool get hasTotal => totalBytes != null && totalBytes! > 0;

  double? get usageRatio {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    final ratio = usedBytes / total;
    if (ratio < 0) {
      return 0;
    }
    if (ratio > 1) {
      return 1;
    }
    return ratio;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'uploadBytes': uploadBytes,
      'downloadBytes': downloadBytes,
      'totalBytes': totalBytes,
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  factory SubscriptionTrafficUsage.fromJson(Map<String, dynamic> json) {
    return SubscriptionTrafficUsage(
      uploadBytes: _parseTrafficBytes(json['uploadBytes']),
      downloadBytes: _parseTrafficBytes(json['downloadBytes']),
      totalBytes: _parseOptionalTrafficBytes(json['totalBytes']),
      expiresAt: _parseDateTime(json['expiresAt'] as String?),
    );
  }
}

class ConfigSource {
  const ConfigSource({
    required this.id,
    required this.rawInput,
    required this.kind,
    this.displayName,
    this.profiles = const <ParsedVpnProfile>[],
    this.selectedProfileIndex = 0,
    this.profileSelectionMode = ProfileSelectionMode.manual,
    this.isUpdating = false,
    this.isPinging = false,
    this.lastUpdatedAt,
    this.lastUpdateError,
    this.autoUpdateIntervalMinutes = defaultSubscriptionAutoUpdateMinutes,
    this.trafficUsage,
    this.tcpPingProfileLatencies =
        const <String, TcpPingProfileLatency>{},
    this.tcpPingLatenciesMs = const <int, int>{},
    this.tcpPingLatencyMs,
    this.tcpPingProfileIndex,
  });

  final String id;
  final String rawInput;
  final ConfigSourceKind kind;
  final String? displayName;
  final List<ParsedVpnProfile> profiles;
  final int selectedProfileIndex;
  final ProfileSelectionMode profileSelectionMode;
  final bool isUpdating;
  final bool isPinging;
  final DateTime? lastUpdatedAt;
  final String? lastUpdateError;
  final int autoUpdateIntervalMinutes;
  final SubscriptionTrafficUsage? trafficUsage;
  final Map<String, TcpPingProfileLatency> tcpPingProfileLatencies;
  final Map<int, int> tcpPingLatenciesMs;
  final int? tcpPingLatencyMs;
  final int? tcpPingProfileIndex;

  bool get isSubscription => kind == ConfigSourceKind.subscription;
  bool get hasMultipleProfiles => profiles.length > 1;
  bool get hasProfiles => profiles.isNotEmpty;
  int get normalizedAutoUpdateIntervalMinutes =>
      normalizeSubscriptionAutoUpdateMinutes(autoUpdateIntervalMinutes);
  Duration get autoUpdateInterval =>
      Duration(minutes: normalizedAutoUpdateIntervalMinutes);

  ParsedVpnProfile? get selectedProfile {
    if (profiles.isEmpty) {
      return null;
    }

    final safeIndex = selectedProfileIndex.clamp(0, profiles.length - 1);
    return profiles[safeIndex];
  }

  int? tcpPingLatencyForProfile(int profileIndex) {
    return tcpPingLatencyInfoForProfile(profileIndex)?.latencyMs ??
        tcpPingLatenciesMs[profileIndex] ??
        (tcpPingProfileIndex == profileIndex ? tcpPingLatencyMs : null);
  }

  TcpPingProfileLatency? tcpPingLatencyInfoForProfile(int profileIndex) {
    if (profileIndex < 0 || profileIndex >= profiles.length) {
      return null;
    }
    return tcpPingProfileLatencies[vpnProfileIdentityKey(profiles[profileIndex])];
  }

  ConfigSource copyWith({
    String? id,
    String? rawInput,
    ConfigSourceKind? kind,
    String? displayName,
    bool clearDisplayName = false,
    List<ParsedVpnProfile>? profiles,
    int? selectedProfileIndex,
    ProfileSelectionMode? profileSelectionMode,
    bool? isUpdating,
    bool? isPinging,
    DateTime? lastUpdatedAt,
    bool clearLastUpdatedAt = false,
    String? lastUpdateError,
    bool clearLastUpdateError = false,
    int? autoUpdateIntervalMinutes,
    SubscriptionTrafficUsage? trafficUsage,
    bool clearTrafficUsage = false,
    Map<String, TcpPingProfileLatency>? tcpPingProfileLatencies,
    bool clearTcpPingProfileLatencies = false,
    Map<int, int>? tcpPingLatenciesMs,
    bool clearTcpPingLatencies = false,
    int? tcpPingLatencyMs,
    bool clearTcpPingLatency = false,
    int? tcpPingProfileIndex,
    bool clearTcpPingProfileIndex = false,
    bool clearTcpPing = false,
  }) {
    final nextProfiles = profiles ?? this.profiles;
    final nextIndex = nextProfiles.isEmpty
        ? 0
        : (selectedProfileIndex ?? this.selectedProfileIndex).clamp(
            0,
            nextProfiles.length - 1,
          );

    return ConfigSource(
      id: id ?? this.id,
      rawInput: rawInput ?? this.rawInput,
      kind: kind ?? this.kind,
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      profiles: nextProfiles,
      selectedProfileIndex: nextIndex,
      profileSelectionMode: profileSelectionMode ?? this.profileSelectionMode,
      isUpdating: isUpdating ?? this.isUpdating,
      isPinging: clearTcpPing ? false : (isPinging ?? this.isPinging),
      lastUpdatedAt: clearLastUpdatedAt
          ? null
          : (lastUpdatedAt ?? this.lastUpdatedAt),
      lastUpdateError: clearLastUpdateError
          ? null
          : (lastUpdateError ?? this.lastUpdateError),
      autoUpdateIntervalMinutes: normalizeSubscriptionAutoUpdateMinutes(
        autoUpdateIntervalMinutes ?? this.autoUpdateIntervalMinutes,
      ),
      trafficUsage: clearTrafficUsage
          ? null
          : (trafficUsage ?? this.trafficUsage),
      tcpPingProfileLatencies:
          clearTcpPing || clearTcpPingProfileLatencies
          ? const <String, TcpPingProfileLatency>{}
          : (tcpPingProfileLatencies ?? this.tcpPingProfileLatencies),
      tcpPingLatenciesMs: clearTcpPing || clearTcpPingLatencies
          ? const <int, int>{}
          : (tcpPingLatenciesMs ?? this.tcpPingLatenciesMs),
      tcpPingLatencyMs: clearTcpPing || clearTcpPingLatency
          ? null
          : (tcpPingLatencyMs ?? this.tcpPingLatencyMs),
      tcpPingProfileIndex: clearTcpPing || clearTcpPingProfileIndex
          ? null
          : (tcpPingProfileIndex ?? this.tcpPingProfileIndex),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'rawInput': rawInput,
      'kind': kind.name,
      'displayName': _parseOptionalString(displayName),
      'profiles': profiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      'selectedProfileIndex': selectedProfileIndex,
      'profileSelectionMode': profileSelectionMode.name,
      'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
      'lastUpdateError': lastUpdateError,
      'autoUpdateIntervalMinutes': normalizedAutoUpdateIntervalMinutes,
      'trafficUsage': trafficUsage?.toJson(),
      'tcpPingProfileLatencies': tcpPingProfileLatencies.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'tcpPingLatenciesMs': tcpPingLatenciesMs.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'tcpPingLatencyMs': tcpPingLatencyMs,
      'tcpPingProfileIndex': tcpPingProfileIndex,
    };
  }

  factory ConfigSource.fromJson(Map<String, dynamic> json) {
    final profiles = ((json['profiles'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ParsedVpnProfile.fromJson)
        .toList(growable: false);

    return ConfigSource(
      id: (json['id'] as String?) ?? '',
      rawInput: (json['rawInput'] as String?) ?? '',
      kind: _configSourceKindByName(json['kind'] as String?),
      displayName: _parseOptionalString(json['displayName']),
      profiles: profiles,
      selectedProfileIndex:
          (json['selectedProfileIndex'] as num?)?.toInt() ?? 0,
      profileSelectionMode: _profileSelectionModeByName(
        json['profileSelectionMode'] as String?,
      ),
      lastUpdatedAt: _parseDateTime(json['lastUpdatedAt'] as String?),
      lastUpdateError: json['lastUpdateError'] as String?,
      autoUpdateIntervalMinutes: _parseAutoUpdateIntervalMinutes(
        json['autoUpdateIntervalMinutes'],
      ),
      trafficUsage: _parseTrafficUsage(json['trafficUsage']),
      tcpPingProfileLatencies: _parseTcpPingProfileLatencies(
        json['tcpPingProfileLatencies'],
      ),
      tcpPingLatenciesMs: _parseTcpPingLatenciesMs(
        json['tcpPingLatenciesMs'],
      ),
      tcpPingLatencyMs: _parseOptionalPositiveInt(json['tcpPingLatencyMs']),
      tcpPingProfileIndex: _parseOptionalProfileIndex(
        json['tcpPingProfileIndex'],
        profiles.length,
      ),
    );
  }
}

int normalizeSubscriptionAutoUpdateMinutes(int minutes) {
  final clamped = minutes.clamp(
    minSubscriptionAutoUpdateMinutes,
    maxSubscriptionAutoUpdateMinutes,
  );
  final steps =
      ((clamped - minSubscriptionAutoUpdateMinutes) /
              subscriptionAutoUpdateStepMinutes)
          .round();
  return minSubscriptionAutoUpdateMinutes +
      steps * subscriptionAutoUpdateStepMinutes;
}

ConfigSourceKind _configSourceKindByName(String? name) {
  if (name == ConfigSourceKind.subscription.name) {
    return ConfigSourceKind.subscription;
  }
  return ConfigSourceKind.config;
}

ProfileSelectionMode _profileSelectionModeByName(String? name) {
  if (name == ProfileSelectionMode.fastest.name) {
    return ProfileSelectionMode.fastest;
  }
  return ProfileSelectionMode.manual;
}

DateTime? _parseDateTime(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

String? _parseOptionalString(Object? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.toString().trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _parseAutoUpdateIntervalMinutes(Object? value) {
  if (value is num) {
    return normalizeSubscriptionAutoUpdateMinutes(value.toInt());
  }
  return defaultSubscriptionAutoUpdateMinutes;
}

int _parseNonNegativeInt(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    return value.toInt();
  }
  return 0;
}

int? _parseOptionalPositiveInt(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    return value.toInt();
  }
  return null;
}

int? _parseOptionalProfileIndex(Object? value, int profileCount) {
  if (value is! num || !value.isFinite) {
    return null;
  }
  final index = value.toInt();
  if (index < 0 || index >= profileCount) {
    return null;
  }
  return index;
}

Map<String, TcpPingProfileLatency> _parseTcpPingProfileLatencies(
  Object? value,
) {
  if (value is! Map) {
    return const <String, TcpPingProfileLatency>{};
  }

  final result = <String, TcpPingProfileLatency>{};
  for (final entry in value.entries) {
    final key = entry.key?.toString().trim();
    if (key == null || key.isEmpty) {
      continue;
    }
    final item = entry.value;
    final Map<String, dynamic>? json = item is Map<String, dynamic>
        ? item
        : item is Map
        ? item.map((key, value) => MapEntry(key.toString(), value))
        : null;
    if (json == null) {
      continue;
    }

    final latency = TcpPingProfileLatency.fromJson(<String, dynamic>{
      ...json,
      'profileKey': json['profileKey'] ?? key,
    });
    if (latency.profileKey.isNotEmpty) {
      result[latency.profileKey] = latency;
    }
  }
  return Map<String, TcpPingProfileLatency>.unmodifiable(result);
}

Map<int, int> _parseTcpPingLatenciesMs(Object? value) {
  if (value is! Map) {
    return const <int, int>{};
  }

  final result = <int, int>{};
  for (final entry in value.entries) {
    final key = int.tryParse(entry.key?.toString() ?? '');
    final latencyMs = _parseOptionalPositiveInt(entry.value);
    if (key != null && key >= 0 && latencyMs != null) {
      result[key] = latencyMs;
    }
  }
  return Map<int, int>.unmodifiable(result);
}

SubscriptionTrafficUsage? _parseTrafficUsage(Object? value) {
  if (value is Map<String, dynamic>) {
    return SubscriptionTrafficUsage.fromJson(value);
  }
  if (value is Map) {
    return SubscriptionTrafficUsage.fromJson(
      value.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
  return null;
}

int _parseTrafficBytes(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    return value.toInt();
  }
  return 0;
}

int? _parseOptionalTrafficBytes(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    return value.toInt();
  }
  return null;
}
