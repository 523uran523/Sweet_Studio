import React, { useState } from 'react';
import { QuickActionKind } from './AppShell';
import { RecipeFormDrawer } from './RecipeFormDrawer';
import { Drawer } from './UiPrimitives';
import { parseRubToCents } from '../core/moneyFormat';
import { QTY_UNITS } from '../core/units';
import {
  addFinancialTransaction,
  createWorkspaceEntity,
  newId,
  upsertInventoryReceipt,
  WorkspaceSnapshot,
} from '../firebase/workspaceService';
import { WorkItemType, Workspace } from '../types/domain';

const TITLES: Record<QuickActionKind, string> = {
  order: 'Новый заказ',
  lead: 'Новая заявка',
  recipe: 'Новый рецепт',
  expense: 'Быстрый расход',
  income: 'Быстрое поступление',
  client: 'Новый клиент',
  receipt: 'Приход на склад',
  task: 'Задача в Работу',
  coupon: 'Одноразовый купон',
  complaint: 'Запись контроля качества',
};

export function QuickCreateDrawer({
  kind,
  workspace,
  data,
  onClose,
  onToast,
}: {
  kind: QuickActionKind | null;
  workspace: Workspace;
  data: WorkspaceSnapshot;
  onClose: () => void;
  onToast: (msg: string) => void;
}) {
  const [title, setTitle] = useState('');
  const [secondary, setSecondary] = useState('');
  const [amountRub, setAmountRub] = useState('2500');
  const [dateVal, setDateVal] = useState(
    new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10),
  );
  const [unit, setUnit] = useState('кг');
  const [qty, setQty] = useState('1');
  const [category, setCategory] = useState('Торты');
  const [accountId, setAccountId] = useState('');
  const [receiptItemId, setReceiptItemId] = useState('');
  const [recordExpense, setRecordExpense] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const reset = () => {
    setTitle('');
    setSecondary('');
    setAmountRub('2500');
    setQty('1');
    setReceiptItemId('');
    setRecordExpense(false);
    setSubmitting(false);
  };

  const handleClose = () => {
    reset();
    onClose();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!kind || submitting) return;
    setSubmitting(true);

    try {
      const locName = data.locations[0]?.name || 'Основная студия';

      if (kind === 'order') {
        const orderId = newId('ord');
        const orderNumber = `№${106 + data.orders.length}`;
        const priceCents = parseRubToCents(amountRub) || 350000;
        const clientNameStr = secondary.trim().slice(0, 140) || 'Новый клиент';
        const matchedClient = data.clients.find(
          (c) => c.name.trim().toLowerCase() === clientNameStr.toLowerCase(),
        );
        const clientId = matchedClient?.id || newId('cli');
        if (!matchedClient) {
          await createWorkspaceEntity(workspace, 'clients', clientId, {
            name: clientNameStr,
            depositCents: 0,
            ordersCount: 1,
            debtCents: 0,
            favorite: false,
          });
        }
        await createWorkspaceEntity(workspace, 'orders', orderId, {
          orderNumber,
          title: title.trim().slice(0, 160),
          clientId,
          clientName: clientNameStr,
          weightGrams: 1500,
          priceCents,
          costCents: Math.round(priceCents * 0.52),
          prepaymentCents: Math.round(priceCents * 0.5),
          paidCents: 0,
          status: 'confirmed',
          dueDate: dateVal,
          assigneeName: 'Владелец',
          locationName: locName,
          favorite: false,
        });
        await createWorkspaceEntity(workspace, 'workItems', newId('wi'), {
          type: 'order',
          sourceId: orderId,
          title: `${orderNumber} · ${title.trim().slice(0, 120)}`,
          assigneeName: 'Владелец',
          locationName: locName,
          dueDate: dateVal,
          priority: 'normal',
          stage: 'queue',
          tags: ['заказ'],
        });
        onToast(`Заказ ${orderNumber} создан`);
      } else if (kind === 'lead') {
        await createWorkspaceEntity(workspace, 'leads', newId('lead'), {
          clientName: title.trim().slice(0, 140),
          phone: secondary.trim().slice(0, 40),
          requestText: category.trim() || 'Запрос на десерт',
          source: 'Telegram',
          budgetCents: parseRubToCents(amountRub),
          nextStep: 'Связаться с клиентом',
          status: 'new',
        });
        onToast('Заявка добавлена');
      } else if (kind === 'expense' || kind === 'income') {
        const acc = data.accounts.find((a) => a.id === accountId) || data.accounts[0];
        const amountCents = parseRubToCents(amountRub);
        if (!acc || amountCents <= 0) {
          onToast('Укажите корректную сумму и счёт');
          setSubmitting(false);
          return;
        }
        await addFinancialTransaction({
          workspace,
          account: acc,
          kind,
          category:
            title.trim() || (kind === 'expense' ? 'Закупка сырья' : 'Оплата заказа'),
          amountCents,
          note: secondary.trim(),
        });
        onToast(kind === 'expense' ? 'Расход проведён' : 'Поступление проведено');
      } else if (kind === 'client') {
        await createWorkspaceEntity(workspace, 'clients', newId('cli'), {
          name: title.trim().slice(0, 140),
          phone: secondary.trim().slice(0, 40),
          preferences: category.trim().slice(0, 400),
          allergens: '',
          depositCents: 0,
          ordersCount: 0,
          debtCents: 0,
          favorite: false,
        });
        onToast('Клиент добавлен');
      } else if (kind === 'receipt') {
        const existingItem = data.inventoryItems.find((i) => i.id === receiptItemId);
        const qVal = Math.max(0.01, Number(qty.replace(',', '.')) || 1);
        const unitCostCents = parseRubToCents(amountRub) || 50000;
        const itemName = (existingItem?.name || title.trim()).slice(0, 140);
        const totalCostCents = Math.round(qVal * unitCostCents);
        const acc =
          recordExpense
            ? data.accounts.find((a) => a.id === accountId) || data.accounts[0]
            : undefined;
        await upsertInventoryReceipt({
          workspace,
          items: data.inventoryItems,
          existingItemId: existingItem?.id,
          name: itemName,
          kind: existingItem?.kind || 'raw',
          category: existingItem?.category || 'Сырьё',
          unit: existingItem?.unit || unit,
          qty: qVal,
          totalCostCents,
          expiresAt: dateVal,
          reason: 'Быстрый приход',
          movementKind: 'receipt',
          account: acc,
        });
        onToast(
          existingItem
            ? `Пополнена позиция «${existingItem.name}» (+${qVal} ${existingItem.unit})`
            : 'Позиция и партия FEFO оприходованы',
        );
      } else if (kind === 'task') {
        const typeVal: WorkItemType = 'task';
        await createWorkspaceEntity(workspace, 'workItems', newId('wi'), {
          type: typeVal,
          title: title.trim().slice(0, 160),
          assigneeName: secondary.trim().slice(0, 120) || 'Владелец',
          locationName: locName,
          dueDate: dateVal,
          priority: 'normal',
          stage: 'queue',
          tags: [],
        });
        onToast('Задача добавлена в Работу');
      } else if (kind === 'coupon') {
        const code = (title.trim() || `SWEET-${Math.floor(100 + Math.random() * 899)}`)
          .toUpperCase()
          .slice(0, 40);
        await createWorkspaceEntity(workspace, 'coupons', newId('cup'), {
          code,
          clientName: secondary.trim().slice(0, 140),
          discountType: 'percent',
          discountValue: Math.max(1, Math.min(90, Number(qty) || 10)),
          expiresAt: dateVal,
          status: 'active',
        });
        onToast(`Купон ${code} выпущен`);
      } else if (kind === 'complaint') {
        await createWorkspaceEntity(workspace, 'complaints', newId('cmp'), {
          title: title.trim().slice(0, 160),
          severity: 'medium',
          status: 'open',
          responsibleName: 'Владелец',
          resolution: secondary.trim().slice(0, 400),
        });
        onToast('Запись контроля качества добавлена');
      }

      handleClose();
    } catch (err) {
      setSubmitting(false);
      onToast(err instanceof Error ? err.message : 'Не удалось сохранить');
    }
  };

  if (kind === 'recipe') {
    return (
      <RecipeFormDrawer
        open
        mode="create"
        workspace={workspace}
        data={data}
        onClose={onClose}
        onToast={onToast}
      />
    );
  }

  return (
    <Drawer
      open={Boolean(kind)}
      title={kind ? TITLES[kind] : ''}
      subtitle="Быстрое создание без потери текущего экрана"
      onClose={handleClose}
    >
      {kind && (
        <form onSubmit={handleSubmit} className="space-y-4">
          {kind === 'receipt' && data.inventoryItems.length > 0 && (
            <label className="block space-y-1 text-sm font-medium">
              <span>Позиция кладовой</span>
              <select
                value={receiptItemId}
                onChange={(e) => {
                  const id = e.target.value;
                  setReceiptItemId(id);
                  const found = data.inventoryItems.find((i) => i.id === id);
                  if (found) {
                    setTitle(found.name);
                    setUnit(found.unit);
                    if (found.avgCostCents > 0) {
                      setAmountRub(String(Math.round(found.avgCostCents / 100)));
                    }
                  } else {
                    setTitle('');
                  }
                }}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="">+ Создать новую позицию</option>
                {data.inventoryItems.map((i) => (
                  <option key={i.id} value={i.id}>
                    {i.name} (остаток {i.qtyOnHand} {i.unit})
                  </option>
                ))}
              </select>
            </label>
          )}

          {!(kind === 'receipt' && receiptItemId) && (
            <label className="block space-y-1 text-sm font-medium">
              <span>
                {kind === 'lead' || kind === 'client'
                  ? 'Имя клиента'
                  : kind === 'expense' || kind === 'income'
                    ? 'Категория операции'
                    : kind === 'coupon'
                      ? 'Код купона'
                      : 'Название'}
              </span>
              <input
                type="text"
                required
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder={
                  kind === 'order'
                    ? 'Например: Ягодный торт 2 кг'
                    : kind === 'expense'
                      ? 'Закупка ягод и сливок'
                      : kind === 'coupon'
                        ? 'SWEET-15'
                        : 'Введите название...'
                }
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          )}

          <label className="block space-y-1 text-sm font-medium">
            <span>
              {kind === 'order'
                ? 'Клиент'
                : kind === 'lead' || kind === 'client'
                  ? 'Телефон'
                  : kind === 'expense' || kind === 'income'
                    ? 'Комментарий'
                    : kind === 'task'
                      ? 'Исполнитель'
                      : kind === 'coupon'
                        ? 'Для клиента'
                        : 'Примечание'}
            </span>
            <input
              type="text"
              value={secondary}
              onChange={(e) => setSecondary(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>

          {(kind === 'order' ||
            kind === 'lead' ||
            kind === 'expense' ||
            kind === 'income' ||
            kind === 'receipt') && (
            <label className="block space-y-1 text-sm font-medium">
              <span>
                {kind === 'receipt' ? 'Цена за единицу, ₽' : 'Сумма, ₽'}
              </span>
              <input
                type="text"
                required
                value={amountRub}
                onChange={(e) => setAmountRub(e.target.value)}
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          )}

          {(kind === 'expense' || kind === 'income') && data.accounts.length > 0 && (
            <label className="block space-y-1 text-sm font-medium">
              <span>Счёт</span>
              <select
                value={accountId || data.accounts[0]?.id || ''}
                onChange={(e) => setAccountId(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                {data.accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            </label>
          )}

          {kind === 'receipt' && (
            <>
              <div className="grid grid-cols-2 gap-3">
                <label className="block space-y-1 text-sm font-medium">
                  <span>Количество</span>
                  <input
                    type="text"
                    value={qty}
                    onChange={(e) => setQty(e.target.value)}
                    className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                  />
                </label>
                <label className="block space-y-1 text-sm font-medium">
                  <span>Единица</span>
                  <select
                    value={unit}
                    disabled={Boolean(receiptItemId)}
                    onChange={(e) => setUnit(e.target.value)}
                    className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] disabled:opacity-60"
                  >
                    {QTY_UNITS.map((u) => (
                      <option key={u} value={u}>
                        {u}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              {data.accounts.length > 0 && (
                <div className="p-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] space-y-2">
                  <label className="flex items-center gap-2 text-xs font-medium cursor-pointer">
                    <input
                      type="checkbox"
                      checked={recordExpense}
                      onChange={(e) => setRecordExpense(e.target.checked)}
                      className="accent-[var(--accent)]"
                    />
                    <span>Списать оплату со счёта в Финансы</span>
                  </label>
                  {recordExpense && (
                    <select
                      value={accountId || data.accounts[0]?.id || ''}
                      onChange={(e) => setAccountId(e.target.value)}
                      className="w-full min-h-[38px] px-2.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs"
                    >
                      {data.accounts.map((a) => (
                        <option key={a.id} value={a.id}>
                          {a.name}
                        </option>
                      ))}
                    </select>
                  )}
                </div>
              )}
            </>
          )}

          {kind === 'coupon' && (
            <label className="block space-y-1 text-sm font-medium">
              <span>Скидка, %</span>
              <input
                type="number"
                min={1}
                max={90}
                value={qty}
                onChange={(e) => setQty(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          )}

          {(kind === 'lead' || kind === 'client') && (
            <label className="block space-y-1 text-sm font-medium">
              <span>
                {kind === 'lead' ? 'Запрос клиента' : 'Предпочтения'}
              </span>
              <input
                type="text"
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          )}

          {(kind === 'order' ||
            kind === 'task' ||
            kind === 'receipt' ||
            kind === 'coupon') && (
            <label className="block space-y-1 text-sm font-medium">
              <span>
                {kind === 'receipt'
                  ? 'Годен до'
                  : kind === 'coupon'
                    ? 'Действует до'
                    : 'Срок / дата'}
              </span>
              <input
                type="date"
                value={dateVal}
                onChange={(e) => setDateVal(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          )}

          <button
            type="submit"
            disabled={submitting}
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium disabled:opacity-60"
          >
            {submitting ? 'Сохраняем...' : 'Сохранить'}
          </button>
        </form>
      )}
    </Drawer>
  );
}
