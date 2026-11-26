import 'package:flutter/cupertino.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/money_format.dart';
import '../../core/units.dart';

/// Строка заказа в том виде, в каком её показывает форма.
///
/// Форма работает с этим представлением, а не с `MaterialItem` напрямую: в
/// новом заказе заказа в базе ещё нет, и строки живут в памяти до сохранения.
class JobLineView {
  const JobLineView({
    required this.name,
    required this.qty,
    required this.unit,
    required this.priceCents,
    required this.costAtOrderCents,
    this.discountCents = 0,
    this.kind = 'work',
    this.itemId,
  });

  final String name;
  final double qty;
  final String unit;
  final int priceCents;

  /// Себестоимость за единицу на момент оформления — снимок, а не ссылка на
  /// каталог: правка цены товара не должна переписывать прошлые заказы.
  final int costAtOrderCents;
  final int discountCents;

  /// `work` — работа/услуга, `good` — товар.
  final String kind;
  final String? itemId;

  int get totalCents => (priceCents * qty).round();
  int get costTotalCents => (costAtOrderCents * qty).round();
  int get netCents => totalCents - discountCents;
  int get marginCents => netCents - costTotalCents;
}

/// Пара ключ/значение, введённая в форме до появления заказа.
class JobAttrDraft {
  const JobAttrDraft(this.key, this.value);
  final String key;
  final String value;
}

/// Карточка «Итог»: цена, себестоимость и маржа.
///
/// Пока строк нет, итог берут из ручного ввода и честно это помечают — иначе
/// цифра выглядит посчитанной, хотя её никто не считал.
class JobTotalsCard extends StatelessWidget {
  const JobTotalsCard({super.key, required this.totals, required this.manual});

  final ({int priceCents, int costCents, bool fromLines}) totals;
  final Widget manual;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final margin = totals.priceCents - totals.costCents;
    final marginPercent = totals.priceCents > 0
        ? (margin * 100 / totals.priceCents).round()
        : null;

    return AppCard(
      child: Column(
        children: [
          if (!totals.fromLines) ...[
            manual,
            const SizedBox(height: 10),
            Text(
              'Суммы введены вручную — строк заказа нет.',
              style: TextStyle(fontSize: 12, color: colors.tertiaryLabel),
            ),
          ] else ...[
            KeyValueRow('Цена', money(totals.priceCents)),
            KeyValueRow('Себестоимость', money(totals.costCents)),
            KeyValueRow(
              'Маржа',
              '${money(margin)}'
              '${marginPercent == null ? '' : ' ($marginPercent%)'}',
              valueColor: margin > 0 ? colors.green : colors.orange,
              emphasis: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Ручной ввод цены и расхода — только для заказов без строк.
class JobManualSumsRow extends StatelessWidget {
  const JobManualSumsRow({
    super.key,
    required this.priceController,
    required this.costController,
    required this.onChanged,
  });

  final TextEditingController priceController;
  final TextEditingController costController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: CupertinoTextField(
            controller: priceController,
            placeholder: 'Цена',
            style: TextStyle(color: colors.label),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '+',
                style: TextStyle(
                  color: colors.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            suffix: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                moneySymbol,
                style: TextStyle(color: colors.secondaryLabel),
              ),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CupertinoTextField(
            controller: costController,
            placeholder: 'Расход',
            style: TextStyle(color: colors.label),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '-',
                style: TextStyle(
                  color: colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            suffix: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                moneySymbol,
                style: TextStyle(color: colors.secondaryLabel),
              ),
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

/// Шит строки заказа: свободная позиция либо правка существующей.
class JobLineEditorSheet extends StatefulWidget {
  const JobLineEditorSheet({super.key, this.initial});

  final JobLineView? initial;

  @override
  State<JobLineEditorSheet> createState() => _JobLineEditorSheetState();
}

class _JobLineEditorSheetState extends State<JobLineEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _qty;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _discount;
  late String _kind;
  late String _unit;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _qty = TextEditingController(text: initial == null ? '1' : formatQty(initial.qty));
    _price = TextEditingController(
      text: ((initial?.priceCents ?? 0) / 100)
          .toStringAsFixed((initial?.priceCents ?? 0) % 100 == 0 ? 0 : 2),
    );
    _cost = TextEditingController(
      text: ((initial?.costAtOrderCents ?? 0) / 100)
          .toStringAsFixed((initial?.costAtOrderCents ?? 0) % 100 == 0 ? 0 : 2),
    );
    _discount = TextEditingController(
      text: ((initial?.discountCents ?? 0) / 100)
          .toStringAsFixed((initial?.discountCents ?? 0) % 100 == 0 ? 0 : 2),
    );
    _kind = initial?.kind ?? 'work';
    _unit = initial?.unit ?? 'шт';
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    _cost.dispose();
    _discount.dispose();
    super.dispose();
  }

  double _d(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

  int _cents(TextEditingController controller) => (_d(controller) * 100).round();

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

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final qty = _d(_qty);
    Navigator.of(context).pop(
      JobLineView(
        name: name,
        qty: qty <= 0 ? 1 : qty,
        unit: _unit,
        priceCents: _cents(_price),
        costAtOrderCents: _cents(_cost),
        discountCents: _cents(_discount),
        kind: _kind,
        itemId: widget.initial?.itemId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final qty = _d(_qty) <= 0 ? 1.0 : _d(_qty);
    final priceCents = _cents(_price);
    final costCents = _cents(_cost);
    final discountCents = _cents(_discount);
    final margin =
        (priceCents * qty).round() - discountCents - (costCents * qty).round();
    final canSave = _name.text.trim().isNotEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
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
                      _isEdit ? 'Строка заказа' : 'Свободная строка',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: canSave ? _submit : null,
                    child: Text(
                      'Добавить',
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
                          placeholder: 'Название',
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        CupertinoSlidingSegmentedControl<String>(
                          groupValue: _kind,
                          children: const {
                            'work': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Работа'),
                            ),
                            'good': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Товар'),
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
                            Expanded(
                              child: CupertinoTextField(
                                controller: _qty,
                                placeholder: 'Кол-во',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _pickUnit,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _unit,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Icon(
                                    CupertinoIcons.chevron_down,
                                    size: 12,
                                    color: colors.tertiaryLabel,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        CupertinoTextField(
                          controller: _price,
                          placeholder: 'Цена за единицу',
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
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        CupertinoTextField(
                          controller: _cost,
                          placeholder: 'Себестоимость за единицу',
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
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        CupertinoTextField(
                          controller: _discount,
                          placeholder: 'Скидка на строку',
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
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: [
                        KeyValueRow(
                          'Сумма строки',
                          money((priceCents * qty).round() - discountCents),
                          dense: true,
                        ),
                        KeyValueRow(
                          'Себестоимость',
                          money((costCents * qty).round()),
                          dense: true,
                        ),
                        KeyValueRow(
                          'Маржа',
                          money(margin),
                          valueColor: margin > 0 ? colors.green : colors.orange,
                          emphasis: true,
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: _isEdit ? 'Сохранить строку' : 'Добавить строку',
                    icon: CupertinoIcons.checkmark,
                    enabled: canSave,
                    onPressed: canSave ? _submit : null,
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

/// Шит параметра: ключ/значение с подсказками из каталога.
class JobAttrSheet extends StatefulWidget {
  const JobAttrSheet({super.key, this.hints = const []});

  final List<String> hints;

  @override
  State<JobAttrSheet> createState() => _JobAttrSheetState();
}

class _JobAttrSheetState extends State<JobAttrSheet> {
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _submit() {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    Navigator.of(context).pop(JobAttrDraft(key, _valueController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canSave = _keyController.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Новый параметр',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: canSave ? _submit : null,
                    child: Text(
                      'Добавить',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: canSave ? colors.accent : colors.tertiaryLabel,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AppCard(
                child: Column(
                  children: [
                    CupertinoTextField(
                      controller: _keyController,
                      placeholder: 'Параметр (вес, вкус, адрес…)',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: _valueController,
                      placeholder: 'Значение',
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              if (widget.hints.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SectionLabel('Раньше указывали'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final hint in widget.hints)
                      ChipButton(
                        label: hint,
                        icon: CupertinoIcons.plus,
                        onPressed: () {
                          _keyController.text = hint;
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
