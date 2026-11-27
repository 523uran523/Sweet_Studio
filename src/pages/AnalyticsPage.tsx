import React, { useMemo, useState } from 'react';
import { Download } from 'lucide-react';
import {
  Card,
  EmptyState,
  MetricTile,
  PageHeader,
} from '../components/UiPrimitives';
import { netCashTotals } from '../core/calculatorCore';
import {
  computeLocationBreakdown,
  matchesLocationFilter,
  resolveLocationName,
} from '../core/locations';
import { formatMoneyCents } from '../core/moneyFormat';
import { attributeOrderToRecipes } from '../core/ordersCore';
import { WorkspaceSnapshot } from '../firebase/workspaceService';

type PeriodFilter = '30d' | '90d' | 'all';

function cutoffIso(period: PeriodFilter): string | null {
  if (period === 'all') return null;
  const days = period === '30d' ? 30 : 90;
  return new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);
}

export function AnalyticsPage({
  data,
  activeLocationId = '',
  hideAmounts,
  onToast,
}: {
  data: WorkspaceSnapshot;
  activeLocationId?: string;
  hideAmounts: boolean;
  onToast: (msg: string) => void;
}) {
  const [period, setPeriod] = useState<PeriodFilter>('30d');
  const minDate = useMemo(() => cutoffIso(period), [period]);

  const metrics = useMemo(() => {
    const ordersInPeriod = data.orders.filter(
      (o) =>
        (!minDate || !o.dueDate || o.dueDate >= minDate) &&
        matchesLocationFilter({
          entityLocationName: o.locationName,
          activeLocationId,
          locations: data.locations,
        }),
    );
    const activeOrCompleted = ordersInPeriod.filter((o) => o.status !== 'cancelled');
    const recognizedOrders = ordersInPeriod.filter(
      (o) => o.status === 'delivered' || o.status === 'closed',
    );

    const posSalesInPeriod = data.posSales.filter(
      (s) =>
        s.status === 'completed' &&
        (!minDate || s.occurredAt.slice(0, 10) >= minDate) &&
        matchesLocationFilter({
          entityLocationId: s.locationId,
          entityLocationName: s.locationName,
          activeLocationId,
          locations: data.locations,
        }),
    );
    const posRevenueCents = posSalesInPeriod.reduce((s, p) => s + p.totalCents, 0);
    const posCostCents = posSalesInPeriod.reduce((s, p) => s + p.costCents, 0);

    const recognizedRevenueCents =
      recognizedOrders.reduce((s, o) => s + o.priceCents, 0) + posRevenueCents;
    const recognizedCostCents =
      recognizedOrders.reduce((s, o) => s + o.costCents, 0) + posCostCents;
    const orderPlanTotalCents = activeOrCompleted.reduce(
      (s, o) => s + o.priceCents,
      0,
    );
    const totalCheckCount = activeOrCompleted.length + posSalesInPeriod.length;
    const avgCheckCents =
      totalCheckCount > 0
        ? Math.round((orderPlanTotalCents + posRevenueCents) / totalCheckCount)
        : null;

    const txInPeriod = data.transactions.filter(
      (t) => !minDate || t.occurredAt >= minDate,
    );
    const { incomeCents: cashIncomeCents, expenseCents: cashExpenseCents } =
      netCashTotals(txInPeriod);

    const grossProfitCents = recognizedRevenueCents - recognizedCostCents;
    const grossMarginPct =
      recognizedRevenueCents > 0
        ? (grossProfitCents / recognizedRevenueCents) * 100
        : null;

    const totalLeads = data.leads.length;
    const convertedLeads = data.leads.filter((l) => l.status === 'converted').length;
    const leadConversionPct =
      totalLeads > 0 ? (convertedLeads / totalLeads) * 100 : null;

    const clientOrderCounts = new Map<string, { name: string; count: number; totalCents: number }>();
    for (const o of activeOrCompleted) {
      const key = o.clientId || o.clientName.toLowerCase();
      const prev = clientOrderCounts.get(key) || {
        name: o.clientName,
        count: 0,
        totalCents: 0,
      };
      prev.count += 1;
      prev.totalCents += o.priceCents;
      clientOrderCounts.set(key, prev);
    }
    for (const s of posSalesInPeriod) {
      if (!s.clientId && !s.clientName) continue;
      const name = s.clientName || 'Клиент кассы';
      const key = s.clientId || name.toLowerCase();
      const prev = clientOrderCounts.get(key) || {
        name,
        count: 0,
        totalCents: 0,
      };
      prev.count += 1;
      prev.totalCents += s.totalCents;
      clientOrderCounts.set(key, prev);
    }
    const uniqueClients = clientOrderCounts.size;
    const repeatClients = Array.from(clientOrderCounts.values()).filter(
      (c) => c.count >= 2,
    ).length;
    const repeatPct =
      uniqueClients > 0 ? (repeatClients / uniqueClients) * 100 : null;

    const topClients = Array.from(clientOrderCounts.values())
      .sort((a, b) => b.totalCents - a.totalCents)
      .slice(0, 6);

    const recipeStatsMap = new Map<
      string,
      {
        title: string;
        ordersCount: number;
        revenueCents: number;
        costCents: number;
        laborHoursTotal: number;
      }
    >();
    for (const o of activeOrCompleted) {
      const attributions = attributeOrderToRecipes(o, data.recipes);
      for (const attr of attributions) {
        const prev = recipeStatsMap.get(attr.key) || {
          title: attr.title,
          ordersCount: 0,
          revenueCents: 0,
          costCents: 0,
          laborHoursTotal: 0,
        };
        prev.ordersCount += attr.ordersCount;
        prev.revenueCents += attr.revenueCents;
        prev.costCents += attr.costCents;
        prev.laborHoursTotal += attr.laborHoursTotal;
        recipeStatsMap.set(attr.key, prev);
      }
    }
    for (const sale of posSalesInPeriod) {
      const ratio = sale.subtotalCents > 0 ? sale.totalCents / sale.subtotalCents : 1;
      for (const line of sale.lines) {
        const rec =
          (line.recipeId ? data.recipes.find((r) => r.id === line.recipeId) : undefined) ||
          data.recipes.find(
            (r) => r.title.trim().toLowerCase() === line.title.trim().toLowerCase(),
          );
        if (!rec) continue;
        const prev = recipeStatsMap.get(rec.id) || {
          title: rec.title,
          ordersCount: 0,
          revenueCents: 0,
          costCents: 0,
          laborHoursTotal: 0,
        };
        prev.ordersCount += line.qty;
        prev.revenueCents += Math.round(line.qty * line.unitPriceCents * ratio);
        prev.costCents += Math.round(line.qty * line.unitCostCents);
        prev.laborHoursTotal += (rec.laborHours ?? 1.0) * line.qty;
        recipeStatsMap.set(rec.id, prev);
      }
    }
    const recipeStats = Array.from(recipeStatsMap.values()).sort(
      (a, b) => b.revenueCents - b.costCents - (a.revenueCents - a.costCents),
    );

    const channelMap = new Map<
      string,
      { channel: string; leads: number; clients: number; spendCents: number }
    >();
    for (const l of data.leads) {
      const ch = l.source || 'Без источника';
      const cur = channelMap.get(ch) || { channel: ch, leads: 0, clients: 0, spendCents: 0 };
      cur.leads += 1;
      channelMap.set(ch, cur);
    }
    for (const c of data.clients) {
      const ch = c.source || 'Без источника';
      const cur = channelMap.get(ch) || { channel: ch, leads: 0, clients: 0, spendCents: 0 };
      cur.clients += 1;
      channelMap.set(ch, cur);
    }
    for (const p of data.contentPosts) {
      if (minDate && p.scheduledDate < minDate) continue;
      const ch = p.channel || 'Продвижение';
      const cur = channelMap.get(ch) || { channel: ch, leads: 0, clients: 0, spendCents: 0 };
      cur.spendCents += p.budgetCents || 0;
      channelMap.set(ch, cur);
    }
    const channelStats = Array.from(channelMap.values()).sort(
      (a, b) => b.leads + b.clients - (a.leads + a.clients),
    );

    const visibleInventoryItems = data.inventoryItems.filter((i) =>
      matchesLocationFilter({
        entityLocationId: i.locationId,
        activeLocationId,
        locations: data.locations,
      }),
    );
    const visibleStockLots = data.stockLots.filter((l) =>
      matchesLocationFilter({
        entityLocationId: l.locationId,
        activeLocationId,
        locations: data.locations,
      }),
    );

    const inventoryValueCents = visibleInventoryItems.reduce(
      (s, i) => s + Math.round(i.qtyOnHand * i.avgCostCents),
      0,
    );
    const quarantineLots = visibleStockLots.filter(
      (l) => l.status === 'quarantine' || l.status === 'expired',
    ).length;
    const issueMovementsCents = data.stockMovements
      .filter((m) => m.kind === 'issue' || m.kind === 'production_out')
      .reduce((s, m) => s + Math.abs(m.totalCents), 0);

    const complaintRatePct =
      activeOrCompleted.length > 0
        ? (data.complaints.length / activeOrCompleted.length) * 100
        : null;

    const locationBreakdown = computeLocationBreakdown({
      locations: data.locations,
      orders: data.orders.filter((o) => !minDate || !o.dueDate || o.dueDate >= minDate),
      posSales: data.posSales.filter((s) => !minDate || s.occurredAt.slice(0, 10) >= minDate),
      inventoryItems: data.inventoryItems,
    });

    return {
      ordersCount: activeOrCompleted.length,
      recognizedCount: recognizedOrders.length,
      posCount: posSalesInPeriod.length,
      recognizedRevenueCents,
      recognizedCostCents,
      grossProfitCents,
      grossMarginPct,
      cashIncomeCents,
      cashExpenseCents,
      avgCheckCents,
      leadConversionPct,
      repeatPct,
      topClients,
      recipeStats,
      channelStats,
      inventoryValueCents,
      quarantineLots,
      issueMovementsCents,
      complaintRatePct,
      locationBreakdown,
    };
  }, [data, minDate, activeLocationId]);

  const handleExportCsv = () => {
    const lines = [
      ['Раздел', 'Показатель', 'Значение'],
      ['Заказы', 'Активных и выполненных заказов', String(metrics.ordersCount)],
      ['Касса (POS)', 'Оплаченных чеков за период', String(metrics.posCount)],
      ['Выручка', 'Признанная выручка заказы+POS (коп.)', String(metrics.recognizedRevenueCents)],
      ['Выручка', 'Валовая прибыль (коп.)', String(metrics.grossProfitCents)],
      ['Деньги', 'Поступления касса (коп.)', String(metrics.cashIncomeCents)],
      ['Деньги', 'Расходы касса (коп.)', String(metrics.cashExpenseCents)],
      ['Склад', 'Стоимость остатков (коп.)', String(metrics.inventoryValueCents)],
      ['Качество', 'Жалоб всего', String(data.complaints.length)],
      ...metrics.recipeStats.map((r) => [
        'Рецепт',
        r.title,
        `заказов=${r.ordersCount}; выручка=${Math.round(r.revenueCents / 100)}р; прибыль=${Math.round((r.revenueCents - r.costCents) / 100)}р`,
      ]),
    ];
    const csv = lines
      .map((row) => row.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(';'))
      .join('\n');
    const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `sweet-studio-analytics-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    onToast('Аналитический отчёт CSV скачан');
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Аналитика и отчёты"
        subtitle={
          activeLocationId
            ? `Точка: ${resolveLocationName(data.locations, activeLocationId)} · выручка, маржа, рецепты и склад`
            : 'Выручка, рентабельность рецептов в час, повторные заказы, каналы и склад без дублирования затрат'
        }
        action={
          <div className="flex flex-wrap items-center gap-2">
            {(
              [
                ['30d', '30 дней'],
                ['90d', '90 дней'],
                ['all', 'Всё время'],
              ] as Array<[PeriodFilter, string]>
            ).map(([id, lbl]) => (
              <button
                key={id}
                type="button"
                onClick={() => setPeriod(id)}
                className={`px-3 py-2 rounded-xl text-xs font-medium border ${
                  period === id
                    ? 'border-[var(--accent)] bg-[var(--soft)]'
                    : 'border-[var(--line)] bg-[var(--card)] text-[var(--muted)]'
                }`}
              >
                {lbl}
              </button>
            ))}
            <button
              type="button"
              onClick={handleExportCsv}
              className="min-h-[40px] px-3.5 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium inline-flex items-center gap-1.5 hover:bg-[var(--soft)]"
            >
              <Download className="w-3.5 h-3.5" />
              <span>CSV</span>
            </button>
          </div>
        }
      />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricTile
          label="Признанная выручка"
          value={formatMoneyCents(metrics.recognizedRevenueCents, hideAmounts)}
          hint={`Заказы: ${metrics.recognizedCount}/${metrics.ordersCount} · Чеки POS: ${metrics.posCount}`}
        />
        <MetricTile
          label="Валовая маржа"
          value={
            metrics.grossMarginPct !== null
              ? `${metrics.grossMarginPct.toFixed(1)}%`
              : 'N/A'
          }
          hint={`Прибыль ${formatMoneyCents(metrics.grossProfitCents, hideAmounts)}`}
        />
        <MetricTile
          label="Средний чек"
          value={
            metrics.avgCheckCents !== null
              ? formatMoneyCents(metrics.avgCheckCents, hideAmounts)
              : 'N/A'
          }
          hint={`Поступления: ${formatMoneyCents(metrics.cashIncomeCents, hideAmounts)}`}
        />
        <MetricTile
          label="Повторные клиенты"
          value={
            metrics.repeatPct !== null ? `${metrics.repeatPct.toFixed(0)}%` : 'N/A'
          }
          hint={
            metrics.leadConversionPct !== null
              ? `Конверсия заявок: ${metrics.leadConversionPct.toFixed(0)}%`
              : 'Конверсия заявок: N/A'
          }
        />
      </div>

      {data.locations.length > 1 && (
        <Card className="p-0 overflow-hidden">
          <div className="px-5 py-4 border-b border-[var(--line)]">
            <h2 className="text-base font-semibold">Разбивка по точкам</h2>
            <p className="text-xs text-[var(--muted)]">
              Сравнение признанной выручки за выбранный период и текущей стоимости остатков
            </p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-xs text-[var(--muted)]">
                  <th className="text-left px-4 py-3 font-medium">Точка</th>
                  <th className="text-right px-4 py-3 font-medium">Заказы</th>
                  <th className="text-right px-4 py-3 font-medium">Чеки POS</th>
                  <th className="text-right px-4 py-3 font-medium">Выручка</th>
                  <th className="text-right px-4 py-3 font-medium">Стоимость склада</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--line)] tabular-nums">
                {metrics.locationBreakdown.map((row) => (
                  <tr
                    key={row.locationId}
                    className={
                      activeLocationId === row.locationId ? 'bg-[var(--soft)]/45' : ''
                    }
                  >
                    <td className="px-4 py-3">
                      <div className="font-medium">{row.locationName}</div>
                      <div className="text-xs text-[var(--muted)]">
                        {row.kind === 'kitchen'
                          ? 'Кухня / цех'
                          : row.kind === 'store'
                            ? 'Витрина / точка продаж'
                            : 'Склад'}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right">{row.ordersCount}</td>
                    <td className="px-4 py-3 text-right">{row.posCount}</td>
                    <td className="px-4 py-3 text-right font-semibold">
                      {formatMoneyCents(row.revenueCents, hideAmounts)}
                    </td>
                    <td className="px-4 py-3 text-right">
                      {formatMoneyCents(row.inventoryValueCents, hideAmounts)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* Recipe profitability */}
      <Card className="p-0 overflow-hidden">
        <div className="px-5 py-4 border-b border-[var(--line)] flex items-center justify-between">
          <div>
            <h2 className="text-base font-semibold">Рентабельность по рецептам</h2>
            <p className="text-xs text-[var(--muted)]">
              На основе снимков стоимости в заказах и плановых трудозатрат
            </p>
          </div>
        </div>
        {metrics.recipeStats.length === 0 ? (
          <div className="p-6">
            <EmptyState
              title="Пока нет заказов с привязанными рецептами"
              description="Привязывайте рецепты к заказам, чтобы видеть прибыль и доходность в час."
            />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-xs text-[var(--muted)]">
                  <th className="text-left px-4 py-3 font-medium">Рецепт</th>
                  <th className="text-right px-4 py-3 font-medium">Заказов</th>
                  <th className="text-right px-4 py-3 font-medium">Выручка</th>
                  <th className="text-right px-4 py-3 font-medium">Прибыль</th>
                  <th className="text-right px-4 py-3 font-medium">Прибыль / час</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--line)] tabular-nums">
                {metrics.recipeStats.map((r) => {
                  const profit = r.revenueCents - r.costCents;
                  const perHour =
                    r.laborHoursTotal > 0
                      ? Math.round(profit / r.laborHoursTotal)
                      : null;
                  return (
                    <tr key={r.title}>
                      <td className="px-4 py-3 font-medium">{r.title}</td>
                      <td className="px-4 py-3 text-right">{r.ordersCount}</td>
                      <td className="px-4 py-3 text-right">
                        {formatMoneyCents(r.revenueCents, hideAmounts)}
                      </td>
                      <td className="px-4 py-3 text-right font-semibold">
                        {formatMoneyCents(profit, hideAmounts)}
                      </td>
                      <td className="px-4 py-3 text-right text-[var(--muted)]">
                        {perHour !== null
                          ? `${formatMoneyCents(perHour, hideAmounts)}/ч`
                          : 'N/A'}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <div className="grid lg:grid-cols-3 gap-6">
        <Card className="space-y-3">
          <h3 className="text-base font-semibold pb-2 border-b border-[var(--line)]">
            Источники и CAC
          </h3>
          {metrics.channelStats.length === 0 ? (
            <p className="text-xs text-[var(--muted)]">Нет данных по источникам.</p>
          ) : (
            <div className="divide-y divide-[var(--line)] text-sm">
              {metrics.channelStats.map((ch) => {
                const acquired = ch.clients || ch.leads;
                const cac =
                  ch.spendCents > 0 && acquired > 0
                    ? Math.round(ch.spendCents / acquired)
                    : null;
                return (
                  <div key={ch.channel} className="py-2.5 flex items-center justify-between gap-2">
                    <div>
                      <div className="font-medium">{ch.channel}</div>
                      <div className="text-xs text-[var(--muted)]">
                        Лидов: {ch.leads} · Клиентов: {ch.clients}
                      </div>
                    </div>
                    <div className="text-right tabular-nums text-xs">
                      <div>Бюджет: {formatMoneyCents(ch.spendCents, hideAmounts)}</div>
                      <div className="text-[var(--muted)]">
                        CAC: {cac !== null ? formatMoneyCents(cac, hideAmounts) : 'N/A'}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </Card>

        <Card className="space-y-3">
          <h3 className="text-base font-semibold pb-2 border-b border-[var(--line)]">
            Топ клиентов
          </h3>
          {metrics.topClients.length === 0 ? (
            <p className="text-xs text-[var(--muted)]">Заказов пока нет.</p>
          ) : (
            <div className="divide-y divide-[var(--line)] text-sm">
              {metrics.topClients.map((c) => (
                <div key={c.name} className="py-2.5 flex items-center justify-between gap-2">
                  <div>
                    <div className="font-medium">{c.name}</div>
                    <div className="text-xs text-[var(--muted)]">Заказов: {c.count}</div>
                  </div>
                  <div className="font-semibold tabular-nums">
                    {formatMoneyCents(c.totalCents, hideAmounts)}
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>

        <Card className="space-y-3">
          <h3 className="text-base font-semibold pb-2 border-b border-[var(--line)]">
            Склад, списания и качество
          </h3>
          <div className="space-y-2.5 text-sm tabular-nums">
            <div className="flex justify-between">
              <span className="text-[var(--muted)]">Стоимость остатков</span>
              <span className="font-semibold">
                {formatMoneyCents(metrics.inventoryValueCents, hideAmounts)}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-[var(--muted)]">Расход/выпуск сырья</span>
              <span>{formatMoneyCents(metrics.issueMovementsCents, hideAmounts)}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-[var(--muted)]">Партии в карантине / просроч.</span>
              <span>{metrics.quarantineLots}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-[var(--muted)]">Доля жалоб на заказы</span>
              <span>
                {metrics.complaintRatePct !== null
                  ? `${metrics.complaintRatePct.toFixed(1)}%`
                  : 'N/A'}
              </span>
            </div>
            <div className="flex justify-between pt-2 border-t border-[var(--line)]">
              <span className="text-[var(--muted)]">Денежный расход (касса)</span>
              <span>{formatMoneyCents(metrics.cashExpenseCents, hideAmounts)}</span>
            </div>
          </div>
        </Card>
      </div>
    </div>
  );
}
