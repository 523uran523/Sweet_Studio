import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Camera,
  ChevronDown,
  ChevronUp,
  Package,
  Plus,
  Star,
  Table2,
  Trash2,
  Upload,
} from 'lucide-react';
import { Drawer, ImageWithFallback } from './UiPrimitives';
import {
  computeCalculatorTotals,
  effectiveQuantity,
  resourceLineTotalCents,
} from '../core/calculatorCore';
import { centsToRubInput, formatMoneyCents, parseRubToCents } from '../core/moneyFormat';
import {
  convertQty,
  convertQtyWithDensity,
  defaultPriceUnit,
  priceUnitsFor,
  QTY_UNITS,
} from '../core/units';
import { RECIPE_IMAGES } from '../firebase/seedDemo';
import {
  createWorkspaceEntity,
  newId,
  updateWorkspaceEntity,
  WorkspaceSnapshot,
} from '../firebase/workspaceService';
import {
  Recipe,
  RecipeIngredientLine,
  RecipePackVariant,
  Workspace,
} from '../types/domain';
import { compressImageFileToDataUrl } from '../utils/imageCompress';

export type RecipeFormMode = 'create' | 'edit' | 'version' | 'variation';

interface EditableIngredientRow extends RecipeIngredientLine {
  rowKey: string;
}

const RECIPE_CATEGORIES = [
  'Торты',
  'Капкейки',
  'Десерты',
  'Чизкейки',
  'Макарон',
  'Кремы',
  'Бисквиты',
  'Начинки',
  'Полуфабрикаты',
];

const COMMON_ALLERGENS = [
  'Молочные продукты',
  'Глютен',
  'Яйца',
  'Орехи',
  'Арахис',
  'Соя',
  'Мёд',
  'Цитрусовые',
];

const GALLERY_PRESETS: Array<{ label: string; url: string }> = [
  { label: 'Ягодный торт', url: RECIPE_IMAGES.berryCake },
  { label: 'Фисташковый рулет', url: RECIPE_IMAGES.pistachioRoll },
  { label: 'Ванильные капкейки', url: RECIPE_IMAGES.cupcakesVanilla },
  { label: 'Шоколадный тарт', url: RECIPE_IMAGES.chocolateTart },
  { label: 'Чизкейк Сан-Себастьян', url: RECIPE_IMAGES.cheesecakeBasque },
];

function recipeDefaultQtyUnit(invUnit: string): string {
  if (invUnit === 'кг') return 'г';
  if (invUnit === 'л') return 'мл';
  return invUnit;
}

export function RecipeFormDrawer({
  open,
  mode,
  sourceRecipe,
  workspace,
  data,
  onClose,
  onToast,
  onSaved,
}: {
  open: boolean;
  mode: RecipeFormMode;
  sourceRecipe?: Recipe | null;
  workspace: Workspace;
  data: WorkspaceSnapshot;
  onClose: () => void;
  onToast: (msg: string) => void;
  onSaved?: (recipeId: string) => void;
}) {
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [title, setTitle] = useState('');
  const [category, setCategory] = useState('Торты');
  const [status, setStatus] = useState<Recipe['status']>('draft');
  const [yieldGrams, setYieldGrams] = useState(1500);
  const [yieldPortions, setYieldPortions] = useState(8);
  const [formSize, setFormSize] = useState('D18');
  const [shelfLifeHours, setShelfLifeHours] = useState(72);
  const [storageCondition, setStorageCondition] = useState('+2…+4 °C');
  const [favorite, setFavorite] = useState(false);

  const [photoUrl, setPhotoUrl] = useState<string>(RECIPE_IMAGES.berryCake);
  const [urlInputOpen, setUrlInputOpen] = useState(false);
  const [photoBusy, setPhotoBusy] = useState(false);

  const [rows, setRows] = useState<EditableIngredientRow[]>([]);
  const [ingredientMode, setIngredientMode] = useState<'list' | 'matrix'>('list');
  const [matrixFilter, setMatrixFilter] = useState('');
  const [selectedInvId, setSelectedInvId] = useState('');
  const [selectedSubRecipeId, setSelectedSubRecipeId] = useState('');

  const [packVariants, setPackVariants] = useState<RecipePackVariant[]>([]);

  const [laborHours, setLaborHours] = useState(1.5);
  const [laborRateRub, setLaborRateRub] = useState('650');
  const [packagingRub, setPackagingRub] = useState('220');
  const [overheadPercent, setOverheadPercent] = useState(10);
  const [marginPercent, setMarginPercent] = useState(65);
  const [customPriceEnabled, setCustomPriceEnabled] = useState(false);
  const [customPriceRub, setCustomPriceRub] = useState('');

  const [steps, setSteps] = useState<string[]>([
    'Подготовить ингредиенты и взвесить по граммовкам.',
    'Выпечь основу / собрать изделие и стабилизировать в холодильнике.',
  ]);
  const [allergens, setAllergens] = useState<string[]>([
    'Молочные продукты',
    'Глютен',
    'Яйца',
  ]);
  const [customAllergen, setCustomAllergen] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;

    if (
      (mode === 'edit' || mode === 'version' || mode === 'variation') &&
      sourceRecipe
    ) {
      setTitle(
        mode === 'variation'
          ? `${sourceRecipe.title} (вариация)`
          : sourceRecipe.title || '',
      );
      setCategory(sourceRecipe.category || 'Торты');
      setStatus(
        mode === 'version' || mode === 'variation'
          ? 'draft'
          : sourceRecipe.status || 'draft',
      );
      setYieldGrams(sourceRecipe.yieldGrams || 1000);
      setYieldPortions(sourceRecipe.yieldPortions || 8);
      setFormSize(sourceRecipe.formSize || '');
      setShelfLifeHours(sourceRecipe.shelfLifeHours || 72);
      setStorageCondition(sourceRecipe.storageCondition || '+2…+4 °C');
      setFavorite(mode === 'variation' ? false : Boolean(sourceRecipe.favorite));
      setPhotoUrl(sourceRecipe.photoUrl || '');
      setRows(
        (sourceRecipe.ingredients || []).map((ing, i) => ({
          ...ing,
          isPackaging: Boolean(
            ing.isPackaging || ing.unit === 'шт' || ing.unit === 'упак',
          ),
          rowKey: `ing_${i}_${Date.now()}`,
        })),
      );
      setPackVariants(
        (sourceRecipe.packVariants || []).map((v) => ({ ...v })),
      );
      setLaborHours(sourceRecipe.laborHours ?? 1.5);
      setLaborRateRub(centsToRubInput(sourceRecipe.laborRateCents ?? 65000));
      setPackagingRub(centsToRubInput(sourceRecipe.packagingCents ?? 22000));
      setOverheadPercent(sourceRecipe.overheadPercent ?? 10);
      setMarginPercent(sourceRecipe.marginPercent ?? 65);
      setCustomPriceEnabled(false);
      setCustomPriceRub(centsToRubInput(sourceRecipe.recommendedPriceCents || 0));
      setSteps(
        sourceRecipe.steps && sourceRecipe.steps.length > 0
          ? [...sourceRecipe.steps]
          : ['Подготовить ингредиенты и собрать изделие.'],
      );
      setAllergens(sourceRecipe.allergens ? [...sourceRecipe.allergens] : []);
    } else {
      setTitle('');
      setCategory('Торты');
      setStatus('draft');
      setYieldGrams(1500);
      setYieldPortions(10);
      setFormSize('D18');
      setShelfLifeHours(72);
      setStorageCondition('+2…+4 °C');
      setFavorite(false);
      setPhotoUrl(RECIPE_IMAGES.berryCake);
      setRows([
        {
          rowKey: `ing_init_${Date.now()}`,
          name: 'Сливочный сыр',
          qty: 500,
          unit: 'г',
          lossPercent: 2,
          priceCents: 95000,
          priceUnit: 'за кг',
          isPackaging: false,
        },
      ]);
      setPackVariants([]);
      setLaborHours(1.5);
      setLaborRateRub('650');
      setPackagingRub('220');
      setOverheadPercent(10);
      setMarginPercent(65);
      setCustomPriceEnabled(false);
      setCustomPriceRub('');
      setSteps([
        'Подготовить ингредиенты и взвесить по граммовкам.',
        'Выпечь основу / собрать изделие и стабилизировать при +4 °C.',
      ]);
      setAllergens(['Молочные продукты', 'Глютен', 'Яйца']);
    }
    setIngredientMode('list');
    setMatrixFilter('');
    setUrlInputOpen(false);
    setSelectedInvId('');
    setSelectedSubRecipeId('');
    setSaving(false);
  }, [open, mode, sourceRecipe]);

  const { edibleMaterialsCents, packagingMaterialsCents, grossGrams } = useMemo(() => {
    let edible = 0;
    let pack = 0;
    let gross = 0;

    for (const r of rows) {
      const eff = effectiveQuantity(r.qty, r.lossPercent) ?? r.qty;
      const lineCents = resourceLineTotalCents({
        qty: eff,
        qtyUnit: r.unit,
        priceCents: r.priceCents,
        priceUnit: r.priceUnit,
      });
      if (r.isPackaging) {
        pack += lineCents;
      } else {
        edible += lineCents;
        const asGrams = convertQty(r.qty, r.unit, 'г');
        if (asGrams !== null) {
          gross += asGrams;
        } else if (r.unit === 'мл' || r.unit === 'л') {
          const inv = r.itemId
            ? data.inventoryItems.find((i) => i.id === r.itemId)
            : undefined;
          const byDens = convertQtyWithDensity(
            r.qty,
            r.unit,
            'г',
            inv?.density || 1,
          );
          if (byDens !== null) gross += byDens;
        }
      }
    }

    return {
      edibleMaterialsCents: edible,
      packagingMaterialsCents: pack,
      grossGrams: Math.round(gross),
    };
  }, [rows, data.inventoryItems]);

  const materialsCents = edibleMaterialsCents + packagingMaterialsCents;

  const totals = useMemo(
    () =>
      computeCalculatorTotals({
        materialsCents: edibleMaterialsCents,
        laborHours,
        laborRateCents: parseRubToCents(laborRateRub),
        otherCents: 0,
        overheadPercent,
        marginPercent,
        pricingMode: 'markup',
        packagingCents: parseRubToCents(packagingRub) + packagingMaterialsCents,
      }),
    [
      edibleMaterialsCents,
      packagingMaterialsCents,
      laborHours,
      laborRateRub,
      overheadPercent,
      marginPercent,
      packagingRub,
    ],
  );

  const finalPriceCents = customPriceEnabled
    ? parseRubToCents(customPriceRub)
    : totals.priceCents;

  const costPerKgCents =
    yieldGrams > 0 ? Math.round((totals.costCents / yieldGrams) * 1000) : 0;
  const costPer100gCents =
    yieldGrams > 0 ? Math.round((totals.costCents / yieldGrams) * 100) : 0;
  const bakeLossPct =
    grossGrams > 0 && grossGrams >= yieldGrams
      ? Math.round(((grossGrams - yieldGrams) / grossGrams) * 1000) / 10
      : 0;

  const handlePhotoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setPhotoBusy(true);
    try {
      const compressed = await compressImageFileToDataUrl(file);
      setPhotoUrl(compressed);
      onToast('Фото загружено и оптимизировано');
    } catch (err) {
      onToast(err instanceof Error ? err.message : 'Не удалось загрузить фото');
    } finally {
      setPhotoBusy(false);
    }
  };

  const handleAddFromInventory = (invId: string) => {
    setSelectedInvId(invId);
    const item = data.inventoryItems.find((i) => i.id === invId);
    if (!item) return;
    const unit = recipeDefaultQtyUnit(item.unit);
    const pUnit = defaultPriceUnit(item.unit);
    const isPack =
      item.kind === 'packaging' || unit === 'шт' || unit === 'упак';
    setRows((prev) => [
      ...prev,
      {
        rowKey: `inv_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
        itemId: item.id,
        name: item.name,
        qty: unit === 'шт' || unit === 'упак' ? 1 : 200,
        unit,
        lossPercent: isPack ? 0 : 2,
        priceCents: item.avgCostCents || 0,
        priceUnit: priceUnitsFor(unit).includes(pUnit)
          ? pUnit
          : priceUnitsFor(unit)[0],
        isPackaging: isPack,
      },
    ]);
    setSelectedInvId('');
  };

  const handleAddSubRecipe = (recId: string) => {
    setSelectedSubRecipeId(recId);
    const sub = data.recipes.find((r) => r.id === recId);
    if (!sub) return;
    if (sourceRecipe && sub.id === sourceRecipe.id) {
      onToast('Нельзя добавить рецепт внутрь самого себя');
      setSelectedSubRecipeId('');
      return;
    }
    const perKgCents = Math.round(
      (sub.costCents / Math.max(sub.yieldGrams || 1, 1)) * 1000,
    );
    setRows((prev) => [
      ...prev,
      {
        rowKey: `sub_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
        subRecipeId: sub.id,
        name: `${sub.title} (полуфабрикат)`,
        qty: Math.min(sub.yieldGrams, 500),
        unit: 'г',
        lossPercent: 0,
        priceCents: perKgCents,
        priceUnit: 'за кг',
        isPackaging: false,
      },
    ]);
    setSelectedSubRecipeId('');
  };

  const handleAddEmptyRow = () => {
    setRows((prev) => [
      ...prev,
      {
        rowKey: `row_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
        name: '',
        qty: 100,
        unit: 'г',
        lossPercent: 2,
        priceCents: 50000,
        priceUnit: 'за кг',
        isPackaging: false,
      },
    ]);
  };

  const setMatrixQuantityForInv = (itemId: string, qty: number) => {
    const item = data.inventoryItems.find((i) => i.id === itemId);
    if (!item) return;
    const cleanQty = Math.max(0, qty);
    setRows((prev) => {
      const existingIdx = prev.findIndex(
        (r) => r.itemId === item.id || (!r.itemId && r.name.toLowerCase() === item.name.toLowerCase()),
      );
      if (cleanQty <= 0) {
        return existingIdx >= 0 ? prev.filter((_, i) => i !== existingIdx) : prev;
      }
      if (existingIdx >= 0) {
        return prev.map((r, i) => (i === existingIdx ? { ...r, qty: cleanQty } : r));
      }
      const unit = recipeDefaultQtyUnit(item.unit);
      const pUnit = defaultPriceUnit(item.unit);
      const isPack =
        item.kind === 'packaging' || unit === 'шт' || unit === 'упак';
      return [
        ...prev,
        {
          rowKey: `mtx_${item.id}_${Date.now()}`,
          itemId: item.id,
          name: item.name,
          qty: cleanQty,
          unit,
          lossPercent: isPack ? 0 : 2,
          priceCents: item.avgCostCents || 0,
          priceUnit: priceUnitsFor(unit).includes(pUnit)
            ? pUnit
            : priceUnitsFor(unit)[0],
          isPackaging: isPack,
        },
      ];
    });
  };

  const setMatrixQuantityForSub = (subId: string, qty: number) => {
    const sub = data.recipes.find((r) => r.id === subId);
    if (!sub) return;
    const cleanQty = Math.max(0, qty);
    setRows((prev) => {
      const existingIdx = prev.findIndex((r) => r.subRecipeId === sub.id);
      if (cleanQty <= 0) {
        return existingIdx >= 0 ? prev.filter((_, i) => i !== existingIdx) : prev;
      }
      if (existingIdx >= 0) {
        return prev.map((r, i) => (i === existingIdx ? { ...r, qty: cleanQty } : r));
      }
      const perKgCents = Math.round(
        (sub.costCents / Math.max(sub.yieldGrams || 1, 1)) * 1000,
      );
      return [
        ...prev,
        {
          rowKey: `mtx_sub_${sub.id}_${Date.now()}`,
          subRecipeId: sub.id,
          name: `${sub.title} (полуфабрикат)`,
          qty: cleanQty,
          unit: 'г',
          lossPercent: 0,
          priceCents: perKgCents,
          priceUnit: 'за кг',
          isPackaging: false,
        },
      ];
    });
  };

  const computeVariantMetrics = (v: RecipePackVariant) => {
    const baseRatio =
      v.mode === 'grams'
        ? v.qtyOrGrams / Math.max(yieldGrams, 1)
        : v.qtyOrGrams / Math.max(yieldPortions || 1, 1);
    const prodCost = Math.round(totals.productionCostCents * baseRatio);
    const totalCost = prodCost + Math.max(0, v.packagingCents || 0);
    const suggestedPrice = Math.round(totalCost * (1 + Math.max(0, marginPercent) / 100));
    return { totalCost, suggestedPrice };
  };

  const addPackPreset = (
    label: string,
    vMode: 'grams' | 'pieces',
    qtyOrGrams: number,
    packagingCents: number,
  ) => {
    setPackVariants((prev) => [
      ...prev,
      {
        id: newId('pv'),
        label,
        mode: vMode,
        qtyOrGrams,
        packagingCents,
      },
    ]);
  };

  const toggleAllergen = (name: string) => {
    setAllergens((prev) =>
      prev.includes(name) ? prev.filter((x) => x !== name) : [...prev, name],
    );
  };

  const handleAddCustomAllergen = () => {
    const val = customAllergen.trim().slice(0, 60);
    if (!val) return;
    if (!allergens.includes(val)) {
      setAllergens((prev) => [...prev, val]);
    }
    setCustomAllergen('');
  };

  const moveStep = (idx: number, dir: -1 | 1) => {
    const target = idx + dir;
    if (target < 0 || target >= steps.length) return;
    setSteps((prev) => {
      const next = [...prev];
      const [item] = next.splice(idx, 1);
      next.splice(target, 0, item);
      return next;
    });
  };

  const validatePhotoUrl = (raw: string): string => {
    const val = raw.trim();
    if (!val) return '';
    if (
      val.startsWith('/src/assets/') ||
      val.startsWith('https://') ||
      val.startsWith('data:image/jpeg;base64,') ||
      val.startsWith('data:image/png;base64,') ||
      val.startsWith('data:image/webp;base64,')
    ) {
      return val;
    }
    throw new Error('Ссылка на фото должна начинаться с https:// или загрузите файл.');
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || saving) return;

    const cleanIngredients: RecipeIngredientLine[] = rows
      .filter((r) => r.name.trim().length > 0 && r.qty > 0)
      .slice(0, 80)
      .map((r) => {
        const line: RecipeIngredientLine = {
          name: r.name.trim().slice(0, 120),
          qty: Number(r.qty) || 0,
          unit: r.unit,
          lossPercent: Math.min(99, Math.max(0, Number(r.lossPercent) || 0)),
          priceCents: Math.max(0, Math.round(r.priceCents)),
          priceUnit: r.priceUnit,
          isPackaging: Boolean(r.isPackaging),
        };
        if (r.itemId) line.itemId = r.itemId;
        if (r.subRecipeId) line.subRecipeId = r.subRecipeId;
        return line;
      });

    if (cleanIngredients.length === 0) {
      onToast('Добавьте хотя бы один ингредиент с количеством > 0');
      return;
    }

    let safePhotoUrl = '';
    try {
      safePhotoUrl = validatePhotoUrl(photoUrl);
    } catch (err) {
      onToast(err instanceof Error ? err.message : 'Некорректное фото');
      return;
    }

    setSaving(true);
    try {
      const cleanSteps = steps
        .map((s) => s.trim())
        .filter((s) => s.length > 0)
        .slice(0, 40);
      const cleanAllergens = allergens
        .map((a) => a.trim().slice(0, 60))
        .filter(Boolean)
        .slice(0, 20);
      const cleanVariants: RecipePackVariant[] = packVariants
        .filter((v) => v.label.trim().length > 0 && v.qtyOrGrams > 0)
        .slice(0, 20)
        .map((v) => {
          const metrics = computeVariantMetrics(v);
          return {
            id: v.id,
            label: v.label.trim().slice(0, 80),
            mode: v.mode,
            qtyOrGrams: Number(v.qtyOrGrams) || 1,
            packagingCents: Math.max(0, Math.round(v.packagingCents || 0)),
            priceCents: v.priceCents ?? metrics.suggestedPrice,
          };
        });

      const nextVersion =
        mode === 'edit' && sourceRecipe
          ? sourceRecipe.version
          : mode === 'version' && sourceRecipe
            ? sourceRecipe.version + 1
            : 1;

      const payload: Record<string, unknown> = {
        title: title.trim().slice(0, 140),
        category: (category.trim() || 'Торты').slice(0, 60),
        version: nextVersion,
        status,
        yieldGrams: Math.max(10, Math.round(yieldGrams) || 1000),
        grossGrams: Math.max(0, Math.round(grossGrams)),
        yieldPortions: Math.max(1, Math.round(yieldPortions) || 1),
        formSize: formSize.trim().slice(0, 60),
        photoUrl: safePhotoUrl,
        ingredients: cleanIngredients,
        packVariants: cleanVariants,
        steps: cleanSteps,
        allergens: cleanAllergens,
        laborHours: Math.max(0, Number(laborHours) || 0),
        laborRateCents: Math.max(0, parseRubToCents(laborRateRub)),
        packagingCents: Math.max(0, parseRubToCents(packagingRub)),
        overheadPercent: Math.max(0, Number(overheadPercent) || 0),
        marginPercent: Math.max(0, Number(marginPercent) || 0),
        costCents: Math.max(0, totals.costCents),
        recommendedPriceCents: Math.max(0, finalPriceCents),
        shelfLifeHours: Math.max(1, Math.round(shelfLifeHours) || 48),
        storageCondition: (storageCondition.trim() || '+2…+4 °C').slice(0, 120),
        favorite,
      };

      if (mode === 'edit' && sourceRecipe) {
        await updateWorkspaceEntity(workspace, 'recipes', sourceRecipe.id, payload);
        onToast(`Рецепт «${title.trim()}» (v${nextVersion}) обновлён`);
        onSaved?.(sourceRecipe.id);
      } else {
        const recId = newId('rec');
        await createWorkspaceEntity(workspace, 'recipes', recId, payload);
        onToast(
          mode === 'version'
            ? `Создана новая версия v${nextVersion}`
            : mode === 'variation'
              ? `Вариация «${title.trim()}» создана`
              : `Рецепт «${title.trim()}» сохранён`,
        );
        onSaved?.(recId);
      }
      onClose();
    } catch (err) {
      onToast(err instanceof Error ? err.message : 'Ошибка сохранения рецепта');
    } finally {
      setSaving(false);
    }
  };

  const drawerTitle =
    mode === 'edit'
      ? `Редактировать рецепт · v${sourceRecipe?.version || 1}`
      : mode === 'version'
        ? `Новая версия рецепта · v${(sourceRecipe?.version || 1) + 1}`
        : mode === 'variation'
          ? 'Новая вариация вкуса'
          : 'Новый рецепт и калькуляция';

  const subRecipeCandidates = data.recipes.filter(
    (r) => !sourceRecipe || r.id !== sourceRecipe.id,
  );

  const filteredMatrixItems = useMemo(() => {
    const q = matrixFilter.trim().toLowerCase();
    return data.inventoryItems.filter(
      (i) => !q || i.name.toLowerCase().includes(q),
    );
  }, [data.inventoryItems, matrixFilter]);

  return (
    <Drawer
      open={open}
      wide
      title={drawerTitle}
      subtitle="Фото, матрица сырья, полуфабрикаты, фасовки и расчёт себестоимости"
      onClose={onClose}
    >
      <form onSubmit={handleSubmit} className="space-y-6 pb-4">
        {/* 1. Photo block */}
        <section className="space-y-3 p-4 rounded-2xl border border-[var(--line)] bg-[var(--bg)]">
          <div className="flex items-center justify-between gap-2">
            <span className="text-sm font-semibold">Фотография десерта</span>
            <div className="flex items-center gap-2">
              <input
                ref={fileInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,image/*"
                onChange={handlePhotoUpload}
                className="hidden"
              />
              <button
                type="button"
                disabled={photoBusy}
                onClick={() => fileInputRef.current?.click()}
                className="min-h-[38px] px-3 py-1.5 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium inline-flex items-center gap-1.5 disabled:opacity-60"
              >
                <Upload className="w-3.5 h-3.5" />
                <span>{photoBusy ? 'Сжатие...' : 'Загрузить с устройства'}</span>
              </button>
              <button
                type="button"
                onClick={() => setUrlInputOpen((v) => !v)}
                className="min-h-[38px] px-3 py-1.5 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium hover:bg-[var(--soft)]"
              >
                Ссылка URL
              </button>
            </div>
          </div>

          <div className="grid sm:grid-cols-3 gap-3 items-start">
            <div className="relative rounded-xl overflow-hidden border border-[var(--line)] bg-[var(--card)]">
              <ImageWithFallback
                src={photoUrl}
                alt={title || 'Превью рецепта'}
                className="w-full h-36 object-cover"
              />
              {photoUrl && (
                <button
                  type="button"
                  onClick={() => setPhotoUrl('')}
                  className="absolute bottom-2 right-2 px-2 py-1 rounded-lg bg-black/65 text-white text-[11px]"
                >
                  Убрать
                </button>
              )}
            </div>

            <div className="sm:col-span-2 space-y-2">
              <div className="text-xs text-[var(--muted)] flex items-center gap-1.5">
                <Camera className="w-3.5 h-3.5" />
                <span>Или выберите готовую обложку студии:</span>
              </div>
              <div className="grid grid-cols-5 gap-2">
                {GALLERY_PRESETS.map((preset) => (
                  <button
                    key={preset.url}
                    type="button"
                    onClick={() => setPhotoUrl(preset.url)}
                    title={preset.label}
                    className={`rounded-xl overflow-hidden border-2 transition-all ${
                      photoUrl === preset.url
                        ? 'border-[var(--accent)] ring-1 ring-[var(--accent)]'
                        : 'border-transparent opacity-80 hover:opacity-100'
                    }`}
                  >
                    <img
                      src={preset.url}
                      alt={preset.label}
                      className="w-full h-14 object-cover"
                    />
                  </button>
                ))}
              </div>
              {urlInputOpen && (
                <input
                  type="url"
                  value={photoUrl.startsWith('data:') ? '' : photoUrl}
                  onChange={(e) => setPhotoUrl(e.target.value)}
                  placeholder="https://example.com/cake.jpg"
                  className="w-full min-h-[38px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs"
                />
              )}
            </div>
          </div>
        </section>

        {/* 2. Basic info & parameters */}
        <section className="space-y-3">
          <div className="flex items-center justify-between gap-2">
            <label className="flex-1 block space-y-1 text-sm font-medium">
              <span>Название рецепта *</span>
              <input
                type="text"
                required
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Например: Наполеон классический с ванильным заварным кремом"
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <button
              type="button"
              onClick={() => setFavorite((f) => !f)}
              title="Добавить в избранное"
              className={`mt-6 min-w-[44px] min-h-[44px] rounded-xl border inline-flex items-center justify-center ${
                favorite
                  ? 'border-[var(--accent)] bg-[var(--soft)]'
                  : 'border-[var(--line)] bg-[var(--bg)]'
              }`}
            >
              <Star
                className={`w-4 h-4 ${
                  favorite
                    ? 'fill-[var(--accent)] text-[var(--accent)]'
                    : 'text-[var(--muted)]'
                }`}
              />
            </button>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 text-sm">
            <label className="space-y-1 font-medium">
              <span>Категория</span>
              <select
                value={
                  RECIPE_CATEGORIES.includes(category) ? category : RECIPE_CATEGORIES[0]
                }
                onChange={(e) => setCategory(e.target.value)}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                {RECIPE_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </label>

            <label className="space-y-1 font-medium">
              <span>Статус карты</span>
              <select
                value={status}
                onChange={(e) => setStatus(e.target.value as Recipe['status'])}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="draft">Черновик</option>
                <option value="review">На проверке</option>
                <option value="approved">Утверждена</option>
                <option value="archived">Архив</option>
              </select>
            </label>

            <label className="space-y-1 font-medium">
              <span>Форма / размер</span>
              <input
                type="text"
                value={formSize}
                onChange={(e) => setFormSize(e.target.value)}
                placeholder="D18 / 30×40"
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>

            <label className="space-y-1 font-medium">
              <span>Выход нетто, г *</span>
              <input
                type="number"
                min={10}
                step={10}
                required
                value={yieldGrams}
                onChange={(e) => setYieldGrams(Number(e.target.value) || 100)}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>

            <label className="space-y-1 font-medium">
              <span>Порций, шт</span>
              <input
                type="number"
                min={1}
                value={yieldPortions}
                onChange={(e) => setYieldPortions(Number(e.target.value) || 1)}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>

            <label className="space-y-1 font-medium">
              <span>Срок годности, ч</span>
              <input
                type="number"
                min={1}
                value={shelfLifeHours}
                onChange={(e) => setShelfLifeHours(Number(e.target.value) || 24)}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          </div>

          <label className="block space-y-1 text-sm font-medium">
            <span>Условия хранения</span>
            <input
              type="text"
              value={storageCondition}
              onChange={(e) => setStorageCondition(e.target.value)}
              placeholder="+2…+4 °C в закрытой коробке"
              className="w-full min-h-[42px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
        </section>

        {/* 3. Ingredients & Quick Matrix */}
        <section className="space-y-3 p-4 rounded-2xl border border-[var(--line)] bg-[var(--bg)]">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
            <div>
              <h3 className="text-sm font-semibold">
                Ингредиенты и полуфабрикаты ({rows.length})
              </h3>
              <p className="text-xs text-[var(--muted)]">
                Раздельный учёт съедобной массы брутто/нетто и расходников/упаковки
              </p>
            </div>
            <div className="flex items-center gap-2 self-start sm:self-auto">
              <button
                type="button"
                onClick={() =>
                  setIngredientMode((m) => (m === 'list' ? 'matrix' : 'list'))
                }
                className={`min-h-[36px] px-3 py-1.5 rounded-xl border text-xs font-medium inline-flex items-center gap-1.5 ${
                  ingredientMode === 'matrix'
                    ? 'border-[var(--accent)] bg-[var(--soft)]'
                    : 'border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)]'
                }`}
              >
                <Table2 className="w-3.5 h-3.5" />
                <span>
                  {ingredientMode === 'matrix' ? 'К списку строк' : 'Матрица из справочника'}
                </span>
              </button>
              {ingredientMode === 'list' && (
                <button
                  type="button"
                  onClick={handleAddEmptyRow}
                  className="min-h-[36px] px-3 py-1.5 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium inline-flex items-center gap-1 hover:bg-[var(--soft)]"
                >
                  <Plus className="w-3.5 h-3.5" />
                  <span>Пустая строка</span>
                </button>
              )}
            </div>
          </div>

          {ingredientMode === 'matrix' ? (
            <div className="space-y-3">
              <input
                type="search"
                value={matrixFilter}
                onChange={(e) => setMatrixFilter(e.target.value)}
                placeholder="Фильтр позиций справочника и полуфабрикатов..."
                className="w-full min-h-[38px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs"
              />
              <div className="max-h-72 overflow-y-auto rounded-xl border border-[var(--line)] bg-[var(--card)]">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="border-b border-[var(--line)] text-[var(--muted)]">
                      <th className="text-left px-3 py-2 font-medium">Позиция / полуфабрикат</th>
                      <th className="text-right px-3 py-2 font-medium">Цена</th>
                      <th className="text-right px-3 py-2 font-medium w-32">Кол-во в рецепт</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[var(--line)]">
                    {filteredMatrixItems.map((item) => {
                      const recUnit = recipeDefaultQtyUnit(item.unit);
                      const matchedRow = rows.find(
                        (r) =>
                          r.itemId === item.id ||
                          (!r.itemId && r.name.toLowerCase() === item.name.toLowerCase()),
                      );
                      return (
                        <tr key={item.id}>
                          <td className="px-3 py-2">
                            <div className="font-medium">{item.name}</div>
                            <div className="text-[11px] text-[var(--muted)]">
                              {item.kind === 'packaging'
                                ? 'Упаковка'
                                : item.kind === 'semi'
                                  ? 'Полуфабрикат'
                                  : 'Сырьё'}
                            </div>
                          </td>
                          <td className="px-3 py-2 text-right tabular-nums text-[var(--muted)]">
                            {formatMoneyCents(item.avgCostCents)}/{item.unit}
                          </td>
                          <td className="px-3 py-2 text-right">
                            <div className="inline-flex items-center gap-1 justify-end">
                              <input
                                type="number"
                                min={0}
                                step="any"
                                value={matchedRow ? matchedRow.qty : ''}
                                placeholder="0"
                                onChange={(e) =>
                                  setMatrixQuantityForInv(
                                    item.id,
                                    Number(e.target.value) || 0,
                                  )
                                }
                                className="w-20 min-h-[32px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-right tabular-nums"
                              />
                              <span className="text-[var(--muted)] w-6 text-left">
                                {recUnit}
                              </span>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                    {subRecipeCandidates
                      .filter(
                        (s) =>
                          !matrixFilter.trim() ||
                          s.title.toLowerCase().includes(matrixFilter.trim().toLowerCase()),
                      )
                      .map((sub) => {
                        const matchedRow = rows.find((r) => r.subRecipeId === sub.id);
                        const per100g = Math.round(
                          (sub.costCents / Math.max(sub.yieldGrams || 1, 1)) * 100,
                        );
                        return (
                          <tr key={sub.id} className="bg-[var(--soft)]/25">
                            <td className="px-3 py-2">
                              <div className="font-medium">{sub.title}</div>
                              <div className="text-[11px] text-[var(--muted)]">
                                Вложенный рецепт
                              </div>
                            </td>
                            <td className="px-3 py-2 text-right tabular-nums text-[var(--muted)]">
                              {formatMoneyCents(per100g)}/100 г
                            </td>
                            <td className="px-3 py-2 text-right">
                              <div className="inline-flex items-center gap-1 justify-end">
                                <input
                                  type="number"
                                  min={0}
                                  step="any"
                                  value={matchedRow ? matchedRow.qty : ''}
                                  placeholder="0"
                                  onChange={(e) =>
                                    setMatrixQuantityForSub(
                                      sub.id,
                                      Number(e.target.value) || 0,
                                    )
                                  }
                                  className="w-20 min-h-[32px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-right tabular-nums"
                                />
                                <span className="text-[var(--muted)] w-6 text-left">г</span>
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                  </tbody>
                </table>
              </div>
            </div>
          ) : (
            <>
              {/* Quick pickers */}
              <div className="grid sm:grid-cols-2 gap-2">
                {data.inventoryItems.length > 0 && (
                  <select
                    value={selectedInvId}
                    onChange={(e) => handleAddFromInventory(e.target.value)}
                    aria-label="Добавить из кладовой"
                    className="min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium"
                  >
                    <option value="">+ Добавить ингредиент из Кладовой...</option>
                    {data.inventoryItems.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.name} ({formatMoneyCents(item.avgCostCents)}/{item.unit})
                      </option>
                    ))}
                  </select>
                )}
                {subRecipeCandidates.length > 0 && (
                  <select
                    value={selectedSubRecipeId}
                    onChange={(e) => handleAddSubRecipe(e.target.value)}
                    aria-label="Добавить полуфабрикат из рецептов"
                    className="min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium"
                  >
                    <option value="">+ Вложить полуфабрикат / рецепт...</option>
                    {subRecipeCandidates.map((sub) => (
                      <option key={sub.id} value={sub.id}>
                        {sub.title} ({sub.yieldGrams} г)
                      </option>
                    ))}
                  </select>
                )}
              </div>

              <div className="space-y-2.5">
                {rows.map((row) => {
                  const eff = effectiveQuantity(row.qty, row.lossPercent) ?? row.qty;
                  const lineCents = resourceLineTotalCents({
                    qty: eff,
                    qtyUnit: row.unit,
                    priceCents: row.priceCents,
                    priceUnit: row.priceUnit,
                  });
                  const pUnits = priceUnitsFor(row.unit);
                  return (
                    <div
                      key={row.rowKey}
                      className="p-2.5 rounded-xl border border-[var(--line)] bg-[var(--card)] space-y-2"
                    >
                      <div className="flex items-center gap-2">
                        <input
                          type="text"
                          value={row.name}
                          onChange={(e) =>
                            setRows((prev) =>
                              prev.map((x) =>
                                x.rowKey === row.rowKey ? { ...x, name: e.target.value } : x,
                              ),
                            )
                          }
                          placeholder="Название ингредиента"
                          className="flex-1 min-h-[36px] px-2.5 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-sm"
                        />
                        <button
                          type="button"
                          onClick={() =>
                            setRows((prev) =>
                              prev.map((x) =>
                                x.rowKey === row.rowKey
                                  ? { ...x, isPackaging: !x.isPackaging }
                                  : x,
                              ),
                            )
                          }
                          title="Упаковка / несъедобный расходник (исключается из массы брутто)"
                          className={`px-2 py-1 rounded-lg border text-[11px] font-medium inline-flex items-center gap-1 whitespace-nowrap ${
                            row.isPackaging
                              ? 'border-[var(--accent)] bg-[var(--soft)] text-[var(--ink)]'
                              : 'border-[var(--line)] text-[var(--muted)]'
                          }`}
                        >
                          <Package className="w-3 h-3" />
                          <span>{row.isPackaging ? 'Упаковка' : 'Сырьё'}</span>
                        </button>
                        <span className="text-xs font-semibold tabular-nums whitespace-nowrap px-1">
                          {formatMoneyCents(lineCents)}
                        </span>
                        <button
                          type="button"
                          onClick={() =>
                            setRows((prev) => prev.filter((x) => x.rowKey !== row.rowKey))
                          }
                          aria-label="Удалить ингредиент"
                          className="p-1.5 text-[var(--muted)] hover:text-[var(--danger)]"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>

                      <div className="grid grid-cols-5 gap-1.5 text-xs">
                        <label className="space-y-0.5">
                          <span className="text-[11px] text-[var(--muted)]">Кол-во</span>
                          <input
                            type="number"
                            min={0}
                            step="any"
                            value={row.qty}
                            onChange={(e) =>
                              setRows((prev) =>
                                prev.map((x) =>
                                  x.rowKey === row.rowKey
                                    ? { ...x, qty: Number(e.target.value) || 0 }
                                    : x,
                                ),
                              )
                            }
                            className="w-full min-h-[34px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                          />
                        </label>
                        <label className="space-y-0.5">
                          <span className="text-[11px] text-[var(--muted)]">Ед.</span>
                          <select
                            value={row.unit}
                            onChange={(e) => {
                              const nextUnit = e.target.value;
                              const nextPrices = priceUnitsFor(nextUnit);
                              setRows((prev) =>
                                prev.map((x) =>
                                  x.rowKey === row.rowKey
                                    ? {
                                        ...x,
                                        unit: nextUnit,
                                        priceUnit: nextPrices.includes(x.priceUnit)
                                          ? x.priceUnit
                                          : nextPrices[0],
                                      }
                                    : x,
                                ),
                              );
                            }}
                            className="w-full min-h-[34px] px-1.5 rounded-lg border border-[var(--line)] bg-[var(--bg)]"
                          >
                            {QTY_UNITS.map((u) => (
                              <option key={u} value={u}>
                                {u}
                              </option>
                            ))}
                          </select>
                        </label>
                        <label className="space-y-0.5">
                          <span className="text-[11px] text-[var(--muted)]">Потери %</span>
                          <input
                            type="number"
                            min={0}
                            max={95}
                            value={row.lossPercent}
                            onChange={(e) =>
                              setRows((prev) =>
                                prev.map((x) =>
                                  x.rowKey === row.rowKey
                                    ? { ...x, lossPercent: Number(e.target.value) || 0 }
                                    : x,
                                ),
                              )
                            }
                            className="w-full min-h-[34px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                          />
                        </label>
                        <label className="space-y-0.5">
                          <span className="text-[11px] text-[var(--muted)]">Цена, ₽</span>
                          <input
                            type="text"
                            value={centsToRubInput(row.priceCents)}
                            onChange={(e) =>
                              setRows((prev) =>
                                prev.map((x) =>
                                  x.rowKey === row.rowKey
                                    ? { ...x, priceCents: parseRubToCents(e.target.value) }
                                    : x,
                                ),
                              )
                            }
                            className="w-full min-h-[34px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                          />
                        </label>
                        <label className="space-y-0.5">
                          <span className="text-[11px] text-[var(--muted)]">База цены</span>
                          <select
                            value={row.priceUnit}
                            onChange={(e) =>
                              setRows((prev) =>
                                prev.map((x) =>
                                  x.rowKey === row.rowKey
                                    ? { ...x, priceUnit: e.target.value }
                                    : x,
                                ),
                              )
                            }
                            className="w-full min-h-[34px] px-1 rounded-lg border border-[var(--line)] bg-[var(--bg)]"
                          >
                            {pUnits.map((u) => (
                              <option key={u} value={u}>
                                {u}
                              </option>
                            ))}
                          </select>
                        </label>
                      </div>
                    </div>
                  );
                })}
              </div>
            </>
          )}

          {/* Gross vs Net yield strip */}
          <div className="pt-2 border-t border-[var(--line)] space-y-2 text-xs tabular-nums">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="text-[var(--muted)]">
                Масса брутто: <strong className="text-[var(--ink)]">{grossGrams} г</strong> ·
                Упёк/уварка: <strong className="text-[var(--ink)]">{bakeLossPct}%</strong> ·
                100 г: <strong className="text-[var(--ink)]">{formatMoneyCents(costPer100gCents)}</strong>
              </span>
              {grossGrams > 0 && (
                <button
                  type="button"
                  onClick={() => setYieldGrams(grossGrams)}
                  className="px-2 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)] font-medium"
                >
                  Выход = Брутто ({grossGrams} г)
                </button>
              )}
            </div>
            <div className="flex justify-between font-medium">
              <span className="text-[var(--muted)]">
                Сырьё: {formatMoneyCents(edibleMaterialsCents)}
                {packagingMaterialsCents > 0
                  ? ` + расходники ${formatMoneyCents(packagingMaterialsCents)}`
                  : ''}
              </span>
              <span>Итого строки: {formatMoneyCents(materialsCents)}</span>
            </div>
          </div>
        </section>

        {/* 4. Labor, Packaging, Overhead & Live Costing */}
        <section className="space-y-4 p-4 rounded-2xl border border-[var(--line)] bg-[var(--soft)]">
          <h3 className="text-sm font-semibold">Труд, накладные и расчёт цены</h3>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
            <label className="space-y-1 font-medium">
              <span className="text-xs">Труд, ч</span>
              <input
                type="number"
                min={0}
                step={0.25}
                value={laborHours}
                onChange={(e) => setLaborHours(Number(e.target.value) || 0)}
                className="w-full min-h-[38px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--card)] tabular-nums"
              />
            </label>
            <label className="space-y-1 font-medium">
              <span className="text-xs">Ставка, ₽/ч</span>
              <input
                type="text"
                value={laborRateRub}
                onChange={(e) => setLaborRateRub(e.target.value)}
                className="w-full min-h-[38px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--card)] tabular-nums"
              />
            </label>
            <label className="space-y-1 font-medium">
              <span className="text-xs">Упаковка, ₽</span>
              <input
                type="text"
                value={packagingRub}
                onChange={(e) => setPackagingRub(e.target.value)}
                className="w-full min-h-[38px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--card)] tabular-nums"
              />
            </label>
            <label className="space-y-1 font-medium">
              <span className="text-xs">Накладные, %</span>
              <input
                type="number"
                min={0}
                max={100}
                value={overheadPercent}
                onChange={(e) => setOverheadPercent(Number(e.target.value) || 0)}
                className="w-full min-h-[38px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--card)] tabular-nums"
              />
            </label>
          </div>

          <div className="space-y-1.5 text-sm">
            <div className="flex items-center justify-between gap-2">
              <span className="font-medium">Наценка к себестоимости</span>
              <div className="flex items-center gap-1.5">
                <input
                  type="number"
                  min={0}
                  max={300}
                  value={marginPercent}
                  onChange={(e) => setMarginPercent(Number(e.target.value) || 0)}
                  className="w-20 min-h-[34px] px-2 rounded-lg border border-[var(--line)] bg-[var(--card)] text-right text-sm tabular-nums"
                />
                <span className="text-xs">%</span>
              </div>
            </div>
            <input
              type="range"
              min={0}
              max={200}
              value={Math.min(200, Math.max(0, marginPercent))}
              onChange={(e) => setMarginPercent(Number(e.target.value))}
              className="w-full accent-[var(--accent)]"
            />
          </div>

          <div className="p-3 rounded-xl bg-[var(--card)] border border-[var(--line)] space-y-2 text-sm tabular-nums">
            <div className="grid grid-cols-3 gap-2 text-xs text-[var(--muted)]">
              <div>Сырьё: {formatMoneyCents(totals.materialsCents)}</div>
              <div>Труд: {formatMoneyCents(totals.laborCents)}</div>
              <div>
                Накладные + уп.:{' '}
                {formatMoneyCents(totals.overheadCents + totals.sellingCostCents)}
              </div>
            </div>
            <div className="pt-2 border-t border-[var(--line)] flex flex-wrap items-center justify-between gap-2">
              <div>
                <div className="text-xs text-[var(--muted)]">Полная себестоимость</div>
                <div className="text-base font-semibold">
                  {formatMoneyCents(totals.costCents)}{' '}
                  <span className="text-xs font-normal text-[var(--muted)]">
                    ({formatMoneyCents(costPerKgCents)}/кг · {formatMoneyCents(costPer100gCents)}/100 г)
                  </span>
                </div>
              </div>
              <div className="text-right">
                <div className="text-xs text-[var(--muted)]">Рекомендованная цена</div>
                <div className="text-lg font-semibold text-[var(--accent)]">
                  {formatMoneyCents(finalPriceCents)}
                </div>
              </div>
            </div>

            <label className="flex items-center gap-2 pt-1 text-xs">
              <input
                type="checkbox"
                checked={customPriceEnabled}
                onChange={(e) => {
                  const checked = e.target.checked;
                  setCustomPriceEnabled(checked);
                  if (checked && !customPriceRub) {
                    setCustomPriceRub(centsToRubInput(totals.priceCents));
                  }
                }}
                className="accent-[var(--accent)]"
              />
              <span>Задать итоговую цену вручную</span>
              {customPriceEnabled && (
                <input
                  type="text"
                  value={customPriceRub}
                  onChange={(e) => setCustomPriceRub(e.target.value)}
                  className="ml-auto w-28 min-h-[32px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-right text-xs tabular-nums"
                />
              )}
            </label>
          </div>
        </section>

        {/* 4b. Pack variants & gift sets */}
        <section className="space-y-3 p-4 rounded-2xl border border-[var(--line)] bg-[var(--bg)]">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h3 className="text-sm font-semibold">
                Варианты фасовки и наборов ({packVariants.length})
              </h3>
              <p className="text-xs text-[var(--muted)]">
                Расчёт цены для наборов (5 шт / 8 шт) или фасовок (330 г) со своей коробкой
              </p>
            </div>
            <div className="flex flex-wrap gap-1.5">
              <button
                type="button"
                onClick={() => addPackPreset('1 шт (витрина)', 'pieces', 1, 0)}
                className="px-2.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-[11px] font-medium hover:bg-[var(--soft)]"
              >
                + 1 шт
              </button>
              <button
                type="button"
                onClick={() => addPackPreset('Набор 5 шт', 'pieces', 5, 9000)}
                className="px-2.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-[11px] font-medium hover:bg-[var(--soft)]"
              >
                + Набор 5 шт
              </button>
              <button
                type="button"
                onClick={() => addPackPreset('Набор 8 шт', 'pieces', 8, 12000)}
                className="px-2.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-[11px] font-medium hover:bg-[var(--soft)]"
              >
                + Набор 8 шт
              </button>
              <button
                type="button"
                onClick={() => addPackPreset('Фасовка 330 г', 'grams', 330, 5000)}
                className="px-2.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-[11px] font-medium hover:bg-[var(--soft)]"
              >
                + 330 г
              </button>
            </div>
          </div>

          {packVariants.length > 0 && (
            <div className="space-y-2">
              {packVariants.map((v) => {
                const metrics = computeVariantMetrics(v);
                return (
                  <div
                    key={v.id}
                    className="p-2.5 rounded-xl border border-[var(--line)] bg-[var(--card)] grid grid-cols-12 gap-2 items-center text-xs"
                  >
                    <input
                      type="text"
                      value={v.label}
                      onChange={(e) =>
                        setPackVariants((prev) =>
                          prev.map((x) =>
                            x.id === v.id ? { ...x, label: e.target.value } : x,
                          ),
                        )
                      }
                      placeholder="Название варианта"
                      className="col-span-12 sm:col-span-4 min-h-[34px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)]"
                    />
                    <select
                      value={v.mode}
                      onChange={(e) =>
                        setPackVariants((prev) =>
                          prev.map((x) =>
                            x.id === v.id
                              ? { ...x, mode: e.target.value as 'grams' | 'pieces' }
                              : x,
                          ),
                        )
                      }
                      className="col-span-4 sm:col-span-2 min-h-[34px] px-1.5 rounded-lg border border-[var(--line)] bg-[var(--bg)]"
                    >
                      <option value="pieces">Порций</option>
                      <option value="grams">Грамм</option>
                    </select>
                    <input
                      type="number"
                      min={1}
                      step="any"
                      value={v.qtyOrGrams}
                      onChange={(e) =>
                        setPackVariants((prev) =>
                          prev.map((x) =>
                            x.id === v.id
                              ? { ...x, qtyOrGrams: Number(e.target.value) || 1 }
                              : x,
                          ),
                        )
                      }
                      aria-label="Вес или штук"
                      className="col-span-4 sm:col-span-2 min-h-[34px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                    />
                    <input
                      type="text"
                      value={centsToRubInput(v.packagingCents)}
                      onChange={(e) =>
                        setPackVariants((prev) =>
                          prev.map((x) =>
                            x.id === v.id
                              ? { ...x, packagingCents: parseRubToCents(e.target.value) }
                              : x,
                          ),
                        )
                      }
                      title="Упаковка для варианта, ₽"
                      placeholder="Упак. ₽"
                      className="col-span-4 sm:col-span-2 min-h-[34px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                    />
                    <div className="col-span-12 sm:col-span-2 flex items-center justify-between sm:justify-end gap-1.5 tabular-nums">
                      <div className="text-right leading-tight">
                        <div className="font-semibold text-[var(--accent)]">
                          {formatMoneyCents(metrics.suggestedPrice)}
                        </div>
                        <div className="text-[10px] text-[var(--muted)]">
                          себ. {formatMoneyCents(metrics.totalCost)}
                        </div>
                      </div>
                      <button
                        type="button"
                        onClick={() =>
                          setPackVariants((prev) => prev.filter((x) => x.id !== v.id))
                        }
                        aria-label="Удалить вариант"
                        className="p-1 text-[var(--muted)] hover:text-[var(--danger)]"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </section>

        {/* 5. Steps */}
        <section className="space-y-2.5">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold">Технология приготовления ({steps.length})</h3>
            <button
              type="button"
              onClick={() => setSteps((prev) => [...prev, ''])}
              className="px-3 py-1 rounded-lg border border-[var(--line)] text-xs font-medium inline-flex items-center gap-1 hover:bg-[var(--soft)]"
            >
              <Plus className="w-3.5 h-3.5" />
              <span>Шаг</span>
            </button>
          </div>
          <div className="space-y-2">
            {steps.map((step, idx) => (
              <div key={idx} className="flex items-start gap-2">
                <span className="w-6 h-9 inline-flex items-center justify-center text-xs font-semibold text-[var(--muted)] tabular-nums shrink-0">
                  {idx + 1}.
                </span>
                <textarea
                  rows={2}
                  value={step}
                  onChange={(e) =>
                    setSteps((prev) =>
                      prev.map((s, i) => (i === idx ? e.target.value : s)),
                    )
                  }
                  placeholder={`Шаг ${idx + 1}...`}
                  className="flex-1 p-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
                />
                <div className="flex flex-col gap-1 shrink-0">
                  <button
                    type="button"
                    disabled={idx === 0}
                    onClick={() => moveStep(idx, -1)}
                    aria-label="Выше"
                    className="p-1 rounded border border-[var(--line)] disabled:opacity-30"
                  >
                    <ChevronUp className="w-3.5 h-3.5" />
                  </button>
                  <button
                    type="button"
                    disabled={idx === steps.length - 1}
                    onClick={() => moveStep(idx, 1)}
                    aria-label="Ниже"
                    className="p-1 rounded border border-[var(--line)] disabled:opacity-30"
                  >
                    <ChevronDown className="w-3.5 h-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() =>
                      setSteps((prev) => prev.filter((_, i) => i !== idx))
                    }
                    aria-label="Удалить шаг"
                    className="p-1 rounded border border-[var(--line)] text-[var(--muted)] hover:text-[var(--danger)]"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* 6. Allergens */}
        <section className="space-y-2.5">
          <h3 className="text-sm font-semibold">Аллергены (с предупреждением о перекрёстном контакте)</h3>
          <div className="flex flex-wrap gap-1.5">
            {COMMON_ALLERGENS.map((al) => {
              const active = allergens.includes(al);
              return (
                <button
                  key={al}
                  type="button"
                  onClick={() => toggleAllergen(al)}
                  className={`px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors ${
                    active
                      ? 'border-[var(--accent)] bg-[var(--soft)] text-[var(--ink)]'
                      : 'border-[var(--line)] bg-[var(--bg)] text-[var(--muted)]'
                  }`}
                >
                  {al}
                </button>
              );
            })}
            {allergens
              .filter((a) => !COMMON_ALLERGENS.includes(a))
              .map((extra) => (
                <button
                  key={extra}
                  type="button"
                  onClick={() => toggleAllergen(extra)}
                  className="px-3 py-1.5 rounded-xl text-xs font-medium border border-[var(--accent)] bg-[var(--soft)]"
                >
                  {extra} ×
                </button>
              ))}
          </div>
          <div className="flex gap-2">
            <input
              type="text"
              value={customAllergen}
              onChange={(e) => setCustomAllergen(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  handleAddCustomAllergen();
                }
              }}
              placeholder="Другой аллерген (например: Желатин)"
              className="flex-1 min-h-[38px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-xs"
            />
            <button
              type="button"
              onClick={handleAddCustomAllergen}
              className="min-h-[38px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium"
            >
              Добавить
            </button>
          </div>
        </section>

        <button
          type="submit"
          disabled={saving}
          className="w-full min-h-[48px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-semibold disabled:opacity-60"
        >
          {saving
            ? 'Сохраняем техкарту...'
            : mode === 'edit'
              ? 'Сохранить изменения'
              : mode === 'version'
                ? `Создать версию v${(sourceRecipe?.version || 1) + 1}`
                : mode === 'variation'
                  ? 'Сохранить вариацию'
                  : 'Сохранить рецепт'}
        </button>
      </form>
    </Drawer>
  );
}
