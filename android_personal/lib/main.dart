import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/notifications_core.dart';
import 'features/onboarding_screen.dart';
import 'features/shell_screen.dart';
import 'state/studio_store.dart';
import 'theme/soft_atelier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalReminderService.instance.init();
  final store = await StudioStore.bootstrap();
  runApp(SweetStudioPersonalApp(store: store));
}

class SweetStudioPersonalApp extends StatelessWidget {
  const SweetStudioPersonalApp({super.key, required this.store});

  final StudioStore store;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StudioStore>.value(
      value: store,
      child: Consumer<StudioStore>(
        builder: (context, store, _) {
          final palette = paletteForIndex(store.profile.themeIndex);
          return MaterialApp(
            title: 'SweetStudio',
            debugShowCheckedModeBanner: false,
            locale: const Locale('ru', 'RU'),
            supportedLocales: const [
              Locale('ru', 'RU'),
              Locale('en', 'US'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildAtelierTheme(palette),
            home: store.profile.onboardingCompleted
                ? const ShellScreen()
                : const OnboardingScreen(),
          );
        },
      ),
    );
  }
}
