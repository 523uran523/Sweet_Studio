import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:masters/state/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('workMode defaults to hybrid, both streams visible', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    expect(settings.workMode, 'hybrid');
    expect(settings.showAppointments, isTrue);
    expect(settings.showJobs, isTrue);
  });

  test('workMode orders hides appointments, keeps jobs', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await settings.setWorkMode('orders');
    expect(settings.workMode, 'orders');
    expect(settings.showAppointments, isFalse);
    expect(settings.showJobs, isTrue);
  });

  test('workMode appointments hides jobs, keeps appointments', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await settings.setWorkMode('appointments');
    expect(settings.workMode, 'appointments');
    expect(settings.showAppointments, isTrue);
    expect(settings.showJobs, isFalse);
  });

  test('unknown workMode values are ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await settings.setWorkMode('chess');
    expect(settings.workMode, 'hybrid');
  });

  test('workMode persists in prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await SettingsController.load();
    await first.setWorkMode('appointments');

    final second = await SettingsController.load();
    expect(second.workMode, 'appointments');
  });
}
