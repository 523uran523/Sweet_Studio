import React, { useMemo, useState } from 'react';
import { Play, Square, Star } from 'lucide-react';
import { Card, MetricTile, PageHeader } from '../components/UiPrimitives';
import { QuickActionKind } from '../components/AppShell';
import { netCashTotals } from '../core/calculatorCore';
import { formatMoneyCents } from '../core/moneyFormat';
import { lotsWord, ordersWord } from '../core/pluralRu';
import { WorkspaceSnapshot } from '../firebase/workspaceService';
import { NavSectionId, OrderStatus, Workspace } from '../types/domain';

type DashPeriod = 'today' | '7d' | '30d' | 'all';

const ORDER_STATUS_RU: Record<OrderStatus, string> = {
  lead: 'Заявка',
  negotiation: 'Согласование',
  confirmed: 'Подтверждён',
  in_progress: 'В работе',
  ready: 'Готов к выдаче',
  delivered: 'Выдан',
  closed: 'Закрыт',
  cancelled: 'Отменён',
};

export function DashboardPage({
  workspace,
  data,
  hideAmounts,
  canViewMoney = true,
  onNavigate,
  onOpenOrder,
  onQuickCreate,
  timerRunning,
  elapsedSec,
  timerLabel,
  onTimerLabelChange,
  onToggleTimer,
}: {
  workspace: Workspace;
  userName: string;
  data: WorkspaceSnapshot;
  hideAmounts: boolean;
  canViewMoney?: boolean;
  onNavigate: (page: NavSectionId) => void;
  onOpenOrder?: (orderId: string) => void;
  onQuickCreate: (kind: QuickActionKind) => void;
  onToast: (msg: string) => void;
  timerRunning: boolean;
  elapsedSec: number;
  timerLabel: string;
  onTimerLabelChange: (v: string) => void;
  onToggleTimer: () => void;
}) {
  const [period, setPeriod] = useState<DashPeriod>('30d');

  const periodCutoff = useMemo(() => {
    if (period === 'all') return null;
    const days = period === 'today' ? 0 : period === '7d' ? 7 : 30;
    return new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);
  }, [period]);

  const metrics = useMemo(() => {
    const filteredTx = data.transactions.filter(
      (tx) => !periodCutoff || tx.occurredAt >= periodCutoff,
    );
    const { incomeCents, expenseCents } = netCashTotals(filteredTx);
    const activeOrders = data.orders
      .filter((o) => o.status !== 'closed' && o.status !== 'cancelled')
      .slice()
      .sort((a, b) => (a.dueDate || '9999-12-31').localeCompare(b.dueDate || '9999-12-31'));
    const totalBalanceCents = data.accounts.reduce((s, a) => s + a.balanceCents, 0);
    const lowStock = data.inventoryItems.filter(
      (i) => i.minQty !== undefined && i.qtyOnHand <= i.minQty,
    );
    const soonDate = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);
    const expiringLots = data.stockLots.filter(
      (l) => l.status === 'active' && l.expiresAt && l.expiresAt <= soonDate,
    );
    return {
      incomeCents,
      expenseCents,
      profitCents: incomeCents - expenseCents,
      totalBalanceCents,
      activeOrders,
      lowStock,
      expiringLots,
    };
  }, [data, periodCutoff]);

  const formatTimer = (sec: number) => {
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h > 0) {
      return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    }
    return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  };

  const favoriteRecipes = data.recipes.filter((r) => r.favorite);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Главная сводка"
        subtitle={workspace.slogan || 'Рабочее пространство кондитера'}
        action={
          <div className="flex flex-wrap items-center gap-2">
            <div className="inline-flex rounded-xl border border-[var(--line)] bg-[var(--card)] p-0.5 text-xs">
              {(
                [
                  ['today', 'Сегодня'],
                  ['7d', '7 дн'],
                  ['30d', '30 дн'],
                  ['all', 'Всё'],
                ] as Array<[DashPeriod, string]>
              ).map(([id, label]) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => setPeriod(id)}
                  className={`px-2.5 py-1.5 rounded-lg font-medium transition-colors ${
                    period === id
                      ? 'bg-[var(--accent)] text-[var(--accent-ink)]'
                      : 'text-[var(--muted)] hover:text-[var(--ink)]'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
            <button
              type="button"
              onClick={() => onQuickCreate('order')}
              className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
            >
              + Новый заказ
            </button>
            {canViewMoney && (
              <button
                type="button"
                onClick={() => onQuickCreate('expense')}
                className="min-h-[44px] px-4 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm font-medium hover:bg-[var(--soft)] whitespace-nowrap shrink-0"
              >
                + Расход
              </button>
            )}
          </div>
        }
      />

      {/* 4-Column KPI Strip */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricTile
          label="Поступления"
          value={formatMoneyCents(metrics.incomeCents, hideAmounts)}
          hint={period === 'all' ? 'За всё время' : period === 'today' ? 'За сегодня' : `За ${period === '7d' ? '7' : '30'} дней`}
          onClick={canViewMoney ? () => onNavigate('money') : undefined}
        />
        <MetricTile
          label="Расходы"
          value={formatMoneyCents(metrics.expenseCents, hideAmounts)}
          hint="Закупки и прочие затраты"
          onClick={canViewMoney ? () => onNavigate('money') : undefined}
        />
        <MetricTile
          label="Остаток на счетах"
          value={formatMoneyCents(metrics.totalBalanceCents, hideAmounts)}
          hint={`Счетов: ${data.accounts.length}`}
          onClick={canViewMoney ? () => onNavigate('money') : undefined}
        />
        <MetricTile
          label="В работе сейчас"
          value={ordersWord(metrics.activeOrders.length)}
          hint={`Заявок: ${data.leads.filter((l) => l.status !== 'converted' && l.status !== 'lost').length}`}
          onClick={() => onNavigate('orders')}
        />
      </div>

      {/* Main Two-Column Grid */}
      <div className="grid lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          <Card>
            <div className="flex items-center justify-between gap-4 pb-4 border-b border-[var(--line)]">
              <h2 className="text-base font-semibold">Ближайшие выдачи и заказы</h2>
              <button
                type="button"
                onClick={() => onNavigate('orders')}
                className="text-xs font-medium text-[var(--accent)] hover:underline whitespace-nowrap shrink-0"
              >
                Все заказы
              </button>
            </div>
            {metrics.activeOrders.length === 0 ? (
              <p className="py-6 text-sm text-[var(--muted)]">
                Активных заказов пока нет. Создайте заказ из рецепта или заявки.
              </p>
            ) : (
              <div className="divide-y divide-[var(--line)]">
                {metrics.activeOrders.slice(0, 6).map((ord) => (
                  <button
                    key={ord.id}
                    type="button"
                    onClick={() => {
                      if (onOpenOrder) onOpenOrder(ord.id);
                      else onNavigate('orders');
                    }}
                    className="w-full text-left py-3.5 flex items-center justify-between gap-4 hover:bg-[var(--soft)]/40 px-2 -mx-2 rounded-lg transition-colors"
                  >
                    <div className="min-w-0">
                      <div className="text-sm font-medium truncate">
                        {ord.orderNumber} · {ord.title}
                      </div>
                      <div className="text-xs text-[var(--muted)] mt-0.5">
                        {ord.clientName} · срок {ord.dueDate || 'не указан'} ·{' '}
                        {ORDER_STATUS_RU[ord.status] || ord.status}
                      </div>
                    </div>
                    <div className="text-right shrink-0 tabular-nums">
                      <div className="text-sm font-semibold">
                        {formatMoneyCents(ord.priceCents, hideAmounts)}
                      </div>
                      <div className="text-xs text-[var(--muted)]">
                        оплачено {formatMoneyCents(ord.paidCents, hideAmounts)}
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </Card>

          {favoriteRecipes.length > 0 && (
            <Card>
              <div className="flex items-center justify-between pb-4 border-b border-[var(--line)]">
                <h2 className="text-base font-semibold flex items-center gap-2">
                  <Star className="w-4 h-4 text-[var(--accent)]" />
                  <span>Избранные рецепты</span>
                </h2>
                <button
                  type="button"
                  onClick={() => onNavigate('recipes')}
                  className="text-xs font-medium text-[var(--accent)] hover:underline whitespace-nowrap"
                >
                  Открыть галерею
                </button>
              </div>
              <div className="grid sm:grid-cols-2 gap-3 pt-4">
                {favoriteRecipes.slice(0, 4).map((r) => (
                  <button
                    key={r.id}
                    type="button"
                    onClick={() => onNavigate('recipes')}
                    className="p-3 rounded-xl border border-[var(--line)] hover:border-[var(--accent)] text-left flex items-center gap-3 transition-colors"
                  >
                    {r.photoUrl && (
                      <img
                        src={r.photoUrl}
                        alt={r.title}
                        referrerPolicy="no-referrer"
                        className="w-12 h-12 rounded-lg object-cover shrink-0"
                      />
                    )}
                    <div className="min-w-0">
                      <div className="text-sm font-medium truncate">{r.title}</div>
                      <div className="text-xs text-[var(--muted)] tabular-nums">
                        {r.yieldGrams} г · {formatMoneyCents(r.recommendedPriceCents, hideAmounts)}
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            </Card>
          )}
        </div>

        {/* Right Rail: Work Timer & Stock Alerts */}
        <div className="space-y-6">
          <Card tone="soft">
            <h2 className="text-base font-semibold">Таймер работы</h2>
            <p className="text-xs text-[var(--muted)] mt-1">
              Не сбрасывается при переходе по вкладкам и пишет время прямо в табель
            </p>
            <div className="mt-4 space-y-3">
              <input
                type="text"
                value={timerLabel}
                onChange={(e) => onTimerLabelChange(e.target.value)}
                disabled={timerRunning}
                placeholder="Над чем работаете..."
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
              />
              <div className="flex items-center justify-between gap-3">
                <span className="text-2xl font-semibold font-mono tabular-nums">
                  {formatTimer(elapsedSec)}
                </span>
                <button
                  type="button"
                  onClick={onToggleTimer}
                  className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium inline-flex items-center gap-2 whitespace-nowrap shrink-0"
                >
                  {timerRunning ? (
                    <>
                      <Square className="w-4 h-4" />
                      <span>Завершить</span>
                    </>
                  ) : (
                    <>
                      <Play className="w-4 h-4" />
                      <span>Старт</span>
                    </>
                  )}
                </button>
              </div>
            </div>
          </Card>

          <Card tone="warm">
            <div className="flex items-center justify-between pb-3 border-b border-[var(--line)]">
              <h2 className="text-base font-semibold">Контроль кладовой</h2>
              <button
                type="button"
                onClick={() => onNavigate('inventory')}
                className="text-xs font-medium underline whitespace-nowrap"
              >
                Кладовая
              </button>
            </div>
            <div className="mt-3 space-y-2.5 text-sm">
              <div className="flex justify-between">
                <span>Ниже минимума</span>
                <span className="font-semibold tabular-nums">
                  {metrics.lowStock.length} поз.
                </span>
              </div>
              <div className="flex justify-between">
                <span>Истекают (≤ 3 дн.)</span>
                <span className="font-semibold tabular-nums">
                  {lotsWord(metrics.expiringLots.length)}
                </span>
              </div>
              {metrics.expiringLots.slice(0, 3).map((lot) => (
                <div
                  key={lot.id}
                  className="pt-2 border-t border-[var(--line)] text-xs text-[var(--muted)]"
                >
                  {lot.itemName} ({lot.lotCode}) — до {lot.expiresAt}
                </div>
              ))}
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
