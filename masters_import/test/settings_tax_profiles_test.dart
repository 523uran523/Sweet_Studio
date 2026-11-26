import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:masters/state/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults created lazily when taxRate is zero', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    final profiles = settings.taxProfiles;
    expect(profiles, hasLength(4));
    expect(profiles.first.id, 'ru_4');
    expect(settings.activeTaxProfileId, 'ru_4');
    expect(settings.getActiveTaxRate(), 4);
  });

  test('old taxRate preserved as fallback when no profiles', () async {
    SharedPreferences.setMockInitialValues({'tax_rate': 7});
    final settings = await SettingsController.load();
    expect(settings.taxProfiles, isEmpty);
    expect(settings.activeTaxProfileId, isNull);
    expect(settings.getActiveTaxRate(), 7);
  });

  test('no presets created when old taxRate is set', () async {
    SharedPreferences.setMockInitialValues({'tax_rate': 6});
    final settings = await SettingsController.load();
    expect(settings.taxProfiles, isEmpty);
  });

  test('CRUD and active switching', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    // add
    await settings.addProfile(
      const TaxProfile(
        id: 'custom_1',
        country: 'RU',
        name: 'УСН 6%',
        ratePercent: 6,
      ),
    );
    expect(settings.taxProfiles, hasLength(5));
    expect(settings.activeTaxProfileId, 'ru_4'); // unchanged
    // update
    await settings.updateProfile(
      const TaxProfile(
        id: 'custom_1',
        country: 'RU',
        name: 'УСН 6% (изм)',
        ratePercent: 7,
      ),
    );
    expect(settings.taxProfiles.last.ratePercent, 7);
    // setActive
    await settings.setActiveProfile('custom_1');
    expect(settings.activeTaxProfileId, 'custom_1');
    expect(settings.getActiveTaxRate(), 7);
    // remove active -> false, stays
    expect(await settings.removeProfile('custom_1'), isFalse);
    expect(settings.taxProfiles, hasLength(5));
    // remove non-active
    expect(await settings.removeProfile('ru_6'), isTrue);
    expect(settings.taxProfiles, hasLength(4));
  });

  test('persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await SettingsController.load();
    await first.addProfile(
      const TaxProfile(id: 'p2', country: 'KZ', name: 'KZ 3%', ratePercent: 3),
    );
    await first.setActiveProfile('p2');
    final second = await SettingsController.load();
    expect(second.taxProfiles.any((p) => p.id == 'p2'), isTrue);
    expect(second.activeTaxProfileId, 'p2');
    expect(second.getActiveTaxRate(), 3);
  });

  test('string aliases removeTaxProfile etc', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await settings.addTaxProfile(
      const TaxProfile(id: 'x', country: 'US', name: 'X', ratePercent: 1),
    );
    expect(settings.taxProfiles.length, 5);
    await settings.updateTaxProfile(
      const TaxProfile(id: 'x', country: 'US', name: 'X2', ratePercent: 2),
    );
    expect(settings.taxProfiles.last.name, 'X2');
  });
}
