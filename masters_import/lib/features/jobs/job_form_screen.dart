import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/units.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/job.dart';
import '../catalog/catalog_screen.dart';
import 'job_form_widgets.dart';
import 'cost_calculator_screen.dart';
import '../../state/masters_store.dart';
import '../../state/settings_controller.dart';
import '../../core/money_format.dart';

class JobFormScreen extends StatefulWidget {
  const JobFormScreen({
    super.key,
    this.jobId,
    this.initialClientId,
    this.initialObjectId,
    this.itemId,
  });
  final String? jobId;
  final String? initialClientId;
  final String? initialObjectId;

  /// Позиция каталога, с которой начинают заказ (из экрана «Каталог»).
  final String? itemId;

  @override
  State<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends State<JobFormScreen> {
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController();
  final _noteController = TextEditingController();
  final _tagsController = TextEditingController();

  String? _clientId;
  String? _objectId;
  String? _assigneeId;
  JobStatus _status = JobStatus.nuevo;
  JobPriority _priority = JobPriority.medium;
  DateTime? _dueDate;
  bool _saving = false;
  bool _seededItem = false;

  /// Строки и параметры, добавленные до появления заказа в базе.
  final List<JobLineDraft> _pendingLines = [];
  final List<JobAttrDraft> _pendingAttrs = [];

  bool get _isEdit => widget.jobId != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isEdit && _assigneeId == null) {
      _assigneeId = context.read<MastersStore>().selfEmployee?.id;
    }
    _loadJob();
  }

  void _loadJob() {
    final store = context.read<MastersStore>();
    if (!_isEdit) {
      if (!_seededItem && widget.itemId != null) {
        _seededItem = true;
        final matches = store.inventoryItems.where(
          (i) => i.id == widget.itemId,
        );
        if (matches.isNotEmpty) {
          final item = matches.first;
          _seededItem = true;
          _pendingLines.add(
            JobLineDraft(
              itemId: item.id,
              name: item.name,
              qty: 1,
              unit: item.unit,
              priceCents: item.sellPriceCents,
              costAtOrderCents: item.kind == 'service' ? 0 : item.costCents,
              kind: item.kind == 'service' ? 'work' : 'good',
            ),
          );
          if (_titleController.text.isEmpty) {
            _titleController.text = item.name;
          }
        }
      }
      if (_clientId == null &&
          widget.initialClientId != null &&
          store.clientById(widget.initialClientId!) != null) {
        _clientId = widget.initialClientId;
      }
      if (_objectId == null && widget.initialObjectId != null) {
        final obj = store.objectById(widget.initialObjectId);
        if (obj != null && (_clientId == null || obj.clientId == _clientId)) {
          _objectId = widget.initialObjectId;
          _clientId ??= obj.clientId;
        }
      }
      return;
    }
    if (_titleController.text.isNotEmpty) return;
    final job = store.jobById(widget.jobId!);
    if (job == null) return;
    _titleController.text = job.title;
    _clientId = job.clientId;
    _objectId = job.objectId;
    _assigneeId = job.assigneeId;
    _status = job.status;
    _priority = job.priority;
    _priceController.text = (job.priceCents / 100)
        .toStringAsFixed(2)
        .replaceAll('.00', '');
    _costController.text = (job.costCents / 100)
        .toStringAsFixed(2)
        .replaceAll('.00', '');
    _noteController.text = job.note ?? '';
    _tagsController.text = job.tags ?? '';
    _dueDate = job.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _noteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  int _parseCents(String v) {
    final normalized = v.trim().replaceAll(',', '.');
    final d = double.tryParse(normalized);
    if (d == null) return 0;
    return (d * 100).round();
  }

  Future<void> _pickClient() async {
    final store = context.read<MastersStore>();
    final clients = store.clients;
    final selected = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 320,
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
                  child: const Text('Новый клиент'),
                  onPressed: () => Navigator.of(ctx).pop('__new__'),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final c in clients)
                    CupertinoButton(
                      onPressed: () => Navigator.of(ctx).pop(c.id),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(c.name),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (selected == '__new__') {
      final name = await _promptText('Имя клиента', 'Иван');
      if (name == null || name.trim().isEmpty) return;
      final client = await store.createClient(name: name.trim());
      if (!mounted) return;
      setState(() {
        _clientId = client.id;
        _objectId = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _clientId = selected;
      _objectId = null;
    });
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

  Future<void> _pickObject() async {
    if (_clientId == null) return;
    final store = context.read<MastersStore>();
    final objects = store.objects
        .where((o) => o.clientId == _clientId)
        .toList();
    if (objects.isEmpty) {
      final title = await _promptText('Новый объект', 'Квартира / адрес');
      if (title == null || title.trim().isEmpty) return;
      final obj = await store.createObject(
        clientId: _clientId!,
        title: title.trim(),
      );
      if (!mounted) return;
      setState(() => _objectId = obj.id);
      return;
    }
    final selected = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 320,
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
                  child: const Text('Новый'),
                  onPressed: () => Navigator.of(ctx).pop('__new__'),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('— без объекта —'),
                    ),
                  ),
                  for (final o in objects)
                    CupertinoButton(
                      onPressed: () => Navigator.of(ctx).pop(o.id),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(o.title),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == '__new__') {
      final title = await _promptText('Новый объект', 'Квартира / адрес');
      if (title == null || title.trim().isEmpty) return;
      final obj = await store.createObject(
        clientId: _clientId!,
        title: title.trim(),
      );
      if (!mounted) return;
      setState(() => _objectId = obj.id);
      return;
    }
    if (!mounted) return;
    setState(() => _objectId = selected);
  }

  Future<void> _pickAssignee() async {
    final store = context.read<MastersStore>();
    final emps = store.employees;
    final selected = await showCupertinoModalPopup<String?>(
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
                  child: const Text('Без'),
                  onPressed: () => Navigator.of(ctx).pop('__none__'),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final e in emps)
                    CupertinoButton(
                      onPressed: () => Navigator.of(ctx).pop(e.id),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(e.name),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (selected == '__none__') {
      setState(() => _assigneeId = null);
      return;
    }
    setState(() => _assigneeId = selected);
  }

  Future<void> _pickPriority() async {
    final selected = await showCupertinoModalPopup<JobPriority?>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Приоритет'),
        actions: [
          for (final p in JobPriority.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(p),
              isDefaultAction: p == _priority,
              child: Text(p.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _priority = selected);
  }

  Future<void> _pickDueDate() async {
    DateTime selected = _dueDate ?? DateTime.now();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => Container(
        height: 300,
        color: context.colors.card,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Отмена'),
                  onPressed: () => Navigator.of(modalContext).pop(),
                ),
                CupertinoButton(
                  child: const Text('Готово'),
                  onPressed: () {
                    setState(() => _dueDate = selected);
                    Navigator.of(modalContext).pop();
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

  // Строки заказа: в режиме правки пишутся в базу сразу, в новом заказе
  // копятся в _pendingLines и применяются после createJob.

  List<JobLineView> _lineViews(MastersStore store) {
    if (!_isEdit) {
      return List<JobLineView>.unmodifiable(_pendingLines);
    }
    return [
      for (final line in store.jobLines(widget.jobId!))
        JobLineView(
          name: line.name,
          qty: line.quantity,
          unit: line.unit,
          priceCents: line.priceCents,
          costAtOrderCents: line.costAtOrderCents,
          discountCents: line.discountCents,
          kind: line.kind,
          itemId: line.itemId,
        ),
    ];
  }

  /// Итог заказа: цена и себестоимость по строкам либо вручную, если строк нет.
  ({int priceCents, int costCents, bool fromLines}) _totals(MastersStore store) {
    final lines = _lineViews(store);
    if (lines.isEmpty) {
      return (
        priceCents: _parseCents(_priceController.text),
        costCents: _parseCents(_costController.text),
        fromLines: false,
      );
    }
    var price = 0;
    var cost = 0;
    for (final line in lines) {
      price += line.totalCents - line.discountCents;
      cost += line.costTotalCents;
    }
    return (priceCents: price, costCents: cost, fromLines: true);
  }

  Future<void> _addFromCatalog() async {
    final store = context.read<MastersStore>();
    final picked = await showCatalogPicker(context);
    if (picked == null || !mounted) return;
    final item = picked.item;
    final qty = picked.quantity;
    final view = JobLineView(
      name: item.name,
      qty: qty,
      unit: item.unit,
      priceCents: item.sellPriceCents,
      costAtOrderCents: item.kind == 'service' ? 0 : item.costCents,
      kind: item.kind == 'service' ? 'work' : 'good',
      itemId: item.id,
    );
    if (_isEdit) {
      await store.createJobLine(
        widget.jobId!,
        itemId: item.id,
        kind: view.kind,
        name: view.name,
        qty: qty,
        unit: item.unit,
        priceCents: item.sellPriceCents,
        costAtOrderCents: view.costAtOrderCents,
      );
      await store.recalcJobTotals(widget.jobId!);
    } else {
      _pendingLines.add(JobLineDraft.fromView(view));
      setState(() {});
    }
  }

  Future<void> _addFreeLine() async {
    final view = await showCupertinoModalPopup<JobLineView>(
      context: context,
      builder: (_) => const JobLineEditorSheet(),
    );
    if (view == null || !mounted) return;
    final store = context.read<MastersStore>();
    if (_isEdit) {
      await store.createJobLine(
        widget.jobId!,
        kind: view.kind,
        name: view.name,
        qty: view.qty,
        unit: view.unit,
        priceCents: view.priceCents,
        costAtOrderCents: view.costAtOrderCents,
        discountCents: view.discountCents,
      );
      await store.recalcJobTotals(widget.jobId!);
    } else {
      _pendingLines.add(JobLineDraft.fromView(view));
      setState(() {});
    }
  }

  Future<void> _editLine(int index) async {
    final store = context.read<MastersStore>();
    final current = _lineViews(store)[index];
    final edited = await showCupertinoModalPopup<JobLineView>(
      context: context,
      builder: (_) => JobLineEditorSheet(initial: current),
    );
    if (edited == null || !mounted) return;
    if (_isEdit) {
      final lines = store.jobLines(widget.jobId!);
      await store.updateJobLine(
        lines[index].id,
        qty: edited.qty,
        priceCents: edited.priceCents,
        costAtOrderCents: edited.costAtOrderCents,
        discountCents: edited.discountCents,
        name: edited.name,
        unit: edited.unit,
      );
      await store.recalcJobTotals(widget.jobId!);
    } else {
      _pendingLines[index] = JobLineDraft.fromView(edited);
      setState(() {});
    }
  }

  Future<void> _deleteLine(int index) async {
    final confirmed = await showAppConfirm(
      context,
      title: 'Удалить строку?',
      message: 'Строка уйдёт из заказа, её сумма вычтется из итога.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final store = context.read<MastersStore>();
    if (_isEdit) {
      final lines = store.jobLines(widget.jobId!);
      await store.deleteMaterial(lines[index].id);
      await store.recalcJobTotals(widget.jobId!);
    } else {
      setState(() => _pendingLines.removeAt(index));
    }
  }

  Future<void> _addAttribute() async {
    final store = context.read<MastersStore>();
    final draft = await showCupertinoModalPopup<JobAttrDraft>(
      context: context,
      builder: (_) => JobAttrSheet(hints: _attributeHints(store)),
    );
    if (draft == null || !mounted) return;
    if (_isEdit) {
      try {
        await store.setAttributeValue(
          entityType: 'job',
          entityId: widget.jobId!,
          key: draft.key,
          raw: draft.value ?? '',
        );
      } on FormatException catch (e) {
        if (!mounted) return;
        await showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Ошибка'),
            content: Text(e.message),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    } else {
      setState(() => _pendingAttrs.add(draft));
    }
  }

  /// Подсказки параметров: какие ключи уже заводили для выбранных позиций.
  List<String> _attributeHints(MastersStore store) {
    final hints = <String>{};
    for (final itemId in _lineViews(store).map((l) => l.itemId)) {
      if (itemId == null) continue;
      for (final attribute in store.attributesOf('item', itemId)) {
        hints.add(attribute.key);
      }
    }
    for (final attribute in _pendingAttrs) {
      hints.add(attribute.key);
    }
    return hints.toList();
  }

  Future<void> _applyPending(MastersStore store, String jobId) async {
    for (final line in _pendingLines) {
      await store.createJobLine(
        jobId,
        itemId: line.itemId,
        kind: line.kind,
        name: line.name,
        qty: line.qty,
        unit: line.unit,
        priceCents: line.priceCents,
        costAtOrderCents: line.costAtOrderCents,
        discountCents: line.discountCents,
      );
    }
    for (final attribute in _pendingAttrs) {
      await store.setAttribute(
        entityType: 'job',
        entityId: jobId,
        key: attribute.key,
        valueText: attribute.value,
      );
    }
    if (_pendingLines.isNotEmpty) await store.recalcJobTotals(jobId);
  }

  Future<void> _save() async {
    final store = context.read<MastersStore>();
    // Название первой строки каталога достаточно: мастер выбрал позицию, а
    // пересказывать её руками — лишний экран с ошибкой.
    final title = _titleController.text.trim();
    final fallbackTitle = _lineViews(store).isEmpty
        ? ''
        : _lineViews(store).first.name;
    final effectiveTitle = title.isEmpty ? fallbackTitle : title;
    if (effectiveTitle.isEmpty) {
      await showAppAlert(
        context,
        title: 'Название',
        message: 'Введите название заказа или добавьте строку из каталога.',
      );
      return;
    }
    if (_clientId == null) {
      await showAppAlert(
        context,
        title: 'Клиент',
        message: 'Выберите клиента.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final totals = _totals(store);
      final manual = totals.fromLines
          ? null
          : (
              priceCents: _parseCents(_priceController.text),
              costCents: _parseCents(_costController.text),
            );
      if (_isEdit) {
        final job = store.jobById(widget.jobId!)!;
        await store.updateJob(
          job.copyWith(
            title: effectiveTitle,
            clientId: _clientId!,
            objectId: _objectId,
            assigneeId: _assigneeId,
            status: _status,
            priority: _priority,
            priceCents: manual?.priceCents,
            costCents: manual?.costCents,
            dueDate: _dueDate,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
            tags: _tagsController.text.trim().isEmpty
                ? null
                : _tagsController.text.trim(),
          ),
        );
        await store.recalcJobTotals(widget.jobId!);
      } else {
        final job = await store.createJob(
          clientId: _clientId!,
          objectId: _objectId,
          assigneeId: _assigneeId,
          title: effectiveTitle,
          status: _status,
          priority: _priority,
          priceCents: manual?.priceCents ?? 0,
          costCents: manual?.costCents ?? 0,
          dueDate: _dueDate,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
          tags: _tagsController.text.trim().isEmpty
              ? null
              : _tagsController.text.trim(),
        );
        await _applyPending(store, job.id);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<MastersStore>();
    final settings = context.watch<SettingsController>();
    final client = _clientId == null ? null : store.clientById(_clientId!);
    final obj = _objectId == null ? null : store.objectById(_objectId);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isEdit ? 'Редактировать заказ' : 'Новый заказ'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: const Text('Сохранить'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
          children: [
            SectionLabel('Что делаем'),
            AppCard(
              child: Column(
                children: [
                  CupertinoTextField(
                    controller: _titleController,
                    placeholder: 'Название заказа',
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(color: colors.label),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          client?.name ?? 'Клиент не выбран',
                          style: TextStyle(
                            color: client == null
                                ? colors.secondaryLabel
                                : colors.label,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _pickClient,
                        child: const Text('Выбрать'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          obj?.title ?? 'Без объекта',
                          style: TextStyle(color: colors.secondaryLabel),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _clientId == null ? null : _pickObject,
                        child: const Text('Объект'),
                      ),
                    ],
                  ),
                  if (settings.teamEnabled) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _assigneeId == null
                                ? 'Исполнитель не выбран'
                                : (context
                                          .read<MastersStore>()
                                          .employeeById(_assigneeId!)
                                          ?.name ??
                                      'Исполнитель'),
                            style: TextStyle(color: colors.secondaryLabel),
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: _pickAssignee,
                          child: const Text('Исполнитель'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                children: [
                  for (final entry in _lineViews(store).asMap().entries) ...[
                    if (entry.key > 0) const Hairline(indent: 12),
                    ListRow(
                      dense: true,
                      title: entry.value.name,
                      subtitle:
                          '${formatQty(entry.value.qty)} ${entry.value.unit}'
                          ' × ${money(entry.value.priceCents)}'
                          ' · себест. ${money(entry.value.costTotalCents)}',
                      icon: entry.value.kind == 'work'
                          ? CupertinoIcons.wrench
                          : CupertinoIcons.cube_box,
                      onTap: () => _editLine(entry.key),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            money(entry.value.netCents),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.only(left: 6),
                            minimumSize: const Size(24, 24),
                            onPressed: () => _deleteLine(entry.key),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 14,
                              color: colors.tertiaryLabel,
                              semanticLabel: 'Удалить строку',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_lineViews(store).isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Text(
                        'Пусто. Добавьте позицию из каталога — цена и себестоимость подставятся сами.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.secondaryLabel,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChipButton(
                          label: '+ Из каталога',
                          icon: CupertinoIcons.cube_box,
                          onPressed: _addFromCatalog,
                        ),
                        ChipButton(
                          label: '+ Свободная строка',
                          icon: CupertinoIcons.plus,
                          color: colors.purple,
                          onPressed: _addFreeLine,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Параметры'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                children: [
                  if (_isEdit)
                    for (final attribute
                        in store.attributesOf('job', widget.jobId!))
                      ListRow(
                        dense: true,
                        icon: CupertinoIcons.tag,
                        title: attribute.key,
                        subtitle: attribute.valueText ??
                            attribute.valueNum?.toString(),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => store.deleteAttribute(attribute.id),
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 14,
                            color: colors.tertiaryLabel,
                            semanticLabel: 'Удалить',
                          ),
                        ),
                      )
                  else
                    for (final attribute in _pendingAttrs)
                      ListRow(
                        dense: true,
                        icon: CupertinoIcons.tag,
                        title: attribute.key,
                        subtitle: attribute.value,
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => setState(
                            () => _pendingAttrs.remove(attribute),
                          ),
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 14,
                            color: colors.tertiaryLabel,
                            semanticLabel: 'Удалить',
                          ),
                        ),
                      ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                    child: ChipButton(
                      label: '+ Параметр',
                      icon: CupertinoIcons.plus,
                      onPressed: _addAttribute,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Приоритет'),
            AppCard(
              child: SecondaryButton(
                label: 'Приоритет: ${_priority.label}',
                icon: CupertinoIcons.list_bullet,
                onPressed: _pickPriority,
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Итог'),
            JobTotalsCard(
              totals: _totals(store),
              manual: JobManualSumsRow(
                priceController: _priceController,
                costController: _costController,
                onChanged: () => setState(() {}),
              ),
            ),
            if (settings.calculatorEnabled) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Калькулятор расходов',
                icon: CupertinoIcons.money_dollar,
                onPressed: () async {
                  final result = await Navigator.of(context)
                      .push<Map<String, int>>(
                        CupertinoPageRoute(
                          builder: (_) =>
                              CostCalculatorScreen(jobId: widget.jobId),
                        ),
                      );
                  if (result == null || !mounted) return;
                  _costController.text = ((result['costCents'] as int) / 100)
                      .toStringAsFixed(2);
                  _priceController.text = ((result['priceCents'] as int) / 100)
                      .toStringAsFixed(2);
                },
              ),
            ],
            const SizedBox(height: 16),
            SectionLabel('Срок и заметки'),
            AppCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Дедлайн',
                        style: TextStyle(color: colors.secondaryLabel),
                      ),
                      const Spacer(),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _pickDueDate,
                        child: Text(
                          _dueDate == null
                              ? 'Не задан'
                              : formatFullDate(_dueDate!),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_dueDate != null)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => setState(() => _dueDate = null),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            size: 16,
                            semanticLabel: 'Очистить',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CupertinoTextField(
                    controller: _noteController,
                    placeholder: 'Заметка',
                    maxLines: 4,
                    minLines: 2,
                  ),
                  if (settings.jobTagsEnabled) ...[
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: _tagsController,
                      placeholder: 'Теги (через запятую)',
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag
                            in context.read<SettingsController>().jobTags)
                          GestureDetector(
                            onTap: () {
                              final current = _tagsController.text.trim();
                              final existing = current.isEmpty
                                  ? <String>[]
                                  : current
                                        .split(',')
                                        .map((e) => e.trim())
                                        .toList();
                              if (!existing.contains(tag)) {
                                _tagsController.text = existing.isEmpty
                                    ? tag
                                    : '$current, $tag';
                                setState(() {});
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: context.colors.cardElevated,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка будущего заказа: тот же набор полей, что и у `JobLineView`, но она
/// живёт в памяти формы, пока заказ не создан.
class JobLineDraft extends JobLineView {
  const JobLineDraft({
    required super.name,
    required super.qty,
    required super.unit,
    required super.priceCents,
    required super.costAtOrderCents,
    super.discountCents,
    super.kind,
    super.itemId,
  });

  factory JobLineDraft.fromView(JobLineView view) => JobLineDraft(
    name: view.name,
    qty: view.qty,
    unit: view.unit,
    priceCents: view.priceCents,
    costAtOrderCents: view.costAtOrderCents,
    discountCents: view.discountCents,
    kind: view.kind,
    itemId: view.itemId,
  );
}
