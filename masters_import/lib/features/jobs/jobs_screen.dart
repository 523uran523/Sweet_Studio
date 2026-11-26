import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../data/models/job.dart';
import '../../core/utils/app_utils.dart';
import 'job_constants.dart';
import '../../state/masters_store.dart';
import '../../state/settings_controller.dart';
import 'job_detail_screen.dart';
import '../../core/money_format.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  String _view = 'process';
  int _statusIndex = 0;
  final _searchController = TextEditingController();
  String _query = '';
  String? _assigneeFilter;
  JobPriority? _priorityFilter;
  String? _tagFilter;
  String? _clientFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _extraFiltersMatch(Job job, MastersStore store) {
    final af = _assigneeFilter;
    if (af != null && af != '__all__' && af.trim().isNotEmpty) {
      final selfId = store.selfEmployee?.id;
      if (af == '__none__') {
        if (job.assigneeId != null) return false;
      } else if (af == '__self__') {
        if (!(job.assigneeId == '__self__' ||
            (selfId != null && job.assigneeId == selfId))) {
          return false;
        }
      } else {
        if (job.assigneeId != af) return false;
      }
    }
    if (_priorityFilter != null && job.priority != _priorityFilter) {
      return false;
    }
    final tf = _tagFilter;
    if (tf != null && tf != '__all__' && tf.trim().isNotEmpty) {
      final tags = (job.tags ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      if (!tags.contains(tf.trim())) {
        return false;
      }
    }
    final cf = _clientFilter;
    if (cf != null && cf != '__all__' && cf.trim().isNotEmpty) {
      final value = cf.trim();
      if (value == '__none__') {
        if (job.clientId.trim().isNotEmpty &&
            store.clientById(job.clientId) != null) {
          return false;
        }
      } else if (job.clientId.trim() != value) {
        return false;
      }
    }
    if (_dateFrom != null || _dateTo != null) {
      final createdAt = job.createdAt;
      if (_dateFrom != null) {
        final from = DateTime(
          _dateFrom!.year,
          _dateFrom!.month,
          _dateFrom!.day,
        );
        if (createdAt.isBefore(from)) return false;
      }
      if (_dateTo != null) {
        final toEnd = DateTime(
          _dateTo!.year,
          _dateTo!.month,
          _dateTo!.day,
          23,
          59,
          59,
          999,
        );
        if (createdAt.isAfter(toEnd)) return false;
      }
    }
    return true;
  }

  bool get _hasActiveFilters =>
      (_assigneeFilter != null &&
          _assigneeFilter != '__all__' &&
          _assigneeFilter!.trim().isNotEmpty) ||
      _priorityFilter != null ||
      (_tagFilter != null &&
          _tagFilter != '__all__' &&
          _tagFilter!.trim().isNotEmpty) ||
      (_clientFilter != null &&
          _clientFilter != '__all__' &&
          _clientFilter!.trim().isNotEmpty) ||
      _dateFrom != null ||
      _dateTo != null;

  List<Job> _filteredJobs(MastersStore store) {
    var list = store.jobs
        .where((j) => !j.archived && _extraFiltersMatch(j, store))
        .toList();
    if (_statusIndex > 0) {
      list = list
          .where((j) => j.status == JobStatus.values[_statusIndex - 1])
          .toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((j) => JobSearchFilter.matches(j, q, store)).toList();
    }
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  String _statusLabel() =>
      _statusIndex == 0 ? 'Все' : JobStatus.values[_statusIndex - 1].label;

  Future<void> _showStatusPicker() async {
    final result = await showCupertinoModalPopup<int>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Фильтр по статусу'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: _statusIndex == 0,
            onPressed: () => Navigator.of(dialogContext).pop(0),
            child: const Text('Все'),
          ),
          for (var i = 0; i < JobStatus.values.length; i++)
            CupertinoActionSheetAction(
              isDefaultAction: _statusIndex == i + 1,
              onPressed: () => Navigator.of(dialogContext).pop(i + 1),
              child: Text(JobStatus.values[i].label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (result != null && mounted) setState(() => _statusIndex = result);
  }

  Future<void> _pickAssigneeFilter() async {
    final store = context.read<MastersStore>();
    final selfId = store.selfEmployee?.id;
    final result = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Исполнитель'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction:
                _assigneeFilter == null || _assigneeFilter == '__all__',
            onPressed: () => Navigator.of(dialogContext).pop('__all__'),
            child: const Text('Все'),
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _assigneeFilter == '__none__',
            onPressed: () => Navigator.of(dialogContext).pop('__none__'),
            child: const Text('Без исполнителя'),
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _assigneeFilter == '__self__',
            onPressed: () => Navigator.of(dialogContext).pop('__self__'),
            child: const Text('Я'),
          ),
          for (final e in store.employees.where(
            (e) => !e.archived && e.id != selfId,
          ))
            CupertinoActionSheetAction(
              isDefaultAction: _assigneeFilter == e.id,
              onPressed: () => Navigator.of(dialogContext).pop(e.id),
              child: Text(e.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _assigneeFilter = result == '__all__' ? null : result;
    });
  }

  Future<void> _pickPriorityFilter() async {
    final result = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Приоритет'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: _priorityFilter == null,
            onPressed: () => Navigator.of(dialogContext).pop('__all__'),
            child: const Text('Все'),
          ),
          for (final p in JobPriority.values)
            CupertinoActionSheetAction(
              isDefaultAction: _priorityFilter == p,
              onPressed: () => Navigator.of(dialogContext).pop(p.name),
              child: Text(p.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result == '__all__') {
        _priorityFilter = null;
      } else {
        _priorityFilter = JobPriority.values
            .where((p) => p.name == result)
            .firstOrNull;
      }
    });
  }

  List<String> _availableTags(MastersStore store) {
    final settings = context.read<SettingsController>();
    final tags = <String>{};
    for (final j in store.jobs) {
      for (final t in (j.tags ?? '').split(',')) {
        final v = t.trim();
        if (v.isNotEmpty) tags.add(v);
      }
    }
    tags.addAll(settings.jobTags);
    final list = tags.toList()..sort();
    return list;
  }

  Future<void> _pickTagFilter() async {
    final store = context.read<MastersStore>();
    final tags = _availableTags(store);
    if (tags.isEmpty) {
      if (!mounted) return;
      await showAppAlert(context, title: 'Теги', message: 'Теги не найдены.');
      return;
    }
    final result = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Тег'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: _tagFilter == null || _tagFilter == '__all__',
            onPressed: () => Navigator.of(dialogContext).pop('__all__'),
            child: const Text('Все'),
          ),
          for (final t in tags)
            CupertinoActionSheetAction(
              isDefaultAction: _tagFilter == t,
              onPressed: () => Navigator.of(dialogContext).pop(t),
              child: Text(t),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _tagFilter = result == '__all__' ? null : result;
    });
  }

  Future<void> _pickClientFilter() async {
    final store = context.read<MastersStore>();
    final result = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Клиент'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction:
                _clientFilter == null || _clientFilter == '__all__',
            onPressed: () => Navigator.of(dialogContext).pop('__all__'),
            child: const Text('Все'),
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _clientFilter == '__none__',
            onPressed: () => Navigator.of(dialogContext).pop('__none__'),
            child: const Text('Без клиента'),
          ),
          for (final c in [
            ...store.clients,
          ]..sort((a, b) => a.name.compareTo(b.name)))
            CupertinoActionSheetAction(
              isDefaultAction: _clientFilter == c.id,
              onPressed: () => Navigator.of(dialogContext).pop(c.id),
              child: Text(c.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _clientFilter = result == '__all__' ? null : result;
    });
  }

  Future<void> _pickDate(bool from) async {
    DateTime selected = from
        ? (_dateFrom ?? DateTime.now())
        : (_dateTo ?? DateTime.now());
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: context.colors.card,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Отмена'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                CupertinoButton(
                  child: const Text('Готово'),
                  onPressed: () {
                    final picked = DateTime(
                      selected.year,
                      selected.month,
                      selected.day,
                    );
                    Navigator.of(ctx).pop();
                    setState(() {
                      if (from) {
                        _dateFrom = picked;
                      } else {
                        _dateTo = picked;
                      }
                    });
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: selected,
                onDateTimeChanged: (dt) => selected = dt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDateFilter() async {
    final action = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Даты'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('from'),
            child: const Text('С'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('to'),
            child: const Text('По'),
          ),
          if (_dateFrom != null || _dateTo != null)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop('clear'),
              child: const Text('Сбросить'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (action == 'from') {
      await _pickDate(true);
    } else if (action == 'to') {
      await _pickDate(false);
    } else if (action == 'clear' || action == 'all') {
      if (mounted) {
        setState(() {
          _dateFrom = null;
          _dateTo = null;
        });
      }
    }
  }

  Future<void> _showFilters() async {
    if (!mounted) return;
    final settings = context.read<SettingsController>();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Фильтры'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _pickClientFilter();
            },
            child: const Text('Клиент'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openDateFilter();
            },
            child: const Text('Даты'),
          ),
          if (settings.teamEnabled)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _pickAssigneeFilter();
              },
              child: const Text('Исполнитель'),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _pickPriorityFilter();
            },
            child: const Text('Приоритет'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _pickTagFilter();
            },
            child: const Text('Тег'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              setState(() {
                _assigneeFilter = null;
                _priorityFilter = null;
                _tagFilter = null;
                _clientFilter = null;
                _dateFrom = null;
                _dateTo = null;
              });
            },
            child: const Text('Сбросить'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  Future<void> _showViewPicker() async {
    final result = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Вид'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: _view == 'list',
            onPressed: () => Navigator.of(dialogContext).pop('list'),
            child: const Text('Список'),
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _view == 'process',
            onPressed: () => Navigator.of(dialogContext).pop('process'),
            child: const Text('Процесс'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (result != null && mounted) setState(() => _view = result);
  }

  Future<void> _showMoreActions() async {
    final colors = context.colors;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Дополнительно'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _showViewPicker();
            },
            child: const Text('Сменить вид'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _showFilters();
            },
            child: const Text('Фильтры'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _showSearch();
            },
            child: const Text('Поиск'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  Future<void> _quickAdd() async {
    final store = context.read<MastersStore>();

    String clientId;
    if (store.clients.isEmpty) {
      final clientName = await _promptText('Имя клиента', 'Иван');
      if (!mounted) return;
      if (clientName == null || clientName.trim().isEmpty) return;
      final client = await store.createClient(name: clientName.trim());
      if (!mounted) return;
      clientId = client.id;
    } else {
      final sorted = [...store.clients]
        ..sort((a, b) => a.name.compareTo(b.name));
      final selected = await showCupertinoModalPopup<String?>(
        context: context,
        builder: (dialogContext) => CupertinoActionSheet(
          title: const Text('Клиент'),
          actions: [
            for (final c in sorted)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(dialogContext).pop(c.id),
                child: Text(c.name),
              ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(dialogContext).pop('__new__'),
              child: const Text('Отмена клиента'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
        ),
      );
      if (!mounted) return;
      if (selected == null) return;
      if (selected == '__new__') {
        final name = await _promptText('Имя клиента', 'Иван');
        if (!mounted) return;
        if (name == null || name.trim().isEmpty) return;
        final phone = await _promptText('Телефон', 'Телефон');
        final client = await store.createClient(
          name: name.trim(),
          phone: phone?.trim() ?? '',
        );
        if (!mounted) return;
        clientId = client.id;
      } else {
        clientId = selected;
      }
    }

    final title = await _promptText('Название заказа', 'Заказ');
    if (!mounted) return;
    if (title == null || title.trim().isEmpty) return;

    final job = await store.createJob(
      title: title.trim(),
      clientId: clientId,
      assigneeId: store.selfEmployee?.id,
      priority: JobPriority.medium,
    );
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(CupertinoPageRoute(builder: (_) => JobDetailScreen(jobId: job.id)));
  }

  Future<String?> _promptText(String title, String placeholder) async {
    final controller = TextEditingController();
    return showCupertinoDialog<String?>(
      context: context,
      builder: (dc) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            autofocus: true,
            decoration: BoxDecoration(
              color: context.colors.card,
              border: Border.all(color: context.colors.separator),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dc).pop(),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dc).pop(controller.text.trim()),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSearch() async {
    _searchController.text = _query;
    final result = await showCupertinoDialog<String?>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Search'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: _searchController,
            placeholder: 'Search',
            autofocus: true,
            onSubmitted: (_) =>
                Navigator.of(dialogContext).pop(_searchController.text.trim()),
            decoration: BoxDecoration(
              color: context.colors.card,
              border: Border.all(color: context.colors.separator),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () =>
                Navigator.of(dialogContext).pop(_searchController.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _query = result);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Заказы'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _showMoreActions,
              child: const Icon(
                CupertinoIcons.ellipsis_circle,
                semanticLabel: 'Дополнительно',
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _quickAdd,
              child: const Icon(CupertinoIcons.plus, semanticLabel: 'Добавить'),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _view == 'list'
                  ? _buildListView(store)
                  : _buildProcessView(store),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(MastersStore store) {
    final colors = context.colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Статус: ${_statusLabel()}',
                  style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                onPressed: _showStatusPicker,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.line_horizontal_3_decrease,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(_statusLabel()),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final jobs = _filteredJobs(store);
              if (jobs.isEmpty) {
                return EmptyState(
                  title: 'Нет заказов',
                  message: _query.isEmpty
                      ? 'Нажмите +, чтобы создать заказ.'
                      : 'Ничего не найдено.',
                  art: Icon(
                    CupertinoIcons.doc_text,
                    size: 48,
                    color: colors.tertiaryLabel,
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 72),
                itemCount: jobs.length,
                itemBuilder: (context, index) {
                  final job = jobs[index];
                  final client = store.clientById(job.clientId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Dismissible(
                      key: ValueKey(job.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(CupertinoIcons.delete, color: colors.red),
                      ),
                      confirmDismiss: (_) => showAppConfirm(
                        context,
                        title: 'Удалить заказ?',
                        message: 'Этапы, материалы и время тоже удалятся.',
                        destructive: true,
                        confirmLabel: 'Удалить',
                      ),
                      onDismissed: (_) =>
                          context.read<MastersStore>().deleteJob(job.id),
                      child: _JobRow(
                        job: job,
                        store: store,
                        clientName: client?.name ?? '—',
                        onTap: () => Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => JobDetailScreen(jobId: job.id),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProcessView(MastersStore store) {
    final colors = context.colors;
    final settings = context.watch<SettingsController>();
    final filteredJobs =
        store.jobs
            .where((j) => !j.archived && _extraFiltersMatch(j, store))
            .where(
              (j) =>
                  _query.isEmpty ||
                  JobSearchFilter.matches(
                    j,
                    _query.trim().toLowerCase(),
                    store,
                  ),
            )
            .toList()
          ..sort((a, b) {
            if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
            return b.updatedAt.compareTo(a.updatedAt);
          });
    final groups = <_ProcessGroup>[
      for (final col in kanbanColumns.where(
        (c) => settings.kanbanColumnEnabled(c.key),
      ))
        _ProcessGroup(
          key: col.key,
          label: col.label,
          statuses: col.statuses,
          jobs: filteredJobs
              .where((j) => col.statuses.contains(j.status))
              .toList(),
        ),
    ];

    final size = MediaQuery.of(context).size;
    final isWide = size.width > size.height;

    Widget buildColumn(_ProcessGroup group, double? width) {
      return DragTarget<Job>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) =>
            store.setJobStatus(details.data.id, group.statuses.first),
        builder: (context, candidateData, rejectedData) {
          final highlight = candidateData.isNotEmpty;
          return Container(
            width: width,
            margin: const EdgeInsets.only(right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: highlight
                        ? colors.accent.withValues(alpha: 0.12)
                        : colors.cardElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(
                        group.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${group.jobs.length}',
                        style: TextStyle(
                          color: colors.secondaryLabel,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: group.jobs.isEmpty
                      ? Center(
                          child: Text(
                            'Нет заказов',
                            style: TextStyle(color: colors.tertiaryLabel),
                          ),
                        )
                      : ListView.builder(
                          physics: const ClampingScrollPhysics(),
                          itemCount: group.jobs.length,
                          itemBuilder: (context, i) {
                            final job = group.jobs[i];
                            final client = store.clientById(job.clientId);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: LongPressDraggable<Job>(
                                data: job,
                                feedback: Material(
                                  elevation: 4,
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 260,
                                    child: _JobCard(
                                      job: job,
                                      store: store,
                                      clientName: client?.name ?? '—',
                                      onTap: () {},
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.35,
                                  child: _JobCard(
                                    job: job,
                                    store: store,
                                    clientName: client?.name ?? '—',
                                    onTap: () {},
                                  ),
                                ),
                                child: _JobCard(
                                  job: job,
                                  store: store,
                                  clientName: client?.name ?? '—',
                                  onTap: () => Navigator.of(context).push(
                                    CupertinoPageRoute(
                                      builder: (_) =>
                                          JobDetailScreen(jobId: job.id),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups) Expanded(child: buildColumn(group, null)),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 72),
      children: [
        for (final group in groups) ...[
          SizedBox(height: 300, child: buildColumn(group, double.infinity)),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

/// Чистая (без UI) фильтрация заказов по текстовому запросу из лупы.
/// Регистронезависимый поиск по названию, заметкам, тегам,
/// имени клиента и имени исполнителя.
class JobSearchFilter {
  const JobSearchFilter._();

  static bool matches(Job job, String query, MastersStore store) {
    final q = query.toLowerCase();
    if (job.title.toLowerCase().contains(q)) return true;
    if ((job.note ?? '').toLowerCase().contains(q)) return true;
    if ((job.tags ?? '').toLowerCase().contains(q)) return true;
    final client = store.clientById(job.clientId);
    if (client != null && client.name.toLowerCase().contains(q)) return true;
    final assigneeId = job.assigneeId;
    if (assigneeId != null && assigneeId.trim().isNotEmpty) {
      final assigneeName = assigneeId == '__self__'
          ? store.selfEmployee?.name
          : store.employeeById(assigneeId)?.name;
      if (assigneeName != null && assigneeName.toLowerCase().contains(q)) {
        return true;
      }
    }
    return false;
  }
}

class _ProcessGroup {
  const _ProcessGroup({
    required this.key,
    required this.label,
    required this.statuses,
    required this.jobs,
  });

  final String key;
  final String label;
  final List<JobStatus> statuses;
  final List<Job> jobs;
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    required this.job,
    required this.store,
    required this.clientName,
    required this.onTap,
  });

  final Job job;
  final MastersStore store;
  final String clientName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusColor = switch (job.status) {
      JobStatus.nuevo => colors.tertiaryLabel,
      JobStatus.inProgress => colors.accent,
      JobStatus.waitingParts => colors.orange,
      JobStatus.done => colors.green,
      JobStatus.closed => colors.secondaryLabel,
    };
    final totalMin = store.totalMinutesForJob(job.id);

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration:
                        job.status == JobStatus.done ||
                            job.status == JobStatus.closed
                        ? TextDecoration.lineThrough
                        : null,
                    color:
                        job.status == JobStatus.done ||
                            job.status == JobStatus.closed
                        ? colors.tertiaryLabel
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Pill(
                      job.priority.label,
                      color: _priorityColor(context, job.priority),
                    ),
                    for (final tag
                        in (job.tags ?? '')
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty))
                      Pill(tag, color: _tagColor(tag)),
                    Text(
                      clientName,
                      style: TextStyle(
                        color: colors.secondaryLabel,
                        fontSize: 12,
                      ),
                    ),
                    if (job.dueDate != null)
                      Pill(
                        job.dueDate!.year == DateTime.now().year
                            ? DateFormat(
                                'd MMM HH:mm',
                                'ru',
                              ).format(job.dueDate!)
                            : DateFormat(
                                'd MMM yyyy HH:mm',
                                'ru',
                              ).format(job.dueDate!),
                        color: _dueColor(context, job),
                      ),
                    if (totalMin > 0)
                      Text(
                        formatMinutes(totalMin),
                        style: TextStyle(
                          color: colors.secondaryLabel,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (job.pinned)
            Icon(CupertinoIcons.star_fill, size: 16, color: colors.accent),
          if (job.priority == JobPriority.high)
            Icon(CupertinoIcons.exclamationmark, size: 16, color: colors.red),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 16,
            color: colors.tertiaryLabel,
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.store,
    required this.clientName,
    this.onTap,
  });

  final Job job;
  final MastersStore store;
  final String clientName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final totalMin = store.totalMinutesForJob(job.id);
    final stages = store.stagesForJob(job.id);
    final done = stages.where((s) => s.done).length;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  job.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration:
                        job.status == JobStatus.done ||
                            job.status == JobStatus.closed
                        ? TextDecoration.lineThrough
                        : null,
                    color:
                        job.status == JobStatus.done ||
                            job.status == JobStatus.closed
                        ? colors.tertiaryLabel
                        : null,
                  ),
                ),
              ),
              if (job.pinned)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Icon(
                    CupertinoIcons.pin_fill,
                    size: 14,
                    color: colors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            clientName,
            style: TextStyle(color: colors.secondaryLabel, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Pill(
                job.priority.label,
                color: _priorityColor(context, job.priority),
              ),
              for (final tag
                  in (job.tags ?? '')
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty))
                Pill(tag, color: _tagColor(tag)),
              if (job.dueDate != null)
                Pill(
                  job.dueDate!.year == DateTime.now().year
                      ? DateFormat('d MMM HH:mm', 'ru').format(job.dueDate!)
                      : DateFormat(
                          'd MMM yyyy HH:mm',
                          'ru',
                        ).format(job.dueDate!),
                  color: _dueColor(context, job),
                ),
              if (totalMin > 0)
                Text(
                  formatMinutes(totalMin),
                  style: TextStyle(color: colors.secondaryLabel, fontSize: 11),
                ),
              if (stages.isNotEmpty)
                Text(
                  '$done/${stages.length}',
                  style: TextStyle(color: colors.secondaryLabel, fontSize: 11),
                ),
            ],
          ),
          if (stages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ProgressBar(
                value: stages.isEmpty ? 0 : done / stages.length,
              ),
            ),
          if (job.priceCents > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${money(job.priceCents)}',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Color _priorityColor(BuildContext context, JobPriority priority) {
  final colors = context.colors;
  return switch (priority) {
    JobPriority.low => const Color(0xFF6B7A8F),
    JobPriority.medium => colors.orange,
    JobPriority.high => colors.red,
  };
}

Color _tagColor(String tag) {
  const palette = <Color>[
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
    Color(0xFF5AC8FA),
    Color(0xFFFFCC00),
    Color(0xFF8E8E93),
  ];
  final hash = tag.trim().codeUnits.fold<int>(
    0,
    (value, unit) => value * 31 + unit,
  );
  return palette[hash.abs() % palette.length];
}

Color _dueColor(BuildContext context, Job job) {
  final colors = context.colors;
  if (job.dueDate == null ||
      job.status == JobStatus.done ||
      job.status == JobStatus.closed) {
    return colors.tertiaryLabel;
  }
  final due = job.dueDate;
  if (due != null && due.isBefore(DateTime.now())) {
    return colors.red;
  }
  return colors.accent;
}
