import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/money_format.dart';
import '../../core/units.dart';
import '../../data/models/entity_attribute.dart';
import '../../data/models/inventory_composition.dart';
import '../../data/models/inventory_item.dart';
import '../../state/masters_store.dart';
import '../inventory/inventory_composition_screen.dart';
import '../jobs/job_form_screen.dart';

/// Каталог: товары и услуги с ценой, себестоимостью и маржой.
///
/// Витрина лежит поверх `inventory_items`: склад отвечает за остаток, каталог —
/// за то, что мастер продаёт, и по какой цене. Отдельной таблицы нет
/// намеренно: позиция, из которой делают заказ, и позиция, которая списывается
/// со склада, должны быть одним и тем же объектом.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, this.initialQuery});

  /// Строка поиска при открытии.
  ///
  /// Нужна, чтобы сигнал низкой маржи в заказе открывал именно ту позицию,
  /// по которой пересматривают цену, а не весь список.
  final String? initialQuery;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final TextEditingController _searchController =
      TextEditingController(text: widget.initialQuery ?? '');
  String get _query => _searchController.text;
  set _query(String value) => _searchController.text = value;
  String _filter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<InventoryItem> _visible(MastersStore store) {
    var list = store.inventoryItems.where((i) => !i.archived).toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (i) =>
                i.name.toLowerCase().contains(q) ||
                i.category.toLowerCase().contains(q) ||
                i.unit.toLowerCase().contains(q),
          )
          .toList();
    }
    switch (_filter) {
      case 'good':
        list = list.where((i) => i.kind == 'good').toList();
      case 'service':
        list = list.where((i) => i.kind == 'service').toList();
      case 'popular':
        list = list.where((i) => store.isItemPopular(i.id)).toList();
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<void> _pickFilter() async {
    final value = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Фильтр каталога'),
        actions: [
          for (final option in const [
            ('all', 'Все позиции'),
            ('good', 'Только товары'),
            ('service', 'Только услуги'),
            ('popular', 'Популярное'),
          ])
            CupertinoActionSheetAction(
              isDefaultAction: option.$1 == _filter,
              onPressed: () => Navigator.of(sheetContext).pop(option.$1),
              child: Text(option.$2),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (value == null || !mounted) return;
    setState(() => _filter = value);
  }

  Future<void> _edit(InventoryItem? item) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _CatalogItemSheet(item: item),
    );
  }

  Future<void> _duplicate(MastersStore store, InventoryItem item) async {
    final copy = await store.createInventoryItem(
      name: '${item.name} (копия)',
      kind: item.kind,
      unit: item.unit,
      sellPriceCents: item.sellPriceCents,
      costCents: item.costCents,
      category: item.category,
      trackStock: item.trackStock,
      minQty: item.minQty,
    );
    for (final attribute in store.attributesOf('item', item.id)) {
      if (attribute.key == 'popular') continue;
      await store.setAttribute(
        entityType: 'item',
        entityId: copy.id,
        key: attribute.key,
        valueText: attribute.valueText,
        valueNum: attribute.valueNum,
        sortOrder: attribute.sortOrder,
      );
    }
  }

  Future<void> _archive(MastersStore store, InventoryItem item) async {
    final confirmed = await showAppConfirm(
      context,
      title: 'В архив?',
      message: '«${item.name}» скроется из каталога. Прошлые заказы не изменятся.',
      confirmLabel: 'В архив',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await store.updateInventoryItem(item.copyWith(archived: true));
  }

  Future<void> _showActions(InventoryItem item) async {
    final store = context.read<MastersStore>();
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(item.name),
        message: Text(
          '${item.kind == 'service' ? 'Услуга' : 'Товар'} · ${item.unit}'
          ' · ${money(item.sellPriceCents)}',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('order'),
            child: const Text('Создать заказ'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('edit'),
            child: const Text('Изменить'),
          ),
          if (item.kind == 'good')
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('composition'),
              child: const Text('Состав'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('popular'),
            child: Text(
              store.isItemPopular(item.id)
                  ? 'Снять «популярное»'
                  : 'Отметить популярным',
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('duplicate'),
            child: const Text('Дублировать'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext).pop('archive'),
            child: const Text('В архив'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'order':
        await Navigator.of(context).push(
          CupertinoPageRoute(builder: (_) => JobFormScreen(itemId: item.id)),
        );
      case 'edit':
        await _edit(item);
      case 'composition':
        if (!mounted) return;
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => InventoryCompositionScreen(itemId: item.id),
          ),
        );
      case 'popular':
        await store.setItemPopular(item.id, !store.isItemPopular(item.id));
      case 'duplicate':
        await _duplicate(store, item);
      case 'archive':
        await _archive(store, item);
    }
  }

  Widget _card(MastersStore store, InventoryItem item) {
    final colors = context.colors;
    final margin = item.sellPriceCents > 0
        ? ((item.sellPriceCents - item.costCents) * 100 / item.sellPriceCents)
              .round()
        : null;
    final attributes = store.attributesOf('item', item.id);
    final compositionCount = store.itemComposition(item.id).length;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: () => _showActions(item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: item.kind == 'service'
                ? CupertinoIcons.wrench
                : CupertinoIcons.cube_box,
            color: item.kind == 'service' ? colors.purple : colors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${money(item.sellPriceCents)}/${item.unit}'
                  ' · себест. ${money(item.costCents)}'
                  '${margin == null ? '' : ' · маржа $margin%'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.secondaryLabel,
                  ),
                ),
                if (store.isItemPopular(item.id) ||
                    attributes.isNotEmpty ||
                    compositionCount > 0) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (store.isItemPopular(item.id))
                        Pill('популярное', color: colors.orange),
                      if (compositionCount > 0)
                        Pill(
                          'состав: $compositionCount',
                          color: colors.accent,
                          icon: CupertinoIcons.cube_box_fill,
                        ),
                      for (final attribute in attributes.take(3))
                        Pill(
                          attribute.valueText == null
                              ? attribute.key
                              : '${attribute.key}: ${attribute.valueText}',
                        ),
                      if (attributes.length > 3)
                        Pill('+${attributes.length - 3}', color: colors.purple),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Icon(
              CupertinoIcons.chevron_right,
              size: 15,
              color: colors.tertiaryLabel,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;
    final items = _visible(store);
    final priced = items.where((i) => i.sellPriceCents > 0).toList();
    final averageMargin = priced.isEmpty
        ? null
        : priced
              .map(
                (i) =>
                    (i.sellPriceCents - i.costCents) * 100 / i.sellPriceCents,
              )
              .reduce((a, b) => a + b) /
              priced.length;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Каталог'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(34, 34),
          onPressed: () => _edit(null),
          child: const Icon(
            CupertinoIcons.plus,
            semanticLabel: 'Новая позиция',
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
          children: [
            CupertinoTextField(
              controller: _searchController,
              placeholder: 'Поиск по каталогу',
              style: TextStyle(color: colors.label),
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  CupertinoIcons.search,
                  size: 16,
                  color: CupertinoColors.systemGrey,
                ),
              ),
              suffix: _query.isEmpty
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(24, 24),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        child: const Icon(
                          CupertinoIcons.clear_circled_solid,
                          size: 16,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ),
              onChanged: (value) => setState(() => _query = value),
              decoration: BoxDecoration(
                color: colors.searchField,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: colors.separator),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChipButton(
                  label: switch (_filter) {
                    'good' => 'Товары',
                    'service' => 'Услуги',
                    'popular' => 'Популярное',
                    _ => 'Все позиции',
                  },
                  icon: CupertinoIcons.line_horizontal_3_decrease,
                  onPressed: _pickFilter,
                ),
                if (_filter != 'all')
                  ChipButton(
                    label: 'Сбросить',
                    icon: CupertinoIcons.xmark,
                    onPressed: () => setState(() => _filter = 'all'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SectionLabel(
              'Позиций ${items.length}'
              '${averageMargin == null ? '' : ' · средняя маржа ${averageMargin.round()}%'}',
            ),
            if (items.isEmpty)
              EmptyState(
                title: _query.isEmpty ? 'Каталог пуст' : 'Ничего не найдено',
                message: _query.isEmpty
                    ? 'Добавьте первую позицию — цену, себестоимость и параметры.'
                    : 'Попробуйте другое название или сбросьте фильтр.',
                art: Icon(
                  CupertinoIcons.cube_box,
                  size: 36,
                  color: colors.tertiaryLabel,
                ),
                actions: [
                  if (_query.isEmpty)
                    PrimaryButton(
                      label: 'Создать первую позицию',
                      icon: CupertinoIcons.plus,
                      onPressed: () => _edit(null),
                    ),
                ],
              )
            else
              ...items.map((item) => _card(store, item)),
          ],
        ),
      ),
    );
  }
}

/// Шит позиции каталога: цена, единица, параметры и отметка «популярное».
///
/// Себестоимость позиции-товара ведёт редактор состава на складе: здесь она
/// только показывается, иначе два экрана спорили бы, кто главный.
class _CatalogItemSheet extends StatefulWidget {
  const _CatalogItemSheet({this.item});

  final InventoryItem? item;

  @override
  State<_CatalogItemSheet> createState() => _CatalogItemSheetState();
}

class _CatalogItemSheetState extends State<_CatalogItemSheet> {
  late final TextEditingController _name;
  late final TextEditingController _sell;
  late final TextEditingController _category;
  late String _kind;
  late String _unit;
  late bool _popular;
  bool _saving = false;

  final _keyController = TextEditingController();
  final _valueController = TextEditingController();

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _sell = TextEditingController(
      text: ((item?.sellPriceCents ?? 0) / 100)
          .toStringAsFixed((item?.sellPriceCents ?? 0) % 100 == 0 ? 0 : 2),
    );
    _category = TextEditingController(text: item?.category ?? '');
    _kind = item?.kind ?? 'good';
    _unit = item?.unit ?? 'шт';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = widget.item?.id;
    _popular = id == null
        ? false
        : context.read<MastersStore>().isItemPopular(id);
  }

  @override
  void dispose() {
    _name.dispose();
    _sell.dispose();
    _category.dispose();
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  int get _sellCents =>
      ((double.tryParse(_sell.text.trim().replaceAll(',', '.')) ?? 0) * 100)
          .round();

  Future<void> _pickUnit() async {
    final extra = kUnitOptions.contains(_unit) ? null : _unit;
    final unit = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Единица измерения'),
        actions: [
          for (final option in [...kUnitOptions, ?extra])
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(option),
              child: Text(
                option,
                style: TextStyle(
                  fontWeight: option == _unit
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (unit != null) setState(() => _unit = unit);
  }

  Future<void> _addAttribute() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    final value = _valueController.text.trim();
    final store = context.read<MastersStore>();
    try {
      await store.setAttributeValue(
        entityType: 'item',
        entityId: widget.item?.id ?? '',
        key: key,
        raw: value,
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      CupertinoAlertDialog(
        title: Text('Ошибка'),
        content: Text(e.message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }
    if (!mounted) return;
    _keyController.clear();
    _valueController.clear();
    setState(() {});
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    final store = context.read<MastersStore>();
    setState(() => _saving = true);
    try {
      final base = widget.item;
      String savedId;
      if (base == null) {
        final created = await store.createInventoryItem(
          name: name,
          kind: _kind,
          unit: _unit,
          sellPriceCents: _sellCents,
          category: _category.text.trim(),
          trackStock: _kind != 'service',
        );
        savedId = created.id;
      } else {
        await store.updateInventoryItem(
          base.copyWith(
            name: name,
            kind: _kind,
            unit: _unit,
            sellPriceCents: _sellCents,
            category: _category.text.trim(),
            trackStock: _kind == 'service' ? false : base.trackStock,
          ),
        );
        savedId = base.id;
      }
      if (store.isItemPopular(savedId) != _popular) {
        await store.setItemPopular(savedId, _popular);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<MastersStore>();
    final item = widget.item;
    final List<EntityAttribute> attributes = item == null
        ? const []
        : store.attributesOf('item', item.id);
    final List<InventoryCompositionLine> composition = item == null
        ? const []
        : store.itemComposition(item.id);
    final canSave = _name.text.trim().isNotEmpty && !_saving;

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit ? 'Позиция каталога' : 'Новая позиция',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: canSave ? _save : null,
                    child: Text(
                      'Сохранить',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: canSave ? colors.accent : colors.tertiaryLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  AppCard(
                    child: Column(
                      children: [
                        CupertinoTextField(
                          controller: _name,
                          placeholder: 'Наименование',
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        CupertinoSlidingSegmentedControl<String>(
                          groupValue: _kind,
                          children: const {
                            'good': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Товар'),
                            ),
                            'service': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Услуга'),
                            ),
                          },
                          onValueChanged: (value) {
                            if (value == null) return;
                            setState(() => _kind = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              'Единица',
                              style: TextStyle(color: colors.secondaryLabel),
                            ),
                            const Spacer(),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _pickUnit,
                              child: Text(
                                _unit,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        CupertinoTextField(
                          controller: _sell,
                          placeholder: 'Цена продажи',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          prefix: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              moneySymbol,
                              style: TextStyle(color: colors.secondaryLabel),
                            ),
                          ),
                          suffix: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              '/$_unit',
                              style: TextStyle(color: colors.secondaryLabel),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        CupertinoTextField(
                          controller: _category,
                          placeholder: 'Категория',
                        ),
                        const SizedBox(height: 4),
                        KeyValueRow(
                          'Себестоимость',
                          _kind == 'service'
                              ? '—'
                              : money(item?.costCents ?? 0),
                          valueColor: colors.secondaryLabel,
                          dense: true,
                        ),
                        KeyValueRow(
                          'Маржа',
                          _sellCents <= 0
                              ? '—'
                              : '${((_sellCents - (item?.costCents ?? 0)) * 100 / _sellCents).round()}%',
                          valueColor:
                              _sellCents > (item?.costCents ?? 0)
                                  ? colors.green
                                  : colors.orange,
                          dense: true,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Популярное',
                                style: TextStyle(color: colors.secondaryLabel),
                              ),
                            ),
                            CupertinoSwitch(
                              value: _popular,
                              onChanged: _isEdit
                                  ? (value) => setState(() => _popular = value)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 16),
                    SectionLabel('Параметры позиции'),
                    AppCard(
                      child: Column(
                        children: [
                          for (final attribute in attributes)
                            ListRow(
                              dense: true,
                              icon: CupertinoIcons.tag,
                              title: attribute.key,
                              subtitle: attribute.valueText ??
                                  attribute.valueNum?.toString(),
                              trailing: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () => context
                                    .read<MastersStore>()
                                    .deleteAttribute(attribute.id),
                                child: Icon(
                                  CupertinoIcons.xmark,
                                  size: 14,
                                  color: colors.tertiaryLabel,
                                  semanticLabel: 'Удалить',
                                ),
                              ),
                            ),
                          if (attributes.isEmpty)
                            Text(
                              'Например: вес, вкус, размер, гарантия.',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.secondaryLabel,
                              ),
                            ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoTextField(
                                  controller: _keyController,
                                  placeholder: 'Параметр',
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: CupertinoTextField(
                                  controller: _valueController,
                                  placeholder: 'Значение',
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 6),
                              MiniAction(
                                label: 'Добавить',
                                icon: CupertinoIcons.plus,
                                onPressed: _addAttribute,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_kind == 'good') ...[
                      const SizedBox(height: 16),
                      SectionLabel('Состав · ${composition.length}'),
                      AppCard(
                        child: Column(
                          children: [
                            KeyValueRow(
                              'Себестоимость состава',
                              money(store.compositionCostCents(item!.id)),
                              dense: true,
                            ),
                            const SizedBox(height: 8),
                            SecondaryButton(
                              label: 'Редактировать состав',
                              icon: CupertinoIcons.cube_box,
                              dense: true,
                              onPressed: () {
                                Navigator.of(context).push(
                                  CupertinoPageRoute(
                                    builder: (_) =>
                                        InventoryCompositionScreen(
                                          itemId: item.id,
                                        ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      'Параметры и состав появятся после сохранения позиции.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.secondaryLabel,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: 'Сохранить',
                    icon: CupertinoIcons.checkmark,
                    enabled: canSave,
                    onPressed: canSave ? _save : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Шит выбора позиции каталога для заказа: поиск + фильтр Товары/Услуги.
///
/// Возвращает выбранную позицию либо пару «позиция + количество», когда мастер
/// поменял количество прямо в шите.
class CatalogPicked {
  const CatalogPicked(this.item, this.quantity);

  final InventoryItem item;
  final double quantity;
}

Future<CatalogPicked?> showCatalogPicker(
  BuildContext context, {
  String title = 'Из каталога',
}) async {
  return showCupertinoModalPopup<CatalogPicked>(
    context: context,
    builder: (_) => _CatalogPickerSheet(title: title),
  );
}

class _CatalogPickerSheet extends StatefulWidget {
  const _CatalogPickerSheet({required this.title});

  final String title;

  @override
  State<_CatalogPickerSheet> createState() => _CatalogPickerSheetState();
}

class _CatalogPickerSheetState extends State<_CatalogPickerSheet> {
  final _searchController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  String _query = '';
  String _filter = 'all';
  InventoryItem? _selected;

  @override
  void dispose() {
    _searchController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  double get _qty {
    final value =
        double.tryParse(_qtyController.text.trim().replaceAll(',', '.')) ?? 0;
    return value <= 0 ? 1 : value;
  }

  void _pick(InventoryItem item) => setState(() => _selected = item);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<MastersStore>();
    var items = store.inventoryItems.where((i) => !i.archived).toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items
          .where(
            (i) =>
                i.name.toLowerCase().contains(q) ||
                i.category.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_filter != 'all') items = items.where((i) => i.kind == _filter).toList();
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.of(context).pop(
                            CatalogPicked(_selected!, _qty),
                          ),
                    child: Text(
                      'Добавить',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _selected == null
                            ? colors.tertiaryLabel
                            : colors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  CupertinoTextField(
                    controller: _searchController,
                    placeholder: 'Поиск по названию',
                    style: TextStyle(color: colors.label),
                    onChanged: (value) => setState(() => _query = value),
                    decoration: BoxDecoration(
                      color: colors.searchField,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: colors.separator),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ChipButton(
                        label: switch (_filter) {
                          'good' => 'Товары',
                          'service' => 'Услуги',
                          _ => 'Товары и услуги',
                        },
                        icon: CupertinoIcons.line_horizontal_3_decrease,
                        onPressed: () async {
                          final value =
                              await showCupertinoModalPopup<String>(
                                context: context,
                                builder: (sheetContext) => CupertinoActionSheet(
                                  title: const Text('Что показывать'),
                                  actions: [
                                    for (final option in const [
                                      ('all', 'Товары и услуги'),
                                      ('good', 'Только товары'),
                                      ('service', 'Только услуги'),
                                    ])
                                      CupertinoActionSheetAction(
                                        isDefaultAction: option.$1 == _filter,
                                        onPressed: () =>
                                            Navigator.of(sheetContext).pop(
                                              option.$1,
                                            ),
                                        child: Text(option.$2),
                                      ),
                                  ],
                                  cancelButton: CupertinoActionSheetAction(
                                    onPressed: () =>
                                        Navigator.of(sheetContext).pop(),
                                    child: const Text('Отмена'),
                                  ),
                                ),
                              );
                          if (value != null && mounted) {
                            setState(() => _filter = value);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Кол-во',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.secondaryLabel,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 72,
                        child: CupertinoTextField(
                          controller: _qtyController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? EmptyState(
                      title: 'Нечего выбирать',
                      message:
                          'Каталог пуст или по запросу ничего нет — создайте позицию в разделе «Каталог».',
                      art: Icon(
                        CupertinoIcons.cube_box,
                        size: 32,
                        color: colors.tertiaryLabel,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final selected = _selected?.id == item.id;
                        return AppCard(
                          padding: EdgeInsets.zero,
                          margin: const EdgeInsets.only(bottom: 8),
                          onTap: () => _pick(item),
                          color: selected
                              ? colors.tint(colors.accent, 0.10)
                              : colors.card,
                          child: ListRow(
                            title: item.name,
                            subtitle:
                                '${money(item.sellPriceCents)}/${item.unit}'
                                ' · ${item.kind == 'service' ? 'услуга' : 'остаток ${formatQty(item.stockQty)}'}',
                            icon: item.kind == 'service'
                                ? CupertinoIcons.wrench
                                : CupertinoIcons.cube_box,
                            trailing: selected
                                ? Icon(
                                    CupertinoIcons.checkmark_alt,
                                    size: 16,
                                    color: colors.accent,
                                  )
                                : null,
                            onTap: () => _pick(item),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
