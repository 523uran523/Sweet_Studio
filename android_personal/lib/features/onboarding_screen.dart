import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/studio_store.dart';
import '../theme/soft_atelier.dart';
import '../ui/atelier_widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameCtrl = TextEditingController(text: 'Моя кондитерская');
  final _sloganCtrl = TextEditingController(text: 'Авторские десерты на заказ');
  int _selectedTheme = 0;
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sloganCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool withDemoData}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<StudioStore>().completeOnboarding(
            studioName: _nameCtrl.text,
            slogan: _sloganCtrl.text,
            themeIndex: _selectedTheme,
            withDemoData: withDemoData,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteForIndex(_selectedTheme);
    final theme = buildAtelierTheme(palette);

    return Theme(
      data: theme,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        'assets/icon.png',
                        width: 54,
                        height: 54,
                        errorBuilder: (_, _, _) => Container(
                          width: 54,
                          height: 54,
                          color: palette.primary,
                          child: Icon(Icons.cake_outlined, color: palette.onPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SweetStudio Personal',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Автономная мастерская на вашем Android — все данные хранятся только на устройстве.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AtelierCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1. Профиль вашей кондитерской',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Название мастерской',
                          hintText: 'Например, Berry Atelier',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _sloganCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Подпись для документов и счетов',
                          hintText: 'Авторские торты и десерты на заказ',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AtelierCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '2. Выберите тему оформления',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(kAtelierPalettes.length, (idx) {
                        final p = kAtelierPalettes[idx];
                        final selected = idx == _selectedTheme;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _selectedTheme = idx),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: selected
                                    ? palette.surfaceAlt
                                    : palette.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      selected ? palette.primary : palette.border,
                                  width: selected ? 1.8 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: p.primary,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: p.background,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          p.description,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: palette.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    Icon(Icons.check_circle,
                                        color: palette.primary),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AtelierCard(
                  color: palette.surfaceAlt,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '3. С чего начать?',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Вы можете сразу открыть чистую мастерскую или посмотреть примеры рецептов, заказов и FEFO-склада на демо-данных (их можно удалить в любой момент).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed:
                            _busy ? null : () => _finish(withDemoData: false),
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Начать с чистой базы'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _finish(withDemoData: true),
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Загрузить демо-данные'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
