import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/calculator_core.dart';
import '../core/money_format.dart';
import '../core/units.dart';
import '../data/draft_storage.dart';
import '../data/models.dart';
import '../state/studio_store.dart';
import '../ui/atelier_widgets.dart';

class RecipesCalculatorScreen extends StatefulWidget {
  const RecipesCalculatorScreen({super.key});

  @override
  State<RecipesCalculatorScreen> createState() =>
      _RecipesCalculatorScreenState();
}

class _RecipesCalculatorScreenState extends State<RecipesCalculatorScreen> {
  int _tab = 0; // 0 = Рецепты, 1 = Калькулятор
  String _search = '';

  // Calculator state
  String? _calcRecipeId;
  int _materialsCents = 150000;
  double _laborHours = 2.0;
  int _laborRateCents = 60000;
  int _packagingCents = 18000;
  double _overheadPct = 10;
  PricingMode _pricingMode = PricingMode.markup;
  double _marginPct = 50;
  double _targetMarginPct = 35;
  int _fixedPriceCents = 400000;
  double _feePct = 0;
  double _defectPct = 0;

  void _loadRecipeIntoCalculator(Recipe r) {
    final materials = r.ingredients.fold<int>(0, (s, l) {
      final eff = effectiveQuantity(l.qty, l.lossPercent) ?? l.qty;
      return s +
          resourceLineTotalCents(
            qty: eff,
            qtyUnit: l.unit,
            priceCents: l.priceCents,
            priceUnit: l.priceUnit,
          );
    });
    setState(() {
      _calcRecipeId = r.id;
      _materialsCents = materials > 0 ? materials : r.costCents;
      _laborHours = r.laborHours;
      _laborRateCents = r.laborRateCents;
      _packagingCents = r.packagingCents;
      _overheadPct = r.overheadPercent;
      _pricingMode = PricingMode.markup;
      _marginPct = r.marginPercent;
      _tab = 1;
    });
  }

  Future<void> _openRecipeEditor(BuildContext context, {Recipe? existing}) async {
    final store = context.read<StudioStore>();
    Map<String, dynamic>? savedDraft;
    if (existing == null) {
      savedDraft = await store.drafts.loadJson(DraftStorage.recipeDraftKey);
    }

    final titleCtrl = TextEditingController(
        text: existing?.title ?? (savedDraft?['title'] as String? ?? ''));
    final categoryCtrl = TextEditingController(
        text: existing?.category ??
            (savedDraft?['category'] as String? ?? 'Торты'));
    final yieldCtrl = TextEditingController(
      text: (existing?.yieldGrams ??
              ((savedDraft?['yieldGrams'] as num?)?.toDouble() ?? 1500))
          .round()
          .toString(),
    );
    final grossCtrl = TextEditingController(
      text: (existing?.grossGrams ??
              ((savedDraft?['grossGrams'] as num?)?.toDouble() ?? 1650))
          .round()
          .toString(),
    );
    final portionsCtrl = TextEditingController(
      text: (existing?.yieldPortions ?? 8).toString(),
    );
    final allergensCtrl = TextEditingController(
      text: existing?.allergens.join(', ') ?? '',
    );
    final stepsCtrl = TextEditingController(
      text: existing?.steps.join('\n') ?? '',
    );
    String? photoPath = existing?.photoPath;

    List<RecipeIngredientLine> ingredients = existing != null
        ? List<RecipeIngredientLine>.from(existing.ingredients)
        : (savedDraft?['ingredients'] is List
            ? (savedDraft!['ingredients'] as List)
                .whereType<Map<String, dynamic>>()
                .map(RecipeIngredientLine.fromJson)
                .toList()
            : <RecipeIngredientLine>[]);

    void persistDraft() {
      if (existing != null) return;
      store.drafts.saveJson(DraftStorage.recipeDraftKey, {
        'title': titleCtrl.text,
        'category': categoryCtrl.text,
        'yieldGrams': double.tryParse(yieldCtrl.text) ?? 1500,
        'grossGrams': double.tryParse(grossCtrl.text) ?? 1650,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
      });
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final edibleGrams = ingredients
              .where((l) => !l.isPackaging)
              .fold<double>(
                  0, (s, l) => s + (convertQty(l.qty, l.unit, 'г') ?? 0));
          final yieldG = double.tryParse(yieldCtrl.text) ?? 0;
          final grossG = double.tryParse(grossCtrl.text) ?? 0;
          final bakeLossPct =
              grossG > 0 ? ((grossG - yieldG) / grossG * 100).clamp(0, 99) : 0.0;

          final materialsCents = ingredients.fold<int>(0, (s, l) {
            final eff = effectiveQuantity(l.qty, l.lossPercent) ?? l.qty;
            return s +
                resourceLineTotalCents(
                  qty: eff,
                  qtyUnit: l.unit,
                  priceCents: l.priceCents,
                  priceUnit: l.priceUnit,
                );
          });

          final calcTotals = computeCalculatorTotals(
            CalculatorInput(
              materialsCents: materialsCents,
              laborHours: existing?.laborHours ?? 1.5,
              laborRateCents: existing?.laborRateCents ?? 60000,
              packagingCents: existing?.packagingCents ?? 0,
              overheadPercent: existing?.overheadPercent ?? 10,
              marginPercent: existing?.marginPercent ?? 45,
            ),
          );

          final resolvedPhoto = store.mediaStore.resolvePhotoFile(photoPath);

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          existing == null
                              ? 'Новый рецепт'
                              : 'Техкарта: ${existing.title}',
                          style: Theme.of(ctx)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (existing != null)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _loadRecipeIntoCalculator(existing);
                          },
                          icon: const Icon(Icons.calculate_outlined, size: 18),
                          label: const Text('В калькулятор'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Photo picker card
                  Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: store.palette.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: store.palette.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: resolvedPhoto != null
                            ? Image.file(resolvedPhoto, fit: BoxFit.cover)
                            : Icon(Icons.cake_outlined,
                                color: store.palette.primary, size: 30),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final picker = ImagePicker();
                                final xFile = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  maxWidth: 1600,
                                  imageQuality: 85,
                                );
                                if (xFile != null) {
                                  final storedName = await store.mediaStore
                                      .savePhotoFromFile(xFile.path);
                                  setModalState(() => photoPath = storedName);
                                }
                              },
                              icon: const Icon(Icons.photo_library_outlined, size: 16),
                              label: const Text('Фото из галереи'),
                            ),
                            if (photoPath != null)
                              TextButton(
                                onPressed: () => setModalState(() => photoPath = null),
                                child: const Text('Убрать фото'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Название рецепта *'),
                    onChanged: (_) => persistDraft(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: categoryCtrl,
                          decoration: const InputDecoration(labelText: 'Категория'),
                          onChanged: (_) => persistDraft(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: portionsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Порций'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: grossCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Брутто, г'),
                          onChanged: (_) {
                            setModalState(() {});
                            persistDraft();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: yieldCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Выход, г'),
                          onChanged: (_) {
                            setModalState(() {});
                            persistDraft();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Съедобная масса ингредиентов: ${edibleGrams.round()} г (упаковка не учитывается) · упёк ${bakeLossPct.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 12, color: store.palette.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Ингредиенты и подрецепты',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final line = await _pickIngredientDialog(
                            ctx,
                            store,
                            existingRecipeId: existing?.id ?? '',
                          );
                          if (line != null) {
                            setModalState(() => ingredients.add(line));
                            persistDraft();
                          }
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Добавить'),
                      ),
                    ],
                  ),
                  for (var idx = 0; idx < ingredients.length; idx++) ...[
                    AtelierCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ingredients[idx].name +
                                      (ingredients[idx].isPackaging
                                          ? ' (упаковка)'
                                          : ''),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${formatQty(ingredients[idx].qty, ingredients[idx].unit)}'
                                  '${ingredients[idx].lossPercent > 0 ? ' · потери ${ingredients[idx].lossPercent}%' : ''}'
                                  ' · ${formatMoneyCents(resourceLineTotalCents(qty: effectiveQuantity(ingredients[idx].qty, ingredients[idx].lossPercent) ?? ingredients[idx].qty, qtyUnit: ingredients[idx].unit, priceCents: ingredients[idx].priceCents, priceUnit: ingredients[idx].priceUnit), currencySymbol: store.profile.currencySymbol)}',
                                  style: TextStyle(
                                      fontSize: 12, color: store.palette.textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setModalState(() => ingredients.removeAt(idx));
                              persistDraft();
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: allergensCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Аллергены (через запятую)',
                      hintText: 'Глютен, Яйца, Лактоза, Орехи',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: stepsCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Шаги приготовления (каждый с новой строки)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  AtelierCard(
                    color: store.palette.surfaceAlt,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Сырьё + упаковка:'),
                            Text(
                              formatMoneyCents(materialsCents,
                                  currencySymbol: store.profile.currencySymbol),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Себест. / Рек. цена:'),
                            Text(
                              '${formatMoneyCents(calcTotals.costCents, currencySymbol: store.profile.currencySymbol)} / ${formatMoneyCents(calcTotals.priceCents, currencySymbol: store.profile.currencySymbol)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: store.palette.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty) return;
                      final rec = Recipe(
                        id: existing?.id ?? newId('rec'),
                        title: titleCtrl.text.trim(),
                        category: categoryCtrl.text.trim().isEmpty
                            ? 'Торты'
                            : categoryCtrl.text.trim(),
                        yieldGrams: (double.tryParse(yieldCtrl.text) ?? 1500)
                            .clamp(1, 100000),
                        grossGrams: double.tryParse(grossCtrl.text),
                        yieldPortions:
                            (int.tryParse(portionsCtrl.text) ?? 1).clamp(1, 500),
                        photoPath: photoPath,
                        ingredients: ingredients,
                        packVariants: existing?.packVariants ?? const [],
                        steps: stepsCtrl.text
                            .split('\n')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList(),
                        allergens: allergensCtrl.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList(),
                        laborHours: existing?.laborHours ?? 1.5,
                        laborRateCents: existing?.laborRateCents ?? 60000,
                        packagingCents: existing?.packagingCents ?? 0,
                        overheadPercent: existing?.overheadPercent ?? 10,
                        marginPercent: existing?.marginPercent ?? 45,
                        costCents: calcTotals.costCents,
                        recommendedPriceCents: calcTotals.priceCents,
                        favorite: existing?.favorite ?? false,
                        updatedAt: DateTime.now().toIso8601String(),
                      );
                      await store.saveRecipe(rec);
                      if (existing == null) {
                        await store.drafts.clearKey(DraftStorage.recipeDraftKey);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Сохранить техкарту'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<RecipeIngredientLine?> _pickIngredientDialog(
    BuildContext context,
    StudioStore store, {
    required String existingRecipeId,
  }) async {
    var mode = 0; // 0 = Из кладовой, 1 = Подрецепт, 2 = Вручную
    String? selectedInvId =
        store.inventoryItems.isNotEmpty ? store.inventoryItems.first.id : null;
    String? selectedSubId;
    final nameCtrl = TextEditingController(
      text: store.inventoryItems.isNotEmpty ? store.inventoryItems.first.name : '',
    );
    final qtyCtrl = TextEditingController(text: '200');
    final lossCtrl = TextEditingController(text: '0');
    var unit = store.inventoryItems.isNotEmpty
        ? store.inventoryItems.first.unit
        : 'г';
    var priceCents = store.inventoryItems.isNotEmpty
        ? store.inventoryItems.first.avgCostCents
        : 10000;
    var priceUnit = defaultPriceUnit(unit);
    final priceCtrl = TextEditingController(text: centsToRubInput(priceCents));
    var isPackaging = store.inventoryItems.isNotEmpty &&
        store.inventoryItems.first.kind == InventoryKind.packaging;

    return showDialog<RecipeIngredientLine>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Добавить ингредиент / упаковку'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Кладовая')),
                    ButtonSegment(value: 1, label: Text('Подрецепт')),
                    ButtonSegment(value: 2, label: Text('Вручную')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => setDlg(() => mode = s.first),
                ),
                const SizedBox(height: 10),
                if (mode == 0 && store.inventoryItems.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: selectedInvId,
                    decoration: const InputDecoration(labelText: 'Позиция кладовой'),
                    items: store.inventoryItems
                        .map((i) => DropdownMenuItem(
                              value: i.id,
                              child: Text('${i.name} (${i.unit})'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      final found = store.inventoryItems.firstWhere((e) => e.id == v);
                      setDlg(() {
                        selectedInvId = found.id;
                        selectedSubId = null;
                        nameCtrl.text = found.name;
                        unit = found.unit;
                        priceCents = found.avgCostCents;
                        priceUnit = defaultPriceUnit(found.unit);
                        priceCtrl.text = centsToRubInput(priceCents);
                        isPackaging = found.kind == InventoryKind.packaging;
                      });
                    },
                  )
                else if (mode == 1)
                  DropdownButtonFormField<String>(
                    initialValue: selectedSubId,
                    decoration: const InputDecoration(labelText: 'Полуфабрикат (рецепт)'),
                    items: store.recipes
                        .where((r) => r.id != existingRecipeId)
                        .map((r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(r.title),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      if (wouldCreateSubRecipeCycle(
                        parentRecipeId: existingRecipeId,
                        candidateSubRecipeId: v,
                        allRecipes: store.recipes,
                      )) {
                        showAtelierMessage(
                          ctx,
                          'Циклическая зависимость запрещена!',
                          isError: true,
                        );
                        return;
                      }
                      final sub = store.recipes.firstWhere((e) => e.id == v);
                      setDlg(() {
                        selectedSubId = sub.id;
                        selectedInvId = null;
                        nameCtrl.text = sub.title;
                        unit = 'г';
                        priceUnit = 'за кг';
                        final perKg = sub.yieldGrams > 0
                            ? ((sub.costCents / sub.yieldGrams) * 1000).round()
                            : sub.costCents;
                        priceCtrl.text = centsToRubInput(perKg);
                        isPackaging = false;
                      });
                    },
                  )
                else
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Количество'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: DropdownButtonFormField<String>(
                        initialValue: kQtyUnits.contains(unit) ? unit : 'г',
                        decoration: const InputDecoration(labelText: 'Ед.'),
                        items: kQtyUnits
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDlg(() {
                              unit = v;
                              if (!priceUnitsFor(unit).contains(priceUnit)) {
                                priceUnit = defaultPriceUnit(unit);
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Цена, ₽'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: kPriceUnits.contains(priceUnit)
                            ? priceUnit
                            : 'за кг',
                        decoration: const InputDecoration(labelText: 'За ед.'),
                        items: kPriceUnits
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDlg(() => priceUnit = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: lossCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Потери при обработке, %'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPackaging,
                  onChanged: (v) => setDlg(() => isPackaging = v == true),
                  title: const Text('Это упаковка / декор (не входит в вес)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(
                  ctx,
                  RecipeIngredientLine(
                    itemId: mode == 0 ? selectedInvId : null,
                    subRecipeId: mode == 1 ? selectedSubId : null,
                    name: nameCtrl.text.trim(),
                    qty: double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0,
                    unit: unit,
                    lossPercent:
                        double.tryParse(lossCtrl.text.replaceAll(',', '.')) ?? 0,
                    priceCents: parseRubToCents(priceCtrl.text),
                    priceUnit: priceUnit,
                    isPackaging: isPackaging,
                  ),
                );
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudioStore>();
    final p = store.palette;
    final curr = store.profile.currencySymbol;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: [
                        ButtonSegment(
                          value: 0,
                          label: Text('Рецепты (${store.recipes.length})'),
                        ),
                        const ButtonSegment(
                          value: 1,
                          label: Text('Калькулятор'),
                        ),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                  ),
                  if (_tab == 0) ...[
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () => _openRecipeEditor(context),
                      tooltip: 'Новый рецепт',
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ],
              ),
              if (_tab == 0) ...[
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Поиск по названию, категории или аллергенам...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _tab == 0
              ? _buildRecipesList(context, store, p, curr)
              : _buildCalculator(context, store, p, curr),
        ),
      ],
    );
  }

  Widget _buildRecipesList(
    BuildContext context,
    StudioStore store,
    dynamic p,
    String curr,
  ) {
    final q = _search.trim().toLowerCase();
    final filtered = store.recipes.where((r) {
      if (q.isEmpty) return true;
      return '${r.title} ${r.category} ${r.allergens.join(' ')}'
          .toLowerCase()
          .contains(q);
    }).toList();

    if (filtered.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyAtelierState(
            icon: Icons.menu_book_outlined,
            title: 'Техкарты не найдены',
            description:
                'Создавайте рецепты с привязкой к кладовой, подрецептами, фото и калькуляцией маржи.',
            actionLabel: 'Создать рецепт',
            onAction: () => _openRecipeEditor(context),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final r = filtered[i];
        final photo = store.mediaStore.resolvePhotoFile(r.photoPath);
        return AtelierCard(
          onTap: () => _openRecipeEditor(ctx, existing: r),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: p.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: photo != null
                    ? Image.file(photo, fit: BoxFit.cover)
                    : Icon(Icons.cake_outlined, color: p.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.category} · выход ${r.yieldGrams.round()} г · ${r.yieldPortions} порц.',
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusBadge(
                          label:
                              'Себест. ${formatMoneyCents(r.costCents, currencySymbol: curr)}',
                          color: p.secondary,
                        ),
                        StatusBadge(
                          label:
                              'Цена ${formatMoneyCents(r.recommendedPriceCents, currencySymbol: curr)}',
                          color: p.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Открыть в калькуляторе',
                onPressed: () => _loadRecipeIntoCalculator(r),
                icon: const Icon(Icons.calculate_outlined),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCalculator(
    BuildContext context,
    StudioStore store,
    dynamic p,
    String curr,
  ) {
    final totals = computeCalculatorTotals(
      CalculatorInput(
        materialsCents: _materialsCents,
        laborHours: _laborHours,
        laborRateCents: _laborRateCents,
        packagingCents: _packagingCents,
        overheadPercent: _overheadPct,
        pricingMode: _pricingMode,
        marginPercent: _marginPct,
        targetMarginPercent: _targetMarginPct,
        fixedPriceCents: _fixedPriceCents,
        commissionPercent: _feePct,
        finishedDefectPercent: _defectPct,
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        if (store.recipes.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _calcRecipeId,
            decoration: const InputDecoration(labelText: 'Загрузить данные из рецепта'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Свободный расчёт')),
              ...store.recipes.map((r) => DropdownMenuItem(
                    value: r.id,
                    child: Text(r.title),
                  )),
            ],
            onChanged: (v) {
              if (v == null) {
                setState(() => _calcRecipeId = null);
              } else {
                final rec = store.recipes.firstWhere((e) => e.id == v);
                _loadRecipeIntoCalculator(rec);
              }
            },
          ),
        const SizedBox(height: 12),
        AtelierCard(
          color: p.surfaceAlt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Рекомендованная цена',
                          style: TextStyle(fontSize: 12, color: p.textMuted)),
                      Text(
                        totals.validPrice
                            ? formatMoneyCents(totals.priceCents, currencySymbol: curr)
                            : 'Некорректные %',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: totals.validPrice ? p.primary : p.danger,
                            ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Чистая маржа',
                          style: TextStyle(fontSize: 12, color: p.textMuted)),
                      Text(
                        formatMoneyCents(totals.marginCents, currencySymbol: curr),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: totals.marginCents >= 0 ? p.success : p.danger,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              Text(
                'Производство: ${formatMoneyCents(totals.productionCostCents, currencySymbol: curr)} · '
                'Коммерческие: ${formatMoneyCents(totals.sellingCostCents, currencySymbol: curr)} · '
                'Безубыточность: ${totals.breakEvenCents != null ? formatMoneyCents(totals.breakEvenCents!, currencySymbol: curr) : '—'}'
                '${totals.roiPercent != null ? ' · ROI ${totals.roiPercent!.toStringAsFixed(0)}%' : ''}',
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AtelierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<PricingMode>(
                segments: const [
                  ButtonSegment(value: PricingMode.markup, label: Text('Наценка %')),
                  ButtonSegment(
                      value: PricingMode.targetMargin, label: Text('Маржа %')),
                  ButtonSegment(
                      value: PricingMode.fixedPrice, label: Text('Фикс. цена')),
                ],
                selected: {_pricingMode},
                onSelectionChanged: (s) => setState(() => _pricingMode = s.first),
              ),
              const SizedBox(height: 12),
              _NumericStepRow(
                label: 'Сырьё, ₽',
                initial: centsToRubInput(_materialsCents),
                onChanged: (v) => setState(() => _materialsCents = parseRubToCents(v)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _NumericStepRow(
                      label: 'Труд, ч',
                      initial: _laborHours.toString(),
                      onChanged: (v) => setState(() =>
                          _laborHours = double.tryParse(v.replaceAll(',', '.')) ?? 0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumericStepRow(
                      label: 'Ставка, ₽/ч',
                      initial: centsToRubInput(_laborRateCents),
                      onChanged: (v) =>
                          setState(() => _laborRateCents = parseRubToCents(v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _NumericStepRow(
                      label: 'Упаковка, ₽',
                      initial: centsToRubInput(_packagingCents),
                      onChanged: (v) =>
                          setState(() => _packagingCents = parseRubToCents(v)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumericStepRow(
                      label: 'Накладные, %',
                      initial: _overheadPct.toStringAsFixed(0),
                      onChanged: (v) => setState(() => _overheadPct =
                          double.tryParse(v.replaceAll(',', '.')) ?? 0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _NumericStepRow(
                      label: _pricingMode == PricingMode.markup
                          ? 'Наценка, %'
                          : (_pricingMode == PricingMode.targetMargin
                              ? 'Целевая маржа, %'
                              : 'Фикс. цена, ₽'),
                      initial: _pricingMode == PricingMode.markup
                          ? _marginPct.toStringAsFixed(0)
                          : (_pricingMode == PricingMode.targetMargin
                              ? _targetMarginPct.toStringAsFixed(0)
                              : centsToRubInput(_fixedPriceCents)),
                      onChanged: (v) => setState(() {
                        final numVal =
                            double.tryParse(v.replaceAll(',', '.')) ?? 0;
                        if (_pricingMode == PricingMode.markup) {
                          _marginPct = numVal;
                        } else if (_pricingMode == PricingMode.targetMargin) {
                          _targetMarginPct = numVal;
                        } else {
                          _fixedPriceCents = parseRubToCents(v);
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumericStepRow(
                      label: 'Комиссия / эквайринг, %',
                      initial: _feePct.toStringAsFixed(0),
                      onChanged: (v) => setState(() =>
                          _feePct = double.tryParse(v.replaceAll(',', '.')) ?? 0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _NumericStepRow(
                label: 'Резерв на брак, %',
                initial: _defectPct.toStringAsFixed(0),
                onChanged: (v) => setState(() =>
                    _defectPct = double.tryParse(v.replaceAll(',', '.')) ?? 0),
              ),
              if (_calcRecipeId != null && totals.validPrice) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () async {
                    final rec = store.recipes
                        .cast<Recipe?>()
                        .firstWhere((r) => r!.id == _calcRecipeId, orElse: () => null);
                    if (rec == null) return;
                    await store.saveRecipe(
                      rec.copyWith(
                        laborHours: _laborHours,
                        laborRateCents: _laborRateCents,
                        packagingCents: _packagingCents,
                        overheadPercent: _overheadPct,
                        marginPercent: _marginPct,
                        costCents: totals.costCents,
                        recommendedPriceCents: totals.priceCents,
                        updatedAt: DateTime.now().toIso8601String(),
                      ),
                    );
                    if (context.mounted) {
                      showAtelierMessage(
                          context, 'Цена и себестоимость сохранены в «${rec.title}».');
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Сохранить в выбранный рецепт'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NumericStepRow extends StatefulWidget {
  const _NumericStepRow({
    required this.label,
    required this.initial,
    required this.onChanged,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_NumericStepRow> createState() => _NumericStepRowState();
}

class _NumericStepRowState extends State<_NumericStepRow> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void didUpdateWidget(covariant _NumericStepRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial && _ctrl.text != widget.initial) {
      // Only sync if widget was externally reloaded (e.g., recipe switch)
      _ctrl.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: widget.label, isDense: true),
      onChanged: widget.onChanged,
    );
  }
}
