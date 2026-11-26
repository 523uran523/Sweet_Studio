import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../core/app_pin_service.dart';
import '../core/money_format.dart';
import '../core/utils/app_utils.dart';
import '../core/yandex_oauth.dart';

/// Налоговый профиль: страна + режим налогообложения + ставка.
class TaxProfile {
  final String id;
  final String country;
  final String name;
  final int ratePercent;

  const TaxProfile({
    required this.id,
    required this.country,
    required this.name,
    required this.ratePercent,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'country': country,
    'name': name,
    'ratePercent': ratePercent,
  };

  factory TaxProfile.fromJson(Map<String, dynamic> json) => TaxProfile(
    id: json['id'] as String,
    country: json['country'] as String,
    name: json['name'] as String,
    ratePercent: json['ratePercent'] as int,
  );

  TaxProfile copyWith({
    String? id,
    String? country,
    String? name,
    int? ratePercent,
  }) => TaxProfile(
    id: id ?? this.id,
    country: country ?? this.country,
    name: name ?? this.name,
    ratePercent: ratePercent ?? this.ratePercent,
  );
}

/// Стандартные пресеты налоговых профилей для первого запуска.
const _defaultTaxProfiles = [
  TaxProfile(
    id: 'ru_4',
    country: 'RU',
    name: 'Самозанятость 4%',
    ratePercent: 4,
  ),
  TaxProfile(
    id: 'ru_6',
    country: 'RU',
    name: 'Самозанятость 6%',
    ratePercent: 6,
  ),
  TaxProfile(id: 'kz_2', country: 'KZ', name: 'Самозанятый', ratePercent: 2),
  TaxProfile(id: 'us_0', country: 'US', name: 'Sole prop', ratePercent: 0),
];

enum AppThemeMode { system, light, dark }

extension AppThemeModeLabel on AppThemeMode {
  String get label => switch (this) {
    AppThemeMode.system => 'Системная',
    AppThemeMode.light => 'Светлая',
    AppThemeMode.dark => 'Тёмная',
  };

  String get shortLabel => switch (this) {
    AppThemeMode.system => 'Система',
    AppThemeMode.light => 'Светлая',
    AppThemeMode.dark => 'Тёмная',
  };
}

class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs);

  final SharedPreferences _prefs;

  static const _themeKey = 'theme_mode';
  static const _businessTypeKey = 'business_type';
  static const _modulesKey = 'modules';
  static const _objectTermKey = 'object_term';
  static const _clientTermKey = 'client_term';
  // Устаревшие ключи WebDAV (логин/пароль): удаляются при загрузке.
  static const _legacyYandexLoginKey = 'yandex_login';
  static const _legacyYandexPasswordKey = 'yandex_password';
  static const _yandexTokenKey = 'yandex_access_token';
  static const _yandexRefreshTokenKey = 'yandex_refresh_token';
  static const _yandexTokenExpiresKey = 'yandex_token_expires_at';
  static const _yandexLastCloudModifiedKey = 'yandex_last_cloud_modified_at';
  static const _yandexAutoBackupKey = 'yandex_auto_backup';
  static const _onboardingKey = 'onboarding_done';
  static const _reminderEnabledKey = 'reminder_enabled';
  static const _reminderHourKey = 'reminder_hour';
  static const _reminderMinuteKey = 'reminder_minute';
  static const _dndEnabledKey = 'dnd_enabled';
  static const _hiddenTabsKey = 'hidden_tabs_v2';
  static const _taxRateKey = 'tax_rate';
  static const _taxProfilesKey = 'tax_profiles';
  static const _activeTaxProfileIdKey = 'active_tax_profile_id';
  static const _taxAccountKey = 'tax_account';
  static const _taxIncomeLimitCentsKey = 'tax_income_limit_cents';
  static const _taxRadarEnabledKey = 'tax_radar_enabled';
  static const _hourRateCentsKey = 'hour_rate_cents';
  static const _jobTagsKey = 'job_tags';
  static const _jobTagsEnabledKey = 'job_tags_enabled';
  static const _appPinHashKey = 'app_pin_hash';
  static const _appPinUnlockedUntilKey = 'app_pin_unlocked_until';
  static const _appBiometricEnabledKey = 'app_biometric_enabled';
  static const _cashShiftEnabledKey = 'cash_shift_enabled';
  static const _kanbanColumnsKey = 'kanban_columns';
  static const _teamEnabledKey = 'team_enabled';
  static const _leadsEnabledKey = 'module_leads';
  static const _creditsEnabledKey = 'module_credits';
  static const _locationsEnabledKey = 'module_locations';
  static const _calculatorEnabledKey = 'calculator_enabled';
  static const _workModeKey = 'work_mode';
  static const _updateMirrorEnabledKey = 'update_mirror_enabled';
  static const _updateMirrorUrlKey = 'update_mirror_url';
  static const _updateChannelKey = 'update_channel';
  static const _currencyCodeKey = 'currency_code';
  static const _currencySymbolKey = 'currency_symbol';
  static const _currencyDecimalsKey = 'currency_decimals';
  static const _moneySeparatorsKey = 'money_separators';

  static Future<SettingsController> load() async {
    tzdata.initializeTimeZones();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController._(prefs);
    currentMoneyFormat = settings.moneyFormat;
    // Миграция: пароли Яндекс Диска больше не хранятся в приложении.
    await prefs.remove(_legacyYandexLoginKey);
    await prefs.remove(_legacyYandexPasswordKey);
    return settings;
  }

  AppThemeMode get themeMode {
    final raw = _prefs.getString(_themeKey);
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => AppThemeMode.system,
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    await _prefs.setString(_themeKey, mode.name);
    notifyListeners();
  }

  bool get reminderEnabled => _prefs.getBool(_reminderEnabledKey) ?? false;

  int get reminderHour => _prefs.getInt(_reminderHourKey) ?? 20;

  int get reminderMinute => _prefs.getInt(_reminderMinuteKey) ?? 0;

  Future<void> setReminder(bool enabled, {int? hour, int? minute}) async {
    await _prefs.setBool(_reminderEnabledKey, enabled);
    if (hour != null) await _prefs.setInt(_reminderHourKey, hour);
    if (minute != null) await _prefs.setInt(_reminderMinuteKey, minute);
    notifyListeners();
  }

  bool get dndEnabled => _prefs.getBool(_dndEnabledKey) ?? false;

  Future<void> setDndEnabled(bool value) async {
    await _prefs.setBool(_dndEnabledKey, value);
    notifyListeners();
  }

  List<int> get hiddenTabs => (_prefs.getStringList(_hiddenTabsKey) ?? const [])
      .map((e) => int.tryParse(e) ?? -1)
      .where((e) => e >= 0)
      .toSet()
      .toList();

  bool isTabVisible(int index) => !hiddenTabs.contains(index);

  Future<void> toggleTabVisible(int index, {required bool visible}) async {
    if (index < 0 || index > 5) return;
    final list = <int>[...hiddenTabs];
    if (visible) {
      list.remove(index);
    } else if (!list.contains(index)) {
      list.add(index);
    }
    await _prefs.setStringList(
      _hiddenTabsKey,
      list.map((e) => e.toString()).toList(),
    );
    notifyListeners();
  }

  String get businessType => _prefs.getString(_businessTypeKey) ?? 'service';
  List<String> get modules => (_prefs.getString(_modulesKey) ?? '')
      .split(',')
      .where((e) => e.isNotEmpty)
      .toList();
  String get objectTerm => _prefs.getString(_objectTermKey) ?? 'Объект';
  String get clientTerm => _prefs.getString(_clientTermKey) ?? 'Клиент';
  int get taxRate => _prefs.getInt(_taxRateKey) ?? 0;

  /// Код валюты (`RUB`, `KZT`, `USD`…). Хранится отдельно от знака:
  /// знак меняется вместе с локалью, а код нужен отчётам и экспорту.
  String get currencyCode => _prefs.getString(_currencyCodeKey) ?? 'RUB';

  /// Валюты, у которых знак ставится перед суммой.
  static const _symbolBeforeCurrencies = <String>{'USD', 'EUR', r'$', '€'};

  /// Денежный формат для экранов и документов.
  ///
  /// Знак и число знаков после запятой берутся из настроек, разделители —
  /// из одной строки `money_separators` (`" |,"` — группа и дробь). Так
  /// пользователь получает `1 200,50 ₽` или `$1,200.50`.
  MoneyFormat get moneyFormat {
    final raw = _prefs.getString(_moneySeparatorsKey) ?? '';
    final parts = raw.split('|');
    final group = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : ' ';
    final decimal = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : ',';
    final symbol = _prefs.getString(_currencySymbolKey) ?? '₽';
    final decimals = _prefs.getInt(_currencyDecimalsKey) ?? 0;
    return MoneyFormat(
      symbol: symbol,
      decimals: decimals.clamp(0, 2),
      groupSeparator: group,
      decimalSeparator: decimal,
      // Рубль и тенге пишутся после суммы, доллар и евро — перед ней.
      symbolAfter:
          !_symbolBeforeCurrencies.contains(currencyCode) &&
          !_symbolBeforeCurrencies.contains(symbol),
    );
  }

  /// Сохраняет валюту и разделители.
  ///
  /// Пустой [symbol] означает «без знака»: часть пользователей ведёт учёт
  /// в условных единицах и не хочет видеть чужой символ.
  Future<void> setCurrency({
    String? code,
    String? symbol,
    int? decimals,
    String? groupSeparator,
    String? decimalSeparator,
  }) async {
    if (code != null) await _prefs.setString(_currencyCodeKey, code);
    if (symbol != null) await _prefs.setString(_currencySymbolKey, symbol);
    if (decimals != null) {
      await _prefs.setInt(_currencyDecimalsKey, decimals.clamp(0, 2));
    }
    if (groupSeparator != null || decimalSeparator != null) {
      final current = moneyFormat;
      await _prefs.setString(
        _moneySeparatorsKey,
        '${groupSeparator ?? current.groupSeparator}|'
        '${decimalSeparator ?? current.decimalSeparator}',
      );
    }
    currentMoneyFormat = moneyFormat;
    notifyListeners();
  }

  /// Список налоговых профилей. При первом чтении лениво инициализируется
  /// пресетами, если профилей ещё нет и старый taxRate не задан.
  List<TaxProfile> get taxProfiles {
    final raw = _prefs.getString(_taxProfilesKey);
    if (raw == null || raw.isEmpty) {
      // Ленивая инициализация пресетов: только если старый taxRate тоже не задан.
      if (taxRate == 0) {
        _initDefaultProfiles();
        // Пресеты записаны в prefs (кэш in-memory обновлён синхронно);
        // возвращаем их напрямую, не рекурсивно.
        return _defaultTaxProfiles;
      }
      return const [];
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TaxProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Повреждённые данные не затираем старый taxRate.
      return const [];
    }
  }

  /// ID активного налогового профиля.
  String? get activeTaxProfileId => _prefs.getString(_activeTaxProfileIdKey);

  /// Активный налоговый профиль или null.
  TaxProfile? get activeTaxProfile {
    final id = activeTaxProfileId;
    if (id == null) return null;
    for (final p in taxProfiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Активный налоговый профиль относится к НПД (лимит дохода применим).
  /// Для УСН/без налога — false. Если профилей нет — true (радар работает).
  bool get npdLimitApplies {
    final profile = activeTaxProfile;
    if (profile == null) return true;
    return profile.name.toLowerCase().contains('самозанят');
  }

  /// Ставка активного профиля. Если профилей нет или активный не найден —
  /// fallback на старый taxRate для обратной совместимости.
  int getActiveTaxRate() {
    final active = activeTaxProfile;
    if (active != null) return active.ratePercent;
    if (taxProfiles.isNotEmpty) {
      // Активный не определён — 0, чтобы не молча подставлять ставку.
      return 0;
    }
    // Нет профилей → fallback на старый taxRate.
    return taxRate;
  }

  /// Инициализация пресетов профилей (ленивая, без форсирования при old taxRate).
  void _initDefaultProfiles() {
    // В SharedPreferences setString обновляет кэш синхронно; запись не блокируем UI.
    unawaited(
      _prefs.setString(
        _taxProfilesKey,
        jsonEncode(_defaultTaxProfiles.map((p) => p.toJson()).toList()),
      ),
    );
    unawaited(
      _prefs.setString(_activeTaxProfileIdKey, _defaultTaxProfiles.first.id),
    );
  }

  /// Добавить новый профиль.
  Future<void> addTaxProfile(TaxProfile profile) async {
    final list = [...taxProfiles, profile];
    await _prefs.setString(
      _taxProfilesKey,
      jsonEncode(list.map((p) => p.toJson()).toList()),
    );
    // Если нет активного — сделать новый активным.
    if (activeTaxProfileId == null) {
      await _prefs.setString(_activeTaxProfileIdKey, profile.id);
    }
    notifyListeners();
  }

  /// Обновить существующий профиль.
  Future<void> updateTaxProfile(TaxProfile profile) async {
    final list = taxProfiles
        .map((p) => p.id == profile.id ? profile : p)
        .toList();
    await _prefs.setString(
      _taxProfilesKey,
      jsonEncode(list.map((p) => p.toJson()).toList()),
    );
    notifyListeners();
  }

  /// Удалить профиль. Нельзя удалить активный профиль — вернёт false.
  Future<bool> removeTaxProfile(String id) async {
    if (activeTaxProfileId == id) return false; // Нельзя удалить активный.
    final list = taxProfiles.where((p) => p.id != id).toList();
    await _prefs.setString(
      _taxProfilesKey,
      jsonEncode(list.map((p) => p.toJson()).toList()),
    );
    if (list.isEmpty) {
      await _prefs.remove(_activeTaxProfileIdKey);
    }
    notifyListeners();
    return true;
  }

  /// Установить активный профиль.
  Future<void> setActiveTaxProfile(String id) async {
    if (taxProfiles.any((p) => p.id == id)) {
      await _prefs.setString(_activeTaxProfileIdKey, id);
      notifyListeners();
    }
  }

  // Алиасы под имена из ТЗ/UI.
  Future<void> addProfile(TaxProfile profile) => addTaxProfile(profile);
  Future<void> updateProfile(TaxProfile profile) => updateTaxProfile(profile);
  Future<bool> removeProfile(String id) => removeTaxProfile(id);
  Future<void> setActiveProfile(String id) => setActiveTaxProfile(id);

  String? get taxAccountId => _prefs.getString(_taxAccountKey);
  List<String> get jobTags =>
      (_prefs.getStringList(_jobTagsKey) ?? const []).toList();

  bool get jobTagsEnabled => _prefs.getBool(_jobTagsEnabledKey) ?? true;

  Future<void> setJobTagsEnabled(bool value) async {
    await _prefs.setBool(_jobTagsEnabledKey, value);
    notifyListeners();
  }

  bool get cashShiftEnabled => _prefs.getBool(_cashShiftEnabledKey) ?? true;

  Future<void> setCashShiftEnabled(bool value) async {
    await _prefs.setBool(_cashShiftEnabledKey, value);
    notifyListeners();
  }

  /// Ключи включённых kanban-колонок экрана «Заказы».
  /// Пусто (или ключ не задан) — все колонки включены.
  List<String> get kanbanColumns =>
      (_prefs.getStringList(_kanbanColumnsKey) ?? const []).toList();

  /// Включена ли kanban-колонка с ключом [key]. По умолчанию — включена.
  bool kanbanColumnEnabled(String key) =>
      kanbanColumns.isEmpty || kanbanColumns.contains(key);

  Future<void> setKanbanColumns(List<String> value) async {
    final next = value.where((e) => e.isNotEmpty).toList();
    await _prefs.setStringList(_kanbanColumnsKey, next);
    notifyListeners();
  }

  /// Включена ли «команда» (сотрудники, зарплаты, назначение исполнителей).
  /// По умолчанию — включена; при выключении соответствующие элементы
  /// интерфейса скрываются (данные не удаляются).
  bool get teamEnabled => _prefs.getBool(_teamEnabledKey) ?? true;

  Future<void> setTeamEnabled(bool value) async {
    await _prefs.setBool(_teamEnabledKey, value);
    notifyListeners();
  }

  /// Включён ли калькулятор цен. По умолчанию — включён.
  bool get calculatorEnabled => _prefs.getBool(_calculatorEnabledKey) ?? true;

  Future<void> setCalculatorEnabled(bool value) async {
    await _prefs.setBool(_calculatorEnabledKey, value);
    notifyListeners();
  }

  /// Модуль «Заявки» (Э3): экран и воронка продаж. По умолчанию выключен,
  /// чтобы не множировать интерфейс у мастеров, которые ведут только заказы
  /// (§5.4: `module_leads`). Данные при этом не удаляются — флаг прячет UI.
  bool get leadsEnabled => _prefs.getBool(_leadsEnabledKey) ?? false;

  Future<void> setLeadsEnabled(bool value) async {
    await _prefs.setBool(_leadsEnabledKey, value);
    notifyListeners();
  }

  /// Модуль «Депозиты и сертификаты» (Э4): деньги клиента на балансе и
  /// отложенная выручка (§5.5: `module_credits`). Как и заявки, по умолчанию
  /// выключен — мастер сам решает, нужны ли ему предоплаты.
  bool get creditsEnabled => _prefs.getBool(_creditsEnabledKey) ?? false;

  Future<void> setCreditsEnabled(bool value) async {
    await _prefs.setBool(_creditsEnabledKey, value);
    notifyListeners();
  }

  /// Модуль «Несколько точек» (Э5): локации, партии со сроками, приёмка и
  /// план производства (§5.6: `module_locations`). По умолчанию выключен: у
  /// соло-мастера один склад, а обязательные локации добавили бы лишний шаг
  /// в каждое списание (§12.2). Таблицы при этом создаются миграцией v25
  /// всегда — включение флага не требует миграции и не может упасть.
  bool get locationsEnabled => _prefs.getBool(_locationsEnabledKey) ?? false;

  Future<void> setLocationsEnabled(bool value) async {
    await _prefs.setBool(_locationsEnabledKey, value);
    notifyListeners();
  }

  /// Режим работы магазина: `orders` (только заказы), `appointments`
  /// (только записи) или `hybrid` (оба потока в едином экране).
  /// По умолчанию — `hybrid`.
  String get workMode => _prefs.getString(_workModeKey) ?? 'hybrid';

  /// Показывать ли записи (скрыты только в режиме «только заказы»).
  bool get showAppointments => workMode != 'orders';

  /// Показывать ли заказы (скрыты только в режиме «только записи»).
  bool get showJobs => workMode != 'appointments';

  Future<void> setWorkMode(String value) async {
    const allowed = {'orders', 'appointments', 'hybrid'};
    if (!allowed.contains(value)) return;
    await _prefs.setString(_workModeKey, value);
    notifyListeners();
  }

  /// Включено ли зеркало обновлений (телефон/бета-сервер).
  bool get updateMirrorEnabled =>
      _prefs.getBool(_updateMirrorEnabledKey) ?? false;

  Future<void> setUpdateMirrorEnabled(bool value) async {
    await _prefs.setBool(_updateMirrorEnabledKey, value);
    notifyListeners();
  }

  /// URL зеркала обновлений. Пусто — зеркало не настроено.
  String get updateMirrorUrl => _prefs.getString(_updateMirrorUrlKey) ?? '';

  Future<void> setUpdateMirrorUrl(String value) async {
    await _prefs.setString(_updateMirrorUrlKey, value.trim());
    notifyListeners();
  }

  /// Канал обновлений: 'stable' или 'beta'.
  String get updateChannel => _prefs.getString(_updateChannelKey) ?? 'stable';

  Future<void> setUpdateChannel(String value) async {
    if (value != 'stable' && value != 'beta') return;
    await _prefs.setString(_updateChannelKey, value);
    notifyListeners();
  }

  /// Презеты стандартной конфигурации: выставляют набор ключей одним действием.
  Future<void> applyConfigPreset(String preset) async {
    switch (preset) {
      case 'solo':
        await setTeamEnabled(false);
        await setCalculatorEnabled(true);
        await setJobTagsEnabled(true);
      case 'team':
        await setTeamEnabled(true);
        await setCalculatorEnabled(true);
        await setJobTagsEnabled(true);
        await setKanbanColumns(const []);
      case 'clients':
        await setTeamEnabled(false);
        await setKanbanColumns(const []);
        await setReminder(true);
      default:
        return;
    }
    notifyListeners();
  }

  Future<void> setBusinessType(String value) async {
    await _prefs.setString(_businessTypeKey, value);
    notifyListeners();
  }

  Future<void> setModules(List<String> value) async {
    await _prefs.setString(_modulesKey, value.join(','));
    notifyListeners();
  }

  Future<void> setObjectTerm(String value) async {
    await _prefs.setString(_objectTermKey, value);
    notifyListeners();
  }

  Future<void> setClientTerm(String value) async {
    await _prefs.setString(_clientTermKey, value);
    notifyListeners();
  }

  Future<void> setTaxRate(int value) async {
    await _prefs.setInt(_taxRateKey, value.clamp(0, 100));
    notifyListeners();
  }

  /// Годовой лимит дохода для НПД-радара (в центах). По умолчанию 2.4М ₽.
  int get taxIncomeLimitCents =>
      _prefs.getInt(_taxIncomeLimitCentsKey) ?? 240000000;

  Future<void> setTaxIncomeLimitCents(int value) async {
    await _prefs.setInt(_taxIncomeLimitCentsKey, value < 0 ? 0 : value);
    notifyListeners();
  }

  /// Включён ли налоговый радар (НПД).
  bool get taxRadarEnabled => _prefs.getBool(_taxRadarEnabledKey) ?? true;

  Future<void> setTaxRadarEnabled(bool value) async {
    await _prefs.setBool(_taxRadarEnabledKey, value);
    notifyListeners();
  }

  Future<void> setTaxAccount(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_taxAccountKey);
    } else {
      await _prefs.setString(_taxAccountKey, value);
    }
    notifyListeners();
  }

  int get hourRateCents => _prefs.getInt(_hourRateCentsKey) ?? 0;

  Future<void> setHourRateCents(int value) async {
    await _prefs.setInt(_hourRateCentsKey, value.clamp(0, 10_000_000));
    notifyListeners();
  }

  Future<void> addJobTag(String value) async {
    final tag = value.trim();
    if (tag.isEmpty || jobTags.contains(tag)) return;
    final next = [...jobTags, tag];
    await _prefs.setStringList(_jobTagsKey, next);
    notifyListeners();
  }

  Future<void> removeJobTag(String value) async {
    final next = jobTags.where((t) => t != value).toList();
    await _prefs.setStringList(_jobTagsKey, next);
    notifyListeners();
  }

  String? get yandexToken => _prefs.getString(_yandexTokenKey);
  String? get yandexRefreshToken => _prefs.getString(_yandexRefreshTokenKey);
  bool get yandexConnected =>
      (_prefs.getString(_yandexTokenKey) ?? '').isNotEmpty;
  bool get yandexAutoBackup => _prefs.getBool(_yandexAutoBackupKey) ?? false;

  DateTime? get yandexLastCloudModified {
    final ms = _prefs.getInt(_yandexLastCloudModifiedKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setYandexLastCloudModified(DateTime? value) async {
    if (value == null) {
      await _prefs.remove(_yandexLastCloudModifiedKey);
    } else {
      await _prefs.setInt(
        _yandexLastCloudModifiedKey,
        value.millisecondsSinceEpoch,
      );
    }
    notifyListeners();
  }

  DateTime? get yandexTokenExpiresAt {
    final raw = _prefs.getInt(_yandexTokenExpiresKey);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  /// Сохраняет токены, полученные после входа через Яндекс ID.
  Future<void> setYandexTokens({
    required String accessToken,
    String? refreshToken,
    int? expiresInSeconds,
  }) async {
    await _prefs.setString(_yandexTokenKey, accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _prefs.setString(_yandexRefreshTokenKey, refreshToken);
    }
    if (expiresInSeconds != null) {
      final expires = DateTime.now().add(Duration(seconds: expiresInSeconds));
      await _prefs.setInt(
        _yandexTokenExpiresKey,
        expires.millisecondsSinceEpoch,
      );
    }
    notifyListeners();
  }

  Future<void> disconnectYandex() async {
    await _prefs.remove(_yandexTokenKey);
    await _prefs.remove(_yandexRefreshTokenKey);
    await _prefs.remove(_yandexTokenExpiresKey);
    notifyListeners();
  }

  /// Возвращает рабочий токен, обновляя его при необходимости.
  Future<String?> ensureYandexToken() async {
    final token = yandexToken;
    if (token == null || token.isEmpty) return null;
    final expires = yandexTokenExpiresAt;
    // Обновляем заранее, за минуту до истечения.
    if (expires == null ||
        expires.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return token;
    }
    final refresh = yandexRefreshToken;
    if (refresh == null || refresh.isEmpty) return token;
    final fresh = await YandexOAuth.refresh(refresh);
    if (fresh == null) return token;
    await setYandexTokens(
      accessToken: fresh['access_token'] as String,
      refreshToken: fresh['refresh_token'] as String?,
      expiresInSeconds: fresh['expires_in'] as int?,
    );
    return yandexToken;
  }

  Future<void> setYandexAutoBackup(bool value) async {
    await _prefs.setBool(_yandexAutoBackupKey, value);
    notifyListeners();
  }

  bool get hasAppPin => (_prefs.getString(_appPinHashKey) ?? '').isNotEmpty;

  DateTime? get appPinUnlockedUntil {
    final value = _prefs.getInt(_appPinUnlockedUntilKey);
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  bool get isAppPinUnlockedNow =>
      !hasAppPin ||
      (appPinUnlockedUntil != null &&
          appPinUnlockedUntil!.isAfter(DateTime.now()));

  Future<void> setAppPin(String? pin) async {
    if (pin == null || pin.trim().isEmpty) {
      await _prefs.remove(_appPinHashKey);
      await _prefs.remove(_appPinUnlockedUntilKey);
    } else {
      await _prefs.setString(_appPinHashKey, AppPinService.hash(pin.trim()));
      await _prefs.setInt(
        _appPinUnlockedUntilKey,
        DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch,
      );
    }
    notifyListeners();
  }

  void unlockAppPin(Duration window) {
    if (!hasAppPin) return;
    _prefs.setInt(
      _appPinUnlockedUntilKey,
      DateTime.now().add(window).millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  bool verifyAppPin(String pin) {
    final stored = _prefs.getString(_appPinHashKey);
    return AppPinService.verify(pin, stored);
  }

  bool get biometricEnabled => _prefs.getBool(_appBiometricEnabledKey) ?? false;

  Future<void> setBiometricEnabled(bool value) async {
    await _prefs.setBool(_appBiometricEnabledKey, value);
    notifyListeners();
  }

  bool get onboardingDone => _prefs.getBool(_onboardingKey) ?? false;

  Future<void> completeOnboarding() async {
    await _prefs.setBool(_onboardingKey, true);
    notifyListeners();
  }

  // ── Синхронизация между устройствами ───────────────────────────────────────

  static const _syncBaseUrlKey = 'sync_base_url';
  static const _syncEmailKey = 'sync_email';
  static const _syncTokenKey = 'sync_token';
  static const _syncTokenExpiresKey = 'sync_token_expires_at';
  static const _syncSpaceIdKey = 'sync_space_id';
  static const _syncSpaceNameKey = 'sync_space_name';
  static const _syncSpaceInviteKey = 'sync_space_invite';
  static const _syncLastSeqKey = 'sync_last_seq';
  static const _syncDeviceIdKey = 'sync_device_id';
  static const _syncLastAtKey = 'sync_last_at';
  static const _syncAutoKey = 'sync_auto';

  static const _defaultSyncBaseUrl = 'http://192.168.1.112:8080';

  String get syncBaseUrl {
    final stored = (_prefs.getString(_syncBaseUrlKey) ?? '').trim();
    return stored.isEmpty ? _defaultSyncBaseUrl : stored;
  }

  Future<void> setSyncBaseUrl(String value) async {
    final url = value.trim();
    if (url.isEmpty) {
      await _prefs.remove(_syncBaseUrlKey);
    } else {
      await _prefs.setString(_syncBaseUrlKey, url);
    }
    notifyListeners();
  }

  String get syncEmail => _prefs.getString(_syncEmailKey) ?? '';
  String get syncToken => _prefs.getString(_syncTokenKey) ?? '';
  bool get syncSignedIn => syncToken.isNotEmpty;

  DateTime? get syncTokenExpiresAt {
    final raw = _prefs.getInt(_syncTokenExpiresKey);
    if (raw == null || raw == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
  }

  Future<void> setSyncSession({
    required String token,
    required String email,
    int expiresAtSeconds = 0,
  }) async {
    await _prefs.setString(_syncTokenKey, token);
    await _prefs.setString(_syncEmailKey, email);
    if (expiresAtSeconds > 0) {
      await _prefs.setInt(_syncTokenExpiresKey, expiresAtSeconds);
    }
    notifyListeners();
  }

  String get syncSpaceId => _prefs.getString(_syncSpaceIdKey) ?? '';
  String get syncSpaceName => _prefs.getString(_syncSpaceNameKey) ?? '';
  String get syncSpaceInvite => _prefs.getString(_syncSpaceInviteKey) ?? '';

  Future<void> setSyncSpace({
    required String id,
    required String name,
    String inviteCode = '',
  }) async {
    await _prefs.setString(_syncSpaceIdKey, id);
    await _prefs.setString(_syncSpaceNameKey, name);
    if (inviteCode.isEmpty) {
      await _prefs.remove(_syncSpaceInviteKey);
    } else {
      await _prefs.setString(_syncSpaceInviteKey, inviteCode);
    }
    notifyListeners();
  }

  Future<void> clearSyncSpace() async {
    await _prefs.remove(_syncSpaceIdKey);
    await _prefs.remove(_syncSpaceNameKey);
    await _prefs.remove(_syncSpaceInviteKey);
    await _prefs.remove(_syncLastSeqKey);
    notifyListeners();
  }

  int get syncLastSeq => _prefs.getInt(_syncLastSeqKey) ?? 0;

  Future<void> setSyncLastSeq(int value) async {
    await _prefs.setInt(_syncLastSeqKey, value < 0 ? 0 : value);
    notifyListeners();
  }

  /// Идентификатор устройства для разрешения конфликтов «последняя запись».
  String get syncDeviceId {
    final stored = _prefs.getString(_syncDeviceIdKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final fresh = newId();
    _prefs.setString(_syncDeviceIdKey, fresh);
    return fresh;
  }

  DateTime? get syncLastAt {
    final raw = _prefs.getInt(_syncLastAtKey);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> markSyncedNow() async {
    await _prefs.setInt(
      _syncLastAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  bool get syncAuto => _prefs.getBool(_syncAutoKey) ?? true;

  Future<void> setSyncAuto(bool value) async {
    await _prefs.setBool(_syncAutoKey, value);
    notifyListeners();
  }

  Future<void> signOutSync() async {
    await _prefs.remove(_syncTokenKey);
    await _prefs.remove(_syncTokenExpiresKey);
    await clearSyncSpace();
    notifyListeners();
  }
}
