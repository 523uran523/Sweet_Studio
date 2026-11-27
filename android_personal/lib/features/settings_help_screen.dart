import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/backup_service.dart';
import '../core/notifications_core.dart';
import '../state/studio_store.dart';
import '../theme/soft_atelier.dart';
import '../ui/atelier_widgets.dart';

class SettingsHelpScreen extends StatefulWidget {
  const SettingsHelpScreen({super.key});

  @override
  State<SettingsHelpScreen> createState() => _SettingsHelpScreenState();
}

class _SettingsHelpScreenState extends State<SettingsHelpScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _sloganCtrl;
  bool _initialized = false;
  bool _busyBackup = false;
  int _mediaBytes = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<StudioStore>();
    if (!_initialized) {
      _nameCtrl = TextEditingController(text: store.profile.studioName);
      _sloganCtrl = TextEditingController(text: store.profile.slogan);
      _initialized = true;
      _refreshMediaSize();
    }
  }

  Future<void> _refreshMediaSize() async {
    final bytes = await context.read<StudioStore>().mediaStore.totalMediaBytes();
    if (mounted) setState(() => _mediaBytes = bytes);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sloganCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAndShareBackup() async {
    if (_busyBackup) return;
    setState(() => _busyBackup = true);
    try {
      final store = context.read<StudioStore>();
      final zipFile = await store.exportBackupZip();
      if (!mounted) return;
      final sizeKb = ((await zipFile.length()) / 1024).ceil();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Резервная копия создана'),
          content: Text(
            'Архив ($sizeKb КБ) содержит базу SQLite, фото и SHA-256 контрольные суммы:\n${zipFile.path}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Готово'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await SharePlus.instance.share(
                  ShareParams(
                    files: [XFile(zipFile.path)],
                    text: 'Резервная копия SweetStudio Personal',
                  ),
                );
              },
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Сохранить / Отправить'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showAtelierMessage(context, 'Ошибка бэкапа: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  Future<void> _pickAndRestoreBackup() async {
    if (_busyBackup) return;
    setState(() => _busyBackup = true);
    BackupInspection? inspection;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      if (!mounted) return;

      final store = context.read<StudioStore>();
      inspection = await store.inspectBackupZip(path);
      if (!mounted) return;

      final counts = inspection.manifest.recordCounts;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Подтвердите восстановление'),
          content: Text(
            'Проверка SHA-256 и целостности SQLite пройдена.\n\n'
            'Дата копии: ${inspection!.manifest.createdAt.substring(0, 10)}\n'
            'Рецептов: ${counts['recipes'] ?? 0} · Заказов: ${counts['orders'] ?? 0}\n'
            'Клиентов: ${counts['clients'] ?? 0} · Фото: ${inspection.mediaCount}\n\n'
            'Текущие данные на устройстве будут заменены на содержимое архива.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Восстановить'),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        await store.restoreFromInspection(inspection);
        _nameCtrl.text = store.profile.studioName;
        _sloganCtrl.text = store.profile.slogan;
        await _refreshMediaSize();
        if (mounted) {
          showAtelierMessage(context, 'Данные и фотографии успешно восстановлены.');
        }
      }
    } catch (e) {
      if (mounted) {
        showAtelierMessage(
          context,
          'Архив отклонён: $e',
          isError: true,
        );
      }
    } finally {
      await inspection?.dispose();
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudioStore>();
    final p = store.palette;
    final prof = store.profile;

    void toggleModule(String key, bool hidden) {
      final list = List<String>.from(prof.hiddenModules);
      if (hidden) {
        if (!list.contains(key)) list.add(key);
      } else {
        list.remove(key);
      }
      store.updateProfile(prof.copyWith(hiddenModules: list));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        AtelierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Профиль мастерской',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Название кондитерской'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sloganCtrl,
                decoration: const InputDecoration(labelText: 'Подпись в счёте / акте'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () async {
                  await store.updateProfile(
                    prof.copyWith(
                      studioName: _nameCtrl.text.trim(),
                      slogan: _sloganCtrl.text.trim(),
                    ),
                  );
                  if (context.mounted) {
                    showAtelierMessage(context, 'Профиль сохранён.');
                  }
                },
                child: const Text('Сохранить профиль'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AtelierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Тема Soft Atelier',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(kAtelierPalettes.length, (i) {
                  final pal = kAtelierPalettes[i];
                  return ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: pal.primary, radius: 8),
                    label: Text(pal.name),
                    selected: prof.themeIndex == i,
                    onSelected: (_) =>
                        store.updateProfile(prof.copyWith(themeIndex: i)),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AtelierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Резервная копия и перенос (.zip)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Хранится только на устройстве. Фотографии рецептов: ${(_mediaBytes / 1024).toStringAsFixed(0)} КБ.\n'
                'Последняя копия: ${prof.lastBackupAt != null ? prof.lastBackupAt!.substring(0, 10) : 'ещё не создавалась'}',
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busyBackup ? null : _createAndShareBackup,
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Экспорт ZIP'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busyBackup ? null : _pickAndRestoreBackup,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Восстановить из ZIP'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final issues = await store.db.checkIntegrity();
                      if (context.mounted) {
                        showAtelierMessage(
                          context,
                          issues.isEmpty
                              ? 'Проверка SQLite пройдена: ошибок нет.'
                              : 'Проблемы БД: ${issues.join(', ')}',
                          isError: issues.isNotEmpty,
                        );
                      }
                    },
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Проверить БД'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AtelierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Уведомления на устройстве',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Даже при отказе в системных push-уведомлениях напоминания всегда видны в колокольчике приложения.',
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prof.notifyOrders,
                onChanged: (v) =>
                    store.updateProfile(prof.copyWith(notifyOrders: v)),
                title: const Text('Напоминания о выдачах заказов'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prof.notifyTasks,
                onChanged: (v) =>
                    store.updateProfile(prof.copyWith(notifyTasks: v)),
                title: const Text('Просроченные задачи'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prof.notifyStock,
                onChanged: (v) =>
                    store.updateProfile(prof.copyWith(notifyStock: v)),
                title: const Text('Низкие остатки в кладовой'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prof.notifyExpiry,
                onChanged: (v) =>
                    store.updateProfile(prof.copyWith(notifyExpiry: v)),
                title: const Text('Истекающий срок годности партий'),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await store.enableAndNotifyLocalReminders();
                        if (context.mounted) {
                          showAtelierMessage(
                            context,
                            ok
                                ? 'Системные уведомления Android разрешены.'
                                : 'Разрешение не выдано — напоминания доступны внутри приложения.',
                            isError: !ok,
                          );
                        }
                      },
                      icon: const Icon(Icons.notifications_active_outlined, size: 18),
                      label: const Text('Разрешить в Android'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final sent = await LocalReminderService.instance
                          .showTestNotification(prof.studioName);
                      if (context.mounted) {
                        showAtelierMessage(
                          context,
                          sent
                              ? 'Тестовое уведомление отправлено.'
                              : 'Сначала выдайте разрешение на уведомления.',
                          isError: !sent,
                        );
                      }
                    },
                    child: const Text('Тест'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AtelierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Опциональные разделы (данные сохраняются)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: !prof.hiddenModules.contains('work'),
                onChanged: (v) => toggleModule('work', !v),
                title: const Text('Вкладка «Работа» (задачи и календарь)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: !prof.hiddenModules.contains('inventory'),
                onChanged: (v) => toggleModule('inventory', !v),
                title: const Text('Кладовая, закупки и производство'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: !prof.hiddenModules.contains('finance'),
                onChanged: (v) => toggleModule('finance', !v),
                title: const Text('Финансы и аналитика'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AtelierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Управление данными',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await store.loadDemoWorkspace();
                      if (context.mounted) {
                        showAtelierMessage(context, 'Демо-данные загружены.');
                      }
                    },
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Загрузить демо-пример'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Очистить базу полностью?'),
                          content: const Text(
                            'Перед очисткой рекомендуется сделать ZIP-бэкап. Все рецепты, заказы, клиенты и операции будут удалены.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Отмена'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Очистить'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        await store.switchToCleanWorkspace();
                        if (context.mounted) {
                          showAtelierMessage(context, 'База очищена.');
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Очистить базу'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const AtelierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Локальная справка (офлайн)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              SizedBox(height: 6),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('1. Автономная работа и конфиденциальность'),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'SweetStudio Personal работает полностью на вашем телефоне в базе SQLite. Вход, интернет и облако не требуются.',
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('2. Рецепты, подрецепты и калькулятор'),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Пересчёт г↔мл использует плотность ингредиента. Упаковка включается в себестоимость, но не прибавляется к съедобному весу. Цены в заказах сохраняются как снимок.',
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('3. FEFO-склад и производство'),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Списание сырья идёт сначала с ближайших по сроку годности активных партий. При нехватке или просрочке списание полностью отменяется.',
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('4. Денежный поток vs Признанная выручка'),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Денежный поток показывает реальное движение денег по счетам (предоплаты, закупки). Признанная выручка считает заказы в статусах «Выдан» и «Закрыт».',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
