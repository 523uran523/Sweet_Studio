import React, { useEffect, useMemo, useState } from 'react';
import {
  Banknote,
  CreditCard,
  Minus,
  Plus,
  QrCode,
  Receipt,
  RotateCcw,
  ScanLine,
  ShoppingBag,
  Trash2,
} from 'lucide-react';
import { PosScannerModal } from '../components/PosScannerModal';
import { Card, Drawer, EmptyState, MetricTile, PageHeader } from '../components/UiPrimitives';
import {
  matchesLocationFilter,
  resolveDefaultLocation,
  resolveLocationName,
} from '../core/locations';
import { formatMoneyCents, parseRubToCents } from '../core/moneyFormat';
import {
  computePosCartTotals,
  computeShiftDiscrepancyCents,
  computeShiftExpectedCashCents,
  evaluateCouponForSale,
  resolvePosScannedCode,
} from '../core/posCore';
import {
  closeCashShift,
  openCashShift,
  recordPosSale,
  refundPosSale,
  WorkspaceSnapshot,
} from '../firebase/workspaceService';
import { CashShift, PosSaleLine, Workspace } from '../types/domain';

export function PosPage({
  workspace,
  userName,
  data,
  activeLocationId = '',
  hideAmounts,
  canWrite = true,
  onToast,
}: {
  workspace: Workspace;
  userName: string;
  data: WorkspaceSnapshot;
  activeLocationId?: string;
  hideAmounts: boolean;
  canWrite?: boolean;
  onToast: (msg: string) => void;
}) {
  const openShift = useMemo(
    () =>
      data.cashShifts.find(
        (s) =>
          s.status === 'open' &&
          matchesLocationFilter({
            entityLocationId: s.locationId,
            entityLocationName: s.locationName,
            activeLocationId,
            locations: data.locations,
          }),
      ) || null,
    [data.cashShifts, activeLocationId, data.locations],
  );

  const activeLocation = useMemo(
    () =>
      (activeLocationId
        ? data.locations.find((l) => l.id === activeLocationId)
        : resolveDefaultLocation(data.locations)) || null,
    [activeLocationId, data.locations],
  );

  const [shiftLocationId, setShiftLocationId] = useState(
    activeLocationId || data.locations[0]?.id || '',
  );
  useEffect(() => {
    if (activeLocationId) {
      setShiftLocationId(activeLocationId);
    }
  }, [activeLocationId]);

  const [shiftAccountId, setShiftAccountId] = useState(
    data.accounts.find((a) => a.type === 'cash')?.id || data.accounts[0]?.id || '',
  );
  const [openingCashRub, setOpeningCashRub] = useState('1000');

  const [closeDrawerOpen, setCloseDrawerOpen] = useState(false);
  const [actualCashRub, setActualCashRub] = useState('');

  const [catalogMode, setCatalogMode] = useState<'finished' | 'all' | 'recipes'>('finished');
  const [search, setSearch] = useState('');
  const [cart, setCart] = useState<PosSaleLine[]>([]);
  const [clientId, setClientId] = useState('');
  const [couponInput, setCouponInput] = useState('');
  const [paymentMethod, setPaymentMethod] = useState<'cash' | 'card'>('cash');
  const [payAccountId, setPayAccountId] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [scannerOpen, setScannerOpen] = useState(false);
  const [scannerMode, setScannerMode] = useState<'any' | 'coupon'>('any');

  const todayIso = new Date().toISOString().slice(0, 10);

  const sellableInventory = useMemo(() => {
    const q = search.trim().toLowerCase();
    return data.inventoryItems.filter((item) => {
      if (
        !matchesLocationFilter({
          entityLocationId: item.locationId,
          activeLocationId,
          locations: data.locations,
        })
      ) {
        return false;
      }
      if (catalogMode === 'finished' && item.kind !== 'finished' && item.kind !== 'semi') {
        return false;
      }
      if (q && !`${item.name} ${item.category || ''}`.toLowerCase().includes(q)) {
        return false;
      }
      return true;
    });
  }, [data.inventoryItems, data.locations, activeLocationId, catalogMode, search]);

  const sellableRecipes = useMemo(() => {
    const q = search.trim().toLowerCase();
    return data.recipes.filter((r) => {
      if (r.status === 'archived') return false;
      if (q && !`${r.title} ${r.category}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [data.recipes, search]);

  const addInventoryToCart = (itemId: string) => {
    const item = data.inventoryItems.find((i) => i.id === itemId);
    if (!item) return;
    const matchedRecipe = data.recipes.find(
      (r) => r.title.trim().toLowerCase() === item.name.trim().toLowerCase(),
    );
    const unitPriceCents = matchedRecipe
      ? matchedRecipe.recommendedPriceCents
      : Math.max(10000, Math.round(item.avgCostCents * 1.8));
    setCart((prev) => {
      const existing = prev.find((l) => l.itemId === item.id);
      if (existing) {
        return prev.map((l) => (l.itemId === item.id ? { ...l, qty: l.qty + 1 } : l));
      }
      return [
        ...prev,
        {
          id: `line_${item.id}`,
          itemId: item.id,
          title: item.name,
          qty: 1,
          unit: item.unit,
          unitPriceCents,
          unitCostCents: item.avgCostCents,
        },
      ];
    });
  };

  const addRecipeToCart = (recipeId: string) => {
    const r = data.recipes.find((x) => x.id === recipeId);
    if (!r) return;
    setCart((prev) => {
      const existing = prev.find((l) => l.recipeId === r.id);
      if (existing) {
        return prev.map((l) => (l.recipeId === r.id ? { ...l, qty: l.qty + 1 } : l));
      }
      return [
        ...prev,
        {
          id: `line_${r.id}`,
          recipeId: r.id,
          title: r.title,
          qty: 1,
          unit: 'шт',
          unitPriceCents: r.recommendedPriceCents,
          unitCostCents: r.costCents,
        },
      ];
    });
  };

  const updateCartQty = (lineId: string, delta: number) => {
    setCart((prev) =>
      prev
        .map((l) => (l.id === lineId ? { ...l, qty: Math.max(0, l.qty + delta) } : l))
        .filter((l) => l.qty > 0),
    );
  };

  const handleScannedCode = (rawCode: string, closeScannerOnMatch = true): boolean => {
    const res = resolvePosScannedCode({
      rawCode,
      coupons: data.coupons,
      inventoryItems: data.inventoryItems,
      stockLots: data.stockLots,
      recipes: data.recipes,
    });

    if (res.kind === 'coupon') {
      setCouponInput(res.coupon.code);
      if (res.coupon.clientId) {
        setClientId(res.coupon.clientId);
      }
      if (res.coupon.status !== 'active') {
        onToast(`Купон ${res.coupon.code} уже погашен или неактивен`);
      } else if (res.coupon.expiresAt && res.coupon.expiresAt < todayIso) {
        onToast(`Срок действия купона ${res.coupon.code} истёк`);
      } else {
        onToast(`Купон ${res.coupon.code} применён к чеку`);
      }
      if (closeScannerOnMatch) setScannerOpen(false);
      return true;
    }

    if (res.kind === 'inventory') {
      addInventoryToCart(res.item.id);
      onToast(
        res.matchedLot
          ? `Добавлено: ${res.item.name} (партия ${res.matchedLot.lotCode})`
          : `Добавлено в чек: ${res.item.name}`,
      );
      if (closeScannerOnMatch) setScannerOpen(false);
      return true;
    }

    if (res.kind === 'recipe') {
      addRecipeToCart(res.recipe.id);
      onToast(`Добавлено в чек: ${res.recipe.title}`);
      if (closeScannerOnMatch) setScannerOpen(false);
      return true;
    }

    if (res.code) {
      onToast(`Код «${res.code}» не найден среди купонов, партий и позиций`);
    }
    return false;
  };

  const rawSubtotalCents = useMemo(
    () =>
      cart.reduce((s, l) => s + Math.round(l.qty * l.unitPriceCents), 0),
    [cart],
  );

  const matchedCoupon = useMemo(() => {
    const code = couponInput.trim().toUpperCase();
    if (!code) return null;
    return data.coupons.find((c) => c.code.trim().toUpperCase() === code) || null;
  }, [couponInput, data.coupons]);

  const couponEval = useMemo(() => {
    if (!matchedCoupon) return { valid: false, discountCents: 0, reason: undefined };
    return evaluateCouponForSale({
      coupon: matchedCoupon,
      subtotalCents: rawSubtotalCents,
      clientId: clientId || undefined,
      todayIso,
    });
  }, [matchedCoupon, rawSubtotalCents, clientId, todayIso]);

  const totals = useMemo(
    () => computePosCartTotals(cart, couponEval.valid ? couponEval.discountCents : 0),
    [cart, couponEval],
  );

  const expectedShiftCash = openShift ? computeShiftExpectedCashCents(openShift) : 0;
  const closeDiscrepancy = computeShiftDiscrepancyCents(
    expectedShiftCash,
    parseRubToCents(actualCashRub),
  );

  const handleOpenShift = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canWrite) {
      onToast('Подписка истекла — продлите доступ в Настройках');
      return;
    }
    const loc = data.locations.find((l) => l.id === shiftLocationId) || data.locations[0];
    const acc = data.accounts.find((a) => a.id === shiftAccountId) || data.accounts[0];
    if (!acc) {
      onToast('Сначала добавьте счёт в разделе «Финансы»');
      return;
    }
    await openCashShift({
      workspace,
      locationId: loc?.id,
      locationName: loc?.name || 'Витрина',
      accountId: acc.id,
      cashierName: userName,
      openingCashCents: parseRubToCents(openingCashRub),
    });
    onToast('Кассовая смена открыта');
  };

  const handleCloseShift = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!openShift) return;
    const actualCents = parseRubToCents(actualCashRub);
    const diffCents = computeShiftDiscrepancyCents(expectedShiftCash, actualCents);
    await closeCashShift({
      workspace,
      shift: openShift,
      closingActualCashCents: actualCents,
      closingDiscrepancyCents: diffCents,
    });
    setCloseDrawerOpen(false);
    onToast('Смена закрыта, Z-отчёт сохранён');
  };

  const handleCheckout = async () => {
    if (!canWrite) {
      onToast('Подписка истекла — продлите доступ в Настройках');
      return;
    }
    if (cart.length === 0 || submitting) return;
    const defaultCashAcc =
      (openShift && data.accounts.find((a) => a.id === openShift.accountId)) ||
      data.accounts.find((a) => a.type === 'cash') ||
      data.accounts[0];
    const defaultCardAcc =
      data.accounts.find(
        (a) => a.type === 'card' || a.type === 'acquiring' || a.type === 'bank',
      ) || data.accounts[0];
    const preferredAcc = paymentMethod === 'card' ? defaultCardAcc : defaultCashAcc;
    const targetAcc =
      (payAccountId ? data.accounts.find((a) => a.id === payAccountId) : undefined) ||
      preferredAcc;
    if (!targetAcc) {
      onToast('Нет доступного счёта для проведения оплаты');
      return;
    }
    setSubmitting(true);
    try {
      const receiptNumber = `Ч-${String(1001 + data.posSales.length)}`;
      const client = data.clients.find((c) => c.id === clientId);
      const saleLocation =
        (openShift?.locationId
          ? data.locations.find((l) => l.id === openShift.locationId)
          : undefined) || activeLocation;
      await recordPosSale({
        workspace,
        shift: openShift,
        location: saleLocation,
        account: targetAcc,
        cashierName: userName,
        paymentMethod,
        lines: cart,
        subtotalCents: totals.subtotalCents,
        discountCents: totals.discountCents,
        totalCents: totals.totalCents,
        costCents: totals.costCents,
        receiptNumber,
        client,
        coupon: couponEval.valid && matchedCoupon ? matchedCoupon : undefined,
        inventoryItems: data.inventoryItems,
        stockLots: data.stockLots,
      });
      setCart([]);
      setCouponInput('');
      setClientId('');
      onToast(`Чек ${receiptNumber} пробит (${formatMoneyCents(totals.totalCents, hideAmounts)})`);
    } catch (err) {
      onToast(err instanceof Error ? err.message : 'Ошибка при оформлении чека');
    } finally {
      setSubmitting(false);
    }
  };

  const filteredSales = useMemo(
    () =>
      data.posSales.filter((s) =>
        matchesLocationFilter({
          entityLocationId: s.locationId,
          entityLocationName: s.locationName,
          activeLocationId,
          locations: data.locations,
        }),
      ),
    [data.posSales, activeLocationId, data.locations],
  );

  const recentSales = useMemo(
    () =>
      [...filteredSales].sort((a, b) => b.occurredAt.localeCompare(a.occurredAt)).slice(0, 12),
    [filteredSales],
  );

  const closedShifts = useMemo(
    () =>
      data.cashShifts
        .filter(
          (s) =>
            s.status === 'closed' &&
            matchesLocationFilter({
              entityLocationId: s.locationId,
              entityLocationName: s.locationName,
              activeLocationId,
              locations: data.locations,
            }),
        )
        .sort((a, b) => (b.closedAt || '').localeCompare(a.closedAt || ''))
        .slice(0, 6),
    [data.cashShifts, activeLocationId, data.locations],
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="Касса и витрина (POS)"
        subtitle="Кассовые смены, быстрая продажа готовой продукции со списанием остатков и Z-отчёт"
        action={
          openShift ? (
            <button
              type="button"
              onClick={() => {
                setActualCashRub(String(Math.round(expectedShiftCash / 100)));
                setCloseDrawerOpen(true);
              }}
              className="min-h-[44px] px-4 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)] text-sm font-medium whitespace-nowrap shrink-0"
            >
              Закрыть смену (Z-отчёт)
            </button>
          ) : undefined
        }
      />

      {/* Shift status / open form */}
      {openShift ? (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <MetricTile
            label="Наличные в кассе"
            value={formatMoneyCents(expectedShiftCash, hideAmounts)}
            hint={`${openShift.locationName} · кассир ${openShift.cashierName}`}
          />
          <MetricTile
            label="Продажи нал"
            value={formatMoneyCents(openShift.cashSalesCents, hideAmounts)}
            hint={`Чеков за смену: ${openShift.salesCount}`}
          />
          <MetricTile
            label="Продажи карта"
            value={formatMoneyCents(openShift.cardSalesCents, hideAmounts)}
            hint="Безналичная оплата"
          />
          <MetricTile
            label="Возвраты"
            value={formatMoneyCents(openShift.refundsCents, hideAmounts)}
            hint={`Открыта ${openShift.openedAt.slice(11, 16)}`}
          />
        </div>
      ) : (
        <Card className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h2 className="text-base font-semibold">Открыть кассовую смену</h2>
              <p className="text-xs text-[var(--muted)]">
                Откройте смену для учёта наличных и формирования Z-отчёта (продажи работают и без смены).
              </p>
            </div>
          </div>
          <form onSubmit={handleOpenShift} className="grid sm:grid-cols-4 gap-3 items-end">
            <label className="block space-y-1 text-xs font-medium">
              <span>Точка / витрина</span>
              <select
                value={shiftLocationId || data.locations[0]?.id || ''}
                onChange={(e) => setShiftLocationId(e.target.value)}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
              >
                {data.locations.length === 0 ? (
                  <option value="">Основная витрина</option>
                ) : (
                  data.locations.map((l) => (
                    <option key={l.id} value={l.id}>
                      {l.name}
                    </option>
                  ))
                )}
              </select>
            </label>
            <label className="block space-y-1 text-xs font-medium">
              <span>Счёт кассы</span>
              <select
                value={shiftAccountId || data.accounts[0]?.id || ''}
                onChange={(e) => setShiftAccountId(e.target.value)}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
              >
                {data.accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="block space-y-1 text-xs font-medium">
              <span>Размен на начало, ₽</span>
              <input
                type="text"
                value={openingCashRub}
                onChange={(e) => setOpeningCashRub(e.target.value)}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm tabular-nums"
              />
            </label>
            <button
              type="submit"
              className="min-h-[42px] px-4 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
            >
              Открыть смену
            </button>
          </form>
        </Card>
      )}

      {/* Main POS Grid: Catalog + Cart */}
      <div className="grid lg:grid-cols-3 gap-6 items-start">
        <div className="lg:col-span-2 space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex flex-wrap gap-1.5">
              {(
                [
                  ['finished', 'Готовая витрина'],
                  ['all', 'Весь склад'],
                  ['recipes', 'По рецептам'],
                ] as Array<[typeof catalogMode, string]>
              ).map(([id, label]) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => setCatalogMode(id)}
                  className={`px-3 py-2 rounded-xl text-xs font-medium border ${
                    catalogMode === id
                      ? 'border-[var(--accent)] bg-[var(--soft)]'
                      : 'border-[var(--line)] bg-[var(--card)] text-[var(--muted)]'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
            <div className="flex items-center gap-2 w-full sm:w-auto">
              <input
                type="search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && search.trim()) {
                    e.preventDefault();
                    if (handleScannedCode(search, false)) {
                      setSearch('');
                    }
                  }
                }}
                placeholder="Поиск или штрихкод + Enter..."
                className="min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm flex-1 sm:w-56"
              />
              <button
                type="button"
                onClick={() => {
                  setScannerMode('any');
                  setScannerOpen(true);
                }}
                title="Сканировать QR-код или штрихкод камерой"
                className="min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] hover:border-[var(--accent)] hover:bg-[var(--soft)] text-xs font-medium inline-flex items-center gap-1.5 whitespace-nowrap shrink-0"
              >
                <ScanLine className="w-4 h-4 text-[var(--accent)]" />
                <span>Сканер</span>
              </button>
            </div>
          </div>

          {catalogMode !== 'recipes' ? (
            sellableInventory.length === 0 ? (
              <EmptyState
                title="На витрине пока пусто"
                description="Добавьте готовые изделия через «Производство» или «Кладовую», либо переключитесь на вкладку «По рецептам»."
              />
            ) : (
              <div className="grid sm:grid-cols-2 gap-3">
                {sellableInventory.map((item) => {
                  const matchedRecipe = data.recipes.find(
                    (r) => r.title.trim().toLowerCase() === item.name.trim().toLowerCase(),
                  );
                  const sellPrice = matchedRecipe
                    ? matchedRecipe.recommendedPriceCents
                    : Math.max(10000, Math.round(item.avgCostCents * 1.8));
                  const outOfStock = item.qtyOnHand <= 0;
                  return (
                    <button
                      key={item.id}
                      type="button"
                      onClick={() => addInventoryToCart(item.id)}
                      className={`p-4 rounded-2xl border bg-[var(--card)] hover:border-[var(--accent)] text-left flex items-center justify-between gap-3 transition-colors ${
                        outOfStock
                          ? 'border-[var(--line)] opacity-75'
                          : 'border-[var(--line)]'
                      }`}
                    >
                      <div className="min-w-0">
                        <div className="text-sm font-semibold truncate">{item.name}</div>
                        <div
                          className={`text-xs mt-0.5 tabular-nums ${
                            outOfStock ? 'text-[var(--danger)]' : 'text-[var(--muted)]'
                          }`}
                        >
                          {outOfStock
                            ? 'Нет на остатке (0)'
                            : `Остаток: ${item.qtyOnHand} ${item.unit}`}
                          {data.locations.length > 1 && (
                            <span className="ml-1.5 text-[var(--muted)]">
                              · {resolveLocationName(data.locations, item.locationId)}
                            </span>
                          )}
                        </div>
                      </div>
                      <div className="text-right shrink-0">
                        <div className="text-sm font-semibold tabular-nums">
                          {formatMoneyCents(sellPrice, hideAmounts)}
                        </div>
                        <div className="text-[11px] text-[var(--accent)]">+ В чек</div>
                      </div>
                    </button>
                  );
                })}
              </div>
            )
          ) : (
            <div className="grid sm:grid-cols-2 gap-3">
              {sellableRecipes.map((r) => (
                <button
                  key={r.id}
                  type="button"
                  onClick={() => addRecipeToCart(r.id)}
                  className="p-4 rounded-2xl border border-[var(--line)] bg-[var(--card)] hover:border-[var(--accent)] text-left flex items-center justify-between gap-3 transition-colors"
                >
                  <div className="min-w-0">
                    <div className="text-sm font-semibold truncate">{r.title}</div>
                    <div className="text-xs text-[var(--muted)] mt-0.5">
                      {r.category} · {r.yieldGrams} г
                    </div>
                  </div>
                  <div className="text-right shrink-0">
                    <div className="text-sm font-semibold tabular-nums">
                      {formatMoneyCents(r.recommendedPriceCents, hideAmounts)}
                    </div>
                    <div className="text-[11px] text-[var(--accent)]">+ В чек</div>
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Cart & Checkout */}
        <Card className="space-y-4 lg:sticky lg:top-20">
          <div className="flex items-center justify-between pb-3 border-b border-[var(--line)]">
            <h2 className="text-base font-semibold flex items-center gap-2">
              <ShoppingBag className="w-4 h-4 text-[var(--accent)]" />
              <span>Текущий чек</span>
            </h2>
            {cart.length > 0 && (
              <button
                type="button"
                onClick={() => setCart([])}
                className="text-xs text-[var(--muted)] hover:text-[var(--danger)]"
              >
                Очистить
              </button>
            )}
          </div>

          {cart.length === 0 ? (
            <p className="text-xs text-[var(--muted)] py-4">
              Выберите позиции из витрины слева, чтобы собрать чек и списать остатки.
            </p>
          ) : (
            <div className="divide-y divide-[var(--line)]">
              {cart.map((line) => (
                <div key={line.id} className="py-2.5 flex items-center justify-between gap-2 text-sm">
                  <div className="min-w-0 flex-1">
                    <div className="font-medium truncate">{line.title}</div>
                    <div className="text-xs text-[var(--muted)] tabular-nums">
                      {formatMoneyCents(line.unitPriceCents, hideAmounts)} / {line.unit}
                    </div>
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    <button
                      type="button"
                      onClick={() => updateCartQty(line.id, -1)}
                      aria-label="Уменьшить количество"
                      className="min-w-[36px] min-h-[36px] rounded-lg border border-[var(--line)] inline-flex items-center justify-center hover:bg-[var(--soft)]"
                    >
                      <Minus className="w-3.5 h-3.5" />
                    </button>
                    <span className="w-6 text-center tabular-nums text-xs font-semibold">
                      {line.qty}
                    </span>
                    <button
                      type="button"
                      onClick={() => updateCartQty(line.id, 1)}
                      aria-label="Увеличить количество"
                      className="min-w-[36px] min-h-[36px] rounded-lg border border-[var(--line)] inline-flex items-center justify-center hover:bg-[var(--soft)]"
                    >
                      <Plus className="w-3.5 h-3.5" />
                    </button>
                    <button
                      type="button"
                      onClick={() => setCart((p) => p.filter((x) => x.id !== line.id))}
                      aria-label="Удалить позицию"
                      className="min-w-[36px] min-h-[36px] rounded-lg text-[var(--muted)] hover:text-[var(--danger)] inline-flex items-center justify-center"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}

          <div className="space-y-2.5 pt-2 border-t border-[var(--line)]">
            <select
              value={clientId}
              onChange={(e) => setClientId(e.target.value)}
              className="w-full min-h-[38px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-xs"
            >
              <option value="">Покупатель без карты</option>
              {data.clients.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>

            <div>
              <div className="flex items-center gap-1.5">
                <input
                  type="text"
                  value={couponInput}
                  onChange={(e) => setCouponInput(e.target.value)}
                  placeholder="Промокод / купон..."
                  className="flex-1 min-w-0 min-h-[38px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-xs uppercase"
                />
                <button
                  type="button"
                  onClick={() => {
                    setScannerMode('coupon');
                    setScannerOpen(true);
                  }}
                  aria-label="Сканировать QR купона"
                  title="Сканировать QR купона камерой"
                  className="min-w-[38px] min-h-[38px] rounded-xl border border-[var(--line)] bg-[var(--bg)] hover:bg-[var(--soft)] inline-flex items-center justify-center shrink-0"
                >
                  <QrCode className="w-4 h-4 text-[var(--accent)]" />
                </button>
              </div>
              {couponInput.trim() && (
                <div className="text-[11px] mt-1">
                  {!matchedCoupon ? (
                    <span className="text-[var(--muted)]">Купон не найден</span>
                  ) : couponEval.valid ? (
                    <span className="text-[var(--accent)] font-medium">
                      Скидка {formatMoneyCents(couponEval.discountCents, hideAmounts)}
                    </span>
                  ) : (
                    <span className="text-[var(--danger)]">{couponEval.reason}</span>
                  )}
                </div>
              )}
            </div>

            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => {
                  setPaymentMethod('cash');
                  const cashAcc =
                    (openShift && data.accounts.find((a) => a.id === openShift.accountId)) ||
                    data.accounts.find((a) => a.type === 'cash');
                  if (cashAcc) setPayAccountId(cashAcc.id);
                }}
                className={`min-h-[40px] rounded-xl border text-xs font-medium inline-flex items-center justify-center gap-1.5 ${
                  paymentMethod === 'cash'
                    ? 'border-[var(--accent)] bg-[var(--soft)]'
                    : 'border-[var(--line)]'
                }`}
              >
                <Banknote className="w-3.5 h-3.5" />
                <span>Наличные</span>
              </button>
              <button
                type="button"
                onClick={() => {
                  setPaymentMethod('card');
                  const cardAcc = data.accounts.find(
                    (a) => a.type === 'card' || a.type === 'acquiring' || a.type === 'bank',
                  );
                  if (cardAcc) setPayAccountId(cardAcc.id);
                }}
                className={`min-h-[40px] rounded-xl border text-xs font-medium inline-flex items-center justify-center gap-1.5 ${
                  paymentMethod === 'card'
                    ? 'border-[var(--accent)] bg-[var(--soft)]'
                    : 'border-[var(--line)]'
                }`}
              >
                <CreditCard className="w-3.5 h-3.5" />
                <span>Карта</span>
              </button>
            </div>

            <select
              value={
                payAccountId ||
                (paymentMethod === 'card'
                  ? data.accounts.find(
                      (a) => a.type === 'card' || a.type === 'acquiring' || a.type === 'bank',
                    )?.id
                  : openShift?.accountId || data.accounts.find((a) => a.type === 'cash')?.id) ||
                data.accounts[0]?.id ||
                ''
              }
              onChange={(e) => setPayAccountId(e.target.value)}
              className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-xs"
            >
              {data.accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  Счёт: {a.name}
                </option>
              ))}
            </select>
          </div>

          <div className="p-3 rounded-xl bg-[var(--soft)] space-y-1 text-sm tabular-nums">
            <div className="flex justify-between text-xs text-[var(--muted)]">
              <span>Подытог</span>
              <span>{formatMoneyCents(totals.subtotalCents, hideAmounts)}</span>
            </div>
            {totals.discountCents > 0 && (
              <div className="flex justify-between text-xs text-[var(--accent)]">
                <span>Скидка</span>
                <span>−{formatMoneyCents(totals.discountCents, hideAmounts)}</span>
              </div>
            )}
            <div className="flex justify-between font-semibold text-base pt-1 border-t border-[var(--line)]">
              <span>К оплате</span>
              <span>{formatMoneyCents(totals.totalCents, hideAmounts)}</span>
            </div>
          </div>

          <button
            type="button"
            disabled={cart.length === 0 || submitting}
            onClick={handleCheckout}
            className="w-full min-h-[44px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium inline-flex items-center justify-center gap-2 disabled:opacity-50"
          >
            <Receipt className="w-4 h-4" />
            <span>{submitting ? 'Проводим чек...' : 'Пробить чек'}</span>
          </button>
        </Card>
      </div>

      {/* Recent POS Receipts & Z-reports */}
      <div className="grid lg:grid-cols-2 gap-6">
        <Card className="p-0 overflow-hidden">
          <div className="px-5 py-4 border-b border-[var(--line)] font-semibold text-sm">
            Последние чеки ({filteredSales.length})
          </div>
          {recentSales.length === 0 ? (
            <p className="p-5 text-xs text-[var(--muted)]">Чеков пока нет.</p>
          ) : (
            <div className="divide-y divide-[var(--line)]">
              {recentSales.map((sale) => (
                <div
                  key={sale.id}
                  className="px-4 sm:px-5 py-3 flex items-center justify-between gap-3 text-sm"
                >
                  <div className="min-w-0 flex-1">
                    <div className="font-medium truncate">
                      {sale.receiptNumber} · {sale.lines.map((l) => `${l.title} ×${l.qty}`).join(', ')}
                    </div>
                    <div className="text-xs text-[var(--muted)]">
                      {sale.occurredAt.slice(0, 16).replace('T', ' ')} ·{' '}
                      {sale.paymentMethod === 'cash' ? 'Нал' : 'Карта'} ·{' '}
                      {sale.status === 'refunded' ? 'Возврат' : 'Оплачен'}
                      {data.locations.length > 1 && sale.locationName
                        ? ` · ${sale.locationName}`
                        : ''}
                    </div>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <span className="font-semibold tabular-nums">
                      {formatMoneyCents(sale.totalCents, hideAmounts)}
                    </span>
                    {sale.status === 'completed' && (
                      <button
                        type="button"
                        title="Оформить возврат чека"
                        aria-label={`Возврат чека ${sale.receiptNumber}`}
                        onClick={async () => {
                          if (!canWrite) {
                            onToast('Подписка истекла — продлите доступ в Настройках');
                            return;
                          }
                          const acc =
                            data.accounts.find((a) => a.id === sale.accountId) ||
                            data.accounts[0];
                          if (!acc) return;
                          await refundPosSale({
                            workspace,
                            sale,
                            account: acc,
                            shift: openShift?.id === sale.shiftId ? openShift : null,
                          });
                          onToast(`Возврат по чеку ${sale.receiptNumber} оформлен`);
                        }}
                        className="min-w-[36px] min-h-[36px] rounded-lg border border-[var(--line)] hover:bg-[var(--soft)] inline-flex items-center justify-center"
                      >
                        <RotateCcw className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>

        <Card className="p-0 overflow-hidden">
          <div className="px-5 py-4 border-b border-[var(--line)] font-semibold text-sm">
            Закрытые смены (Z-отчёты)
          </div>
          {closedShifts.length === 0 ? (
            <p className="p-5 text-xs text-[var(--muted)]">Закрытых смен пока нет.</p>
          ) : (
            <div className="divide-y divide-[var(--line)]">
              {closedShifts.map((sh: CashShift) => (
                <div
                  key={sh.id}
                  className="px-4 sm:px-5 py-3 flex items-center justify-between gap-3 text-sm tabular-nums"
                >
                  <div className="min-w-0 flex-1">
                    <div className="font-medium truncate">
                      {sh.locationName} · {sh.cashierName}
                    </div>
                    <div className="text-xs text-[var(--muted)]">
                      Чеков: {sh.salesCount} · Нал {formatMoneyCents(sh.cashSalesCents, hideAmounts)} ·
                      Карта {formatMoneyCents(sh.cardSalesCents, hideAmounts)}
                    </div>
                  </div>
                  <div className="text-right text-xs shrink-0">
                    <div className="font-semibold">
                      Факт: {formatMoneyCents(sh.closingActualCashCents || 0, hideAmounts)}
                    </div>
                    <div className="text-[var(--muted)]">
                      Расх.: {formatMoneyCents(sh.closingDiscrepancyCents || 0, hideAmounts)}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* Close Shift Drawer */}
      <Drawer
        open={closeDrawerOpen}
        title="Закрытие кассовой смены (Z-отчёт)"
        subtitle={openShift ? `${openShift.locationName} · кассир ${openShift.cashierName}` : ''}
        onClose={() => setCloseDrawerOpen(false)}
      >
        {openShift && (
          <form onSubmit={handleCloseShift} className="space-y-4">
            <div className="p-3.5 rounded-xl bg-[var(--soft)] text-sm space-y-1 tabular-nums">
              <div className="flex justify-between">
                <span>Ожидается наличных в кассе:</span>
                <span className="font-semibold">
                  {formatMoneyCents(expectedShiftCash, hideAmounts)}
                </span>
              </div>
              <div className="flex justify-between text-xs text-[var(--muted)]">
                <span>Безналичная выручка:</span>
                <span>{formatMoneyCents(openShift.cardSalesCents, hideAmounts)}</span>
              </div>
            </div>
            <label className="block space-y-1 text-sm font-medium">
              <span>Фактические наличные в кассе, ₽</span>
              <input
                type="text"
                required
                value={actualCashRub}
                onChange={(e) => setActualCashRub(e.target.value)}
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <div className="text-xs text-[var(--muted)] tabular-nums">
              Расхождение: {formatMoneyCents(closeDiscrepancy, hideAmounts)}
            </div>
            <button
              type="submit"
              className="w-full min-h-[44px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
            >
              Закрыть смену и сохранить Z-отчёт
            </button>
          </form>
        )}
      </Drawer>

      <PosScannerModal
        open={scannerOpen}
        title={scannerMode === 'coupon' ? 'Сканер QR-кода купона' : 'Сканер QR и штрихкодов'}
        subtitle={
          scannerMode === 'coupon'
            ? 'Наведите камеру на QR-код купона клиента или выберите его фото'
            : 'Наведите камеру на QR-код купона, код партии или штрихкод позиции'
        }
        onScan={(code) => handleScannedCode(code, true)}
        onClose={() => setScannerOpen(false)}
      />
    </div>
  );
}
