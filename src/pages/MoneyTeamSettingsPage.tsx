import React, { useMemo, useState } from 'react';
import { Download, RotateCcw, Trash2, Upload } from 'lucide-react';
import {
  Card,
  Drawer,
  MetricTile,
  PageHeader,
} from '../components/UiPrimitives';
import { netCashTotals } from '../core/calculatorCore';
import { centsToRubInput, formatMoneyCents, parseRubToCents } from '../core/moneyFormat';
import { computeWorkspacePayrollPreview } from '../core/payrollEngine';
import {
  addFinancialTransaction,
  createWorkspaceEntity,
  deleteWorkspaceEntity,
  newId,
  reverseFinancialTransaction,
  transferBetweenAccounts,
  updateWorkspaceEntity,
  updateWorkspacePrefs,
  WorkspaceSnapshot,
} from '../firebase/workspaceService';
import {
  Account,
  BusinessFormat,
  LocationItem,
  MoneyTransaction,
  PayrollPeriod,
  PayType,
  SOFT_ATELIER_THEMES,
  UiDensity,
  UserRole,
  Workspace,
  WorkspaceMember,
} from '../types/domain';
import { NAV_ITEMS } from '../components/AppShell';

function advanceRecurringDate(currentIso: string, cadence: 'monthly' | 'weekly'): string {
  const base = currentIso ? new Date(currentIso + 'T12:00:00') : new Date();
  if (Number.isNaN(base.getTime())) {
    return new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10);
  }
  if (cadence === 'weekly') {
    base.setDate(base.getDate() + 7);
    return base.toISOString().slice(0, 10);
  }
  const origDay = base.getDate();
  base.setMonth(base.getMonth() + 1);
  if (base.getDate() < origDay) {
    base.setDate(0);
  }
  return base.toISOString().slice(0, 10);
}

export function MoneyPage({
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
  const [kind, setKind] = useState<'income' | 'expense' | 'transfer'>('expense');
  const [category, setCategory] = useState('Закупка ингредиентов');
  const [amountRub, setAmountRub] = useState('');
  const [accountId, setAccountId] = useState(data.accounts[0]?.id || '');
  const [toAccountId, setToAccountId] = useState(data.accounts[1]?.id || '');
  const [note, setNote] = useState('');
  const [txFilter, setTxFilter] = useState<'all' | MoneyTransaction['kind']>('all');

  const [accountDrawer, setAccountDrawer] = useState(false);
  const [accName, setAccName] = useState('');
  const [accType, setAccType] = useState<Account['type']>('card');
  const [accInitialRub, setAccInitialRub] = useState('0');

  const [recurringDrawer, setRecurringDrawer] = useState(false);
  const [recTitle, setRecTitle] = useState('');
  const [recAmountRub, setRecAmountRub] = useState('');
  const [recCadence, setRecCadence] = useState<'monthly' | 'weekly'>('monthly');
  const [recNextDate, setRecNextDate] = useState(
    new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10),
  );
  const [recCategory, setRecCategory] = useState('Аренда и сервисы');
  const [recAccountId, setRecAccountId] = useState(data.accounts[0]?.id || '');

  const totals = useMemo(() => {
    const { incomeCents, expenseCents, netCents, reversedIds } = netCashTotals(
      data.transactions,
    );
    const balance = data.accounts.reduce((s, a) => s + a.balanceCents, 0);
    return {
      income: incomeCents,
      expense: expenseCents,
      net: netCents,
      balance,
      reversedIds,
    };
  }, [data.transactions, data.accounts]);

  const filteredTransactions = useMemo(() => {
    const sorted = [...data.transactions].sort((a, b) =>
      (b.occurredAt || '').localeCompare(a.occurredAt || ''),
    );
    if (txFilter === 'all') return sorted;
    return sorted.filter((tx) => tx.kind === txFilter);
  }, [data.transactions, txFilter]);

  const handleAddTx = async (e: React.FormEvent) => {
    e.preventDefault();
    const acc = data.accounts.find((a) => a.id === accountId) || data.accounts[0];
    const amountCents = parseRubToCents(amountRub);
    if (!acc || amountCents <= 0) return;

    if (kind === 'transfer') {
      const toAcc =
        data.accounts.find((a) => a.id === toAccountId) ||
        data.accounts.find((a) => a.id !== acc.id);
      if (!toAcc || toAcc.id === acc.id) {
        onToast('Выберите другой счёт назначения для перевода');
        return;
      }
      await transferBetweenAccounts({
        workspace,
        fromAccount: acc,
        toAccount: toAcc,
        amountCents,
        note,
      });
      setAmountRub('');
      setNote('');
      setDrawerOpen(false);
      onToast(`Перевод ${formatMoneyCents(amountCents)} выполнен`);
      return;
    }

    await addFinancialTransaction({
      workspace,
      account: acc,
      kind,
      category,
      amountCents,
      note,
    });
    setAmountRub('');
    setNote('');
    setDrawerOpen(false);
    onToast('Финансовая операция проведена');
  };

  const handleStorno = async (tx: MoneyTransaction) => {
    if (totals.reversedIds.has(tx.id)) {
      onToast('Эта проводка уже сторнирована');
      return;
    }
    const acc =
      data.accounts.find((a) => a.id === tx.accountId) || data.accounts[0];
    if (!acc) return;
    try {
      await reverseFinancialTransaction({
        workspace,
        account: acc,
        originalTx: tx,
        existingTransactions: data.transactions,
      });
      onToast('Создана корректировочная запись (сторно)');
    } catch (err) {
      onToast(err instanceof Error ? err.message : 'Не удалось выполнить сторно');
    }
  };

  const handleAddAccount = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!accName.trim()) return;
    await createWorkspaceEntity(workspace, 'accounts', newId('acc'), {
      name: accName.trim().slice(0, 100),
      type: accType,
      balanceCents: parseRubToCents(accInitialRub),
    });
    setAccName('');
    setAccInitialRub('0');
    setAccountDrawer(false);
    onToast('Счёт добавлен');
  };

  const handleAddRecurring = async (e: React.FormEvent) => {
    e.preventDefault();
    const amountCents = parseRubToCents(recAmountRub);
    if (!recTitle.trim() || amountCents <= 0) return;
    await createWorkspaceEntity(workspace, 'recurringPayments', newId('rp'), {
      title: recTitle.trim().slice(0, 120),
      amountCents,
      cadence: recCadence,
      nextDueDate: recNextDate,
      category: recCategory.trim().slice(0, 80),
      active: true,
    });
    setRecTitle('');
    setRecAmountRub('');
    setRecurringDrawer(false);
    onToast('Регулярный платёж добавлен');
  };

  const handleExportCsv = () => {
    const rows = [
      ['Дата', 'Тип', 'Категория', 'Счёт', 'Сумма (руб.)', 'Комментарий'],
      ...filteredTransactions.map((tx) => [
        tx.occurredAt,
        tx.kind,
        tx.category,
        tx.accountName || '',
        (tx.amountCents / 100).toFixed(2),
        tx.note || '',
      ]),
    ];
    const csv = rows
      .map((r) => r.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(';'))
      .join('\n');
    const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `sweet-studio-money-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    onToast('Журнал операций CSV скачан');
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Финансы и отчёты"
        subtitle="Счета, переводы между счетами, журнал операций со сторно и регулярные платежи"
        action={
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={handleExportCsv}
              className="min-h-[44px] px-3.5 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm font-medium inline-flex items-center gap-1.5 hover:bg-[var(--soft)]"
            >
              <Download className="w-4 h-4" />
              <span>CSV</span>
            </button>
            <button
              type="button"
              onClick={() => setDrawerOpen(true)}
              className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
            >
              + Операция
            </button>
          </div>
        }
      />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricTile
          label="На счетах"
          value={formatMoneyCents(totals.balance, hideAmounts)}
        />
        <MetricTile
          label="Поступления"
          value={formatMoneyCents(totals.income, hideAmounts)}
        />
        <MetricTile
          label="Расходы"
          value={formatMoneyCents(totals.expense, hideAmounts)}
        />
        <MetricTile
          label="Чистый поток"
          value={formatMoneyCents(totals.net, hideAmounts)}
        />
      </div>

      <div className="grid lg:grid-cols-3 gap-6">
        <Card className="lg:col-span-2 p-0 overflow-hidden">
          <div className="px-5 py-4 border-b border-[var(--line)] flex flex-wrap items-center justify-between gap-2">
            <span className="font-semibold">Журнал операций (неизменяемый)</span>
            <div className="flex flex-wrap gap-1">
              {(
                [
                  ['all', 'Все'],
                  ['income', 'Доходы'],
                  ['expense', 'Расходы'],
                  ['transfer', 'Переводы'],
                  ['reversal', 'Сторно'],
                ] as Array<[typeof txFilter, string]>
              ).map(([id, lbl]) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => setTxFilter(id)}
                  className={`px-2.5 py-1 rounded-lg text-xs font-medium border ${
                    txFilter === id
                      ? 'border-[var(--accent)] bg-[var(--soft)]'
                      : 'border-[var(--line)] text-[var(--muted)]'
                  }`}
                >
                  {lbl}
                </button>
              ))}
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-xs text-[var(--muted)]">
                  <th className="text-left px-4 py-3 font-medium">Дата</th>
                  <th className="text-left px-4 py-3 font-medium">Категория</th>
                  <th className="text-left px-4 py-3 font-medium">Счёт</th>
                  <th className="text-right px-4 py-3 font-medium">Сумма</th>
                  <th className="text-right px-4 py-3 font-medium">Сторно</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--line)]">
                {filteredTransactions.map((tx) => (
                  <tr key={tx.id}>
                    <td className="px-4 py-3 tabular-nums text-[var(--muted)]">
                      {tx.occurredAt}
                    </td>
                    <td className="px-4 py-3">
                      <div className="font-medium">{tx.category}</div>
                      {tx.note && (
                        <div className="text-xs text-[var(--muted)]">{tx.note}</div>
                      )}
                    </td>
                    <td className="px-4 py-3 text-[var(--muted)]">
                      {tx.accountName || 'Счёт'}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums font-semibold">
                      {tx.kind === 'income' ? '+' : tx.kind === 'transfer' ? '⇄ ' : '−'}
                      {formatMoneyCents(tx.amountCents, hideAmounts)}
                    </td>
                    <td className="px-4 py-3 text-right">
                      {tx.kind !== 'reversal' &&
                        tx.kind !== 'transfer' &&
                        (totals.reversedIds.has(tx.id) ? (
                          <span className="text-[11px] text-[var(--muted)]">
                            Сторнировано
                          </span>
                        ) : (
                          <button
                            type="button"
                            onClick={() => handleStorno(tx)}
                            title="Создать сторно"
                            className="p-1.5 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)]"
                          >
                            <RotateCcw className="w-3.5 h-3.5" />
                          </button>
                        ))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>

        <div className="space-y-6">
          <Card>
            <div className="flex items-center justify-between pb-3 border-b border-[var(--line)]">
              <h3 className="text-base font-semibold">Счета</h3>
              <button
                type="button"
                onClick={() => setAccountDrawer(true)}
                className="text-xs font-medium px-2.5 py-1 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)]"
              >
                + Счёт
              </button>
            </div>
            <div className="divide-y divide-[var(--line)] mt-2">
              {data.accounts.map((acc) => (
                <div key={acc.id} className="py-3 flex justify-between text-sm tabular-nums">
                  <span>{acc.name}</span>
                  <span className="font-semibold">
                    {formatMoneyCents(acc.balanceCents, hideAmounts)}
                  </span>
                </div>
              ))}
            </div>
          </Card>

          <Card>
            <div className="flex items-center justify-between pb-3 border-b border-[var(--line)]">
              <h3 className="text-base font-semibold">Регулярные платежи</h3>
              <button
                type="button"
                onClick={() => setRecurringDrawer(true)}
                className="text-xs font-medium px-2.5 py-1 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)]"
              >
                + Платёж
              </button>
            </div>
            <div className="divide-y divide-[var(--line)] mt-2">
              {data.recurringPayments.length === 0 ? (
                <p className="py-3 text-xs text-[var(--muted)]">
                  Добавьте аренду, подписки или регулярные услуги.
                </p>
              ) : (
                <div className="space-y-2">
                  {data.accounts.length > 1 && (
                    <select
                      aria-label="Счёт списания регулярных платежей"
                      value={recAccountId || data.accounts[0]?.id || ''}
                      onChange={(e) => setRecAccountId(e.target.value)}
                      className="w-full min-h-[36px] px-2.5 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-xs mt-1"
                    >
                      {data.accounts.map((a) => (
                        <option key={a.id} value={a.id}>
                          Списывать со счёта: {a.name}
                        </option>
                      ))}
                    </select>
                  )}
                  {data.recurringPayments.map((rp) => (
                    <div key={rp.id} className="py-3 space-y-2">
                      <div className="flex justify-between text-sm">
                        <span className="font-medium">{rp.title}</span>
                        <span className="font-semibold tabular-nums">
                          {formatMoneyCents(rp.amountCents, hideAmounts)}
                        </span>
                      </div>
                      <div className="flex items-center justify-between text-xs text-[var(--muted)]">
                        <span>
                          След. дата: {rp.nextDueDate} ·{' '}
                          {rp.cadence === 'weekly' ? 'еженед.' : 'ежемес.'}
                        </span>
                        <button
                          type="button"
                          onClick={async () => {
                            const acc =
                              data.accounts.find((a) => a.id === recAccountId) ||
                              data.accounts[0];
                            if (!acc) return;
                            await addFinancialTransaction({
                              workspace,
                              account: acc,
                              kind: 'expense',
                              category: rp.category || 'Аренда',
                              amountCents: rp.amountCents,
                              note: rp.title,
                            });
                            const nextDate = advanceRecurringDate(
                              rp.nextDueDate,
                              rp.cadence,
                            );
                            await updateWorkspaceEntity(
                              workspace,
                              'recurringPayments',
                              rp.id,
                              { nextDueDate: nextDate },
                            );
                            onToast(
                              `Платёж «${rp.title}» проведён, след. дата ${nextDate}`,
                            );
                          }}
                          className="px-2.5 py-1 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)] text-[var(--ink)]"
                        >
                          Провести
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </Card>
        </div>
      </div>

      {/* Transaction / Transfer Drawer */}
      <Drawer
        open={drawerOpen}
        title="Новая финансовая операция"
        onClose={() => setDrawerOpen(false)}
      >
        <form onSubmit={handleAddTx} className="space-y-4">
          <div className="grid grid-cols-3 gap-2">
            <button
              type="button"
              onClick={() => {
                setKind('expense');
                setCategory('Закупка ингредиентов');
              }}
              className={`min-h-[42px] rounded-xl border text-xs font-medium ${
                kind === 'expense'
                  ? 'border-[var(--accent)] bg-[var(--soft)]'
                  : 'border-[var(--line)]'
              }`}
            >
              Расход
            </button>
            <button
              type="button"
              onClick={() => {
                setKind('income');
                setCategory('Оплата заказа');
              }}
              className={`min-h-[42px] rounded-xl border text-xs font-medium ${
                kind === 'income'
                  ? 'border-[var(--accent)] bg-[var(--soft)]'
                  : 'border-[var(--line)]'
              }`}
            >
              Поступление
            </button>
            <button
              type="button"
              onClick={() => setKind('transfer')}
              className={`min-h-[42px] rounded-xl border text-xs font-medium ${
                kind === 'transfer'
                  ? 'border-[var(--accent)] bg-[var(--soft)]'
                  : 'border-[var(--line)]'
              }`}
            >
              Перевод
            </button>
          </div>
          <label className="block space-y-1 text-sm font-medium">
            <span>Сумма, ₽</span>
            <input
              type="text"
              required
              value={amountRub}
              onChange={(e) => setAmountRub(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
            />
          </label>
          {kind !== 'transfer' && (
            <label className="block space-y-1 text-sm font-medium">
              <span>Категория</span>
              <input
                type="text"
                required
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          )}
          <label className="block space-y-1 text-sm font-medium">
            <span>{kind === 'transfer' ? 'Со счёта' : 'Счёт'}</span>
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
          {kind === 'transfer' && (
            <label className="block space-y-1 text-sm font-medium">
              <span>На счёт</span>
              <select
                value={toAccountId || data.accounts[1]?.id || ''}
                onChange={(e) => setToAccountId(e.target.value)}
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
          <label className="block space-y-1 text-sm font-medium">
            <span>Комментарий</span>
            <input
              type="text"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            {kind === 'transfer' ? 'Перевести между счетами' : 'Провести операцию'}
          </button>
        </form>
      </Drawer>

      {/* New Account Drawer */}
      <Drawer
        open={accountDrawer}
        title="Новый счёт"
        onClose={() => setAccountDrawer(false)}
      >
        <form onSubmit={handleAddAccount} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Название счёта</span>
            <input
              type="text"
              required
              value={accName}
              onChange={(e) => setAccName(e.target.value)}
              placeholder="Например: Тинькофф ИП или Касса витрины"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Тип</span>
              <select
                value={accType}
                onChange={(e) => setAccType(e.target.value as Account['type'])}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="card">Карта</option>
                <option value="bank">Расчётный счёт</option>
                <option value="cash">Наличные</option>
                <option value="acquiring">Эквайринг</option>
              </select>
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Начальный остаток, ₽</span>
              <input
                type="text"
                value={accInitialRub}
                onChange={(e) => setAccInitialRub(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          </div>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Создать счёт
          </button>
        </form>
      </Drawer>

      {/* New Recurring Payment Drawer */}
      <Drawer
        open={recurringDrawer}
        title="Новый регулярный платёж"
        onClose={() => setRecurringDrawer(false)}
      >
        <form onSubmit={handleAddRecurring} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Название</span>
            <input
              type="text"
              required
              value={recTitle}
              onChange={(e) => setRecTitle(e.target.value)}
              placeholder="Например: Аренда студии или CRM"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Сумма, ₽</span>
              <input
                type="text"
                required
                value={recAmountRub}
                onChange={(e) => setRecAmountRub(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Периодичность</span>
              <select
                value={recCadence}
                onChange={(e) =>
                  setRecCadence(e.target.value as 'monthly' | 'weekly')
                }
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="monthly">Ежемесячно</option>
                <option value="weekly">Еженедельно</option>
              </select>
            </label>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Следующая дата</span>
              <input
                type="date"
                value={recNextDate}
                onChange={(e) => setRecNextDate(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Категория</span>
              <input
                type="text"
                value={recCategory}
                onChange={(e) => setRecCategory(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          </div>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Добавить платёж
          </button>
        </form>
      </Drawer>
    </div>
  );
}

export function TeamPage({
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
  const [editingMember, setEditingMember] = useState<WorkspaceMember | null>(null);
  const [payoutPeriod, setPayoutPeriod] = useState<PayrollPeriod | null>(null);
  const [payoutAccountId, setPayoutAccountId] = useState(data.accounts[0]?.id || '');
  const [payoutRub, setPayoutRub] = useState('');

  const [name, setName] = useState('');
  const [role, setRole] = useState<UserRole>('confectioner');
  const [payType, setPayType] = useState<PayType>('hourly');
  const [rateRub, setRateRub] = useState('550');
  const [percent, setPercent] = useState(15);
  const [activeMemberFlag, setActiveMemberFlag] = useState(true);

  const monthStart = new Date().toISOString().slice(0, 7) + '-01';
  const today = new Date().toISOString().slice(0, 10);

  const previewLines = useMemo(
    () =>
      computeWorkspacePayrollPreview({
        startDate: monthStart,
        endDate: today,
        members: data.members,
        timeEntries: data.timeEntries,
        orders: data.orders,
      }),
    [monthStart, today, data.members, data.timeEntries, data.orders],
  );

  const totalPreviewCents = previewLines.reduce((s, l) => s + l.amountCents, 0);

  const handleAddMember = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    await createWorkspaceEntity(workspace, 'members', newId('mem'), {
      name: name.trim().slice(0, 120),
      role,
      payType,
      rateCents: parseRubToCents(rateRub),
      percent,
      active: true,
    });
    setName('');
    setDrawerOpen(false);
    onToast('Сотрудник добавлен в команду');
  };

  const openEditMember = (m: WorkspaceMember) => {
    setEditingMember(m);
    setName(m.name);
    setRole(m.role);
    setPayType(m.payType);
    setRateRub(centsToRubInput(m.rateCents || 0));
    setPercent(m.percent || 0);
    setActiveMemberFlag(m.active);
  };

  const handleSaveMember = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingMember || !name.trim()) return;
    await updateWorkspaceEntity(workspace, 'members', editingMember.id, {
      name: name.trim().slice(0, 120),
      role,
      payType,
      rateCents: parseRubToCents(rateRub),
      percent,
      active: activeMemberFlag,
    });
    setEditingMember(null);
    onToast('Карточка сотрудника обновлена');
  };

  const handleClosePeriod = async () => {
    await createWorkspaceEntity(workspace, 'payrollPeriods', newId('pay'), {
      title: `Расчётный период ${monthStart} — ${today}`,
      startDate: monthStart,
      endDate: today,
      status: 'closed',
      totalAccruedCents: totalPreviewCents,
      totalPaidCents: 0,
      lines: previewLines,
    });
    onToast('Ведомость зафиксирована снимком (preview = close)');
  };

  const handlePayoutSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!payoutPeriod) return;
    const cents = parseRubToCents(payoutRub);
    if (cents <= 0) return;
    const acc = data.accounts.find((a) => a.id === payoutAccountId) || data.accounts[0];
    if (!acc) {
      onToast('Сначала добавьте счёт в разделе «Финансы»');
      return;
    }
    await addFinancialTransaction({
      workspace,
      account: acc,
      kind: 'expense',
      category: 'Зарплата',
      amountCents: cents,
      note: `Выплата по ведомости: ${payoutPeriod.title}`,
    });
    await updateWorkspaceEntity(workspace, 'payrollPeriods', payoutPeriod.id, {
      totalPaidCents: (payoutPeriod.totalPaidCents || 0) + cents,
    });
    setPayoutPeriod(null);
    onToast(`Выплата ${formatMoneyCents(cents)} проведена в Финансы`);
  };

  const ROLE_RU: Record<UserRole, string> = {
    owner: 'Владелец',
    admin: 'Администратор',
    confectioner: 'Кондитер',
    seller: 'Продавец',
    marketer: 'Маркетолог',
    storekeeper: 'Кладовщик',
    accountant: 'Бухгалтер',
  };

  const PAY_RU: Record<PayType, string> = {
    hourly: 'Почасовая',
    piece: 'Сдельная',
    percent: 'Процент',
    salary: 'Оклад',
    mixed: 'Смешанная',
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Команда и зарплата"
        subtitle="Роли, ставки, выплата по ведомостям и движок расчёта начислений"
        action={
          <>
            <button
              type="button"
              onClick={handleClosePeriod}
              className="min-h-[44px] px-4 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm font-medium hover:bg-[var(--soft)] whitespace-nowrap shrink-0"
            >
              Закрыть период
            </button>
            <button
              type="button"
              onClick={() => {
                setName('');
                setRole('confectioner');
                setPayType('hourly');
                setRateRub('550');
                setPercent(15);
                setDrawerOpen(true);
              }}
              className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
            >
              + Сотрудник
            </button>
          </>
        }
      />

      <div className="grid lg:grid-cols-2 gap-6">
        <Card>
          <h3 className="text-base font-semibold pb-3 border-b border-[var(--line)]">
            Сотрудники ({data.members.length})
          </h3>
          <div className="divide-y divide-[var(--line)] mt-2">
            {data.members.map((m) => (
              <button
                key={m.id}
                type="button"
                onClick={() => openEditMember(m)}
                className="w-full text-left py-3 px-2 -mx-2 rounded-lg hover:bg-[var(--soft)]/50 flex items-center justify-between gap-3 transition-colors"
              >
                <div>
                  <div className="text-sm font-semibold">
                    {m.name}
                    {!m.active && (
                      <span className="ml-2 text-[11px] font-normal text-[var(--muted)]">
                        (неактивен)
                      </span>
                    )}
                  </div>
                  <div className="text-xs text-[var(--muted)]">
                    {ROLE_RU[m.role] || m.role} · {PAY_RU[m.payType] || m.payType}
                  </div>
                </div>
                <div className="text-sm tabular-nums text-right">
                  {m.payType === 'percent'
                    ? `${m.percent || 0}%`
                    : `${formatMoneyCents(m.rateCents || 0, hideAmounts)}`}
                </div>
              </button>
            ))}
          </div>
        </Card>

        <Card>
          <div className="flex items-center justify-between pb-3 border-b border-[var(--line)]">
            <h3 className="text-base font-semibold">Предрасчёт за текущий месяц</h3>
            <span className="text-sm font-semibold tabular-nums">
              {formatMoneyCents(totalPreviewCents, hideAmounts)}
            </span>
          </div>
          <div className="divide-y divide-[var(--line)] mt-2 text-sm">
            {previewLines.map((line) => (
              <div key={line.memberId} className="py-3 flex items-center justify-between gap-3">
                <div>
                  <div className="font-medium">{line.memberName}</div>
                  <div className="text-xs text-[var(--muted)] tabular-nums">
                    {line.minutes} мин · {line.ordersCount} заказов
                    {line.needsReview ? ' · Требует проверки ставки' : ''}
                  </div>
                </div>
                <div className="font-semibold tabular-nums">
                  {formatMoneyCents(line.amountCents, hideAmounts)}
                </div>
              </div>
            ))}
          </div>
        </Card>
      </div>

      {data.payrollPeriods.length > 0 && (
        <Card>
          <h3 className="text-base font-semibold pb-3 border-b border-[var(--line)]">
            Ведомости ({data.payrollPeriods.length})
          </h3>
          <div className="divide-y divide-[var(--line)] mt-2 text-sm">
            {data.payrollPeriods.map((p) => {
              const unpaid = Math.max(0, p.totalAccruedCents - (p.totalPaidCents || 0));
              return (
                <div
                  key={p.id}
                  className="py-3 flex flex-wrap items-center justify-between gap-3 tabular-nums"
                >
                  <div>
                    <div className="font-medium">
                      {p.title}{' '}
                      <span className="text-xs text-[var(--muted)]">
                        ({p.status === 'closed' ? 'закрыта' : 'открыта'})
                      </span>
                    </div>
                    <div className="text-xs text-[var(--muted)]">
                      Начислено: {formatMoneyCents(p.totalAccruedCents, hideAmounts)} · Выплачено:{' '}
                      {formatMoneyCents(p.totalPaidCents || 0, hideAmounts)}
                    </div>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {unpaid > 0 && (
                      <button
                        type="button"
                        onClick={() => {
                          setPayoutPeriod(p);
                          setPayoutAccountId(data.accounts[0]?.id || '');
                          setPayoutRub(centsToRubInput(unpaid));
                        }}
                        className="px-3 py-1.5 rounded-lg bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium"
                      >
                        Выплатить ({formatMoneyCents(unpaid, hideAmounts)})
                      </button>
                    )}
                    {p.status === 'closed' ? (
                      <button
                        type="button"
                        onClick={async () => {
                          await updateWorkspaceEntity(workspace, 'payrollPeriods', p.id, {
                            status: 'open',
                          });
                          onToast('Период переоткрыт для корректировок');
                        }}
                        className="px-3 py-1.5 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium"
                      >
                        Переоткрыть
                      </button>
                    ) : (
                      <button
                        type="button"
                        onClick={async () => {
                          await updateWorkspaceEntity(workspace, 'payrollPeriods', p.id, {
                            status: 'closed',
                            totalAccruedCents: totalPreviewCents,
                            lines: previewLines,
                          });
                          onToast('Ведомость пересчитана и закрыта');
                        }}
                        className="px-3 py-1.5 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium"
                      >
                        Закрыть заново
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </Card>
      )}

      {/* Payout Drawer */}
      <Drawer
        open={Boolean(payoutPeriod)}
        title="Выплата по ведомости"
        subtitle={payoutPeriod?.title}
        onClose={() => setPayoutPeriod(null)}
      >
        {payoutPeriod && (
          <form onSubmit={handlePayoutSubmit} className="space-y-4">
            <label className="block space-y-1 text-sm font-medium">
              <span>Сумма выплаты, ₽</span>
              <input
                type="text"
                required
                value={payoutRub}
                onChange={(e) => setPayoutRub(e.target.value)}
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Счёт списания</span>
              <select
                value={payoutAccountId || data.accounts[0]?.id || ''}
                onChange={(e) => setPayoutAccountId(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                {data.accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name} ({formatMoneyCents(a.balanceCents, hideAmounts)})
                  </option>
                ))}
              </select>
            </label>
            <button
              type="submit"
              className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
            >
              Выплатить и провести расход
            </button>
          </form>
        )}
      </Drawer>

      {/* Edit Member Drawer */}
      <Drawer
        open={Boolean(editingMember)}
        title="Редактировать сотрудника"
        onClose={() => setEditingMember(null)}
      >
        {editingMember && (
          <form onSubmit={handleSaveMember} className="space-y-4">
            <label className="block space-y-1 text-sm font-medium">
              <span>Имя</span>
              <input
                type="text"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <div className="grid grid-cols-2 gap-3">
              <label className="block space-y-1 text-sm font-medium">
                <span>Роль</span>
                <select
                  value={role}
                  onChange={(e) => setRole(e.target.value as UserRole)}
                  className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                >
                  <option value="owner">Владелец</option>
                  <option value="confectioner">Кондитер</option>
                  <option value="seller">Продавец</option>
                  <option value="storekeeper">Кладовщик</option>
                  <option value="marketer">Маркетолог</option>
                  <option value="admin">Администратор</option>
                </select>
              </label>
              <label className="block space-y-1 text-sm font-medium">
                <span>Тип оплаты</span>
                <select
                  value={payType}
                  onChange={(e) => setPayType(e.target.value as PayType)}
                  className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                >
                  <option value="hourly">Почасовая</option>
                  <option value="piece">Сдельная (за заказ)</option>
                  <option value="percent">Процент от заказа</option>
                  <option value="salary">Оклад</option>
                  <option value="mixed">Смешанная</option>
                </select>
              </label>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <label className="block space-y-1 text-sm font-medium">
                <span>Ставка, ₽</span>
                <input
                  type="text"
                  value={rateRub}
                  onChange={(e) => setRateRub(e.target.value)}
                  className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
              <label className="block space-y-1 text-sm font-medium">
                <span>Процент, %</span>
                <input
                  type="number"
                  min={0}
                  max={100}
                  value={percent}
                  onChange={(e) => setPercent(Number(e.target.value) || 0)}
                  className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                />
              </label>
            </div>
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <input
                type="checkbox"
                checked={activeMemberFlag}
                onChange={(e) => setActiveMemberFlag(e.target.checked)}
                className="accent-[var(--accent)]"
              />
              <span>Активный сотрудник</span>
            </label>
            <button
              type="submit"
              className="w-full min-h-[44px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
            >
              Сохранить изменения
            </button>
          </form>
        )}
      </Drawer>

      <Drawer
        open={drawerOpen}
        title="Добавить сотрудника"
        onClose={() => setDrawerOpen(false)}
      >
        <form onSubmit={handleAddMember} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Имя</span>
            <input
              type="text"
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Роль</span>
              <select
                value={role}
                onChange={(e) => setRole(e.target.value as UserRole)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="confectioner">Кондитер</option>
                <option value="seller">Продавец</option>
                <option value="storekeeper">Кладовщик</option>
                <option value="marketer">Маркетолог</option>
                <option value="admin">Администратор</option>
              </select>
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Тип оплаты</span>
              <select
                value={payType}
                onChange={(e) => setPayType(e.target.value as PayType)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="hourly">Почасовая</option>
                <option value="piece">Сдельная (за заказ)</option>
                <option value="percent">Процент от заказа</option>
                <option value="salary">Оклад</option>
                <option value="mixed">Смешанная</option>
              </select>
            </label>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Ставка, ₽</span>
              <input
                type="text"
                value={rateRub}
                onChange={(e) => setRateRub(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Процент, %</span>
              <input
                type="number"
                min={0}
                max={100}
                value={percent}
                onChange={(e) => setPercent(Number(e.target.value) || 0)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          </div>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Добавить
          </button>
        </form>
      </Drawer>
    </div>
  );
}

export function SettingsPage({
  workspace,
  allWorkspaces = [],
  data,
  onSwitchWorkspace,
  onCreateWorkspace,
  onToast,
}: {
  workspace: Workspace;
  allWorkspaces?: Workspace[];
  data: WorkspaceSnapshot;
  onSwitchWorkspace?: (workspaceId: string) => void;
  onCreateWorkspace?: () => void;
  onToast: (msg: string) => void;
}) {
  const hiddenSet = new Set(workspace.hiddenModules || []);
  const pins = workspace.pins || ['work', 'orders', 'recipes'];

  const [studioName, setStudioName] = useState(workspace.name);
  const [studioSlogan, setStudioSlogan] = useState(workspace.slogan || '');
  const [locDrawer, setLocDrawer] = useState(false);
  const [locName, setLocName] = useState('');
  const [locKind, setLocKind] = useState<LocationItem['kind']>('kitchen');
  const [locAddress, setLocAddress] = useState('');

  const [restoring, setRestoring] = useState(false);
  const [restorePreview, setRestorePreview] = useState<{
    fileName: string;
    counts: Record<string, number>;
    parsedData: Partial<Record<keyof WorkspaceSnapshot, Array<Record<string, unknown>>>>;
  } | null>(null);

  const handleToggleModule = async (id: string, visible: boolean) => {
    const next = visible
      ? (workspace.hiddenModules || []).filter((x) => x !== id)
      : [...(workspace.hiddenModules || []), id];
    await updateWorkspacePrefs(workspace.id, { hiddenModules: next });
    onToast(visible ? 'Модуль включён' : 'Модуль скрыт (данные сохранены)');
  };

  const handleTogglePin = async (id: string, checked: boolean) => {
    if (checked && pins.length >= 3) {
      onToast('Можно закрепить не более 3 вкладок для мобильного меню');
      return;
    }
    const next = checked ? [...pins, id] : pins.filter((x) => x !== id);
    await updateWorkspacePrefs(workspace.id, { pins: next });
  };

  const handleExportJson = () => {
    const payload = {
      exportedAt: new Date().toISOString(),
      workspace,
      data,
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], {
      type: 'application/json',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `sweet-studio-backup-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
    onToast('Резервная копия JSON скачана');
  };

  const RESTORABLE_COLLECTIONS: Array<keyof WorkspaceSnapshot> = [
    'clients',
    'suppliers',
    'accounts',
    'inventoryItems',
    'recipes',
    'leads',
    'orders',
    'coupons',
    'contentPosts',
    'recurringPayments',
  ];

  const handleBackupFilePick = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    try {
      const raw = JSON.parse(await file.text()) as {
        data?: Partial<Record<keyof WorkspaceSnapshot, Array<Record<string, unknown>>>>;
      };
      if (!raw?.data || typeof raw.data !== 'object') {
        onToast('Неверный формат файла резервной копии');
        return;
      }
      const counts: Record<string, number> = {};
      const parsedData: Partial<
        Record<keyof WorkspaceSnapshot, Array<Record<string, unknown>>>
      > = {};
      for (const col of RESTORABLE_COLLECTIONS) {
        const arr = Array.isArray(raw.data[col]) ? raw.data[col]! : [];
        const existingIds = new Set(
          (data[col] as Array<{ id: string }>).map((x) => x.id),
        );
        const fresh = arr.filter(
          (item) => typeof item?.id === 'string' && !existingIds.has(item.id),
        );
        if (fresh.length > 0) {
          counts[col] = fresh.length;
          parsedData[col] = fresh;
        }
      }
      setRestorePreview({ fileName: file.name, counts, parsedData });
    } catch {
      onToast('Не удалось прочитать JSON-файл');
    }
  };

  const handleConfirmRestore = async () => {
    if (!restorePreview || restoring) return;
    setRestoring(true);
    let totalRestored = 0;
    try {
      for (const col of RESTORABLE_COLLECTIONS) {
        const items = restorePreview.parsedData[col] || [];
        for (const item of items) {
          const rawId = typeof item.id === 'string' ? item.id : newId('imp');
          const safeId = /^[a-zA-Z0-9_-]{1,128}$/.test(rawId)
            ? rawId
            : newId('imp');
          const cleaned: Record<string, unknown> = {};
          for (const [k, v] of Object.entries(item)) {
            if (
              k === 'id' ||
              k === 'workspaceId' ||
              k === 'ownerId' ||
              k === 'createdAt' ||
              k === 'updatedAt' ||
              v === undefined
            ) {
              continue;
            }
            cleaned[k] = v;
          }
          await createWorkspaceEntity(workspace, col, safeId, cleaned);
          totalRestored += 1;
        }
      }
      setRestorePreview(null);
      onToast(
        totalRestored > 0
          ? `Восстановлено записей: ${totalRestored}`
          : 'Новых записей для восстановления не найдено',
      );
    } catch (err) {
      onToast(
        err instanceof Error ? err.message : 'Ошибка при восстановлении копии',
      );
    } finally {
      setRestoring(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Настройки рабочего пространства"
        subtitle="Темы Soft Atelier, формат бизнеса, модули, закреплённые вкладки и резервные копии"
        action={
          <div className="flex flex-wrap items-center gap-2">
            <label className="min-h-[44px] px-4 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm font-medium inline-flex items-center gap-2 hover:bg-[var(--soft)] cursor-pointer whitespace-nowrap shrink-0">
              <Upload className="w-4 h-4" />
              <span>Импорт JSON</span>
              <input
                type="file"
                accept=".json,application/json"
                className="sr-only"
                onChange={handleBackupFilePick}
              />
            </label>
            <button
              type="button"
              onClick={handleExportJson}
              className="min-h-[44px] px-4 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm font-medium inline-flex items-center gap-2 hover:bg-[var(--soft)] whitespace-nowrap shrink-0"
            >
              <Download className="w-4 h-4" />
              <span>Экспорт JSON</span>
            </button>
          </div>
        }
      />

      {restorePreview && (
        <Card tone="soft" className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h3 className="text-sm font-semibold">
                Предпросмотр восстановления: {restorePreview.fileName}
              </h3>
              <p className="text-xs text-[var(--muted)]">
                Уже существующие в студии записи сохраняются без перезаписи; добавляются только отсутствующие.
              </p>
            </div>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setRestorePreview(null)}
                className="px-3 py-1.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs font-medium"
              >
                Отмена
              </button>
              <button
                type="button"
                disabled={
                  restoring || Object.keys(restorePreview.counts).length === 0
                }
                onClick={handleConfirmRestore}
                className="px-3.5 py-1.5 rounded-lg bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium disabled:opacity-50"
              >
                {restoring ? 'Восстанавливаем...' : 'Восстановить недостающие'}
              </button>
            </div>
          </div>
          <div className="flex flex-wrap gap-2 text-xs">
            {Object.keys(restorePreview.counts).length === 0 ? (
              <span className="text-[var(--muted)]">
                Все записи из резервной копии уже присутствуют в этом пространстве.
              </span>
            ) : (
              Object.entries(restorePreview.counts).map(([col, cnt]) => (
                <span
                  key={col}
                  className="px-2.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] tabular-nums"
                >
                  {col}: +{cnt}
                </span>
              ))
            )}
          </div>
        </Card>
      )}

      <div className="grid lg:grid-cols-2 gap-6">
        <Card className="space-y-4">
          <h2 className="text-base font-semibold">Профиль студии и пространства</h2>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              if (!studioName.trim()) return;
              await updateWorkspacePrefs(workspace.id, {
                name: studioName.trim().slice(0, 120),
                slogan: studioSlogan.trim().slice(0, 200),
              });
              onToast('Название и описание студии обновлены');
            }}
            className="space-y-3"
          >
            <label className="block space-y-1 text-sm font-medium">
              <span>Название кондитерской / студии</span>
              <input
                type="text"
                required
                value={studioName}
                onChange={(e) => setStudioName(e.target.value)}
                className="w-full min-h-[42px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Слоган или подпись на главной</span>
              <input
                type="text"
                value={studioSlogan}
                onChange={(e) => setStudioSlogan(e.target.value)}
                placeholder="Например: Авторские муссовые торты и макаронс"
                className="w-full min-h-[42px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <button
              type="submit"
              className="min-h-[40px] px-4 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium"
            >
              Сохранить профиль студии
            </button>
          </form>

          {(allWorkspaces.length > 0 || onCreateWorkspace) && (
            <div className="pt-4 border-t border-[var(--line)] space-y-2.5">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-semibold">Рабочие пространства</span>
                {onCreateWorkspace && (
                  <button
                    type="button"
                    onClick={onCreateWorkspace}
                    className="px-2.5 py-1 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium"
                  >
                    + Новое пространство
                  </button>
                )}
              </div>
              <div className="space-y-1.5">
                {allWorkspaces.map((ws) => (
                  <div
                    key={ws.id}
                    className={`p-2.5 rounded-xl border flex items-center justify-between gap-2 text-xs ${
                      ws.id === workspace.id
                        ? 'border-[var(--accent)] bg-[var(--soft)]'
                        : 'border-[var(--line)] bg-[var(--bg)]'
                    }`}
                  >
                    <div>
                      <div className="font-semibold">{ws.name}</div>
                      <div className="text-[var(--muted)]">
                        {ws.businessFormat === 'home'
                          ? 'Домашний кондитер'
                          : ws.businessFormat === 'network'
                            ? 'Сеть'
                            : 'Студия'}
                      </div>
                    </div>
                    {ws.id === workspace.id ? (
                      <span className="font-medium text-[var(--accent)]">Активно</span>
                    ) : (
                      onSwitchWorkspace && (
                        <button
                          type="button"
                          onClick={() => onSwitchWorkspace(ws.id)}
                          className="px-2.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)] font-medium"
                        >
                          Переключить
                        </button>
                      )
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </Card>

        <Card className="space-y-4">
          <div className="flex items-center justify-between gap-2">
            <h2 className="text-base font-semibold">Точки, цеха и склады</h2>
            <button
              type="button"
              onClick={() => {
                setLocName('');
                setLocKind('kitchen');
                setLocAddress('');
                setLocDrawer(true);
              }}
              className="px-3 py-1.5 rounded-xl border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium"
            >
              + Точка
            </button>
          </div>
          {data.locations.length === 0 ? (
            <p className="text-xs text-[var(--muted)]">
              Добавьте кухню, точку выдачи или склад, чтобы привязывать заказы и партии.
            </p>
          ) : (
            <div className="divide-y divide-[var(--line)]">
              {data.locations.map((loc) => (
                <div key={loc.id} className="py-2.5 flex items-center justify-between gap-3 text-sm">
                  <div>
                    <div className="font-medium">{loc.name}</div>
                    <div className="text-xs text-[var(--muted)]">
                      {loc.kind === 'kitchen'
                        ? 'Цех / Кухня'
                        : loc.kind === 'store'
                          ? 'Витрина / Точка выдачи'
                          : 'Склад'}
                      {loc.address ? ` · ${loc.address}` : ''}
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={async () => {
                      await deleteWorkspaceEntity(workspace, 'locations', loc.id);
                      onToast(`Точка «${loc.name}» удалена`);
                    }}
                    title="Удалить точку"
                    className="p-1.5 rounded-lg border border-[var(--line)] text-[var(--muted)] hover:text-[var(--danger)]"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              ))}
            </div>
          )}
        </Card>

        <Card className="space-y-4">
          <h2 className="text-base font-semibold">Темы Soft Atelier</h2>
          <div className="grid grid-cols-2 gap-3">
            {SOFT_ATELIER_THEMES.map((t) => (
              <button
                key={t.index}
                type="button"
                onClick={async () => {
                  await updateWorkspacePrefs(workspace.id, { themeIndex: t.index });
                  onToast(`Тема «${t.name}» применена`);
                }}
                className={`p-3 rounded-xl border text-left transition-colors ${
                  (workspace.themeIndex ?? 0) === t.index
                    ? 'border-[var(--accent)] ring-1 ring-[var(--accent)]'
                    : 'border-[var(--line)]'
                }`}
                style={{ backgroundColor: t.bg, color: t.ink }}
              >
                <div className="flex items-center gap-2">
                  <span
                    className="w-4 h-4 rounded-md shrink-0"
                    style={{ backgroundColor: t.accent }}
                  />
                  <span className="text-sm font-semibold">{t.name}</span>
                </div>
              </button>
            ))}
          </div>

          <div className="pt-4 border-t border-[var(--line)] grid sm:grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Формат бизнеса</span>
              <select
                value={workspace.businessFormat}
                onChange={async (e) => {
                  await updateWorkspacePrefs(workspace.id, {
                    businessFormat: e.target.value as BusinessFormat,
                  });
                  onToast('Формат обновлён');
                }}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="home">Домашний кондитер</option>
                <option value="studio">Кондитерская студия</option>
                <option value="network">Сеть кондитерских</option>
              </select>
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Плотность интерфейса</span>
              <select
                value={workspace.density || 'standard'}
                onChange={async (e) => {
                  await updateWorkspacePrefs(workspace.id, {
                    density: e.target.value as UiDensity,
                  });
                }}
                className="w-full min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="standard">Стандартная</option>
                <option value="compact">Компактная</option>
                <option value="spacious">Свободная</option>
              </select>
            </label>
          </div>
        </Card>

        <Card className="space-y-4">
          <h2 className="text-base font-semibold">Модули и закреплённые вкладки</h2>
          <p className="text-xs text-[var(--muted)]">
            Отключение модуля скрывает его из навигации, но сохраняет все данные. Для
            мобильной панели выберите до 3 закреплённых вкладок.
          </p>
          <div className="grid grid-cols-2 gap-2 text-sm">
            {NAV_ITEMS.filter(
              (n) =>
                n.id !== 'dashboard' &&
                n.id !== 'settings' &&
                n.id !== 'academy',
            ).map((item) => {
              const visible = !hiddenSet.has(item.id);
              const pinned = pins.includes(item.id);
              return (
                <div
                  key={item.id}
                  className="p-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] flex items-center justify-between gap-2"
                >
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={visible}
                      onChange={(e) =>
                        handleToggleModule(item.id, e.target.checked)
                      }
                      className="accent-[var(--accent)]"
                    />
                    <span className="truncate">{item.label}</span>
                  </label>
                  <button
                    type="button"
                    onClick={() => handleTogglePin(item.id, !pinned)}
                    className={`px-2 py-0.5 rounded-md text-[11px] border ${
                      pinned
                        ? 'border-[var(--accent)] bg-[var(--soft)]'
                        : 'border-[var(--line)] text-[var(--muted)]'
                    }`}
                  >
                    {pinned ? 'Закреплена' : 'Закрепить'}
                  </button>
                </div>
              );
            })}
          </div>
        </Card>
      </div>

      <Drawer
        open={locDrawer}
        title="Новая точка / цех"
        onClose={() => setLocDrawer(false)}
      >
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            if (!locName.trim()) return;
            await createWorkspaceEntity(workspace, 'locations', newId('loc'), {
              name: locName.trim().slice(0, 120),
              kind: locKind,
              address: locAddress.trim().slice(0, 240),
              isDefault: data.locations.length === 0,
            });
            setLocDrawer(false);
            onToast('Точка добавлена');
          }}
          className="space-y-4"
        >
          <label className="block space-y-1 text-sm font-medium">
            <span>Название</span>
            <input
              type="text"
              required
              value={locName}
              onChange={(e) => setLocName(e.target.value)}
              placeholder="Например: Основная кухня или ТЦ Галерея"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Тип</span>
            <select
              value={locKind}
              onChange={(e) => setLocKind(e.target.value as LocationItem['kind'])}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              <option value="kitchen">Цех / Кухня</option>
              <option value="store">Витрина / Точка выдачи</option>
              <option value="warehouse">Склад</option>
            </select>
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Адрес</span>
            <input
              type="text"
              value={locAddress}
              onChange={(e) => setLocAddress(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Добавить точку
          </button>
        </form>
      </Drawer>
    </div>
  );
}

const ACADEMY_LESSONS = [
  {
    id: 'start',
    title: '1. Первые шаги и профиль бизнеса',
    minutes: 3,
    body: 'Выберите формат («Домашний кондитер», «Студия» или «Сеть») и настройте видимость модулей. Отключение раздела не удаляет ваши данные.',
  },
  {
    id: 'recipe',
    title: '2. Создание рецепта и пересчёт веса',
    minutes: 4,
    body: 'Откройте карточку рецепта, подвигайте ползунок веса или введите точное значение в граммах — ингредиенты и стоимость пересчитаются автоматически.',
  },
  {
    id: 'calc',
    title: '3. Калькулятор себестоимости и маржи',
    minutes: 5,
    body: 'Ядро калькулятора учитывает потери при обработке, время работы мастера, упаковку, доставку, процент эквайринга и показывает точку безубыточности и ROI.',
  },
  {
    id: 'fefo',
    title: '4. Кладовая, партии FEFO и карантин',
    minutes: 4,
    body: 'При списании по FEFO система автоматически выбирает самые ранние годные партии и пропускает просроченные или переведённые в карантин.',
  },
  {
    id: 'orders',
    title: '5. От заявки к заказу и оплатам',
    minutes: 4,
    body: 'Конвертация заявки в заказ выполняется однократно и сразу создаёт карточку в едином пространстве «Работа». Приём оплаты обновляет баланс счёта и журнал.',
  },
  {
    id: 'payroll',
    title: '6. Табель, таймер и закрытие зарплаты',
    minutes: 5,
    body: 'Таймер на главной записывает время в табель. При закрытии периода ведомость сохраняется неизменяемым снимком, совпадающим с предрасчётом.',
  },
];

export function AcademyPage() {
  const [doneIds, setDoneIds] = useState<string[]>(() => {
    try {
      return JSON.parse(localStorage.getItem('sweet_academy_done') || '[]');
    } catch {
      return [];
    }
  });

  const toggle = (id: string) => {
    const next = doneIds.includes(id)
      ? doneIds.filter((x) => x !== id)
      : [...doneIds, id];
    setDoneIds(next);
    localStorage.setItem('sweet_academy_done', JSON.stringify(next));
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Академия Sweet Studio"
        subtitle={`Пройдено уроков: ${doneIds.length} из ${ACADEMY_LESSONS.length}`}
      />
      <div className="grid md:grid-cols-2 gap-4">
        {ACADEMY_LESSONS.map((lesson) => {
          const checked = doneIds.includes(lesson.id);
          return (
            <Card key={lesson.id} className="space-y-2.5">
              <label className="flex items-start gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() => toggle(lesson.id)}
                  className="mt-1 w-4 h-4 accent-[var(--accent)]"
                />
                <div>
                  <div className="text-base font-semibold">{lesson.title}</div>
                  <div className="text-xs text-[var(--muted)] mt-0.5">
                    {lesson.minutes} мин · пошаговый разбор
                  </div>
                </div>
              </label>
              <p className="text-sm text-[var(--muted)] leading-relaxed">
                {lesson.body}
              </p>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
