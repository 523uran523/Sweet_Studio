import React, { useEffect, useMemo, useState } from 'react';
import {
  CopyPlus,
  Package,
  Pencil,
  Plus,
  Printer,
  Sparkles,
  Star,
  Table2,
  Trash2,
} from 'lucide-react';
import { RecipeFormDrawer, RecipeFormMode } from '../components/RecipeFormDrawer';
import {
  Card,
  Drawer,
  EmptyState,
  ImageWithFallback,
  PageHeader,
} from '../components/UiPrimitives';
import {
  computeCalculatorTotals,
  effectiveQuantity,
  PricingMode,
  resourceLineTotalCents,
} from '../core/calculatorCore';
import { centsToRubInput, formatMoneyCents, parseRubToCents } from '../core/moneyFormat';
import {
  convertQty,
  convertQtyWithDensity,
  defaultPriceUnit,
  formatQty,
  priceUnitsFor,
  QTY_UNITS,
} from '../core/units';
import {
  createWorkspaceEntity,
  newId,
  updateWorkspaceEntity,
  WorkspaceSnapshot,
} from '../firebase/workspaceService';
import { filterVisibleRecipesForRole } from '../core/rbac';
import { Recipe, RecipeIngredientLine, UserRole, Workspace, WorkspaceMember } from '../types/domain';

interface CalcTariffProfile {
  overheadPct: number;
  laborRateRub: string;
  ovenKw: number;
  kwhTariffRub: string;
  depreciationRub: string;
  rentPerOrderRub: string;
  acquiringPct: number;
  commissionPct: number;
  defectPct: number;
}

function loadSavedCalcProfile(workspaceId: string): Partial<CalcTariffProfile> {
  try {
    const raw = localStorage.getItem(`sweet_calc_profile_${workspaceId}`);
    return raw ? (JSON.parse(raw) as Partial<CalcTariffProfile>) : {};
  } catch {
    return {};
  }
}

export function RecipesPage({
  workspace,
  data,
  hideAmounts,
  userRole = 'owner',
  member = null,
  canEditRecipes = true,
  onOpenInCalculator,
  onToast,
}: {
  workspace: Workspace;
  data: WorkspaceSnapshot;
  hideAmounts: boolean;
  userRole?: UserRole;
  member?: WorkspaceMember | null;
  canEditRecipes?: boolean;
  onOpenInCalculator: (recipe: Recipe) => void;
  onToast: (msg: string) => void;
}) {
  const [categoryFilter, setCategoryFilter] = useState('Все');
  const [search, setSearch] = useState('');
  const [selectedRecipe, setSelectedRecipe] = useState<Recipe | null>(null);
  const [targetWeightGrams, setTargetWeightGrams] = useState<number>(2000);
  const [baseDiameter, setBaseDiameter] = useState<number>(18);
  const [targetDiameter, setTargetDiameter] = useState<number>(18);

  const [formOpen, setFormOpen] = useState(false);
  const [formMode, setFormMode] = useState<RecipeFormMode>('create');
  const [formSourceRecipe, setFormSourceRecipe] = useState<Recipe | null>(null);

  const roleVisibleRecipes = useMemo(
    () => filterVisibleRecipesForRole(data.recipes, userRole, member),
    [data.recipes, userRole, member],
  );

  const activeRecipe = useMemo(
    () =>
      selectedRecipe
        ? roleVisibleRecipes.find((r) => r.id === selectedRecipe.id) || selectedRecipe
        : null,
    [roleVisibleRecipes, selectedRecipe],
  );

  const categories = useMemo(() => {
    const set = new Set<string>(['Все', 'Торты', 'Капкейки', 'Десерты']);
    roleVisibleRecipes.forEach((r) => set.add(r.category));
    return Array.from(set);
  }, [roleVisibleRecipes]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return roleVisibleRecipes.filter((r) => {
      if (categoryFilter !== 'Все' && r.category !== categoryFilter) return false;
      if (q && !`${r.title} ${r.category}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [roleVisibleRecipes, categoryFilter, search]);

  const openDetail = (r: Recipe) => {
    setSelectedRecipe(r);
    setTargetWeightGrams(r.yieldGrams || 1000);
    const match = (r.formSize || '').match(/D\s*(\d{2})/i);
    const d = match ? Number(match[1]) : 18;
    setBaseDiameter(d);
    setTargetDiameter(d);
  };

  const openForm = (mode: RecipeFormMode, source?: Recipe | null) => {
    setFormMode(mode);
    setFormSourceRecipe(source || null);
    setFormOpen(true);
  };

  const scaleFactor = activeRecipe
    ? targetWeightGrams / Math.max(activeRecipe.yieldGrams || 1, 1)
    : 1;

  const handleToggleFav = async (r: Recipe, e: React.MouseEvent) => {
    e.stopPropagation();
    await updateWorkspaceEntity(workspace, 'recipes', r.id, {
      favorite: !r.favorite,
    });
  };

  const handleCreateOrderFromRecipe = async (r: Recipe) => {
    const ordId = newId('ord');
    const wiId = newId('wi');
    const num = `№${106 + data.orders.length}`;
    const scaledPrice = Math.round(r.recommendedPriceCents * scaleFactor);
    const scaledCost = Math.round(r.costCents * scaleFactor);
    const due = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);

    await createWorkspaceEntity(workspace, 'orders', ordId, {
      orderNumber: num,
      title: `${r.title} (${Math.round(targetWeightGrams)} г)`.slice(0, 160),
      clientName: 'Новый клиент',
      items: [
        {
          id: newId('item'),
          recipeId: r.id,
          recipeTitle: r.title.slice(0, 160),
          qty: 1,
          weightGrams: targetWeightGrams,
          priceCents: scaledPrice,
          costCents: scaledCost,
        },
      ],
      recipeId: r.id,
      recipeTitle: r.title,
      weightGrams: targetWeightGrams,
      priceCents: scaledPrice,
      costCents: scaledCost,
      prepaymentCents: Math.round(scaledPrice * 0.5),
      paidCents: 0,
      status: 'negotiation',
      dueDate: due,
      assigneeName: 'Владелец',
      locationName: data.locations[0]?.name || 'Основная студия',
      allergens: (r.allergens || []).join(', '),
      favorite: false,
    });
    await createWorkspaceEntity(workspace, 'workItems', wiId, {
      type: 'order',
      sourceId: ordId,
      title: `${num} · ${r.title}`,
      assigneeName: 'Владелец',
      locationName: data.locations[0]?.name || 'Основная студия',
      dueDate: due,
      priority: 'normal',
      stage: 'queue',
      tags: ['из рецепта'],
    });
    setSelectedRecipe(null);
    onToast(`Создан заказ ${num} на ${Math.round(targetWeightGrams)} г`);
  };

  const detailEdible = useMemo(
    () => (activeRecipe?.ingredients || []).filter((i) => !i.isPackaging),
    [activeRecipe],
  );
  const detailPackaging = useMemo(
    () => (activeRecipe?.ingredients || []).filter((i) => i.isPackaging),
    [activeRecipe],
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="Мои рецепты"
        subtitle="Фотографии, версии технологических карт, аллергены и пересчёт веса"
        action={
          canEditRecipes ? (
            <button
              type="button"
              onClick={() => openForm('create')}
              className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
            >
              + Рецепт
            </button>
          ) : undefined
        }
      />

      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-1.5">
          {categories.map((cat) => (
            <button
              key={cat}
              type="button"
              onClick={() => setCategoryFilter(cat)}
              className={`px-3.5 py-2 rounded-xl text-sm font-medium border transition-colors whitespace-nowrap shrink-0 ${
                categoryFilter === cat
                  ? 'border-[var(--accent)] bg-[var(--soft)]'
                  : 'border-[var(--line)] bg-[var(--card)] text-[var(--muted)]'
              }`}
            >
              {cat}
            </button>
          ))}
        </div>
        <input
          type="search"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Поиск по рецептам..."
          className="min-h-[42px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm sm:w-64"
        />
      </div>

      {filtered.length === 0 ? (
        <EmptyState
          title="Рецепты не найдены"
          description="Создайте первую технологическую карту или измените фильтр."
          actionLabel="+ Добавить рецепт"
          onAction={() => openForm('create')}
        />
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {filtered.map((r) => (
            <article
              key={r.id}
              onClick={() => openDetail(r)}
              className="rounded-2xl border border-[var(--line)] bg-[var(--card)] overflow-hidden cursor-pointer hover:border-[var(--accent)] transition-colors flex flex-col"
            >
              <ImageWithFallback
                src={r.photoUrl}
                alt={r.title}
                className="w-full h-48 object-cover"
              />
              <div className="p-4 flex-1 flex flex-col justify-between gap-3">
                <div>
                  <div className="flex items-center justify-between gap-2 text-xs text-[var(--muted)]">
                    <span>
                      {r.category} · v{r.version} ·{' '}
                      {r.status === 'approved'
                        ? 'Утверждена'
                        : r.status === 'review'
                          ? 'На проверке'
                          : r.status === 'archived'
                            ? 'Архив'
                            : 'Черновик'}
                    </span>
                    <button
                      type="button"
                      onClick={(e) => handleToggleFav(r, e)}
                      aria-label="В избранное"
                      className="p-1 rounded-lg hover:bg-[var(--soft)]"
                    >
                      <Star
                        className={`w-4 h-4 ${
                          r.favorite
                            ? 'fill-[var(--accent)] text-[var(--accent)]'
                            : 'text-[var(--muted)]'
                        }`}
                      />
                    </button>
                  </div>
                  <h3 className="mt-1.5 text-base font-semibold leading-snug">
                    {r.title}
                  </h3>
                </div>

                <div className="pt-3 border-t border-[var(--line)] flex items-center justify-between text-sm tabular-nums">
                  <span className="text-[var(--muted)]">
                    {r.yieldGrams} г · {r.formSize || `${r.yieldPortions || 8} порц.`}
                  </span>
                  <span className="font-semibold">
                    {formatMoneyCents(r.recommendedPriceCents, hideAmounts)}
                  </span>
                </div>
              </div>
            </article>
          ))}
        </div>
      )}

      {/* Recipe Detail & Dynamic Rescaling Drawer */}
      <Drawer
        open={Boolean(activeRecipe)}
        title={activeRecipe?.title || ''}
        subtitle={
          activeRecipe
            ? `${activeRecipe.category} · Версия v${activeRecipe.version} · Срок хранения ${activeRecipe.shelfLifeHours || 48} ч (${activeRecipe.storageCondition || '+2…+4 °C'})`
            : ''
        }
        onClose={() => setSelectedRecipe(null)}
      >
        {activeRecipe && (
          <div className="space-y-5">
            <ImageWithFallback
              src={activeRecipe.photoUrl}
              alt={activeRecipe.title}
              className="w-full h-48 object-cover rounded-xl"
            />

            {/* Gross vs Net & 100g Cost Strip */}
            <div className="grid grid-cols-3 gap-2 text-xs tabular-nums">
              <div className="p-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]">
                <div className="text-[var(--muted)]">Брутто / Нетто</div>
                <div className="font-semibold mt-0.5">
                  {activeRecipe.grossGrams
                    ? `${activeRecipe.grossGrams} → ${activeRecipe.yieldGrams} г`
                    : `${activeRecipe.yieldGrams} г`}
                </div>
              </div>
              <div className="p-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]">
                <div className="text-[var(--muted)]">Упёк / уварка</div>
                <div className="font-semibold mt-0.5">
                  {activeRecipe.grossGrams &&
                  activeRecipe.grossGrams > activeRecipe.yieldGrams
                    ? `${Math.round(((activeRecipe.grossGrams - activeRecipe.yieldGrams) / activeRecipe.grossGrams) * 1000) / 10}%`
                    : '0%'}
                </div>
              </div>
              <div className="p-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]">
                <div className="text-[var(--muted)]">Себ. 100 г</div>
                <div className="font-semibold mt-0.5">
                  {formatMoneyCents(
                    Math.round(
                      (activeRecipe.costCents / Math.max(activeRecipe.yieldGrams, 1)) * 100,
                    ),
                    hideAmounts,
                  )}
                </div>
              </div>
            </div>

            {/* Dynamic Weight & Diameter Scaling Control */}
            <div className="p-4 rounded-xl border border-[var(--line)] bg-[var(--soft)] space-y-3">
              <div className="flex items-center justify-between gap-3">
                <span className="text-sm font-semibold">Пересчёт выхода (вес, г)</span>
                <input
                  type="number"
                  min={100}
                  step={50}
                  value={targetWeightGrams}
                  onChange={(e) =>
                    setTargetWeightGrams(Math.max(1, Number(e.target.value) || 100))
                  }
                  className="w-28 min-h-[38px] px-2.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-right text-sm font-mono tabular-nums"
                />
              </div>
              <input
                type="range"
                min={300}
                max={6000}
                step={50}
                value={Math.min(6000, Math.max(300, targetWeightGrams))}
                onChange={(e) => setTargetWeightGrams(Number(e.target.value))}
                className="w-full accent-[var(--accent)]"
              />
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex flex-wrap gap-1.5">
                  {[1000, 1500, 2000, 3000, 4000].map((g) => (
                    <button
                      key={g}
                      type="button"
                      onClick={() => setTargetWeightGrams(g)}
                      className="px-2.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs tabular-nums"
                    >
                      {g} г
                    </button>
                  ))}
                </div>
                <div className="flex items-center gap-1.5 text-xs">
                  <span className="text-[var(--muted)]">Форма D:</span>
                  <select
                    value={baseDiameter}
                    onChange={(e) => setBaseDiameter(Number(e.target.value))}
                    className="px-1.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] tabular-nums"
                  >
                    {[14, 16, 18, 20, 22, 24, 26].map((d) => (
                      <option key={d} value={d}>
                        {d} см
                      </option>
                    ))}
                  </select>
                  <span>→</span>
                  <select
                    value={targetDiameter}
                    onChange={(e) => {
                      const nextD = Number(e.target.value);
                      setTargetDiameter(nextD);
                      const factor = Math.pow(nextD / Math.max(baseDiameter, 1), 2);
                      const nextGrams = Math.max(
                        100,
                        Math.round(((activeRecipe.yieldGrams || 1000) * factor) / 10) * 10,
                      );
                      setTargetWeightGrams(nextGrams);
                    }}
                    className="px-1.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] tabular-nums"
                  >
                    {[14, 16, 18, 20, 22, 24, 26].map((d) => (
                      <option key={d} value={d}>
                        {d} см
                      </option>
                    ))}
                  </select>
                </div>
              </div>
              <div className="flex justify-between text-sm pt-2 border-t border-[var(--line)] tabular-nums">
                <span>
                  Себестоимость:{' '}
                  <strong>
                    {formatMoneyCents(
                      Math.round(activeRecipe.costCents * scaleFactor),
                      hideAmounts,
                    )}
                  </strong>
                </span>
                <span>
                  Цена:{' '}
                  <strong>
                    {formatMoneyCents(
                      Math.round(activeRecipe.recommendedPriceCents * scaleFactor),
                      hideAmounts,
                    )}
                  </strong>
                </span>
              </div>
            </div>

            {/* Pack Variants Table */}
            {activeRecipe.packVariants && activeRecipe.packVariants.length > 0 && (
              <div>
                <h3 className="text-sm font-semibold pb-2 border-b border-[var(--line)]">
                  Варианты фасовки и наборов
                </h3>
                <div className="divide-y divide-[var(--line)] text-xs tabular-nums">
                  {activeRecipe.packVariants.map((pv) => (
                    <div key={pv.id} className="py-2 flex items-center justify-between gap-2">
                      <div>
                        <span className="font-medium text-sm">{pv.label}</span>
                        <span className="text-[var(--muted)] ml-2">
                          ({pv.qtyOrGrams} {pv.mode === 'grams' ? 'г' : 'шт'} · уп.{' '}
                          {formatMoneyCents(pv.packagingCents, hideAmounts)})
                        </span>
                      </div>
                      <span className="font-semibold text-sm">
                        {formatMoneyCents(pv.priceCents || 0, hideAmounts)}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Edible Ingredients + Warehouse Stock Check */}
            <div>
              <h3 className="text-sm font-semibold pb-2 border-b border-[var(--line)]">
                Ингредиенты (с пересчётом ×{scaleFactor.toFixed(2)})
              </h3>
              <div className="divide-y divide-[var(--line)] text-sm">
                {detailEdible.map((ing, i) => {
                  const needed = ing.qty * scaleFactor;
                  const inv = ing.itemId
                    ? data.inventoryItems.find((x) => x.id === ing.itemId)
                    : data.inventoryItems.find(
                        (x) => x.name.toLowerCase() === ing.name.toLowerCase(),
                      );
                  let stockBadge: string | null = null;
                  let shortage = false;
                  if (inv) {
                    const neededInInvUnit = convertQtyWithDensity(
                      needed,
                      ing.unit,
                      inv.unit,
                      inv.density,
                    );
                    if (neededInInvUnit !== null) {
                      shortage = inv.qtyOnHand + 1e-6 < neededInInvUnit;
                      stockBadge = shortage
                        ? `на складе ${formatQty(inv.qtyOnHand, inv.unit)} (не хватает)`
                        : `на складе ${formatQty(inv.qtyOnHand, inv.unit)}`;
                    }
                  }
                  return (
                    <div key={i} className="py-2 flex items-center justify-between gap-2">
                      <div>
                        <div>{ing.name}</div>
                        {stockBadge && (
                          <div
                            className={`text-[11px] ${
                              shortage ? 'text-[var(--danger)]' : 'text-[var(--muted)]'
                            }`}
                          >
                            {stockBadge}
                          </div>
                        )}
                      </div>
                      <span className="tabular-nums font-medium shrink-0">
                        {formatQty(needed, ing.unit)}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>

            {detailPackaging.length > 0 && (
              <div>
                <h3 className="text-sm font-semibold pb-2 border-b border-[var(--line)] flex items-center gap-1.5">
                  <Package className="w-3.5 h-3.5 text-[var(--muted)]" />
                  <span>Упаковка и расходники</span>
                </h3>
                <div className="divide-y divide-[var(--line)] text-sm">
                  {detailPackaging.map((ing, i) => (
                    <div key={i} className="py-2 flex items-center justify-between gap-2">
                      <span>{ing.name}</span>
                      <span className="tabular-nums font-medium">
                        {formatQty(ing.qty * scaleFactor, ing.unit)}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Steps */}
            {activeRecipe.steps && activeRecipe.steps.length > 0 && (
              <div>
                <h3 className="text-sm font-semibold pb-2 border-b border-[var(--line)]">
                  Технология приготовления
                </h3>
                <ol className="mt-2 space-y-2 text-sm list-decimal list-inside text-[var(--muted)]">
                  {activeRecipe.steps.map((s, idx) => (
                    <li key={idx} className="text-[var(--ink)]">
                      {s}
                    </li>
                  ))}
                </ol>
              </div>
            )}

            {/* Allergens */}
            {activeRecipe.allergens && activeRecipe.allergens.length > 0 && (
              <div className="text-xs text-[var(--muted)]">
                Аллергены (требуется проверка перекрёстного контакта):{' '}
                <span className="text-[var(--ink)] font-medium">
                  {activeRecipe.allergens.join(', ')}
                </span>
              </div>
            )}

            <div className="pt-4 border-t border-[var(--line)] grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => handleCreateOrderFromRecipe(activeRecipe)}
                className="col-span-2 min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap"
              >
                Создать заказ ({Math.round(targetWeightGrams)} г)
              </button>
              {canEditRecipes && (
                <>
                  <button
                    type="button"
                    onClick={() => openForm('edit', activeRecipe)}
                    className="min-h-[42px] px-3 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium inline-flex items-center justify-center gap-1.5 hover:bg-[var(--soft)]"
                  >
                    <Pencil className="w-3.5 h-3.5" />
                    <span>Редактировать</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => openForm('version', activeRecipe)}
                    className="min-h-[42px] px-3 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium inline-flex items-center justify-center gap-1.5 hover:bg-[var(--soft)]"
                  >
                    <CopyPlus className="w-3.5 h-3.5" />
                    <span>Новая версия v{activeRecipe.version + 1}</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => openForm('variation', activeRecipe)}
                    className="min-h-[42px] px-3 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium inline-flex items-center justify-center gap-1.5 hover:bg-[var(--soft)]"
                  >
                    <Sparkles className="w-3.5 h-3.5" />
                    <span>Вариация вкуса</span>
                  </button>
                </>
              )}
              <button
                type="button"
                onClick={() => {
                  const r = activeRecipe;
                  setSelectedRecipe(null);
                  onOpenInCalculator(r);
                }}
                className="min-h-[42px] px-3 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium hover:bg-[var(--soft)]"
              >
                В калькулятор
              </button>
              <button
                type="button"
                onClick={() => window.print()}
                className="col-span-2 min-h-[42px] px-3 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium inline-flex items-center justify-center gap-1.5 hover:bg-[var(--soft)]"
              >
                <Printer className="w-3.5 h-3.5" />
                <span>Печать техкарты</span>
              </button>
            </div>
          </div>
        )}
      </Drawer>

      <RecipeFormDrawer
        open={formOpen}
        mode={formMode}
        sourceRecipe={formSourceRecipe}
        workspace={workspace}
        data={data}
        onClose={() => setFormOpen(false)}
        onToast={onToast}
      />
    </div>
  );
}

interface CalcRow extends RecipeIngredientLine {
  id: string;
}

export function CalculatorPage({
  workspace,
  data,
  initialRecipe,
  hideAmounts,
  onToast,
}: {
  workspace: Workspace;
  data: WorkspaceSnapshot;
  initialRecipe: Recipe | null;
  hideAmounts: boolean;
  onToast: (msg: string) => void;
}) {
  const savedProfile = useMemo(
    () => loadSavedCalcProfile(workspace.id),
    [workspace.id],
  );

  const [selectedRecipeId, setSelectedRecipeId] = useState<string>(
    initialRecipe?.id || data.recipes[0]?.id || '',
  );
  const [matrixMode, setMatrixMode] = useState(false);
  const [matrixFilter, setMatrixFilter] = useState('');

  const [rows, setRows] = useState<CalcRow[]>(() => {
    const src = initialRecipe || data.recipes[0];
    if (src?.ingredients?.length) {
      return src.ingredients.map((ing, i) => ({
        ...ing,
        isPackaging: Boolean(
          ing.isPackaging || ing.unit === 'шт' || ing.unit === 'упак',
        ),
        id: `row_${i}`,
      }));
    }
    return [
      {
        id: 'row_0',
        name: 'Сливочный сыр',
        qty: 600,
        unit: 'г',
        lossPercent: 3,
        priceCents: 95000,
        priceUnit: 'за кг',
        isPackaging: false,
      },
      {
        id: 'row_1',
        name: 'Сливки 33%',
        qty: 400,
        unit: 'мл',
        lossPercent: 2,
        priceCents: 68000,
        priceUnit: 'за л',
        isPackaging: false,
      },
    ];
  });

  const [laborHours, setLaborHours] = useState<number>(initialRecipe?.laborHours ?? 2);
  const [laborRateRub, setLaborRateRub] = useState<string>(
    initialRecipe?.laborRateCents !== undefined
      ? centsToRubInput(initialRecipe.laborRateCents)
      : savedProfile.laborRateRub || '650',
  );
  const [packagingRub, setPackagingRub] = useState<string>(
    centsToRubInput(initialRecipe?.packagingCents ?? 25000),
  );
  const [shippingRub, setShippingRub] = useState<string>('0');
  const [overheadPct, setOverheadPct] = useState<number>(
    initialRecipe?.overheadPercent ?? savedProfile.overheadPct ?? 12,
  );
  const [defectPct, setDefectPct] = useState<number>(savedProfile.defectPct ?? 2);
  const [acquiringPct, setAcquiringPct] = useState<number>(
    savedProfile.acquiringPct ?? 2.2,
  );
  const [commissionPct, setCommissionPct] = useState<number>(
    savedProfile.commissionPct ?? 0,
  );

  // Resources, utility tariffs & rent
  const [showResources, setShowResources] = useState(false);
  const [ovenKw, setOvenKw] = useState<number>(savedProfile.ovenKw ?? 2.5);
  const [ovenHours, setOvenHours] = useState<number>(1.2);
  const [kwhTariffRub, setKwhTariffRub] = useState<string>(
    savedProfile.kwhTariffRub || '6.5',
  );
  const [depreciationRub, setDepreciationRub] = useState<string>(
    savedProfile.depreciationRub || '60',
  );
  const [rentPerOrderRub, setRentPerOrderRub] = useState<string>(
    savedProfile.rentPerOrderRub || '0',
  );

  const [pricingMode, setPricingMode] = useState<PricingMode>('markup');
  const [marginPct, setMarginPct] = useState<number>(
    initialRecipe?.marginPercent ?? 65,
  );
  const [targetMarginPct, setTargetMarginPct] = useState<number>(38);
  const [fixedPriceRub, setFixedPriceRub] = useState<string>('4500');
  const [yieldGrams, setYieldGrams] = useState<number>(
    initialRecipe?.yieldGrams ?? 2000,
  );
  const [yieldPortions, setYieldPortions] = useState<number>(
    initialRecipe?.yieldPortions ?? 8,
  );
  const [savingRecipe, setSavingRecipe] = useState(false);

  // Persist user's tariff/resource profile per workspace in localStorage
  useEffect(() => {
    try {
      const profile: CalcTariffProfile = {
        overheadPct,
        laborRateRub,
        ovenKw,
        kwhTariffRub,
        depreciationRub,
        rentPerOrderRub,
        acquiringPct,
        commissionPct,
        defectPct,
      };
      localStorage.setItem(
        `sweet_calc_profile_${workspace.id}`,
        JSON.stringify(profile),
      );
    } catch {
      // ignore quota errors
    }
  }, [
    workspace.id,
    overheadPct,
    laborRateRub,
    ovenKw,
    kwhTariffRub,
    depreciationRub,
    rentPerOrderRub,
    acquiringPct,
    commissionPct,
    defectPct,
  ]);

  useEffect(() => {
    if (!initialRecipe) return;
    setSelectedRecipeId(initialRecipe.id);
    if (initialRecipe.ingredients?.length) {
      setRows(
        initialRecipe.ingredients.map((ing, i) => ({
          ...ing,
          isPackaging: Boolean(
            ing.isPackaging || ing.unit === 'шт' || ing.unit === 'упак',
          ),
          id: `r_${i}`,
        })),
      );
    }
    setLaborHours(initialRecipe.laborHours ?? 2);
    setLaborRateRub(centsToRubInput(initialRecipe.laborRateCents ?? 65000));
    setPackagingRub(centsToRubInput(initialRecipe.packagingCents ?? 25000));
    setOverheadPct(initialRecipe.overheadPercent ?? 12);
    setMarginPct(initialRecipe.marginPercent ?? 65);
    setYieldGrams(initialRecipe.yieldGrams ?? 2000);
    setYieldPortions(initialRecipe.yieldPortions ?? 8);
  }, [initialRecipe]);

  const loadFromRecipe = (id: string) => {
    setSelectedRecipeId(id);
    const rec = data.recipes.find((r) => r.id === id);
    if (!rec) return;
    if (rec.ingredients?.length) {
      setRows(
        rec.ingredients.map((ing, i) => ({
          ...ing,
          isPackaging: Boolean(
            ing.isPackaging || ing.unit === 'шт' || ing.unit === 'упак',
          ),
          id: `rec_${i}_${Date.now()}`,
        })),
      );
    }
    setLaborHours(rec.laborHours ?? 2);
    setLaborRateRub(centsToRubInput(rec.laborRateCents ?? 65000));
    setPackagingRub(centsToRubInput(rec.packagingCents ?? 25000));
    setOverheadPct(rec.overheadPercent ?? 12);
    setMarginPct(rec.marginPercent ?? 65);
    setYieldGrams(rec.yieldGrams ?? 2000);
    setYieldPortions(rec.yieldPortions ?? 8);
  };

  const applyProfile = (profile: 'home' | 'studio' | 'marketplace') => {
    if (profile === 'home') {
      setOverheadPct(8);
      setRentPerOrderRub('0');
      setDepreciationRub('35');
      setAcquiringPct(0);
      setCommissionPct(0);
      setDefectPct(1);
      onToast('Профиль: Домашняя кухня');
    } else if (profile === 'studio') {
      setOverheadPct(12);
      setRentPerOrderRub('250');
      setDepreciationRub('90');
      setAcquiringPct(2.2);
      setCommissionPct(0);
      setDefectPct(2);
      onToast('Профиль: Кондитерская студия');
    } else {
      setOverheadPct(12);
      setRentPerOrderRub('250');
      setDepreciationRub('90');
      setAcquiringPct(2.2);
      setCommissionPct(15);
      setDefectPct(3);
      onToast('Профиль: Витрина / агрегатор');
    }
  };

  const setMatrixQuantityForInv = (itemId: string, qty: number) => {
    const item = data.inventoryItems.find((i) => i.id === itemId);
    if (!item) return;
    const cleanQty = Math.max(0, qty);
    setRows((prev) => {
      const idx = prev.findIndex(
        (r) =>
          r.itemId === item.id ||
          (!r.itemId && r.name.toLowerCase() === item.name.toLowerCase()),
      );
      if (cleanQty <= 0) {
        return idx >= 0 ? prev.filter((_, i) => i !== idx) : prev;
      }
      if (idx >= 0) {
        return prev.map((r, i) => (i === idx ? { ...r, qty: cleanQty } : r));
      }
      const u = item.unit === 'кг' ? 'г' : item.unit === 'л' ? 'мл' : item.unit;
      const pu = defaultPriceUnit(item.unit);
      const isPack = item.kind === 'packaging' || u === 'шт' || u === 'упак';
      return [
        ...prev,
        {
          id: `mtx_${item.id}_${Date.now()}`,
          itemId: item.id,
          name: item.name,
          qty: cleanQty,
          unit: u,
          lossPercent: isPack ? 0 : 2,
          priceCents: item.avgCostCents,
          priceUnit: priceUnitsFor(u).includes(pu) ? pu : priceUnitsFor(u)[0],
          isPackaging: isPack,
        },
      ];
    });
  };

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
        const g = convertQty(r.qty, r.unit, 'г');
        if (g !== null) {
          gross += g;
        } else if (r.unit === 'мл' || r.unit === 'л') {
          const inv = r.itemId
            ? data.inventoryItems.find((i) => i.id === r.itemId)
            : undefined;
          const bg = convertQtyWithDensity(r.qty, r.unit, 'г', inv?.density || 1);
          if (bg !== null) gross += bg;
        }
      }
    }
    return {
      edibleMaterialsCents: edible,
      packagingMaterialsCents: pack,
      grossGrams: Math.round(gross),
    };
  }, [rows, data.inventoryItems]);

  const electricityCents = useMemo(() => {
    const tariffCents = parseRubToCents(kwhTariffRub);
    return Math.max(0, Math.round(ovenKw * ovenHours * tariffCents));
  }, [ovenKw, ovenHours, kwhTariffRub]);

  const otherResourcesCents =
    electricityCents + parseRubToCents(depreciationRub);

  const totals = useMemo(
    () =>
      computeCalculatorTotals({
        materialsCents: edibleMaterialsCents,
        laborHours,
        laborRateCents: parseRubToCents(laborRateRub),
        otherCents: otherResourcesCents,
        overheadPercent: overheadPct,
        overheadFixedCents: parseRubToCents(rentPerOrderRub),
        marginPercent: marginPct,
        pricingMode,
        targetMarginPercent: targetMarginPct,
        fixedPriceCents: parseRubToCents(fixedPriceRub),
        packagingCents: parseRubToCents(packagingRub) + packagingMaterialsCents,
        shippingCents: parseRubToCents(shippingRub),
        acquiringPercent: acquiringPct,
        commissionPercent: commissionPct,
        finishedDefectPercent: defectPct,
      }),
    [
      edibleMaterialsCents,
      packagingMaterialsCents,
      laborHours,
      laborRateRub,
      otherResourcesCents,
      overheadPct,
      rentPerOrderRub,
      marginPct,
      pricingMode,
      targetMarginPct,
      fixedPriceRub,
      packagingRub,
      shippingRub,
      acquiringPct,
      commissionPct,
      defectPct,
    ],
  );

  const perKgCents =
    yieldGrams > 0 ? Math.round((totals.priceCents / yieldGrams) * 1000) : 0;
  const costPer100gCents =
    yieldGrams > 0 ? Math.round((totals.productionCostCents / yieldGrams) * 100) : 0;

  const selectedRecipe = useMemo(
    () => data.recipes.find((r) => r.id === selectedRecipeId),
    [data.recipes, selectedRecipeId],
  );

  const packComparisons = useMemo(() => {
    const markupMultiplier =
      totals.costCents > 0 && totals.priceCents > 0
        ? totals.priceCents / totals.costCents
        : 1 + Math.max(0, marginPct) / 100;

    if (selectedRecipe?.packVariants && selectedRecipe.packVariants.length > 0) {
      return selectedRecipe.packVariants.map((pv) => {
        const ratio =
          pv.mode === 'grams'
            ? pv.qtyOrGrams / Math.max(yieldGrams, 1)
            : pv.qtyOrGrams / Math.max(yieldPortions || 1, 1);
        const cost =
          Math.round(totals.productionCostCents * ratio) + (pv.packagingCents || 0);
        const price = Math.round(cost * markupMultiplier);
        return { label: pv.label, cost, price };
      });
    }
    const perPortionCost = Math.round(
      totals.productionCostCents / Math.max(yieldPortions || 1, 1),
    );
    return [
      {
        label: '100 г нетто',
        cost: costPer100gCents,
        price: Math.round(costPer100gCents * markupMultiplier),
      },
      {
        label: '1 порция (без коробки)',
        cost: perPortionCost,
        price: Math.round(perPortionCost * markupMultiplier),
      },
      {
        label: 'Набор 5 шт (+коробка 90 ₽)',
        cost: perPortionCost * 5 + 9000,
        price: Math.round((perPortionCost * 5 + 9000) * markupMultiplier),
      },
      {
        label: 'Набор 8 шт (+коробка 120 ₽)',
        cost: perPortionCost * 8 + 12000,
        price: Math.round((perPortionCost * 8 + 12000) * markupMultiplier),
      },
    ];
  }, [
    selectedRecipe,
    totals.productionCostCents,
    totals.costCents,
    totals.priceCents,
    marginPct,
    yieldGrams,
    yieldPortions,
    costPer100gCents,
  ]);

  const handleSaveToRecipe = async () => {
    const rec = data.recipes.find((r) => r.id === selectedRecipeId);
    if (!rec || savingRecipe) return;
    setSavingRecipe(true);
    try {
      const cleanIngredients: RecipeIngredientLine[] = rows
        .filter((r) => r.name.trim())
        .map((r) => {
          const line: RecipeIngredientLine = {
            name: r.name.trim().slice(0, 120),
            qty: Number(r.qty) || 0,
            unit: r.unit,
            lossPercent: Math.max(0, Math.min(99, Number(r.lossPercent) || 0)),
            priceCents: Math.max(0, Math.round(r.priceCents)),
            priceUnit: r.priceUnit,
            isPackaging: Boolean(r.isPackaging),
          };
          if (r.itemId) line.itemId = r.itemId;
          if (r.subRecipeId) line.subRecipeId = r.subRecipeId;
          return line;
        });

      await updateWorkspaceEntity(workspace, 'recipes', rec.id, {
        yieldGrams: Math.max(1, Math.round(yieldGrams)),
        grossGrams: Math.max(0, grossGrams),
        yieldPortions: Math.max(1, Math.round(yieldPortions)),
        ingredients: cleanIngredients,
        laborHours,
        laborRateCents: parseRubToCents(laborRateRub),
        packagingCents: parseRubToCents(packagingRub),
        overheadPercent: overheadPct,
        marginPercent: marginPct,
        costCents: Math.max(0, totals.costCents),
        recommendedPriceCents: Math.max(0, totals.priceCents),
      });
      onToast(`Расчёт сохранён в рецепт «${rec.title}»`);
    } finally {
      setSavingRecipe(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Калькулятор себестоимости"
        subtitle="Сырьё с потерями, труд, электричество, аренда, комиссии, наборы и ROI (тарифы сохраняются автоматически)"
        action={
          data.recipes.length > 0 && (
            <select
              aria-label="Загрузить из рецепта"
              value={selectedRecipeId}
              onChange={(e) => loadFromRecipe(e.target.value)}
              className="min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
            >
              <option value="">Загрузить из рецепта...</option>
              {data.recipes.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.title}
                </option>
              ))}
            </select>
          )
        }
      />

      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs text-[var(--muted)] mr-1">Профили тарифов:</span>
        <button
          type="button"
          onClick={() => applyProfile('home')}
          className="px-3 py-1.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs font-medium hover:bg-[var(--soft)]"
        >
          Домашняя кухня
        </button>
        <button
          type="button"
          onClick={() => applyProfile('studio')}
          className="px-3 py-1.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs font-medium hover:bg-[var(--soft)]"
        >
          Студия / цех
        </button>
        <button
          type="button"
          onClick={() => applyProfile('marketplace')}
          className="px-3 py-1.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs font-medium hover:bg-[var(--soft)]"
        >
          Витрина / агрегатор
        </button>
      </div>

      <div className="grid lg:grid-cols-3 gap-6 items-start">
        <div className="lg:col-span-2 space-y-6">
          {/* Ingredients / Resources */}
          <Card>
            <div className="flex flex-wrap items-center justify-between gap-2 pb-3 border-b border-[var(--line)]">
              <h2 className="text-base font-semibold">Сырьё и ингредиенты</h2>
              <div className="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={() => setMatrixMode((v) => !v)}
                  className={`px-3 py-1.5 rounded-lg border text-xs font-medium inline-flex items-center gap-1 ${
                    matrixMode
                      ? 'border-[var(--accent)] bg-[var(--soft)]'
                      : 'border-[var(--line)] hover:bg-[var(--soft)]'
                  }`}
                >
                  <Table2 className="w-3.5 h-3.5" />
                  <span>{matrixMode ? 'Режим списка' : 'Матрица из справочника'}</span>
                </button>
                {!matrixMode && data.inventoryItems.length > 0 && (
                  <select
                    value=""
                    aria-label="Добавить из кладовой"
                    onChange={(e) => {
                      const item = data.inventoryItems.find((x) => x.id === e.target.value);
                      if (!item) return;
                      const u = item.unit === 'кг' ? 'г' : item.unit === 'л' ? 'мл' : item.unit;
                      const pu = defaultPriceUnit(item.unit);
                      const isPack =
                        item.kind === 'packaging' || u === 'шт' || u === 'упак';
                      setRows((prev) => [
                        ...prev,
                        {
                          id: `inv_${Date.now()}`,
                          itemId: item.id,
                          name: item.name,
                          qty: u === 'шт' || u === 'упак' ? 1 : 200,
                          unit: u,
                          lossPercent: isPack ? 0 : 2,
                          priceCents: item.avgCostCents,
                          priceUnit: priceUnitsFor(u).includes(pu)
                            ? pu
                            : priceUnitsFor(u)[0],
                          isPackaging: isPack,
                        },
                      ]);
                    }}
                    className="min-h-[34px] px-2.5 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-xs"
                  >
                    <option value="">+ Из Кладовой...</option>
                    {data.inventoryItems.map((i) => (
                      <option key={i.id} value={i.id}>
                        {i.name}
                      </option>
                    ))}
                  </select>
                )}
                {!matrixMode && (
                  <button
                    type="button"
                    onClick={() =>
                      setRows((prev) => [
                        ...prev,
                        {
                          id: `row_${Date.now()}`,
                          name: 'Новый ингредиент',
                          qty: 100,
                          unit: 'г',
                          lossPercent: 0,
                          priceCents: 50000,
                          priceUnit: 'за кг',
                          isPackaging: false,
                        },
                      ])
                    }
                    className="px-3 py-1.5 rounded-lg border border-[var(--line)] text-xs font-medium inline-flex items-center gap-1 hover:bg-[var(--soft)]"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Добавить строку</span>
                  </button>
                )}
              </div>
            </div>

            {matrixMode ? (
              <div className="mt-3 space-y-3">
                <input
                  type="search"
                  value={matrixFilter}
                  onChange={(e) => setMatrixFilter(e.target.value)}
                  placeholder="Быстрый фильтр справочника..."
                  className="w-full min-h-[38px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-xs"
                />
                <div className="max-h-72 overflow-y-auto rounded-xl border border-[var(--line)]">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b border-[var(--line)] text-[var(--muted)]">
                        <th className="text-left px-3 py-2 font-medium">Позиция</th>
                        <th className="text-right px-3 py-2 font-medium">Цена</th>
                        <th className="text-right px-3 py-2 font-medium w-32">Кол-во</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-[var(--line)]">
                      {data.inventoryItems
                        .filter(
                          (i) =>
                            !matrixFilter.trim() ||
                            i.name.toLowerCase().includes(matrixFilter.trim().toLowerCase()),
                        )
                        .map((item) => {
                          const u =
                            item.unit === 'кг' ? 'г' : item.unit === 'л' ? 'мл' : item.unit;
                          const matched = rows.find(
                            (r) =>
                              r.itemId === item.id ||
                              (!r.itemId && r.name.toLowerCase() === item.name.toLowerCase()),
                          );
                          return (
                            <tr key={item.id}>
                              <td className="px-3 py-2 font-medium">{item.name}</td>
                              <td className="px-3 py-2 text-right tabular-nums text-[var(--muted)]">
                                {formatMoneyCents(item.avgCostCents, hideAmounts)}/{item.unit}
                              </td>
                              <td className="px-3 py-2 text-right">
                                <div className="inline-flex items-center gap-1 justify-end">
                                  <input
                                    type="number"
                                    min={0}
                                    step="any"
                                    value={matched ? matched.qty : ''}
                                    placeholder="0"
                                    onChange={(e) =>
                                      setMatrixQuantityForInv(
                                        item.id,
                                        Number(e.target.value) || 0,
                                      )
                                    }
                                    className="w-20 min-h-[32px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-right tabular-nums"
                                  />
                                  <span className="text-[var(--muted)] w-6 text-left">{u}</span>
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
              <div className="mt-3 space-y-3">
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
                      key={row.id}
                      className="grid grid-cols-12 gap-2 items-center p-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                    >
                      <input
                        type="text"
                        value={row.name}
                        onChange={(e) =>
                          setRows((prev) =>
                            prev.map((x) =>
                              x.id === row.id ? { ...x, name: e.target.value } : x,
                            ),
                          )
                        }
                        className="col-span-12 sm:col-span-4 min-h-[38px] px-2.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-sm"
                      />
                      <input
                        type="number"
                        min={0}
                        step="any"
                        value={row.qty}
                        onChange={(e) =>
                          setRows((prev) =>
                            prev.map((x) =>
                              x.id === row.id
                                ? { ...x, qty: Number(e.target.value) || 0 }
                                : x,
                            ),
                          )
                        }
                        aria-label="Количество"
                        className="col-span-4 sm:col-span-2 min-h-[38px] px-2 rounded-lg border border-[var(--line)] bg-[var(--card)] text-sm tabular-nums"
                      />
                      <select
                        value={row.unit}
                        onChange={(e) => {
                          const nextUnit = e.target.value;
                          const nextPriceUnits = priceUnitsFor(nextUnit);
                          setRows((prev) =>
                            prev.map((x) =>
                              x.id === row.id
                                ? {
                                    ...x,
                                    unit: nextUnit,
                                    priceUnit: nextPriceUnits.includes(x.priceUnit)
                                      ? x.priceUnit
                                      : nextPriceUnits[0],
                                  }
                                : x,
                            ),
                          );
                        }}
                        className="col-span-4 sm:col-span-1 min-h-[38px] px-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs"
                      >
                        {QTY_UNITS.map((u) => (
                          <option key={u} value={u}>
                            {u}
                          </option>
                        ))}
                      </select>
                      <input
                        type="number"
                        min={0}
                        max={99}
                        value={row.lossPercent}
                        onChange={(e) =>
                          setRows((prev) =>
                            prev.map((x) =>
                              x.id === row.id
                                ? { ...x, lossPercent: Number(e.target.value) || 0 }
                                : x,
                            ),
                          )
                        }
                        title="Потери, %"
                        aria-label="Потери в процентах"
                        className="col-span-4 sm:col-span-1 min-h-[38px] px-1.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs tabular-nums"
                      />
                      <input
                        type="text"
                        value={centsToRubInput(row.priceCents)}
                        onChange={(e) =>
                          setRows((prev) =>
                            prev.map((x) =>
                              x.id === row.id
                                ? { ...x, priceCents: parseRubToCents(e.target.value) }
                                : x,
                            ),
                          )
                        }
                        aria-label="Цена закупки"
                        className="col-span-5 sm:col-span-2 min-h-[38px] px-2 rounded-lg border border-[var(--line)] bg-[var(--card)] text-sm tabular-nums"
                      />
                      <select
                        value={row.priceUnit}
                        onChange={(e) =>
                          setRows((prev) =>
                            prev.map((x) =>
                              x.id === row.id ? { ...x, priceUnit: e.target.value } : x,
                            ),
                          )
                        }
                        className="col-span-4 sm:col-span-1 min-h-[38px] px-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs"
                      >
                        {pUnits.map((u) => (
                          <option key={u} value={u}>
                            {u}
                          </option>
                        ))}
                      </select>
                      <div className="col-span-3 sm:col-span-1 flex items-center justify-end gap-1">
                        <button
                          type="button"
                          onClick={() =>
                            setRows((prev) =>
                              prev.map((x) =>
                                x.id === row.id
                                  ? { ...x, isPackaging: !x.isPackaging }
                                  : x,
                              ),
                            )
                          }
                          title={row.isPackaging ? 'Упаковка' : 'Съедобное сырьё'}
                          className={`p-1 rounded ${
                            row.isPackaging
                              ? 'text-[var(--accent)] bg-[var(--soft)]'
                              : 'text-[var(--muted)]'
                          }`}
                        >
                          <Package className="w-3.5 h-3.5" />
                        </button>
                        <span className="text-xs font-semibold tabular-nums hidden xl:inline">
                          {formatMoneyCents(lineCents, hideAmounts)}
                        </span>
                        <button
                          type="button"
                          onClick={() =>
                            setRows((prev) => prev.filter((x) => x.id !== row.id))
                          }
                          aria-label="Удалить строку"
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

            <div className="mt-3 pt-2.5 border-t border-[var(--line)] flex flex-wrap justify-between gap-2 text-xs text-[var(--muted)] tabular-nums">
              <span>Масса брутто (съедобное): {grossGrams} г</span>
              <span>
                Сырьё: {formatMoneyCents(edibleMaterialsCents, hideAmounts)}
                {packagingMaterialsCents > 0
                  ? ` + расходники ${formatMoneyCents(packagingMaterialsCents, hideAmounts)}`
                  : ''}
              </span>
            </div>
          </Card>

          {/* Labor, Packaging, Overhead, Fees */}
          <Card>
            <h2 className="text-base font-semibold pb-3 border-b border-[var(--line)]">
              Труд, упаковка, логистика и комиссии
            </h2>
            <div className="mt-4 grid sm:grid-cols-3 gap-4 text-sm">
              <label className="space-y-1">
                <span className="font-medium">Труд, часов</span>
                <input
                  type="number"
                  min={0}
                  step={0.25}
                  value={laborHours}
                  onChange={(e) => setLaborHours(Number(e.target.value) || 0)}
                  className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
              <label className="space-y-1">
                <span className="font-medium">Ставка труда, ₽/ч</span>
                <input
                  type="text"
                  value={laborRateRub}
                  onChange={(e) => setLaborRateRub(e.target.value)}
                  className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
              <label className="space-y-1">
                <span className="font-medium">Упаковка и лента, ₽</span>
                <input
                  type="text"
                  value={packagingRub}
                  onChange={(e) => setPackagingRub(e.target.value)}
                  className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
              <label className="space-y-1">
                <span className="font-medium">Накладные, %</span>
                <input
                  type="number"
                  min={0}
                  max={100}
                  value={overheadPct}
                  onChange={(e) => setOverheadPct(Number(e.target.value) || 0)}
                  className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
              <label className="space-y-1">
                <span className="font-medium">Риск брака, %</span>
                <input
                  type="number"
                  min={0}
                  max={99}
                  value={defectPct}
                  onChange={(e) => setDefectPct(Number(e.target.value) || 0)}
                  className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
              <label className="space-y-1">
                <span className="font-medium">Эквайринг, %</span>
                <input
                  type="number"
                  min={0}
                  max={99}
                  step={0.1}
                  value={acquiringPct}
                  onChange={(e) => setAcquiringPct(Number(e.target.value) || 0)}
                  className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
              <label className="space-y-1">
                <span className="font-medium">Доставка, ₽</span>
                <input
                  type="text"
                  value={shippingRub}
                  onChange={(e) => setShippingRub(e.target.value)}
                  className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
              <label className="space-y-1">
                <span className="font-medium">Комиссия площадки, %</span>
                <input
                  type="number"
                  min={0}
                  max={99}
                  step={0.5}
                  value={commissionPct}
                  onChange={(e) => setCommissionPct(Number(e.target.value) || 0)}
                  className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
              <div className="grid grid-cols-2 gap-2">
                <label className="space-y-1">
                  <span className="font-medium">Выход, г</span>
                  <input
                    type="number"
                    min={1}
                    value={yieldGrams}
                    onChange={(e) => setYieldGrams(Number(e.target.value) || 1000)}
                    className="w-full min-h-[42px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                  />
                </label>
                <label className="space-y-1">
                  <span className="font-medium">Порций</span>
                  <input
                    type="number"
                    min={1}
                    value={yieldPortions}
                    onChange={(e) => setYieldPortions(Number(e.target.value) || 1)}
                    className="w-full min-h-[42px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                  />
                </label>
              </div>
            </div>
          </Card>

          {/* Utilities, equipment & rent */}
          <Card>
            <button
              type="button"
              onClick={() => setShowResources((v) => !v)}
              className="w-full flex items-center justify-between text-left"
            >
              <div>
                <h2 className="text-base font-semibold">
                  Ресурсы, оборудование и аренда
                </h2>
                <p className="text-xs text-[var(--muted)]">
                  Электроэнергия ({formatMoneyCents(electricityCents, hideAmounts)}), амортизация и распределённая аренда
                </p>
              </div>
              <span className="text-xs font-medium text-[var(--accent)]">
                {showResources ? 'Свернуть' : 'Настроить'}
              </span>
            </button>
            {showResources && (
              <div className="mt-4 pt-4 border-t border-[var(--line)] grid sm:grid-cols-5 gap-3 text-sm">
                <label className="space-y-1">
                  <span className="text-xs font-medium">Мощность, кВт</span>
                  <input
                    type="number"
                    min={0}
                    step={0.1}
                    value={ovenKw}
                    onChange={(e) => setOvenKw(Number(e.target.value) || 0)}
                    className="w-full min-h-[40px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                  />
                </label>
                <label className="space-y-1">
                  <span className="text-xs font-medium">Время, ч</span>
                  <input
                    type="number"
                    min={0}
                    step={0.1}
                    value={ovenHours}
                    onChange={(e) => setOvenHours(Number(e.target.value) || 0)}
                    className="w-full min-h-[40px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                  />
                </label>
                <label className="space-y-1">
                  <span className="text-xs font-medium">Тариф, ₽/кВт·ч</span>
                  <input
                    type="text"
                    value={kwhTariffRub}
                    onChange={(e) => setKwhTariffRub(e.target.value)}
                    className="w-full min-h-[40px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                  />
                </label>
                <label className="space-y-1">
                  <span className="text-xs font-medium">Амортизация, ₽</span>
                  <input
                    type="text"
                    value={depreciationRub}
                    onChange={(e) => setDepreciationRub(e.target.value)}
                    className="w-full min-h-[40px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                  />
                </label>
                <label className="space-y-1">
                  <span className="text-xs font-medium">Аренда/заказ, ₽</span>
                  <input
                    type="text"
                    value={rentPerOrderRub}
                    onChange={(e) => setRentPerOrderRub(e.target.value)}
                    className="w-full min-h-[40px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                  />
                </label>
              </div>
            )}
          </Card>

          {/* Sets & Pack Variants Comparison */}
          <Card>
            <h2 className="text-base font-semibold pb-3 border-b border-[var(--line)]">
              Наборы и фасовки (себестоимость и цена)
            </h2>
            <div className="mt-2 divide-y divide-[var(--line)] text-sm tabular-nums">
              {packComparisons.map((item, idx) => (
                <div key={idx} className="py-2.5 flex items-center justify-between gap-3">
                  <div>
                    <div className="font-medium">{item.label}</div>
                    <div className="text-xs text-[var(--muted)]">
                      Себестоимость: {formatMoneyCents(item.cost, hideAmounts)}
                    </div>
                  </div>
                  <div className="text-right font-semibold text-[var(--accent)]">
                    {formatMoneyCents(item.price, hideAmounts)}
                  </div>
                </div>
              ))}
            </div>
          </Card>
        </div>

        {/* Sticky Results Summary */}
        <Card tone="soft" className="lg:sticky lg:top-24 space-y-4">
          <h2 className="text-base font-semibold">Итог расчёта</h2>

          <div className="space-y-2">
            <span className="text-xs font-medium text-[var(--muted)] block">
              Модель ценообразования
            </span>
            <div className="grid grid-cols-3 gap-1 p-1 rounded-xl bg-[var(--card)] border border-[var(--line)]">
              {(
                [
                  ['markup', 'Наценка'],
                  ['targetMargin', 'Маржа'],
                  ['fixedPrice', 'Своя цена'],
                ] as Array<[PricingMode, string]>
              ).map(([m, lbl]) => (
                <button
                  key={m}
                  type="button"
                  onClick={() => setPricingMode(m)}
                  className={`py-1.5 rounded-lg text-xs font-medium ${
                    pricingMode === m
                      ? 'bg-[var(--accent)] text-[var(--accent-ink)]'
                      : 'text-[var(--muted)]'
                  }`}
                >
                  {lbl}
                </button>
              ))}
            </div>
          </div>

          {pricingMode === 'markup' && (
            <div className="space-y-1.5 text-sm">
              <div className="flex items-center justify-between gap-2">
                <span>Наценка, %</span>
                <input
                  type="number"
                  min={0}
                  value={marginPct}
                  onChange={(e) => setMarginPct(Number(e.target.value) || 0)}
                  className="w-20 px-2 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-right font-semibold tabular-nums text-sm"
                />
              </div>
              <input
                type="range"
                min={0}
                max={200}
                value={Math.min(200, Math.max(0, marginPct))}
                onChange={(e) => setMarginPct(Number(e.target.value))}
                className="w-full accent-[var(--accent)]"
              />
            </div>
          )}

          {pricingMode === 'targetMargin' && (
            <div className="space-y-1.5 text-sm">
              <div className="flex items-center justify-between gap-2">
                <span>Целевая маржа (&lt; 100%)</span>
                <input
                  type="number"
                  min={0}
                  max={99}
                  value={targetMarginPct}
                  onChange={(e) => setTargetMarginPct(Number(e.target.value) || 0)}
                  className="w-20 px-2 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-right font-semibold tabular-nums text-sm"
                />
              </div>
              <input
                type="range"
                min={5}
                max={85}
                value={Math.min(85, Math.max(5, targetMarginPct))}
                onChange={(e) => setTargetMarginPct(Number(e.target.value))}
                className="w-full accent-[var(--accent)]"
              />
            </div>
          )}

          {pricingMode === 'fixedPrice' && (
            <label className="block space-y-1 text-sm">
              <span>Фиксированная цена, ₽</span>
              <input
                type="text"
                value={fixedPriceRub}
                onChange={(e) => setFixedPriceRub(e.target.value)}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] tabular-nums"
              />
            </label>
          )}

          <div className="pt-3 border-t border-[var(--line)] space-y-2 text-sm tabular-nums">
            <div className="flex justify-between">
              <span className="text-[var(--muted)]">Сырьё (с потерями)</span>
              <span>{formatMoneyCents(totals.materialsCents, hideAmounts)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-[var(--muted)]">Труд</span>
              <span>{formatMoneyCents(totals.laborCents, hideAmounts)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-[var(--muted)]">Электричество и амортизация</span>
              <span>{formatMoneyCents(totals.otherCents, hideAmounts)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-[var(--muted)]">Накладные, аренда и брак</span>
              <span>
                {formatMoneyCents(
                  totals.overheadCents + totals.finishedDefectCents,
                  hideAmounts,
                )}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-[var(--muted)]">Упаковка, доставка, сборы</span>
              <span>{formatMoneyCents(totals.sellingCostCents, hideAmounts)}</span>
            </div>
            <div className="flex justify-between font-medium pt-2 border-t border-[var(--line)]">
              <span>Полная себестоимость</span>
              <span>{formatMoneyCents(totals.costCents, hideAmounts)}</span>
            </div>
            <div className="flex justify-between text-xs text-[var(--muted)]">
              <span>Точка безубыточности</span>
              <span>
                {totals.breakEvenCents !== null
                  ? formatMoneyCents(totals.breakEvenCents, hideAmounts)
                  : '—'}
              </span>
            </div>
          </div>

          <div className="pt-3 border-t border-[var(--line)] space-y-1 tabular-nums">
            <div className="text-xs text-[var(--muted)]">Рекомендуемая цена</div>
            <div className="text-3xl font-semibold">
              {totals.validPrice
                ? formatMoneyCents(totals.priceCents, hideAmounts)
                : 'Проверьте %'}
            </div>
            <div className="text-xs text-[var(--muted)]">
              {formatMoneyCents(perKgCents, hideAmounts)}/кг · Прибыль{' '}
              {formatMoneyCents(totals.marginCents, hideAmounts)} · ROI{' '}
              {totals.roiPercent !== null ? `${totals.roiPercent.toFixed(0)}%` : '—'}
            </div>
          </div>

          {selectedRecipeId && (
            <button
              type="button"
              disabled={savingRecipe || !totals.validPrice}
              onClick={handleSaveToRecipe}
              className="w-full min-h-[42px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium disabled:opacity-50"
            >
              {savingRecipe ? 'Сохраняем...' : 'Сохранить расчёт в рецепт'}
            </button>
          )}
        </Card>
      </div>
    </div>
  );
}
