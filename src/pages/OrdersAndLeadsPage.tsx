import React, { useEffect, useMemo, useState } from 'react';
import { Copy, PackageMinus, Pencil, Printer, Star, Trash2, Undo2 } from 'lucide-react';
import {
  Card,
  Drawer,
  EmptyState,
  PageHeader,
} from '../components/UiPrimitives';
import { centsToRubInput, formatMoneyCents, parseRubToCents } from '../core/moneyFormat';
import { convertQtyWithDensity } from '../core/units';
import {
  consumeInventoryFefo,
  convertLeadToOrder,
  createWorkspaceEntity,
  deleteWorkspaceEntity,
  newId,
  payOrderWithDeposit,
  recordOrderPayment,
  refundOrderPayment,
  syncOrderWorkItemsStatus,
  updateWorkspaceEntity,
  WorkspaceSnapshot,
} from '../firebase/workspaceService';
import { Lead, Order, OrderStatus, Workspace } from '../types/domain';

const ORDER_STATUS_LABELS: Record<OrderStatus, string> = {
  lead: 'Заявка',
  negotiation: 'Согласование',
  confirmed: 'Подтверждён',
  in_progress: 'В работе',
  ready: 'Готов',
  delivered: 'Выдан',
  closed: 'Закрыт',
  cancelled: 'Отменён',
};

export function OrdersPage({
  workspace,
  data,
  hideAmounts,
  initialOrderId,
  onClearInitialOrder,
  onToast,
}: {
  workspace: Workspace;
  data: WorkspaceSnapshot;
  hideAmounts: boolean;
  initialOrderId?: string | null;
  onClearInitialOrder?: () => void;
  onToast: (msg: string) => void;
}) {
  const [statusFilter, setStatusFilter] = useState<'active' | 'all' | OrderStatus>('active');
  const [selectedOrder, setSelectedOrder] = useState<Order | null>(null);
  const [createOpen, setCreateOpen] = useState(false);

  const [payRub, setPayRub] = useState('');
  const [payAccountId, setPayAccountId] = useState(data.accounts[0]?.id || '');
  const [refundOpen, setRefundOpen] = useState(false);
  const [refundRub, setRefundRub] = useState('');
  const [editMode, setEditMode] = useState(false);

  // Edit order form fields
  const [editTitle, setEditTitle] = useState('');
  const [editClientName, setEditClientName] = useState('');
  const [editWeight, setEditWeight] = useState(1500);
  const [editPriceRub, setEditPriceRub] = useState('');
  const [editDue, setEditDue] = useState('');
  const [editAddress, setEditAddress] = useState('');
  const [editWishes, setEditWishes] = useState('');
  const [editAllergens, setEditAllergens] = useState('');

  useEffect(() => {
    if (!initialOrderId) return;
    const found = data.orders.find((o) => o.id === initialOrderId);
    if (found) {
      setSelectedOrder(found);
      setPayAccountId(data.accounts[0]?.id || '');
      setPayRub('');
      setRefundOpen(false);
      setEditMode(false);
      onClearInitialOrder?.();
    }
  }, [initialOrderId, data.orders, data.accounts, onClearInitialOrder]);

  const [newTitle, setNewTitle] = useState('');
  const [newClientId, setNewClientId] = useState('');
  const [newClient, setNewClient] = useState('');
  const [newRecipeId, setNewRecipeId] = useState('');
  const [newWeight, setNewWeight] = useState(2000);
  const [newPriceRub, setNewPriceRub] = useState('4500');
  const [newDue, setNewDue] = useState(
    new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10),
  );
  const [newDeliveryAddress, setNewDeliveryAddress] = useState('');
  const [newAllergens, setNewAllergens] = useState('');
  const [newCouponId, setNewCouponId] = useState('');
  const [newWishes, setNewWishes] = useState('');

  const filtered = useMemo(() => {
    return data.orders.filter((o) => {
      if (statusFilter === 'active') {
        return o.status !== 'closed' && o.status !== 'cancelled';
      }
      if (statusFilter === 'all') return true;
      return o.status === statusFilter;
    });
  }, [data.orders, statusFilter]);

  const activeOrder = useMemo(
    () => data.orders.find((o) => o.id === selectedOrder?.id) || selectedOrder,
    [data.orders, selectedOrder],
  );

  const todayIso = new Date().toISOString().slice(0, 10);
  const activeCoupons = useMemo(
    () =>
      data.coupons.filter(
        (c) => c.status === 'active' && (!c.expiresAt || c.expiresAt >= todayIso),
      ),
    [data.coupons, todayIso],
  );

  const selectedRecipe = useMemo(
    () => data.recipes.find((r) => r.id === newRecipeId),
    [data.recipes, newRecipeId],
  );

  const selectedCoupon = useMemo(
    () => activeCoupons.find((c) => c.id === newCouponId),
    [activeCoupons, newCouponId],
  );

  const basePriceCents = parseRubToCents(newPriceRub);
  const couponEligible = Boolean(
    selectedCoupon &&
      (!selectedCoupon.minOrderCents || basePriceCents >= selectedCoupon.minOrderCents) &&
      (!selectedCoupon.clientId || !newClientId || selectedCoupon.clientId === newClientId),
  );
  const discountCents = useMemo(() => {
    if (!selectedCoupon || !couponEligible || basePriceCents <= 0) return 0;
    if (selectedCoupon.discountType === 'percent') {
      const pct = Math.max(0, Math.min(100, selectedCoupon.discountValue));
      return Math.round((basePriceCents * pct) / 100);
    }
    return Math.min(basePriceCents, Math.max(0, selectedCoupon.discountValue));
  }, [selectedCoupon, couponEligible, basePriceCents]);

  const finalPriceCents = Math.max(0, basePriceCents - discountCents);
  const scaledCostCents = useMemo(() => {
    if (selectedRecipe && selectedRecipe.yieldGrams > 0) {
      return Math.max(
        0,
        Math.round((selectedRecipe.costCents * newWeight) / selectedRecipe.yieldGrams),
      );
    }
    return Math.round(finalPriceCents * 0.52);
  }, [selectedRecipe, newWeight, finalPriceCents]);

  const mergeAllergens = (a?: string, b?: string[]) => {
    const parts = [
      ...(a ? a.split(',').map((s) => s.trim()) : []),
      ...(b || []).map((s) => s.trim()),
    ].filter(Boolean);
    return Array.from(new Set(parts)).join(', ').slice(0, 240);
  };

  const handleSelectClient = (cid: string) => {
    setNewClientId(cid);
    const client = data.clients.find((c) => c.id === cid);
    if (!client) return;
    setNewClient(client.name);
    if (client.address) setNewDeliveryAddress(client.address);
    setNewAllergens(mergeAllergens(client.allergens, selectedRecipe?.allergens));
  };

  const handleSelectRecipe = (rid: string) => {
    setNewRecipeId(rid);
    const r = data.recipes.find((x) => x.id === rid);
    if (!r) return;
    if (!newTitle) setNewTitle(r.title);
    setNewWeight(r.yieldGrams);
    setNewPriceRub(String(Math.round(r.recommendedPriceCents / 100)));
    const selectedClientObj = data.clients.find((c) => c.id === newClientId);
    setNewAllergens(mergeAllergens(selectedClientObj?.allergens, r.allergens));
  };

  const handleWeightChange = (nextGrams: number) => {
    const safeGrams = Math.max(100, nextGrams || 100);
    setNewWeight(safeGrams);
    if (selectedRecipe && selectedRecipe.yieldGrams > 0) {
      const scaledPriceCents = Math.round(
        (selectedRecipe.recommendedPriceCents * safeGrams) / selectedRecipe.yieldGrams,
      );
      setNewPriceRub(String(Math.round(scaledPriceCents / 100)));
    }
  };

  const handleCreateOrder = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTitle.trim() || !newClient.trim()) return;
    if (selectedCoupon && !couponEligible) {
      onToast('Купон не подходит к выбранному клиенту или сумме заказа');
      return;
    }

    const rec = selectedRecipe;
    const orderNumber = `№${106 + data.orders.length}`;
    const orderId = newId('ord');

    let resolvedClientId = newClientId;
    const trimmedClient = newClient.trim().slice(0, 140);
    if (!resolvedClientId) {
      const existingCli = data.clients.find(
        (c) => c.name.trim().toLowerCase() === trimmedClient.toLowerCase(),
      );
      if (existingCli) {
        resolvedClientId = existingCli.id;
        await updateWorkspaceEntity(workspace, 'clients', existingCli.id, {
          ordersCount: (existingCli.ordersCount || 0) + 1,
        });
      } else {
        resolvedClientId = newId('cli');
        const cliPayload: Record<string, unknown> = {
          name: trimmedClient,
          ordersCount: 1,
          depositCents: 0,
          debtCents: 0,
          favorite: false,
        };
        if (newDeliveryAddress.trim()) {
          cliPayload.address = newDeliveryAddress.trim().slice(0, 240);
        }
        if (newAllergens.trim()) {
          cliPayload.allergens = newAllergens.trim().slice(0, 240);
        }
        await createWorkspaceEntity(workspace, 'clients', resolvedClientId, cliPayload);
      }
    } else {
      const cli = data.clients.find((c) => c.id === resolvedClientId);
      if (cli) {
        await updateWorkspaceEntity(workspace, 'clients', cli.id, {
          ordersCount: (cli.ordersCount || 0) + 1,
        });
      }
    }

    const payload: Record<string, unknown> = {
      orderNumber,
      title: newTitle.trim().slice(0, 160),
      clientId: resolvedClientId,
      clientName: trimmedClient,
      recipeId: rec?.id || '',
      recipeTitle: rec?.title || '',
      weightGrams: newWeight,
      priceCents: finalPriceCents,
      costCents: scaledCostCents,
      prepaymentCents: Math.round(finalPriceCents * 0.5),
      paidCents: 0,
      status: 'confirmed',
      dueDate: newDue,
      assigneeName: 'Владелец',
      locationName: data.locations[0]?.name || 'Основная студия',
      wishes: newWishes.trim().slice(0, 400),
      allergens: newAllergens.trim().slice(0, 240),
      favorite: false,
    };
    if (newDeliveryAddress.trim()) {
      payload.deliveryAddress = newDeliveryAddress.trim().slice(0, 240);
    }
    if (discountCents > 0 && selectedCoupon) {
      payload.discountCents = discountCents;
      payload.couponCode = selectedCoupon.code.slice(0, 40);
    }

    await createWorkspaceEntity(workspace, 'orders', orderId, payload);
    await createWorkspaceEntity(workspace, 'workItems', newId('wi'), {
      type: 'order',
      sourceId: orderId,
      title: `${orderNumber} · ${newTitle.trim().slice(0, 120)}`,
      assigneeName: 'Владелец',
      locationName: data.locations[0]?.name || 'Основная студия',
      dueDate: newDue,
      priority: 'normal',
      stage: 'queue',
      tags: ['заказ'],
    });

    if (selectedCoupon && couponEligible && discountCents > 0) {
      await updateWorkspaceEntity(workspace, 'coupons', selectedCoupon.id, {
        status: 'redeemed',
        redeemedOrderId: orderId,
      });
    }

    setNewTitle('');
    setNewClientId('');
    setNewClient('');
    setNewRecipeId('');
    setNewWeight(2000);
    setNewPriceRub('4500');
    setNewDeliveryAddress('');
    setNewAllergens('');
    setNewCouponId('');
    setNewWishes('');
    setCreateOpen(false);
    onToast(`Заказ ${orderNumber} создан`);
  };

  const handlePay = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeOrder) return;
    const amountCents = parseRubToCents(payRub);
    const remainingCents = Math.max(0, activeOrder.priceCents - activeOrder.paidCents);
    const account =
      data.accounts.find((a) => a.id === payAccountId) || data.accounts[0];
    if (!account || amountCents <= 0) {
      onToast('Укажите корректную сумму оплаты и счёт');
      return;
    }
    if (remainingCents === 0) {
      onToast('Заказ уже полностью оплачен');
      return;
    }
    if (amountCents > remainingCents) {
      onToast(
        `Сумма превышает остаток к оплате (${formatMoneyCents(remainingCents)})`,
      );
      return;
    }

    await recordOrderPayment({
      workspace,
      order: activeOrder,
      account,
      amountCents,
    });
    setPayRub('');
    onToast(`Оплата ${formatMoneyCents(amountCents)} проведена`);
  };

  const activeRemainingCents = activeOrder
    ? Math.max(0, activeOrder.priceCents - activeOrder.paidCents)
    : 0;

  const activeClientObj = useMemo(() => {
    if (!activeOrder) return undefined;
    return (
      (activeOrder.clientId
        ? data.clients.find((c) => c.id === activeOrder.clientId)
        : undefined) ||
      data.clients.find(
        (c) => c.name.trim().toLowerCase() === activeOrder.clientName.trim().toLowerCase(),
      )
    );
  }, [activeOrder, data.clients]);

  const startEditOrder = (ord: Order) => {
    setEditTitle(ord.title);
    setEditClientName(ord.clientName);
    setEditWeight(ord.weightGrams || 1500);
    setEditPriceRub(centsToRubInput(ord.priceCents));
    setEditDue(ord.dueDate || '');
    setEditAddress(ord.deliveryAddress || '');
    setEditWishes(ord.wishes || '');
    setEditAllergens(ord.allergens || '');
    setEditMode(true);
  };

  const handleSaveEditOrder = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeOrder || !editTitle.trim() || !editClientName.trim()) return;
    const priceCents = parseRubToCents(editPriceRub);
    await updateWorkspaceEntity(workspace, 'orders', activeOrder.id, {
      title: editTitle.trim().slice(0, 160),
      clientName: editClientName.trim().slice(0, 140),
      weightGrams: Math.max(50, Number(editWeight) || 1000),
      priceCents,
      dueDate: editDue,
      deliveryAddress: editAddress.trim().slice(0, 240),
      wishes: editWishes.trim().slice(0, 400),
      allergens: editAllergens.trim().slice(0, 240),
    });
    setEditMode(false);
    onToast(`Заказ ${activeOrder.orderNumber} обновлён`);
  };

  const handleDeleteOrder = async (ord: Order) => {
    const linkedWorks = data.workItems.filter((w) => w.sourceId === ord.id);
    for (const w of linkedWorks) {
      await deleteWorkspaceEntity(workspace, 'workItems', w.id);
    }
    await deleteWorkspaceEntity(workspace, 'orders', ord.id);
    setSelectedOrder(null);
    onToast(`Заказ ${ord.orderNumber} удалён`);
  };

  const handleDeductOrderStock = async (ord: Order) => {
    const rec = data.recipes.find((r) => r.id === ord.recipeId);
    if (!rec || !rec.ingredients || rec.ingredients.length === 0) {
      onToast('У заказа нет рецепта с составом ингредиентов');
      return;
    }
    const scale =
      rec.yieldGrams > 0 && ord.weightGrams ? ord.weightGrams / rec.yieldGrams : 1;
    let workingLots = data.stockLots;
    let actualCost = 0;
    let deductedCount = 0;
    try {
      for (const ing of rec.ingredients) {
        const inv =
          (ing.itemId ? data.inventoryItems.find((i) => i.id === ing.itemId) : undefined) ||
          data.inventoryItems.find(
            (i) => i.name.trim().toLowerCase() === ing.name.trim().toLowerCase(),
          );
        if (!inv) continue;
        const neededInRecipeUnit = ing.qty * scale;
        const converted = convertQtyWithDensity(
          neededInRecipeUnit,
          ing.unit,
          inv.unit,
          inv.density,
        );
        const qtyInInvUnit = converted !== null ? converted : neededInRecipeUnit;
        const res = await consumeInventoryFefo({
          workspace,
          item: inv,
          lots: workingLots,
          qtyToConsume: Math.round(qtyInInvUnit * 1000) / 1000,
          reason: `Списание на заказ ${ord.orderNumber} (${ord.title})`,
        });
        workingLots = res.updatedLots;
        actualCost += res.totalCostCents;
        deductedCount += 1;
      }
      if (deductedCount === 0) {
        onToast('Ни один ингредиент рецепта не привязан к кладовой');
        return;
      }
      await updateWorkspaceEntity(workspace, 'orders', ord.id, {
        stockDeducted: true,
        ...(actualCost > 0 ? { costCents: actualCost } : {}),
      });
      onToast(`Сырьё по заказу ${ord.orderNumber} списано по FEFO`);
    } catch (err) {
      onToast(err instanceof Error ? err.message : 'Ошибка при списании со склада');
    }
  };

  const handleRepeatOrder = async (src: Order) => {
    const rec = data.recipes.find((r) => r.id === src.recipeId);
    const weight = src.weightGrams || rec?.yieldGrams || 2000;
    const priceCents =
      rec && rec.yieldGrams > 0
        ? Math.round((rec.recommendedPriceCents * weight) / rec.yieldGrams)
        : src.priceCents;
    const costCents =
      rec && rec.yieldGrams > 0
        ? Math.round((rec.costCents * weight) / rec.yieldGrams)
        : src.costCents;
    const orderNumber = `№${106 + data.orders.length}`;
    const orderId = newId('ord');
    const dueDate = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);

    const payload: Record<string, unknown> = {
      orderNumber,
      title: src.title.slice(0, 160),
      clientName: src.clientName.slice(0, 140),
      recipeId: rec?.id || src.recipeId || '',
      recipeTitle: rec?.title || src.recipeTitle || '',
      weightGrams: weight,
      priceCents,
      costCents,
      prepaymentCents: Math.round(priceCents * 0.5),
      paidCents: 0,
      status: 'confirmed',
      dueDate,
      assigneeName: src.assigneeName || 'Владелец',
      locationName: src.locationName || data.locations[0]?.name || 'Основная студия',
      wishes: (src.wishes || '').slice(0, 400),
      allergens: (src.allergens || '').slice(0, 240),
      favorite: false,
    };
    if (src.clientId) payload.clientId = src.clientId;
    if (src.deliveryAddress) payload.deliveryAddress = src.deliveryAddress.slice(0, 240);

    await createWorkspaceEntity(workspace, 'orders', orderId, payload);
    await createWorkspaceEntity(workspace, 'workItems', newId('wi'), {
      type: 'order',
      sourceId: orderId,
      title: `${orderNumber} · ${src.title.slice(0, 120)}`,
      assigneeName: src.assigneeName || 'Владелец',
      locationName: src.locationName || data.locations[0]?.name || 'Основная студия',
      dueDate,
      priority: 'normal',
      stage: 'queue',
      tags: ['повтор'],
    });
    setSelectedOrder(null);
    onToast(`Создан повтор заказа ${orderNumber} по актуальной цене`);
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Заказы"
        subtitle="Снимки рецепта и цены, статусы, частичные оплаты и сметы"
        action={
          <button
            type="button"
            onClick={() => setCreateOpen(true)}
            className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
          >
            + Новый заказ
          </button>
        }
      />

      <div className="flex flex-wrap items-center gap-1.5">
        {(
          [
            ['active', 'Активные'],
            ['all', 'Все'],
            ['confirmed', 'Подтверждены'],
            ['in_progress', 'В работе'],
            ['ready', 'Готовы'],
            ['closed', 'Закрыты'],
          ] as Array<[typeof statusFilter, string]>
        ).map(([id, lbl]) => (
          <button
            key={id}
            type="button"
            onClick={() => setStatusFilter(id)}
            className={`px-3.5 py-2 rounded-xl text-xs font-medium border whitespace-nowrap shrink-0 ${
              statusFilter === id
                ? 'border-[var(--accent)] bg-[var(--soft)]'
                : 'border-[var(--line)] bg-[var(--card)] text-[var(--muted)]'
            }`}
          >
            {lbl}
          </button>
        ))}
      </div>

      {filtered.length === 0 ? (
        <EmptyState
          title="Заказов по фильтру нет"
          description="Оформите новый заказ или переведите заявку в заказ."
          actionLabel="+ Новый заказ"
          onAction={() => setCreateOpen(true)}
        />
      ) : (
        <Card className="p-0 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-xs text-[var(--muted)]">
                  <th className="text-left px-4 py-3 font-medium">Заказ</th>
                  <th className="text-left px-4 py-3 font-medium">Клиент</th>
                  <th className="text-left px-4 py-3 font-medium">Срок</th>
                  <th className="text-left px-4 py-3 font-medium">Статус</th>
                  <th className="text-right px-4 py-3 font-medium">Оплачено / Цена</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--line)]">
                {filtered.map((ord) => (
                  <tr
                    key={ord.id}
                    onClick={() => {
                      setSelectedOrder(ord);
                      setPayAccountId(data.accounts[0]?.id || '');
                      setPayRub('');
                      setRefundOpen(false);
                      setEditMode(false);
                    }}
                    className="hover:bg-[var(--soft)]/30 cursor-pointer"
                  >
                    <td className="px-4 py-3.5">
                      <div className="font-medium flex items-center gap-1.5">
                        {ord.favorite && (
                          <Star className="w-3.5 h-3.5 fill-[var(--accent)] text-[var(--accent)]" />
                        )}
                        <span>
                          {ord.orderNumber} · {ord.title}
                        </span>
                      </div>
                      {ord.recipeTitle && (
                        <div className="text-xs text-[var(--muted)]">
                          {ord.recipeTitle}
                          {ord.weightGrams ? ` · ${ord.weightGrams} г` : ''}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3.5 text-[var(--muted)]">
                      {ord.clientName}
                    </td>
                    <td className="px-4 py-3.5 tabular-nums text-[var(--muted)]">
                      {ord.dueDate || '—'}
                    </td>
                    <td className="px-4 py-3.5">
                      <span className="text-xs font-medium">
                        {ORDER_STATUS_LABELS[ord.status]}
                      </span>
                    </td>
                    <td className="px-4 py-3.5 text-right tabular-nums">
                      <div className="font-semibold">
                        {formatMoneyCents(ord.priceCents, hideAmounts)}
                      </div>
                      <div className="text-xs text-[var(--muted)]">
                        оплачено {formatMoneyCents(ord.paidCents, hideAmounts)}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* Order Detail & Payments Drawer */}
      <Drawer
        open={Boolean(activeOrder)}
        title={activeOrder ? `${activeOrder.orderNumber} · ${activeOrder.title}` : ''}
        subtitle={
          activeOrder
            ? `Клиент: ${activeOrder.clientName} · Выдача: ${activeOrder.dueDate || 'не задана'}`
            : ''
        }
        onClose={() => {
          setSelectedOrder(null);
          setEditMode(false);
        }}
      >
        {activeOrder && (
          <div className="space-y-5">
            {editMode ? (
              <form onSubmit={handleSaveEditOrder} className="space-y-3 p-4 rounded-xl border border-[var(--line)] bg-[var(--bg)]">
                <div className="text-sm font-semibold">Редактирование заказа</div>
                <label className="block space-y-1 text-xs font-medium">
                  <span>Название заказа</span>
                  <input
                    type="text"
                    required
                    value={editTitle}
                    onChange={(e) => setEditTitle(e.target.value)}
                    className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
                  />
                </label>
                <div className="grid grid-cols-2 gap-2">
                  <label className="block space-y-1 text-xs font-medium">
                    <span>Клиент</span>
                    <input
                      type="text"
                      required
                      value={editClientName}
                      onChange={(e) => setEditClientName(e.target.value)}
                      className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
                    />
                  </label>
                  <label className="block space-y-1 text-xs font-medium">
                    <span>Дата выдачи</span>
                    <input
                      type="date"
                      value={editDue}
                      onChange={(e) => setEditDue(e.target.value)}
                      className="w-full min-h-[40px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
                    />
                  </label>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <label className="block space-y-1 text-xs font-medium">
                    <span>Вес, г</span>
                    <input
                      type="number"
                      min={50}
                      value={editWeight}
                      onChange={(e) => setEditWeight(Number(e.target.value) || 100)}
                      className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm tabular-nums"
                    />
                  </label>
                  <label className="block space-y-1 text-xs font-medium">
                    <span>Цена, ₽</span>
                    <input
                      type="text"
                      required
                      value={editPriceRub}
                      onChange={(e) => setEditPriceRub(e.target.value)}
                      className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm tabular-nums"
                    />
                  </label>
                </div>
                <label className="block space-y-1 text-xs font-medium">
                  <span>Адрес доставки</span>
                  <input
                    type="text"
                    value={editAddress}
                    onChange={(e) => setEditAddress(e.target.value)}
                    className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
                  />
                </label>
                <label className="block space-y-1 text-xs font-medium">
                  <span>Пожелания</span>
                  <textarea
                    rows={2}
                    value={editWishes}
                    onChange={(e) => setEditWishes(e.target.value)}
                    className="w-full p-2.5 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
                  />
                </label>
                <label className="block space-y-1 text-xs font-medium">
                  <span>Аллергены</span>
                  <input
                    type="text"
                    value={editAllergens}
                    onChange={(e) => setEditAllergens(e.target.value)}
                    className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
                  />
                </label>
                <div className="flex gap-2">
                  <button
                    type="submit"
                    className="flex-1 min-h-[40px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium"
                  >
                    Сохранить
                  </button>
                  <button
                    type="button"
                    onClick={() => setEditMode(false)}
                    className="px-4 min-h-[40px] rounded-xl border border-[var(--line)] text-xs font-medium"
                  >
                    Отмена
                  </button>
                </div>
              </form>
            ) : (
              <>
                <div className="grid grid-cols-2 gap-3 p-4 rounded-xl border border-[var(--line)] bg-[var(--soft)] tabular-nums text-sm">
                  <div>
                    <div className="text-xs text-[var(--muted)]">Сумма заказа</div>
                    <div className="text-lg font-semibold">
                      {formatMoneyCents(activeOrder.priceCents, hideAmounts)}
                    </div>
                    {Boolean(activeOrder.discountCents) && (
                      <div className="text-xs text-[var(--muted)]">
                        Скидка {formatMoneyCents(activeOrder.discountCents || 0, hideAmounts)}
                        {activeOrder.couponCode ? ` (${activeOrder.couponCode})` : ''}
                      </div>
                    )}
                  </div>
                  <div>
                    <div className="text-xs text-[var(--muted)]">Остаток к оплате</div>
                    <div className="text-lg font-semibold">
                      {formatMoneyCents(activeRemainingCents, hideAmounts)}
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-[var(--muted)]">Оплачено</div>
                    <div>{formatMoneyCents(activeOrder.paidCents, hideAmounts)}</div>
                  </div>
                  <div>
                    <div className="text-xs text-[var(--muted)]">План. себестоимость</div>
                    <div>{formatMoneyCents(activeOrder.costCents, hideAmounts)}</div>
                  </div>
                </div>

                <label className="block space-y-1 text-sm font-medium">
                  <span>Статус заказа</span>
                  <select
                    value={activeOrder.status}
                    onChange={async (e) => {
                      const next = e.target.value as OrderStatus;
                      await updateWorkspaceEntity(workspace, 'orders', activeOrder.id, {
                        status: next,
                      });
                      await syncOrderWorkItemsStatus(
                        workspace,
                        data.workItems,
                        activeOrder.id,
                        next,
                      );
                      onToast(`Статус: ${ORDER_STATUS_LABELS[next]}`);
                    }}
                    className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                  >
                {(Object.keys(ORDER_STATUS_LABELS) as OrderStatus[]).map((st) => (
                  <option key={st} value={st}>
                    {ORDER_STATUS_LABELS[st]}
                  </option>
                ))}
              </select>
            </label>

            {activeOrder.deliveryAddress && (
              <div className="p-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm">
                <div className="text-xs text-[var(--muted)]">Адрес доставки</div>
                <div className="mt-1">{activeOrder.deliveryAddress}</div>
              </div>
            )}

            {activeOrder.wishes && (
              <div className="p-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm">
                <div className="text-xs text-[var(--muted)]">Пожелания</div>
                <div className="mt-1">{activeOrder.wishes}</div>
              </div>
            )}

            {activeOrder.allergens && (
              <div className="p-3 rounded-xl bg-[var(--warm)] text-sm">
                <div className="text-xs font-semibold">Аллергены</div>
                <div className="mt-0.5">{activeOrder.allergens}</div>
              </div>
            )}

            {/* Payment Form */}
            <form
              onSubmit={handlePay}
              className="p-4 rounded-xl border border-[var(--line)] bg-[var(--bg)] space-y-3"
            >
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-semibold">Принять оплату</span>
                {activeRemainingCents > 0 && (
                  <button
                    type="button"
                    onClick={() =>
                      setPayRub(
                        String(Math.round((activeRemainingCents / 100) * 100) / 100),
                      )
                    }
                    className="text-xs font-medium px-2.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)]"
                  >
                    Оплатить остаток
                  </button>
                )}
              </div>
              <div className="grid grid-cols-2 gap-2">
                <input
                  type="text"
                  required
                  value={payRub}
                  onChange={(e) => setPayRub(e.target.value)}
                  placeholder="Сумма, ₽"
                  className="min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm tabular-nums"
                />
                <select
                  value={payAccountId || data.accounts[0]?.id || ''}
                  onChange={(e) => setPayAccountId(e.target.value)}
                  className="min-h-[42px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
                >
                  {data.accounts.map((acc) => (
                    <option key={acc.id} value={acc.id}>
                      {acc.name}
                    </option>
                  ))}
                </select>
              </div>
              <button
                type="submit"
                disabled={activeRemainingCents === 0}
                className="w-full min-h-[42px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium disabled:opacity-50"
              >
                {activeRemainingCents === 0 ? 'Оплачено полностью' : 'Провести оплату'}
              </button>

              {activeRemainingCents > 0 &&
                activeClientObj &&
                (activeClientObj.depositCents || 0) > 0 && (
                  <button
                    type="button"
                    onClick={async () => {
                      const useCents = Math.min(
                        activeRemainingCents,
                        activeClientObj.depositCents || 0,
                      );
                      await payOrderWithDeposit({
                        workspace,
                        order: activeOrder,
                        client: activeClientObj,
                        amountCents: useCents,
                      });
                      onToast(
                        `Списано с депозита ${activeClientObj.name}: ${formatMoneyCents(useCents)}`,
                      );
                    }}
                    className="w-full min-h-[38px] rounded-xl border border-[var(--accent)] bg-[var(--soft)] text-xs font-medium"
                  >
                    Списать с депозита ({formatMoneyCents(activeClientObj.depositCents || 0, hideAmounts)})
                  </button>
                )}
            </form>

            {activeOrder.paidCents > 0 && (
              <div className="p-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] space-y-2">
                <button
                  type="button"
                  onClick={() => {
                    setRefundOpen(!refundOpen);
                    setRefundRub(centsToRubInput(activeOrder.paidCents));
                  }}
                  className="text-xs font-medium inline-flex items-center gap-1.5 text-[var(--muted)] hover:text-[var(--ink)]"
                >
                  <Undo2 className="w-3.5 h-3.5" />
                  <span>Оформить возврат оплаты клиенту</span>
                </button>
                {refundOpen && (
                  <div className="grid grid-cols-2 gap-2 pt-1">
                    <input
                      type="text"
                      value={refundRub}
                      onChange={(e) => setRefundRub(e.target.value)}
                      placeholder="Сумма возврата, ₽"
                      className="min-h-[38px] px-2.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs tabular-nums"
                    />
                    <button
                      type="button"
                      onClick={async () => {
                        const cents = parseRubToCents(refundRub);
                        const acc =
                          data.accounts.find((a) => a.id === payAccountId) ||
                          data.accounts[0];
                        if (!acc || cents <= 0 || cents > activeOrder.paidCents) {
                          onToast('Проверьте сумму возврата и счёт');
                          return;
                        }
                        await refundOrderPayment({
                          workspace,
                          order: activeOrder,
                          account: acc,
                          amountCents: cents,
                        });
                        setRefundOpen(false);
                        onToast(`Возврат ${formatMoneyCents(cents)} оформлен`);
                      }}
                      className="min-h-[38px] rounded-lg border border-[var(--danger)] text-[var(--danger)] text-xs font-medium"
                    >
                      Подтвердить возврат
                    </button>
                  </div>
                )}
              </div>
            )}

            <div className="flex flex-wrap gap-2 pt-2 border-t border-[var(--line)]">
              <button
                type="button"
                onClick={() => startEditOrder(activeOrder)}
                className="min-h-[40px] px-3.5 py-2 rounded-xl border border-[var(--line)] text-xs font-medium inline-flex items-center gap-1.5 hover:bg-[var(--soft)]"
              >
                <Pencil className="w-3.5 h-3.5" />
                <span>Редактировать</span>
              </button>
              {activeOrder.recipeId && !activeOrder.stockDeducted && (
                <button
                  type="button"
                  onClick={() => handleDeductOrderStock(activeOrder)}
                  className="min-h-[40px] px-3.5 py-2 rounded-xl border border-[var(--line)] text-xs font-medium inline-flex items-center gap-1.5 hover:bg-[var(--soft)]"
                >
                  <PackageMinus className="w-3.5 h-3.5" />
                  <span>Списать сырьё (FEFO)</span>
                </button>
              )}
              {activeOrder.stockDeducted && (
                <span className="min-h-[40px] px-3 py-2 rounded-xl bg-[var(--soft)] text-xs font-medium inline-flex items-center">
                  Сырьё списано
                </span>
              )}
              <button
                type="button"
                onClick={() => window.print()}
                className="min-h-[40px] px-3.5 py-2 rounded-xl border border-[var(--line)] text-xs font-medium inline-flex items-center gap-1.5 hover:bg-[var(--soft)]"
              >
                <Printer className="w-3.5 h-3.5" />
                <span>Печать сметы</span>
              </button>
              <button
                type="button"
                onClick={() => handleRepeatOrder(activeOrder)}
                className="min-h-[40px] px-3.5 py-2 rounded-xl border border-[var(--line)] text-xs font-medium inline-flex items-center gap-1.5 hover:bg-[var(--soft)]"
              >
                <Copy className="w-3.5 h-3.5" />
                <span>Повторить</span>
              </button>
              {(activeOrder.status === 'lead' ||
                activeOrder.status === 'negotiation' ||
                activeOrder.status === 'cancelled') && (
                <button
                  type="button"
                  onClick={() => handleDeleteOrder(activeOrder)}
                  className="min-h-[40px] px-3.5 py-2 rounded-xl border border-[var(--line)] text-[var(--danger)] text-xs font-medium inline-flex items-center gap-1.5 hover:bg-[var(--soft)]"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                  <span>Удалить</span>
                </button>
              )}
            </div>
              </>
            )}
          </div>
        )}
      </Drawer>

      {/* New Order Drawer */}
      <Drawer
        open={createOpen}
        title="Новый заказ"
        subtitle="Привязка клиента, рецепта с пересчётом веса и купона"
        onClose={() => setCreateOpen(false)}
      >
        <form onSubmit={handleCreateOrder} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Название или состав заказа</span>
            <input
              type="text"
              required
              value={newTitle}
              onChange={(e) => setNewTitle(e.target.value)}
              placeholder="Например: Ягодный медовик 2 кг"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Выбрать из базы клиентов</span>
              <select
                value={newClientId}
                onChange={(e) => handleSelectClient(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="">Вручную / новый клиент</option>
                {data.clients.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                    {c.phone ? ` · ${c.phone}` : ''}
                  </option>
                ))}
              </select>
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Имя клиента</span>
              <input
                type="text"
                required
                value={newClient}
                onChange={(e) => {
                  setNewClient(e.target.value);
                  if (newClientId) setNewClientId('');
                }}
                placeholder="Имя клиента"
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          </div>

          <label className="block space-y-1 text-sm font-medium">
            <span>Рецепт (снимок + пересчёт веса)</span>
            <select
              value={newRecipeId}
              onChange={(e) => handleSelectRecipe(e.target.value)}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              <option value="">Без привязки к рецепту</option>
              {data.recipes.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.title} ({r.yieldGrams} г)
                </option>
              ))}
            </select>
          </label>

          <div className="grid grid-cols-3 gap-2">
            <label className="block space-y-1 text-sm font-medium">
              <span>Вес, г</span>
              <input
                type="number"
                min={100}
                value={newWeight}
                onChange={(e) => handleWeightChange(Number(e.target.value))}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Цена до скидки, ₽</span>
              <input
                type="text"
                required
                value={newPriceRub}
                onChange={(e) => setNewPriceRub(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Выдача</span>
              <input
                type="date"
                value={newDue}
                onChange={(e) => setNewDue(e.target.value)}
                className="w-full min-h-[44px] px-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          </div>

          <label className="block space-y-1 text-sm font-medium">
            <span>Купон / промокод</span>
            <select
              value={newCouponId}
              onChange={(e) => setNewCouponId(e.target.value)}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              <option value="">Без купона</option>
              {activeCoupons.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.code} (
                  {c.discountType === 'percent'
                    ? `-${c.discountValue}%`
                    : `-${formatMoneyCents(c.discountValue)}`}
                  {c.clientName ? ` · ${c.clientName}` : ''})
                </option>
              ))}
            </select>
            {selectedCoupon && !couponEligible && (
              <span className="text-xs text-rose-600 block">
                Купон требует другого клиента или минимальную сумму заказа{' '}
                {selectedCoupon.minOrderCents
                  ? formatMoneyCents(selectedCoupon.minOrderCents)
                  : ''}
              </span>
            )}
          </label>

          <div className="grid grid-cols-3 gap-2 p-3 rounded-xl bg-[var(--soft)] text-xs tabular-nums">
            <div>
              <div className="text-[var(--muted)]">Скидка</div>
              <div className="font-semibold">
                {discountCents > 0
                  ? `-${formatMoneyCents(discountCents, hideAmounts)}`
                  : '—'}
              </div>
            </div>
            <div>
              <div className="text-[var(--muted)]">Итого к оплате</div>
              <div className="font-semibold">
                {formatMoneyCents(finalPriceCents, hideAmounts)}
              </div>
            </div>
            <div>
              <div className="text-[var(--muted)]">План. себестоимость</div>
              <div className="font-semibold">
                {formatMoneyCents(scaledCostCents, hideAmounts)}
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Адрес доставки</span>
              <input
                type="text"
                value={newDeliveryAddress}
                onChange={(e) => setNewDeliveryAddress(e.target.value)}
                placeholder="Самовывоз или адрес"
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Аллергены</span>
              <input
                type="text"
                value={newAllergens}
                onChange={(e) => setNewAllergens(e.target.value)}
                placeholder="Орехи, глютен, мёд..."
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          </div>

          <label className="block space-y-1 text-sm font-medium">
            <span>Пожелания и декор</span>
            <textarea
              rows={2}
              value={newWishes}
              onChange={(e) => setNewWishes(e.target.value)}
              className="w-full p-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Создать заказ
          </button>
        </form>
      </Drawer>
    </div>
  );
}

export function LeadsPage({
  workspace,
  data,
  hideAmounts,
  onToast,
}: {
  workspace: Workspace;
  data: WorkspaceSnapshot;
  hideAmounts: boolean;
  onToast: (msg: string) => void;
}) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [clientName, setClientName] = useState('');
  const [phone, setPhone] = useState('');
  const [requestText, setRequestText] = useState('');
  const [source, setSource] = useState('Telegram');
  const [budgetRub, setBudgetRub] = useState('4500');
  const [nextStep, setNextStep] = useState('Согласовать начинку');

  const handleCreateLead = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!clientName.trim() || !requestText.trim()) return;
    await createWorkspaceEntity(workspace, 'leads', newId('lead'), {
      clientName: clientName.trim().slice(0, 140),
      phone: phone.trim().slice(0, 40),
      requestText: requestText.trim().slice(0, 400),
      source,
      budgetCents: parseRubToCents(budgetRub),
      nextStep: nextStep.trim().slice(0, 160),
      status: 'new',
    });
    setClientName('');
    setPhone('');
    setRequestText('');
    setDrawerOpen(false);
    onToast('Заявка добавлена');
  };

  const handleConvert = async (lead: Lead) => {
    if (lead.status === 'converted') return;
    await convertLeadToOrder(workspace, lead, data.orders.length, data.clients);
    onToast(`Заявка от ${lead.clientName} переведена в заказ`);
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Заявки"
        subtitle="Входящие обращения, источники и однократная конверсия в заказ"
        action={
          <button
            type="button"
            onClick={() => setDrawerOpen(true)}
            className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
          >
            + Новая заявка
          </button>
        }
      />

      {data.leads.length === 0 ? (
        <EmptyState
          title="Заявок пока нет"
          description="Фиксируйте входящие запросы из соцсетей и мессенджеров здесь."
          actionLabel="+ Добавить заявку"
          onAction={() => setDrawerOpen(true)}
        />
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {data.leads.map((lead) => (
            <Card key={lead.id} className="space-y-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="text-xs text-[var(--muted)]">
                    {lead.source || 'Прямое обращение'} · {lead.phone || 'без телефона'}
                  </div>
                  <h3 className="text-base font-semibold mt-0.5">{lead.clientName}</h3>
                </div>
                <span className="text-sm font-semibold tabular-nums">
                  {lead.budgetCents
                    ? formatMoneyCents(lead.budgetCents, hideAmounts)
                    : '—'}
                </span>
              </div>
              <p className="text-sm">{lead.requestText}</p>
              <div className="pt-3 border-t border-[var(--line)] flex flex-wrap items-center justify-between gap-3">
                <span className="text-xs text-[var(--muted)]">
                  {lead.status === 'converted'
                    ? 'Переведена в заказ'
                    : lead.status === 'lost'
                      ? 'Отказ'
                      : `Шаг: ${lead.nextStep || 'уточнить детали'}`}
                </span>
                {lead.status !== 'converted' && (
                  <div className="flex items-center gap-2">
                    <select
                      aria-label="Статус заявки"
                      value={lead.status}
                      onChange={async (e) => {
                        await updateWorkspaceEntity(workspace, 'leads', lead.id, {
                          status: e.target.value,
                        });
                        onToast('Статус заявки обновлён');
                      }}
                      className="min-h-[34px] px-2 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-xs"
                    >
                      <option value="new">Новая</option>
                      <option value="contacted">Связались</option>
                      <option value="quoted">КП отправлено</option>
                      <option value="lost">Отказ</option>
                    </select>
                    <button
                      type="button"
                      onClick={() => handleConvert(lead)}
                      className="min-h-[34px] px-3.5 py-1.5 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium whitespace-nowrap shrink-0"
                    >
                      В заказ
                    </button>
                  </div>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}

      <Drawer
        open={drawerOpen}
        title="Новая заявка"
        onClose={() => setDrawerOpen(false)}
      >
        <form onSubmit={handleCreateLead} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Имя клиента</span>
            <input
              type="text"
              required
              value={clientName}
              onChange={(e) => setClientName(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Телефон</span>
              <input
                type="text"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Источник</span>
              <select
                value={source}
                onChange={(e) => setSource(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="Telegram">Telegram</option>
                <option value="Instagram">Instagram</option>
                <option value="WhatsApp">WhatsApp</option>
                <option value="Рекомендация">Рекомендация</option>
                <option value="Сайт">Сайт</option>
              </select>
            </label>
          </div>
          <label className="block space-y-1 text-sm font-medium">
            <span>Запрос клиента</span>
            <textarea
              rows={3}
              required
              value={requestText}
              onChange={(e) => setRequestText(e.target.value)}
              className="w-full p-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Бюджет, ₽</span>
              <input
                type="text"
                value={budgetRub}
                onChange={(e) => setBudgetRub(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Следующий шаг</span>
              <input
                type="text"
                value={nextStep}
                onChange={(e) => setNextStep(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          </div>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Сохранить заявку
          </button>
        </form>
      </Drawer>
    </div>
  );
}
