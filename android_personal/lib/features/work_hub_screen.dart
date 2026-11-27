import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/money_format.dart';
import '../core/work_recurrence.dart';
import '../data/models.dart';
import '../state/studio_store.dart';
import '../ui/atelier_widgets.dart';

class WorkHubScreen extends StatefulWidget {
  const WorkHubScreen({super.key});

  @override
  State<WorkHubScreen> createState() => _WorkHubScreenState();
}

class _WorkHubScreenState extends State<WorkHubScreen> {
  int _viewMode = 0; // 0: Список, 1: Канбан, 2: Календарь
  int _filter = 0; // 0: Все, 1: Сегодня, 2: Просроченные
  String _search = '';
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _selectedDayIso;

  List<WorkItem> _combinedItems(StudioStore store) {
    final list = List<WorkItem>.from(store.workItems);
    for (final ord in store.orders) {
      if (ord.status == OrderStatus.cancelled) continue;
      final stage = (ord.status == OrderStatus.delivered ||
              ord.status == OrderStatus.closed)
          ? WorkStage.done
          : (ord.status == OrderStatus.inProgress ||
                  ord.status == OrderStatus.ready
              ? WorkStage.inProgress
              : WorkStage.queue);
      list.add(
        WorkItem(
          id: 'order_card_${ord.id}',
          type: WorkItemType.order,
          sourceId: ord.id,
          title: '${ord.orderNumber}: ${ord.title} (${ord.clientName})',
          dueDate: ord.dueDate,
          priority: WorkPriority.high,
          stage: stage,
          tags: ['Заказ', kOrderStatusLabelsRu[ord.status] ?? ''],
        ),
      );
    }
    return list;
  }

  List<WorkItem> _filteredItems(List<WorkItem> all) {
    final today = todayIsoDate();
    final q = _search.trim().toLowerCase();
    return all.where((item) {
      if (q.isNotEmpty && !item.title.toLowerCase().contains(q)) return false;
      if (_filter == 1) {
        return item.dueDate == today && item.stage != WorkStage.done;
      }
      if (_filter == 2) {
        return item.dueDate != null &&
            item.dueDate!.isNotEmpty &&
            item.dueDate!.compareTo(today) < 0 &&
            item.stage != WorkStage.done;
      }
      return true;
    }).toList();
  }

  Future<void> _openTaskEditor(BuildContext context, {WorkItem? existing}) async {
    final store = context.read<StudioStore>();
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final tagsCtrl = TextEditingController(text: existing?.tags.join(', ') ?? '');
    var dueDate = existing?.dueDate ?? todayIsoDate();
    var priority = existing?.priority ?? WorkPriority.normal;
    var type = existing?.type ?? WorkItemType.task;
    var recurrence = existing?.recurrence ?? WorkRecurrence.none;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null ? 'Новая задача' : 'Редактировать задачу',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Название задачи *',
                    hintText: 'Например, Закупить сливки и ягоды',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<WorkItemType>(
                        initialValue: type,
                        decoration: const InputDecoration(labelText: 'Тип'),
                        items: const [
                          DropdownMenuItem(
                              value: WorkItemType.task, child: Text('Задача')),
                          DropdownMenuItem(
                              value: WorkItemType.production,
                              child: Text('Производство')),
                          DropdownMenuItem(
                              value: WorkItemType.purchase,
                              child: Text('Закупка')),
                          DropdownMenuItem(
                              value: WorkItemType.quality,
                              child: Text('Качество')),
                        ],
                        onChanged: (v) {
                          if (v != null) setModalState(() => type = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<WorkPriority>(
                        initialValue: priority,
                        decoration: const InputDecoration(labelText: 'Приоритет'),
                        items: const [
                          DropdownMenuItem(
                              value: WorkPriority.low, child: Text('Низкий')),
                          DropdownMenuItem(
                              value: WorkPriority.normal, child: Text('Обычный')),
                          DropdownMenuItem(
                              value: WorkPriority.high, child: Text('Высокий')),
                        ],
                        onChanged: (v) {
                          if (v != null) setModalState(() => priority = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.tryParse(dueDate) ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setModalState(() => dueDate = todayIsoDate(picked));
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text('Срок: $dueDate'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<WorkRecurrence>(
                        initialValue: recurrence,
                        decoration: const InputDecoration(labelText: 'Повтор'),
                        items: WorkRecurrence.values
                            .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(kRecurrenceLabelsRu[r] ?? r.name),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setModalState(() => recurrence = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tagsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Теги (через запятую)',
                    hintText: 'Выпечка, Закуп',
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () async {
                    if (titleCtrl.text.trim().isEmpty) return;
                    final tags = tagsCtrl.text
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    final item = WorkItem(
                      id: existing?.id ?? newId('wi'),
                      type: type,
                      sourceId: existing?.sourceId,
                      title: titleCtrl.text.trim(),
                      dueDate: dueDate,
                      priority: priority,
                      stage: existing?.stage ?? WorkStage.queue,
                      tags: tags,
                      recurrence: recurrence,
                      seriesId: recurrence == WorkRecurrence.none
                          ? null
                          : (existing?.seriesId ?? newId('ser')),
                      occurrenceIndex: recurrence == WorkRecurrence.none
                          ? null
                          : (existing?.occurrenceIndex ?? 1),
                    );
                    await store.saveWorkItem(item);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(existing == null ? 'Создать задачу' : 'Сохранить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudioStore>();
    final p = store.palette;
    final all = _combinedItems(store);
    final items = _filteredItems(all);
    final today = todayIsoDate();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Список')),
                        ButtonSegment(value: 1, label: Text('Канбан')),
                        ButtonSegment(value: 2, label: Text('Календарь')),
                      ],
                      selected: {_viewMode},
                      onSelectionChanged: (s) =>
                          setState(() => _viewMode = s.first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _openTaskEditor(context),
                    tooltip: 'Добавить задачу',
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Поиск по задачам и заказам...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final opt in [
                      (0, 'Все (${all.length})'),
                      (1, 'Сегодня'),
                      (2, 'Просроченные'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(opt.$2),
                          selected: _filter == opt.$1,
                          onSelected: (_) => setState(() => _filter = opt.$1),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _viewMode == 0
              ? _buildListView(context, store, items, today)
              : _viewMode == 1
                  ? _buildKanbanView(context, store, items, today)
                  : _buildCalendarView(context, store, items, p),
        ),
      ],
    );
  }

  Widget _buildListView(
    BuildContext context,
    StudioStore store,
    List<WorkItem> items,
    String today,
  ) {
    final p = store.palette;
    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyAtelierState(
            icon: Icons.task_alt_outlined,
            title: 'Задачи по фильтру не найдены',
            description:
                'Создайте задачу или повторяющийся чек-лист (например, ежедневная проверка температур).',
            actionLabel: 'Добавить задачу',
            onAction: () => _openTaskEditor(context),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final item = items[i];
        final isOrder = item.type == WorkItemType.order;
        final overdue = item.stage != WorkStage.done &&
            item.dueDate != null &&
            item.dueDate!.isNotEmpty &&
            item.dueDate!.compareTo(today) < 0;

        return AtelierCard(
          onTap: isOrder ? () => store.setTab(2) : () => _openTaskEditor(ctx, existing: item),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isOrder)
                Checkbox(
                  value: item.stage == WorkStage.done,
                  onChanged: (checked) async {
                    await store.moveWorkItemStage(
                      item,
                      checked == true ? WorkStage.done : WorkStage.queue,
                    );
                  },
                )
              else
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.cake_outlined, color: p.primary, size: 20),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: item.stage == WorkStage.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.dueDate != null && item.dueDate!.isNotEmpty)
                          StatusBadge(
                            label: item.dueDate!,
                            color: overdue ? p.danger : p.primary,
                          ),
                        StatusBadge(
                          label: kWorkStageLabelsRu[item.stage] ?? '',
                          color: item.stage == WorkStage.done
                              ? p.success
                              : p.secondary,
                        ),
                        if (item.recurrence != WorkRecurrence.none)
                          StatusBadge(
                            label: kRecurrenceLabelsRu[item.recurrence] ?? '',
                            color: p.warning,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isOrder)
                PopupMenuButton<WorkStage>(
                  tooltip: 'Стадия',
                  onSelected: (s) => store.moveWorkItemStage(item, s),
                  itemBuilder: (_) => [
                    for (final s in WorkStage.values)
                      PopupMenuItem(
                        value: s,
                        child: Text(kWorkStageLabelsRu[s] ?? s.name),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKanbanView(
    BuildContext context,
    StudioStore store,
    List<WorkItem> items,
    String today,
  ) {
    final p = store.palette;
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
      children: [
        for (final stage in WorkStage.values) ...[
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        kWorkStageLabelsRu[stage] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusBadge(
                        label: '${items.where((e) => e.stage == stage).length}',
                        color: p.primary,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final item
                          in items.where((e) => e.stage == stage)) ...[
                        AtelierCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              if (item.dueDate != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    item.dueDate!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: item.dueDate!.compareTo(today) < 0 &&
                                              stage != WorkStage.done
                                          ? p.danger
                                          : p.textMuted,
                                    ),
                                  ),
                                ),
                              if (item.type != WorkItemType.order) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    if (stage != WorkStage.queue)
                                      TextButton(
                                        onPressed: () => store.moveWorkItemStage(
                                          item,
                                          stage == WorkStage.done
                                              ? WorkStage.inProgress
                                              : WorkStage.queue,
                                        ),
                                        child: const Text('← Назад'),
                                      ),
                                    const Spacer(),
                                    if (stage != WorkStage.done)
                                      FilledButton.tonal(
                                        onPressed: () => store.moveWorkItemStage(
                                          item,
                                          stage == WorkStage.queue
                                              ? WorkStage.inProgress
                                              : WorkStage.done,
                                        ),
                                        child: Text(
                                          stage == WorkStage.queue
                                              ? 'В работу →'
                                              : 'Готово ✓',
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _buildCalendarView(
    BuildContext context,
    StudioStore store,
    List<WorkItem> items,
    dynamic p,
  ) {
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startOffset = (firstDay.weekday - 1) % 7;

    final mapByDay = <String, List<WorkItem>>{};
    for (final w in items) {
      if (w.dueDate != null && w.dueDate!.length >= 10) {
        final key = w.dueDate!.substring(0, 10);
        (mapByDay[key] ??= []).add(w);
      }
    }

    const monthsRu = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];

    final selectedItems = _selectedDayIso != null
        ? (mapByDay[_selectedDayIso!] ?? const <WorkItem>[])
        : const <WorkItem>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
      children: [
        AtelierCard(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      _calendarMonth = DateTime(year, month - 1);
                      _selectedDayIso = null;
                    }),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${monthsRu[month - 1]} $year',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _calendarMonth = DateTime(year, month + 1);
                      _selectedDayIso = null;
                    }),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('Пн', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('Вт', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('Ср', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('Чт', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('Пт', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('Сб', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('Вс', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.0,
                ),
                itemCount: startOffset + daysInMonth,
                itemBuilder: (_, idx) {
                  if (idx < startOffset) return const SizedBox.shrink();
                  final day = idx - startOffset + 1;
                  final iso =
                      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                  final dayCount = mapByDay[iso]?.length ?? 0;
                  final selected = _selectedDayIso == iso;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selectedDayIso = iso),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: selected
                            ? p.primary
                            : (dayCount > 0 ? p.surfaceAlt : null),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: selected ? p.onPrimary : null,
                            ),
                          ),
                          if (dayCount > 0)
                            Text(
                              '•$dayCount',
                              style: TextStyle(
                                fontSize: 10,
                                color: selected ? p.onPrimary : p.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedDayIso != null) ...[
          SectionHeader(title: 'События на $_selectedDayIso'),
          const SizedBox(height: 8),
          if (selectedItems.isEmpty)
            const Text('На выбранную дату задач и выдач нет.')
          else
            for (final w in selectedItems) ...[
              AtelierCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        w.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    StatusBadge(
                      label: kWorkStageLabelsRu[w.stage] ?? '',
                      color: p.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ],
    );
  }
}
