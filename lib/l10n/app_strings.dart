import 'package:flutter/widgets.dart';

import '../models/split_tunnel.dart';
import '../models/vpn_profile.dart';

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();
  static const supportedLocales = <Locale>[Locale('ru'), Locale('en')];

  static AppStrings of(BuildContext context) {
    final strings = Localizations.of<AppStrings>(context, AppStrings);
    assert(strings != null, 'AppStrings not found in context');
    return strings!;
  }

  bool get _ru => language == AppLanguage.ru;

  String get tcpPingAction => _ru ? 'Пинг' : 'Ping';
  String get autoFastestAction => _ru ? 'Auto fastest' : 'Auto fastest';

  String get appSettingsCategoryLabel =>
      _ru ? 'Настройки приложения' : 'App settings';
  String get vpnSettingsCategoryLabel => _ru ? 'Настройки VPN' : 'VPN settings';
  String get otherSettingsCategoryLabel => _ru ? 'Прочее' : 'Other';
  String get languageSettingsLabel => _ru ? 'Язык' : 'Language';

  String get trafficModeLabel => _ru ? 'Режим' : 'Mode';
  String get systemProxyModeLabel => _ru ? 'Системный proxy' : 'System proxy';
  String get tunModeLabel => 'TUN';
  String get dnsSettingsLabel => _ru ? 'DNS серверы' : 'DNS servers';
  String get primaryDnsServerLabel => 'Primary DNS';
  String get secondaryDnsServerLabel => 'Secondary DNS';
  String get ipv4DnsServersLabel => 'IPv4';
  String get ipv6DnsServersLabel => 'IPv6';
  String get resetAction => 'Reset';
  String get saveAction => 'Save';
  String get dnsServersIncompleteMessage => 'Enter both DNS servers.';
  String dnsServersInvalid(String servers) => 'Invalid DNS: $servers';
  String get dnsModeLabel => _ru ? 'Режим DNS' : 'DNS mode';
  String get dnsModeClassicLabel => _ru ? 'Классический' : 'Classic';
  String get dnsModeDohLabel => 'DoH';
  String get dnsModeDotLabel => 'DoT';
  String get dohServerHint => 'https://1.1.1.1/dns-query';
  String get dotServerHint => '1.1.1.1 or cloudflare-dns.com';
  String get dohServerInvalidMessage =>
      _ru ? 'Введите https:// URL' : 'Enter an https:// URL';
  String get dotServerInvalidMessage =>
      _ru ? 'Введите хост (или хост:порт)' : 'Enter a host (or host:port)';
  String get tunIpModeLabel => _ru ? 'IP-режим TUN' : 'TUN IP mode';
  String get splitTunnelLabel => _ru ? 'Сплит-туннелинг' : 'Split tunneling';
  String get splitTunnelAppsLabel => _ru ? 'Приложения' : 'Applications';
  String get splitTunnelSearchHint =>
      _ru ? 'Поиск приложения' : 'Search applications';
  String get splitTunnelRefreshTooltip =>
      _ru ? 'Обновить список приложений' : 'Refresh application list';
  String get splitTunnelOffModeLabel => _ru ? 'Отключено' : 'Disabled';
  String get splitTunnelWhitelistModeLabel =>
      _ru ? 'Whitelist режим' : 'Whitelist mode';
  String get splitTunnelBlacklistModeLabel =>
      _ru ? 'Blacklist режим' : 'Blacklist mode';
  String splitTunnelSelectedCount(int count) =>
      _ru ? 'Выбрано: $count' : 'Selected: $count';
  String get splitTunnelNoAppsFound =>
      _ru ? 'Приложения не найдены.' : 'No applications found.';
  String get splitTunnelTunHint => _ru
      ? 'При включении сплита приложение использует TUN-режим.'
      : 'Enabling split tunneling switches the app to TUN mode.';
  String get appSplitTunnelLabel =>
      _ru ? 'Сплит-туннелинг приложений' : 'App split tunneling';
  String get domainSplitTunnelLabel =>
      _ru ? 'Сплит-туннелинг доменов' : 'Domain split tunneling';
  String get domainSplitTunnelDomainsLabel =>
      _ru ? 'Домены и IP' : 'Domains and IPs';
  String get domainSplitTunnelInputHint =>
      'domain.ru, *.ru, 1.2.3.4, 1.2.3.0/24';
  String get domainSplitTunnelAddTooltip =>
      _ru ? 'Добавить домен или IP' : 'Add domain or IP';
  String get domainSplitTunnelUdpPortsLabel =>
      _ru ? 'Исключенные UDP-порты' : 'Excluded UDP ports';
  String get domainSplitTunnelUdpPortInputHint => '443, 500, 4500';
  String get domainSplitTunnelUdpPortAddTooltip =>
      _ru ? 'Добавить UDP-порт' : 'Add UDP port';
  String domainSplitTunnelUdpPortsCount(int count) =>
      _ru ? 'Портов: $count' : 'Ports: $count';
  String get domainSplitTunnelNoUdpPorts =>
      _ru ? 'UDP-порты не добавлены.' : 'No UDP ports added.';
  String domainSplitTunnelSelectedCount(int count) =>
      _ru ? 'Выбрано: $count' : 'Selected: $count';
  String get domainSplitTunnelNoDomains =>
      _ru ? 'Домены и IP не добавлены.' : 'No domains or IPs added.';
  String get domainSplitTunnelTunHint => _ru
      ? 'Сплит-туннелинг доменов использует TUN-режим.'
      : 'Domain split tunneling uses TUN mode.';
  String get killswitchLabel => _ru ? 'Killswitch' : 'Killswitch';
  String get killswitchSubtitle => _ru
      ? 'Блокирует интернет при внезапном обрыве VPN'
      : 'Blocks internet if the VPN drops unexpectedly';
  String get killswitchEngagedNotification => _ru
      ? 'Killswitch активен — трафик заблокирован'
      : 'Killswitch active — internet blocked';
  String get killswitchUnsupportedMessage => _ru
      ? 'Killswitch недоступен на этой платформе.'
      : 'Killswitch is not available on this platform.';
  String get windowsInterferenceTitle =>
      _ru ? 'Найдены мешающие процессы' : 'Conflicting processes found';
  String get windowsInterferenceMessage => _ru
      ? 'Эти программы могут мешать стабильной работе VPN. Их можно закрыть полностью перед подключением.'
      : 'These programs can make the VPN unstable. You can close them before connecting.';
  String windowsInterferenceDetectedCount(int count) =>
      _ru ? 'Обнаружено: $count' : 'Detected: $count';
  String get windowsInterferenceCloseAction => _ru ? 'Закрыть' : 'Close';
  String get windowsInterferenceTerminateAction =>
      _ru ? 'Выключить все процессы' : 'Turn off all processes';
  String windowsInterferenceTerminatedMessage(int affected, int failed) => _ru
      ? 'Выключено процессов: $affected${failed > 0 ? ', ошибок: $failed' : ''}.'
      : 'Processes stopped: $affected${failed > 0 ? ', failed: $failed' : ''}.';
  String windowsInterferenceActionFailed(String error) => _ru
      ? 'Не удалось выполнить действие: $error'
      : 'Could not complete the action: $error';
  String get clearVpnCacheLabel =>
      _ru ? 'Полностью удалить кеш VPN' : 'Clear all VPN cache';
  String get clearVpnCacheSubtitle => _ru
      ? 'Удаляет профили, настройки, временные файлы и локальные данные'
      : 'Deletes profiles, settings, temporary files, and local data';
  String get clearVpnCacheDisabledSubtitle => _ru
      ? 'Отключите VPN перед очисткой'
      : 'Disconnect the VPN before clearing cache';
  String get clearVpnCacheDialogTitle =>
      _ru ? 'Удалить кеш VPN?' : 'Clear VPN cache?';
  String get clearVpnCacheDialogMessage => _ru
      ? 'Будут удалены добавленные конфиги, подписки, настройки, временные файлы и локальные данные TemnyiVPN/EntropyVPN на этом ПК. Это действие нельзя отменить.'
      : 'This will delete added configs, subscriptions, settings, temporary files, and local TemnyiVPN/EntropyVPN data on this PC. This cannot be undone.';
  String get clearVpnCacheConfirmAction => _ru ? 'Удалить кеш' : 'Clear cache';
  String clearVpnCacheSuccessMessage(int count) => _ru
      ? 'Кеш VPN удален. Удалено объектов: $count.'
      : 'VPN cache cleared. Deleted items: $count.';
  String clearVpnCachePartialMessage(int deleted, int failed) => _ru
      ? 'Кеш частично удален. Удалено: $deleted, ошибок: $failed.'
      : 'VPN cache partially cleared. Deleted: $deleted, failed: $failed.';
  String clearVpnCacheFailedMessage(Object error) => _ru
      ? 'Не удалось удалить кеш VPN: $error'
      : 'Could not clear VPN cache: $error';
  String get logsLabel => _ru ? 'Логи' : 'Logs';
  String get copyLogsAction => _ru ? 'Копировать логи' : 'Copy logs';
  String get noLogsYet => _ru ? 'Логи пока не появились.' : 'No logs yet.';
  String get logsCopiedMessage => _ru ? 'Логи скопированы.' : 'Logs copied.';
  String get notificationsSettingsLabel =>
      _ru ? 'Уведомления' : 'Notifications';
  String get updatesSettingsLabel => _ru ? 'Обновления' : 'Updates';
  String get inAppUpdateNotificationsLabel =>
      _ru ? 'In-app update notifications' : 'In-app update notifications';
  String get androidUpdateNotificationsLabel =>
      _ru ? 'Push notifications for updates' : 'Push notifications for updates';
  String get autoInstallUpdateLabel => _ru
      ? 'Automatically install update after downloading'
      : 'Automatically install update after downloading';
  String get checkForUpdatesAction =>
      _ru ? 'Проверить обновления' : 'Check for updates';
  String get appUpdateUpToDateMessage =>
      _ru ? 'У вас последняя версия.' : 'You are on the latest version.';
  String get appUpdateDialogTitle => _ru ? 'New update' : 'New update';
  String appUpdateAvailableMessage(String version) => _ru
      ? 'TemnyiVPN $version is available'
      : 'TemnyiVPN $version is available';
  String appUpdateCurrentVersion(String version) =>
      _ru ? 'Installed version: $version' : 'Installed version: $version';
  String appUpdatePublishedAt(String date) =>
      _ru ? 'Published: $date' : 'Published: $date';
  String get appUpdateOpenReleaseAction =>
      _ru ? 'Open release' : 'Open release';
  String get appUpdateOpenFailedMessage => _ru
      ? 'Could not open the release page.'
      : 'Could not open the release page.';
  String get appUpdateDownloadAction =>
      _ru ? 'Download update' : 'Download update';
  String get appUpdateApplyAction =>
      _ru ? 'Install and restart' : 'Install and restart';
  String appUpdateDownloadingMessage(int percent) =>
      _ru ? 'Downloading update… $percent%' : 'Downloading update… $percent%';
  String get appUpdatePreparingMessage =>
      _ru ? 'Preparing update…' : 'Preparing update…';
  String get appUpdateReadyMessage => _ru
      ? 'Update downloaded. The app will close to finish installing.'
      : 'Update downloaded. The app will close to finish installing.';
  String get appUpdateInstallingMessage =>
      _ru ? 'Installing update…' : 'Installing update…';
  String appUpdateFailedMessage(String error) =>
      _ru ? 'Update failed: $error' : 'Update failed: $error';
  String get inputLabel =>
      _ru ? 'Добавить конфиг или подписку' : 'Add a config or subscription';
  String get inputHint => _ru
      ? 'Вставьте ссылку vless://, vmess://, trojan://, ss://, hysteria://, hy2:// или http(s)-подписку'
      : 'Paste a vless://, vmess://, trojan://, ss://, hysteria://, hy2:// link, sing-box:// import link, sing-box JSON, or an http(s) subscription URL';
  String get addSourceAction => _ru ? 'Добавить' : 'Add';
  String get pasteFromClipboardAction =>
      _ru ? 'Вставить из буфера' : 'Paste from clipboard';
  String get clearInputAction => _ru ? 'Clear input' : 'Clear input';
  String get importFromJsonAction =>
      _ru ? 'Импортировать JSON файл' : 'Import from JSON';
  String get exportJsonAction => _ru ? 'Сохранить как JSON' : 'Save as JSON';
  String get jsonExportedMessage => 'JSON file exported.';
  String get jsonExportFailedMessage => 'Could not export the JSON file.';
  String get jsonImportFailedMessage =>
      'Could not import the selected JSON file.';
  String get scanQrAction => _ru ? 'Сканировать QR' : 'Scan QR';
  String get buyVpnAction => _ru ? 'Купить VPN' : 'Buy VPN';
  String get qrGalleryAction => _ru ? 'Галерея' : 'Gallery';
  String get qrCameraAction => _ru ? 'Камера' : 'Camera';
  String get qrPasteImageAction =>
      _ru ? 'Вставить изображение с QR' : 'Paste QR image';
  String get qrBrowseImageAction =>
      _ru ? 'Выбрать изображение' : 'Select image';
  String get qrClipboardImageMissingMessage =>
      _ru ? 'Clipboard has no image.' : 'Clipboard has no image.';
  String get turnFlashOnAction => _ru ? 'Turn flash on' : 'Turn flash on';
  String get turnFlashOffAction => _ru ? 'Turn flash off' : 'Turn flash off';
  String get qrCodeNotFoundMessage =>
      _ru ? 'No QR code found.' : 'No QR code found.';
  String get qrScanFailedMessage =>
      _ru ? 'Could not scan QR code.' : 'Could not scan QR code.';
  String get cameraUnavailableMessage =>
      _ru ? 'Camera unavailable.' : 'Camera unavailable.';
  String get clipboardEmptyMessage =>
      _ru ? 'Буфер обмена пуст.' : 'Clipboard is empty.';
  String get autoUpdateLabel => _ru ? 'Автообновление' : 'Auto-update';
  String get subscriptionTrafficLabel => _ru ? 'Трафик' : 'Traffic';
  String subscriptionTrafficUsedOf(String used, String total) =>
      '$used / $total';
  String subscriptionTrafficExpires(String date) =>
      _ru ? 'до $date' : 'until $date';
  String get aboutSubscriptionAction => _ru ? 'О подписке' : 'About';
  String get aboutSubscriptionDialogTitle => _ru ? 'О подписке' : 'About';
  String get profileInfoAction => _ru ? 'О конфигурации' : 'Config info';
  String get profileInfoCoreLabel => _ru ? 'Ядро' : 'Core';
  String get profileInfoProtocolLabel => _ru ? 'Протокол' : 'Protocol';
  String get profileInfoTransportLabel => _ru ? 'Транспорт' : 'Transport';
  String get profileInfoTlsLabel => _ru ? 'Шифрование' : 'Security';
  String get profileInfoServerLabel => _ru ? 'Сервер' : 'Server';
  String get aboutAppLabel => _ru ? 'О приложении' : 'About';
  String get aboutAppVersionLabel => _ru ? 'Версия приложения' : 'App version';
  String get subscriptionExpiresLabel => _ru ? 'Истекает' : 'Expires';
  String get closeAction => _ru ? 'Закрыть' : 'Close';
  String autoUpdateIntervalValue(Duration interval) {
    final minutes = interval.inMinutes;
    if (minutes < 60) {
      return _ru ? 'Каждые $minutes мин' : 'Every ${minutes}m';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes.remainder(60);
    if (remainingMinutes == 0) {
      if (_ru && hours == 1) {
        return 'Каждый час';
      }
      return _ru ? 'Каждые $hours ч' : 'Every ${hours}h';
    }
    return _ru
        ? 'Каждые $hours ч $remainingMinutes мин'
        : 'Every ${hours}h ${remainingMinutes}m';
  }

  String get noProfilesLoaded =>
      _ru ? 'Профили еще не загружены' : 'Profiles are not loaded yet';
  String get removeSourceAction => _ru ? 'Удалить' : 'Delete';
  String get updateNowAction => _ru ? 'Обновить' : 'Update';
  String get powerConnectedLabel => _ru ? 'Подключено' : 'Connected';
  String get powerDisconnectedLabel => _ru ? 'Отключено' : 'Disconnected';
  String get connectingLabel => _ru ? 'Подключение' : 'Connecting';
  String get disconnectingLabel => _ru ? 'Отключение' : 'Disconnecting';
  String get failedLabel => _ru ? 'Ошибка' : 'Error';
  String get profileSelectorLabel =>
      _ru ? 'Профиль из подписки' : 'Subscription profile';
  String profileSelectorHelper(int count) =>
      _ru ? 'Найдено профилей: $count' : 'Profiles found: $count';
  String get xrayLabel => 'Xray';
  String get singBoxLabel => 'Sing-box';
  String get russianLabel => _ru ? 'Русский' : 'Russian';
  String get englishLabel => 'English';

  String coreName(CoreFlavor core) => switch (core) {
    CoreFlavor.xray => xrayLabel,
    CoreFlavor.singBox => singBoxLabel,
  };

  String tunIpModeName(TunIpMode mode) => switch (mode) {
    TunIpMode.ipv4 => 'IPv4',
    TunIpMode.dualStack => 'IPv4 + IPv6',
    TunIpMode.ipv6 => 'IPv6',
  };

  String splitTunnelModeName(SplitTunnelMode mode) => switch (mode) {
    SplitTunnelMode.off => splitTunnelOffModeLabel,
    SplitTunnelMode.whitelist => splitTunnelWhitelistModeLabel,
    SplitTunnelMode.blacklist => splitTunnelBlacklistModeLabel,
  };

  String protocolName(LinkProtocol protocol) => switch (protocol) {
    LinkProtocol.vless => 'VLESS',
    LinkProtocol.vmess => 'VMess',
    LinkProtocol.trojan => 'Trojan',
    LinkProtocol.shadowsocks => 'Shadowsocks',
    LinkProtocol.hysteria => 'Hysteria',
    LinkProtocol.hysteria2 => 'Hysteria2',
  };

  String transportName(TransportMode transport) => switch (transport) {
    TransportMode.raw => 'RAW/TCP',
    TransportMode.ws => 'WebSocket',
    TransportMode.grpc => 'gRPC',
    TransportMode.http => 'HTTP',
    TransportMode.httpUpgrade => 'HTTPUpgrade',
    TransportMode.quic => 'QUIC',
    TransportMode.xhttp => 'XHTTP',
  };

  String tlsName(TlsMode tlsMode) => switch (tlsMode) {
    TlsMode.none => _ru ? 'Нет' : 'None',
    TlsMode.tls => 'TLS',
    TlsMode.reality => 'REALITY',
  };
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode == 'ru' || locale.languageCode == 'en';
  }

  @override
  Future<AppStrings> load(Locale locale) async {
    return AppStrings(
      locale.languageCode == 'ru' ? AppLanguage.ru : AppLanguage.en,
    );
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
