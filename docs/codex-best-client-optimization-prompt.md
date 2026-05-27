# Codex Prompt: EntropyVPN Optimization, Low Ping, Simple UX

Ты работаешь в репозитории EntropyVPN: Flutter VPN client для Windows, Android и Linux с Xray-core, sing-box, TUN, system proxy, подписками и импортом share links.

Главная цель: сделать клиент быстрым, простым и с минимальной задержкой. Не переписывай проект с нуля. Улучшай существующую архитектуру: `VpnController`, native TCP ping через FFI, Windows native runtime/service, Android `VpnService`, текущие UI-компоненты и существующие тесты.

## Контекст по текущему коду

- Ping сейчас находится в `lib/services/tcp_ping_service.dart` и native C++ `native/share_link_parser.cpp`.
- В Dart задано `tcpPingTimeout = 5s`, `tcpPingMaxConcurrent = 8`.
- Native ping делает TCP connect latency, запускает batch через `Isolate.run`, возвращает только успешные результаты.
- `VpnController.pingSource()` и `pingProfile()` живут в `lib/services/vpn_controller.dart`.
- Для Windows TUN активного подключения есть `CoreRuntimeService.withTcpPingBypassRoutes()`, который временно добавляет host routes для ping.
- `ConfigSource` хранит `tcpPingLatenciesMs`, но не сохраняет их в `toJson()`. После рестарта измерения теряются.
- Подписки показываются в `lib/main_sources.dart`; списка поиска/сортировки по задержке нет.
- Android connect в `lib/services/core_runtime_service_android.dart` перед стартом вызывает `_resolveAndroidServerCountryCode(profile)`, который может делать DNS + HTTP GeoIP и задерживать подключение.
- Windows runtime уже оптимизирован через native runtime channel, service helper, prewarm TUN adapter и startup timing logs. Это надо сохранить.
- В проекте уже есть полезные тесты: `test/tcp_ping_service_test.dart`, `test/vpn_controller_test.dart`, `test/xray_tun_startup_timing_test.dart`, `test/app_state_store_test.dart`.

## Обязательные принципы

1. Низкий ping важнее красивых новых функций.
2. UX должен быть проще: меньше ручных действий, понятный выбор "лучший сервер".
3. Измерения должны быть быстрыми и не блокировать connect.
4. Не ломай Windows service/native runtime и Android quick settings tile.
5. Не отправляй пользовательские конфиги, ключи, UUID, пароли или подписки во внешние сервисы.
6. Любая сетевая проверка должна быть локальной: DNS/connect/protocol-safe probe к самому endpoint.
7. Сохраняй существующий стиль Flutter/Dart/Kotlin/C++ и lints.

## Приоритет 1: Smart Fastest Server

Реализуй режим автоматического выбора лучшего профиля в подписке.

Требования:

- Добавь понятную модель выбора профиля:
  - `manual`: пользователь сам выбрал профиль.
  - `fastest`: клиент выбирает профиль с минимальной задержкой.
- В `ConfigSource` добавь устойчивое хранение latency не только по индексу, а по стабильному ключу профиля.
- Добавь `measuredAt`, `failureCount`, возможно `lastError` для профиля, чтобы не выбирать старые или нестабильные результаты.
- При импорте или обновлении подписки:
  - не блокируй UI;
  - запускай быстрый background scan;
  - если включен `fastest`, выбирай лучший профиль автоматически;
  - если пользователь уже вручную выбрал профиль, не перетирай выбор без явного действия.
- При ручном нажатии "Ping" для всей подписки выбирай лучший профиль, если пользователь нажал отдельную команду "Best"/"Fastest".
- Сохраняй latency cache в `PersistedAppState`, но помечай старые измерения как stale.

Где смотреть:

- `lib/models/config_source.dart`
- `lib/services/vpn_controller.dart`
- `lib/services/tcp_ping_service.dart`
- `lib/services/app_state_store.dart`
- `lib/main_sources.dart`

## Приоритет 2: Faster And More Accurate Ping

Улучши ping так, чтобы он быстро находил хороший сервер и не зависал на плохих endpoints.

Текущая проблема: `timeout=5s` и `maxConcurrent=8` могут делать scan большой подписки слишком долгим.

Сделай:

- Двухфазный scan:
  - quick pass: короткий timeout около 800-1200 ms, concurrency 16-32;
  - fallback pass: только для выбранного/подозрительно хороших/неизмеренных профилей, timeout 2500-3000 ms.
- В native C++ добавь более дружелюбный Happy Eyeballs подход:
  - не ждать долго первый IPv6/IPv4 адрес, если второй может подключиться быстрее;
  - учитывать `TunIpMode` или параметр preferred address family там, где это безопасно.
- Не бросай ошибку "failed for all targets" как единственный UX-результат для частично плохой подписки; возвращай per-target failures в модель, чтобы UI мог показать "не измерен".
- Для UDP-first протоколов (`hysteria`, `hysteria2`) не делай вид, что TCP ping равен реальной задержке. Либо реализуй безопасный protocol-aware UDP probe, либо показывай отдельный статус "UDP latency unavailable" и не включай такие профили в TCP-only автосравнение без понижающего confidence.
- Не делай полноценную авторизацию или отправку секретов ради проверки ping.

Где смотреть:

- `lib/services/tcp_ping_service.dart`
- `native/share_link_parser.cpp`, блок `tcp_connect_latency_ms()` и `measure_tcp_pings_json()`
- `test/tcp_ping_service_test.dart`
- `test/vpn_controller_test.dart`

## Приоритет 3: Connect Must Not Wait For GeoIP

Убери любые неважные сетевые операции из критического пути подключения.

Найденная проблема:

- `CoreRuntimeServiceAndroid._startOnAndroid()` и `_saveAndroidStartPayload()` ждут `_resolveAndroidServerCountryCode(profile)`.
- `GeoIpService.resolveServer()` может делать DNS lookup до 4s и HTTP к `ipwho.is` до 5s+5s.
- Это может задержать Android connect ради флага страны в notification.

Сделай:

- Android start должен стартовать VPN сразу.
- Country code для notification должен браться только из уже готового cache или передаваться `null`.
- Если GeoIP нужен, обновляй его после подключения асинхронно и не блокируй runtime start.
- Добавь тест, который доказывает, что Android payload build/start не ждет slow GeoIP.

Где смотреть:

- `lib/services/core_runtime_service_android.dart`
- `lib/services/geo_ip_service.dart`
- `android/app/src/main/kotlin/com/example/entropy_vpn/EntropyVpnService.kt`
- `android/app/src/main/kotlin/com/example/entropy_vpn/EntropyVpnRuntimeStore.kt`

## Приоритет 4: Startup Optimization And Benchmarks

Сохрани текущие timing logs и добавь измеримые цели.

Цели:

- Windows system proxy connect: не регрессировать startup time.
- Windows TUN connect: использовать уже существующий prewarm/service path.
- Android connect: не ждать GeoIP, notification permission, slow DNS или UI work.
- Повторное подключение к тому же профилю должно быть быстрее за счет cache.

Что улучшить:

- Кешировать resolved core binary path в `CoreRuntimeService._resolveBinary()` с invalidation при ошибке.
- Не вызывать тяжелый stop/cleanup перед start, если runtime точно не запущен и нет pending cleanup.
- Проверить, где можно безопасно переиспользовать build config payload по ключу `(profile identity, core, traffic mode, tun ip mode, dns, split tunnel)`.
- Android `updateDefaultNetwork()` содержит retry loops с `Thread.sleep(100)`. Убери их из критического startup path, если можно сделать best-effort async update.
- Android runtime store сейчас публикует весь список logs на каждую строку. Сделай delta/revision events или coalescing, чтобы частые логи не дергали Flutter UI.

Где смотреть:

- `lib/services/core_runtime_service_process.dart`
- `lib/services/core_runtime_service_windows.dart`
- `lib/services/core_runtime_service_lifecycle.dart`
- `android/app/src/main/kotlin/com/example/entropy_vpn/EntropyVpnService.kt`
- `android/app/src/main/kotlin/com/example/entropy_vpn/EntropyVpnRuntimeStore.kt`
- `test/xray_tun_startup_timing_test.dart`

## Приоритет 5: Simpler UI

Сделай интерфейс проще для обычного пользователя.

Требования:

- На главном экране должен быть понятный сценарий:
  - добавить подписку;
  - нажать connect;
  - клиент сам выбрал лучший профиль.
- В подписке добавь:
  - поиск по названию/стране/server;
  - сортировку `Best ping`, `Name`, `Country`, `Protocol`;
  - явный чип/кнопку `Auto fastest` или `Best`;
  - компактный статус latency: `23 ms`, `stale`, `failed`, `checking`.
- Не перегружай карточки. Расширенные параметры оставь в settings.
- На mobile список подписки не должен становиться тяжелым при сотнях профилей.

Где смотреть:

- `lib/main_connect.dart`
- `lib/main_sources.dart`
- `lib/main_helpers.dart`
- `lib/l10n/app_strings.dart`

## Приоритет 6: Routing, DNS, And Protocol Defaults

Проверь дефолты на минимальную задержку без потери безопасности.

Сделай:

- Сохрани Windows default `systemProxy`, если пользователю не нужен full TUN, split tunnel или killswitch. Это быстрее и проще.
- Android остается TUN по архитектуре.
- Не включай `dualStack` по умолчанию, если IPv6 часто ломает endpoint. Добавь `Auto IP family` только если можешь подтвердить latency/route выбор тестами.
- Для DNS:
  - не ломай текущую поддержку classic/DoH/DoT;
  - не делай DNS-проверки в connect path;
  - добавь быстрый fallback только там, где это не меняет приватность неожиданно.
- Для sing-box/Xray config builder не меняй semantics существующих конфигов без тестов.

Где смотреть:

- `native/share_link_parser.cpp`
- `lib/services/core_config_builder.dart`
- `lib/models/dns_settings.dart`
- `lib/services/core_runtime_service_config_io.dart`

## Приоритет 7: Tests And Validation

Добавь или обнови тесты.

Минимум:

- `test/tcp_ping_service_test.dart`:
  - quick scan возвращает успешные targets;
  - timeout не блокирует весь batch слишком долго;
  - результаты сортируются/мапятся по profile key.
- `test/vpn_controller_test.dart`:
  - fastest mode выбирает профиль с минимальной latency;
  - manual mode не перетирается background scan;
  - refresh subscription сохраняет latency по стабильным ключам, где возможно;
  - stale/failure не побеждают свежий хороший latency.
- `test/app_state_store_test.dart`:
  - latency metadata round-trip.
- Android/GeoIP:
  - тест или injectable fake, который доказывает, что connect не ждет slow GeoIP.
- UI:
  - widget tests для сортировки/поиска, если локальные паттерны позволяют.

Перед финалом запусти:

```powershell
flutter test
flutter analyze
```

Если есть platform-specific build context:

```powershell
flutter build windows
```

Не запускай реальные elevated Windows TUN smoke tests без явного opt-in.

## Acceptance Criteria

Готово считается только если:

- Пользователь может импортировать подписку и нажать Connect без ручного выбора сервера.
- Клиент автоматически выбирает лучший доступный профиль, если включен `fastest`.
- Большая подписка не зависает из-за ping scan.
- Android connect не блокируется GeoIP.
- Latency переживает перезапуск, но stale данные не вводят в заблуждение.
- UI стал проще, а не сложнее.
- Существующие Windows service/runtime, Android tile и import flows не сломаны.
- Тесты покрывают новый выбор лучшего сервера и критичные performance paths.

## Не делай

- Не добавляй внешнюю телеметрию.
- Не отправляй конфиги/UUID/password/server list третьим сервисам.
- Не переписывай Flutter UI полностью.
- Не удаляй Windows native service path и prewarm TUN.
- Не делай ping через полноценное подключение с пользовательскими секретами, если это не нужно.
- Не меняй лицензию, package name или release updater без отдельной задачи.
