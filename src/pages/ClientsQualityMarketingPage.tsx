import React, { useMemo, useState } from 'react';
import { Copy, Merge, Printer, QrCode, Star } from 'lucide-react';
import {
  Card,
  Drawer,
  EmptyState,
  PageHeader,
} from '../components/UiPrimitives';
import { centsToRubInput, formatMoneyCents, parseRubToCents } from '../core/moneyFormat';
import {
  addFinancialTransaction,
  createWorkspaceEntity,
  deleteWorkspaceEntity,
  newId,
  recordClientDepositTopUp,
  updateWorkspaceEntity,
  WorkspaceSnapshot,
} from '../firebase/workspaceService';
import { Client, Complaint, ContentPost, Coupon, NavSectionId, OrderStatus, Workspace } from '../types/domain';

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

export function ClientsPage({
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
  const [search, setSearch] = useState('');
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [selectedClient, setSelectedClient] = useState<Client | null>(null);

  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [address, setAddress] = useState('');
  const [source, setSource] = useState('Telegram');
  const [preferences, setPreferences] = useState('');
  const [allergens, setAllergens] = useState('');

  // Edit state for active client
  const [editName, setEditName] = useState('');
  const [editPhone, setEditPhone] = useState('');
  const [editEmail, setEditEmail] = useState('');
  const [editSource, setEditSource] = useState('');
  const [editAddress, setEditAddress] = useState('');
  const [editPreferences, setEditPreferences] = useState('');
  const [editAllergens, setEditAllergens] = useState('');
  const [depositRub, setDepositRub] = useState('1000');
  const [depositAccountId, setDepositAccountId] = useState(data.accounts[0]?.id || '');
  const [mergeOpen, setMergeOpen] = useState(false);
  const [merging, setMerging] = useState(false);

  const activeClient = useMemo(
    () => data.clients.find((c) => c.id === selectedClient?.id) || selectedClient,
    [data.clients, selectedClient],
  );

  const openClientDetail = (c: Client) => {
    setSelectedClient(c);
    setEditName(c.name);
    setEditPhone(c.phone || '');
    setEditEmail(c.email || '');
    setEditSource(c.source || '');
    setEditAddress(c.address || '');
    setEditPreferences(c.preferences || '');
    setEditAllergens(c.allergens || '');
    setDepositAccountId(data.accounts[0]?.id || '');
  };

  const clientOrders = useMemo(() => {
    if (!activeClient) return [];
    const nameLow = activeClient.name.toLowerCase();
    return data.orders.filter(
      (o) =>
        o.clientId === activeClient.id ||
        o.clientName.toLowerCase() === nameLow,
    );
  }, [activeClient, data.orders]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return data.clients.filter(
      (c) =>
        !q ||
        `${c.name} ${c.phone || ''} ${c.preferences || ''} ${c.allergens || ''}`
          .toLowerCase()
          .includes(q),
    );
  }, [data.clients, search]);

  const duplicateWarning = useMemo(() => {
    const digits = phone.replace(/\D/g, '');
    if (digits.length < 6) return null;
    return data.clients.find(
      (c) => c.phone && c.phone.replace(/\D/g, '') === digits,
    );
  }, [phone, data.clients]);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    await createWorkspaceEntity(workspace, 'clients', newId('cli'), {
      name: name.trim().slice(0, 140),
      phone: phone.trim().slice(0, 40),
      source: source.slice(0, 80),
      address: address.trim().slice(0, 240),
      preferences: preferences.trim().slice(0, 400),
      allergens: allergens.trim().slice(0, 240),
      depositCents: 0,
      ordersCount: 0,
      debtCents: 0,
      favorite: false,
    });
    setName('');
    setPhone('');
    setAddress('');
    setPreferences('');
    setAllergens('');
    setDrawerOpen(false);
    onToast('Клиент сохранён');
  };

  const handleSaveEdit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeClient || !editName.trim()) return;
    await updateWorkspaceEntity(workspace, 'clients', activeClient.id, {
      name: editName.trim().slice(0, 140),
      phone: editPhone.trim().slice(0, 40),
      email: editEmail.trim().slice(0, 160),
      source: editSource.trim().slice(0, 80),
      address: editAddress.trim().slice(0, 240),
      preferences: editPreferences.trim().slice(0, 400),
      allergens: editAllergens.trim().slice(0, 240),
    });
    onToast('Карточка клиента обновлена');
  };

  const duplicatePairs = useMemo(() => {
    const pairs: Array<{ primary: Client; duplicate: Client; reason: string }> = [];
    const seen = new Set<string>();
    for (let i = 0; i < data.clients.length; i++) {
      for (let j = i + 1; j < data.clients.length; j++) {
        const a = data.clients[i];
        const b = data.clients[j];
        if (seen.has(a.id) || seen.has(b.id)) continue;
        const phoneA = (a.phone || '').replace(/\D+/g, '');
        const phoneB = (b.phone || '').replace(/\D+/g, '');
        const samePhone = phoneA.length >= 6 && phoneA === phoneB;
        const sameName = a.name.trim().toLowerCase() === b.name.trim().toLowerCase();
        if (samePhone || sameName) {
          pairs.push({
            primary: a,
            duplicate: b,
            reason: samePhone ? `Совпадает телефон (${a.phone})` : `Совпадает имя (${a.name})`,
          });
          seen.add(b.id);
        }
      }
    }
    return pairs;
  }, [data.clients]);

  const handleMergePair = async (primary: Client, duplicate: Client) => {
    setMerging(true);
    try {
      const affectedOrders = data.orders.filter(
        (o) =>
          o.clientId === duplicate.id ||
          (!o.clientId && o.clientName.trim().toLowerCase() === duplicate.name.trim().toLowerCase()),
      );
      for (const ord of affectedOrders) {
        await updateWorkspaceEntity(workspace, 'orders', ord.id, {
          clientId: primary.id,
          clientName: primary.name.slice(0, 140),
        });
      }
      await updateWorkspaceEntity(workspace, 'clients', primary.id, {
        phone: (primary.phone || duplicate.phone || '').slice(0, 40),
        email: (primary.email || duplicate.email || '').slice(0, 160),
        address: (primary.address || duplicate.address || '').slice(0, 240),
        preferences: [primary.preferences, duplicate.preferences].filter(Boolean).join('; ').slice(0, 400),
        allergens: [primary.allergens, duplicate.allergens].filter(Boolean).join('; ').slice(0, 240),
        depositCents: (primary.depositCents || 0) + (duplicate.depositCents || 0),
        debtCents: (primary.debtCents || 0) + (duplicate.debtCents || 0),
        ordersCount: Math.max((primary.ordersCount || 0) + (duplicate.ordersCount || 0), affectedOrders.length),
      });
      await deleteWorkspaceEntity(workspace, 'clients', duplicate.id);
      onToast(`Клиенты объединены в карточку «${primary.name}»`);
    } finally {
      setMerging(false);
    }
  };

  const handleDepositChange = async (deltaSign: 1 | -1) => {
    if (!activeClient) return;
    const cents = parseRubToCents(depositRub);
    if (cents <= 0) return;
    if (deltaSign > 0) {
      const acc =
        data.accounts.find((a) => a.id === depositAccountId) || data.accounts[0];
      if (!acc) {
        onToast('Сначала добавьте счёт в разделе «Финансы»');
        return;
      }
      await recordClientDepositTopUp({
        workspace,
        client: activeClient,
        account: acc,
        amountCents: cents,
      });
      onToast(`Депозит пополнен на ${formatMoneyCents(cents)}`);
      return;
    }
    const prev = activeClient.depositCents || 0;
    if (prev <= 0) {
      onToast('На депозите нет средств');
      return;
    }
    const nextDeposit = Math.max(0, prev - cents);
    await updateWorkspaceEntity(workspace, 'clients', activeClient.id, {
      depositCents: nextDeposit,
    });
    onToast(`Списано с депозита ${formatMoneyCents(Math.min(prev, cents))}`);
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Клиенты"
        subtitle="Вкусы, аллергены со слов клиента, адреса доставки, депозиты и контроль дублей"
        action={
          <div className="flex flex-wrap gap-2">
            {duplicatePairs.length > 0 && (
              <button
                type="button"
                onClick={() => setMergeOpen(true)}
                className="min-h-[44px] px-3.5 py-2 rounded-xl border border-[var(--line)] bg-[var(--warm)] text-[var(--warm-ink)] text-sm font-medium inline-flex items-center gap-1.5 whitespace-nowrap"
              >
                <Merge className="w-4 h-4" />
                <span>Дубли: {duplicatePairs.length}</span>
              </button>
            )}
            <button
              type="button"
              onClick={() => setDrawerOpen(true)}
              className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
            >
              + Клиент
            </button>
          </div>
        }
      />

      <input
        type="search"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        placeholder="Поиск по имени, телефону, вкусам..."
        className="w-full sm:w-80 min-h-[42px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm"
      />

      {filtered.length === 0 ? (
        <EmptyState
          title="Клиенты не найдены"
          description="Добавьте карточку клиента с предпочтениями и аллергенами."
          actionLabel="+ Добавить клиента"
          onAction={() => setDrawerOpen(true)}
        />
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {filtered.map((c) => {
            const linkedCount = data.orders.filter(
              (o) =>
                o.clientId === c.id ||
                o.clientName.toLowerCase() === c.name.toLowerCase(),
            ).length;
            return (
              <button
                key={c.id}
                type="button"
                onClick={() => openClientDetail(c)}
                className="text-left w-full block rounded-2xl focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)]"
              >
                <Card className="space-y-2.5 cursor-pointer hover:border-[var(--accent)] transition-colors h-full">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <h3 className="text-base font-semibold flex items-center gap-1.5">
                        {c.favorite && (
                          <Star className="w-3.5 h-3.5 fill-[var(--accent)] text-[var(--accent)] shrink-0" />
                        )}
                        <span>{c.name}</span>
                      </h3>
                      <div className="text-xs text-[var(--muted)]">
                        {c.phone || 'Телефон не указан'} · Заказов:{' '}
                        {Math.max(c.ordersCount || 0, linkedCount)}
                        {c.source ? ` · ${c.source}` : ''}
                      </div>
                    </div>
                    <div className="text-right tabular-nums text-xs">
                      <div>
                        Депозит: {formatMoneyCents(c.depositCents || 0, hideAmounts)}
                      </div>
                      {(c.debtCents || 0) > 0 && (
                        <div className="text-[var(--danger)]">
                          Долг: {formatMoneyCents(c.debtCents || 0, hideAmounts)}
                        </div>
                      )}
                    </div>
                  </div>
                  {c.preferences && (
                    <div className="text-sm">
                      <span className="text-[var(--muted)]">Предпочтения: </span>
                      {c.preferences}
                    </div>
                  )}
                  {c.allergens && (
                    <div className="text-xs text-[var(--warm-ink)] bg-[var(--warm)] px-2.5 py-1.5 rounded-lg">
                      Аллергены: {c.allergens}
                    </div>
                  )}
                  {c.address && (
                    <div className="text-xs text-[var(--muted)]">Адрес: {c.address}</div>
                  )}
                </Card>
              </button>
            );
          })}
        </div>
      )}

      {/* Client Detail & Edit Drawer */}
      <Drawer
        open={Boolean(activeClient)}
        title={activeClient ? activeClient.name : ''}
        subtitle={
          activeClient
            ? `Депозит: ${formatMoneyCents(activeClient.depositCents || 0, hideAmounts)}`
            : ''
        }
        onClose={() => setSelectedClient(null)}
      >
        {activeClient && (
          <div className="space-y-6">
            <div className="flex items-center justify-between gap-2 p-3 rounded-xl bg-[var(--soft)]">
              <div className="text-sm">
                <span className="text-[var(--muted)]">Баланс депозита: </span>
                <strong className="tabular-nums">
                  {formatMoneyCents(activeClient.depositCents || 0, hideAmounts)}
                </strong>
              </div>
              <button
                type="button"
                onClick={async () => {
                  await updateWorkspaceEntity(workspace, 'clients', activeClient.id, {
                    favorite: !activeClient.favorite,
                  });
                }}
                className="px-3 py-1.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs font-medium inline-flex items-center gap-1"
              >
                <Star
                  className={`w-3.5 h-3.5 ${
                    activeClient.favorite
                      ? 'fill-[var(--accent)] text-[var(--accent)]'
                      : 'text-[var(--muted)]'
                  }`}
                />
                <span>{activeClient.favorite ? 'В избранном' : 'В избранное'}</span>
              </button>
            </div>

            {/* Deposit top-up / use */}
            <div className="p-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] space-y-2.5">
              <div className="text-xs font-semibold">Операция с депозитом</div>
              <div className="grid grid-cols-2 gap-2">
                <input
                  type="text"
                  value={depositRub}
                  onChange={(e) => setDepositRub(e.target.value)}
                  placeholder="Сумма, ₽"
                  className="min-h-[38px] px-3 rounded-lg border border-[var(--line)] bg-[var(--card)] text-sm tabular-nums"
                />
                <select
                  value={depositAccountId || data.accounts[0]?.id || ''}
                  onChange={(e) => setDepositAccountId(e.target.value)}
                  className="min-h-[38px] px-2 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs"
                >
                  {data.accounts.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => handleDepositChange(1)}
                  className="min-h-[38px] rounded-lg bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium"
                >
                  + Пополнить депозит
                </button>
                <button
                  type="button"
                  onClick={() => handleDepositChange(-1)}
                  className="min-h-[38px] rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs font-medium hover:bg-[var(--soft)]"
                >
                  − Списать с депозита
                </button>
              </div>
            </div>

            {/* Edit Form */}
            <form onSubmit={handleSaveEdit} className="space-y-3">
              <div className="text-xs font-semibold text-[var(--muted)]">
                Профиль клиента
              </div>
              <label className="block space-y-1 text-xs font-medium">
                <span>Имя</span>
                <input
                  type="text"
                  required
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
                />
              </label>
              <div className="grid grid-cols-2 gap-2">
                <label className="block space-y-1 text-xs font-medium">
                  <span>Телефон</span>
                  <input
                    type="text"
                    value={editPhone}
                    onChange={(e) => setEditPhone(e.target.value)}
                    className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
                  />
                </label>
                <label className="block space-y-1 text-xs font-medium">
                  <span>Источник</span>
                  <input
                    type="text"
                    value={editSource}
                    onChange={(e) => setEditSource(e.target.value)}
                    className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
                  />
                </label>
              </div>
              <label className="block space-y-1 text-xs font-medium">
                <span>Email</span>
                <input
                  type="email"
                  value={editEmail}
                  onChange={(e) => setEditEmail(e.target.value)}
                  className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
                />
              </label>
              <label className="block space-y-1 text-xs font-medium">
                <span>Адрес доставки</span>
                <input
                  type="text"
                  value={editAddress}
                  onChange={(e) => setEditAddress(e.target.value)}
                  className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
                />
              </label>
              <label className="block space-y-1 text-xs font-medium">
                <span>Предпочтения</span>
                <input
                  type="text"
                  value={editPreferences}
                  onChange={(e) => setEditPreferences(e.target.value)}
                  className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
                />
              </label>
              <label className="block space-y-1 text-xs font-medium">
                <span>Аллергены со слов клиента</span>
                <input
                  type="text"
                  value={editAllergens}
                  onChange={(e) => setEditAllergens(e.target.value)}
                  className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
                />
              </label>
              <button
                type="submit"
                className="w-full min-h-[42px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
              >
                Сохранить изменения
              </button>
            </form>

            {/* Orders History */}
            <div className="space-y-2 pt-3 border-t border-[var(--line)]">
              <div className="text-xs font-semibold">
                История заказов ({clientOrders.length})
              </div>
              {clientOrders.length === 0 ? (
                <p className="text-xs text-[var(--muted)]">
                  Заказов по этому клиенту пока нет.
                </p>
              ) : (
                <div className="divide-y divide-[var(--line)] text-xs">
                  {clientOrders.map((ord) => (
                    <div
                      key={ord.id}
                      className="py-2 flex items-center justify-between gap-2 tabular-nums"
                    >
                      <div>
                        <div className="font-medium">
                          {ord.orderNumber} · {ord.title}
                        </div>
                        <div className="text-[var(--muted)]">
                          {ord.dueDate || '—'} · {ORDER_STATUS_RU[ord.status] || ord.status}
                        </div>
                      </div>
                      <div className="font-semibold">
                        {formatMoneyCents(ord.priceCents, hideAmounts)}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </Drawer>

      {/* New Client Drawer */}
      <Drawer
        open={drawerOpen}
        title="Новый клиент"
        onClose={() => setDrawerOpen(false)}
      >
        <form onSubmit={handleCreate} className="space-y-4">
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
              <span>Телефон</span>
              <input
                type="text"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
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
          {duplicateWarning && (
            <span className="text-xs text-[var(--danger)] block">
              Найден клиент с таким телефоном: {duplicateWarning.name}
            </span>
          )}
          <label className="block space-y-1 text-sm font-medium">
            <span>Адрес доставки</span>
            <input
              type="text"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Предпочтения</span>
            <input
              type="text"
              value={preferences}
              onChange={(e) => setPreferences(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Аллергены со слов клиента</span>
            <input
              type="text"
              value={allergens}
              onChange={(e) => setAllergens(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Сохранить клиента
          </button>
        </form>
      </Drawer>

      {/* Merge Duplicates Drawer */}
      <Drawer
        open={mergeOpen}
        title="Объединение дублей клиентов"
        subtitle="Все заказы, депозиты и заметки будут перенесены в основную карточку"
        onClose={() => setMergeOpen(false)}
      >
        {duplicatePairs.length === 0 ? (
          <p className="text-sm text-[var(--muted)]">Дублей не обнаружено.</p>
        ) : (
          <div className="space-y-3">
            {duplicatePairs.map(({ primary, duplicate, reason }) => (
              <Card key={`${primary.id}_${duplicate.id}`} className="space-y-2.5">
                <div className="text-xs text-[var(--warm-ink)] bg-[var(--warm)] px-2.5 py-1 rounded-lg">
                  {reason}
                </div>
                <div className="grid grid-cols-2 gap-2 text-xs">
                  <div className="p-2.5 rounded-xl bg-[var(--soft)]">
                    <div className="font-semibold">Оставить: {primary.name}</div>
                    <div className="text-[var(--muted)]">{primary.phone || '—'}</div>
                  </div>
                  <div className="p-2.5 rounded-xl border border-[var(--line)]">
                    <div className="font-semibold">Слить: {duplicate.name}</div>
                    <div className="text-[var(--muted)]">{duplicate.phone || '—'}</div>
                  </div>
                </div>
                <button
                  type="button"
                  disabled={merging}
                  onClick={() => handleMergePair(primary, duplicate)}
                  className="w-full min-h-[40px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium disabled:opacity-60"
                >
                  {merging ? 'Объединяем...' : 'Объединить в одну карточку'}
                </button>
              </Card>
            ))}
          </div>
        )}
      </Drawer>
    </div>
  );
}

function SimpleQrSvg({ value }: { value: string }) {
  const cells = useMemo(() => {
    const size = 15;
    let hash = 2166136261;
    for (let i = 0; i < value.length; i++) {
      hash ^= value.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    const grid: boolean[] = [];
    for (let r = 0; r < size; r++) {
      for (let c = 0; c < size; c++) {
        const inFinder =
          (r < 4 && c < 4) ||
          (r < 4 && c >= size - 4) ||
          (r >= size - 4 && c < 4);
        if (inFinder) {
          const fr = r >= size - 4 ? r - (size - 4) : r;
          const fc = c >= size - 4 ? c - (size - 4) : c;
          grid.push(fr === 0 || fr === 3 || fc === 0 || fc === 3 || (fr >= 1 && fr <= 2 && fc >= 1 && fc <= 2));
        } else {
          hash ^= (r * 31 + c * 17) & 0xff;
          hash = Math.imul(hash, 16777619);
          grid.push((hash & 1) === 1);
        }
      }
    }
    return { size, grid };
  }, [value]);

  return (
    <svg
      viewBox={`0 0 ${cells.size} ${cells.size}`}
      className="w-28 h-28 rounded-lg bg-white p-1.5 border border-[var(--line)]"
      aria-label={`QR-код для ${value}`}
    >
      {cells.grid.map((on, i) =>
        on ? (
          <rect
            key={i}
            x={i % cells.size}
            y={Math.floor(i / cells.size)}
            width={1}
            height={1}
            fill="#141414"
          />
        ) : null,
      )}
    </svg>
  );
}

export function LoyaltyPage({
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
  const [previewCoupon, setPreviewCoupon] = useState<Coupon | null>(null);
  const [code, setCode] = useState(`SWEET-${Math.floor(100 + Math.random() * 899)}`);
  const [clientId, setClientId] = useState('');
  const [clientName, setClientName] = useState('');
  const [discountType, setDiscountType] = useState<Coupon['discountType']>('percent');
  const [discountInput, setDiscountInput] = useState('10');
  const [minOrderRub, setMinOrderRub] = useState('');

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!code.trim()) return;
    const selectedClient = data.clients.find((c) => c.id === clientId);
    const val =
      discountType === 'percent'
        ? Math.min(95, Math.max(1, Math.round(Number(discountInput) || 10)))
        : Math.max(100, parseRubToCents(discountInput));
    const minCents = parseRubToCents(minOrderRub);

    const payload: Record<string, unknown> = {
      code: code.trim().toUpperCase().slice(0, 40),
      clientName: (selectedClient?.name || clientName.trim()).slice(0, 140),
      discountType,
      discountValue: val,
      expiresAt: new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10),
      status: 'active',
    };
    if (selectedClient) payload.clientId = selectedClient.id;
    if (minCents > 0) payload.minOrderCents = minCents;

    await createWorkspaceEntity(workspace, 'coupons', newId('cup'), payload);
    setCode(`SWEET-${Math.floor(100 + Math.random() * 899)}`);
    setClientId('');
    setClientName('');
    setMinOrderRub('');
    setDrawerOpen(false);
    onToast('Одноразовый купон выпущен');
  };

  const handleRedeem = async (coupon: Coupon) => {
    if (coupon.status !== 'active') return;
    await updateWorkspaceEntity(workspace, 'coupons', coupon.id, {
      status: 'redeemed',
    });
    onToast(`Купон ${coupon.code} погашен (повторное использование заблокировано)`);
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Лояльность и купоны"
        subtitle="Персональные одноразовые купоны с защитой от двойного погашения"
        action={
          <button
            type="button"
            onClick={() => setDrawerOpen(true)}
            className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
          >
            + Выпустить купон
          </button>
        }
      />

      {data.coupons.length === 0 ? (
        <EmptyState
          title="Купонов пока нет"
          description="Выпустите персональный промокод или купон на скидку."
          actionLabel="+ Выпустить купон"
          onAction={() => setDrawerOpen(true)}
        />
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {data.coupons.map((c) => (
            <Card key={c.id} className="space-y-3">
              <div className="flex items-center justify-between gap-2">
                <span className="font-mono font-semibold text-base">{c.code}</span>
                <span className="text-xs text-[var(--muted)]">
                  {c.status === 'active'
                    ? 'Активен'
                    : c.status === 'redeemed'
                      ? 'Погашен'
                      : 'Истёк'}
                </span>
              </div>
              <div className="text-sm">
                Скидка:{' '}
                <strong className="tabular-nums">
                  {c.discountType === 'percent'
                    ? `${c.discountValue}%`
                    : formatMoneyCents(c.discountValue, hideAmounts)}
                </strong>
                {c.minOrderCents ? (
                  <span className="text-xs text-[var(--muted)] ml-1.5">
                    от {formatMoneyCents(c.minOrderCents, hideAmounts)}
                  </span>
                ) : null}
              </div>
              <div className="text-xs text-[var(--muted)]">
                Клиент: {c.clientName || 'Любой'} · до {c.expiresAt || 'бессрочно'}
              </div>
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => setPreviewCoupon(c)}
                  className="px-3 min-h-[38px] rounded-xl border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium inline-flex items-center gap-1"
                >
                  <QrCode className="w-3.5 h-3.5" />
                  <span>Карточка</span>
                </button>
                {c.status === 'active' && (
                  <button
                    type="button"
                    onClick={() => handleRedeem(c)}
                    className="flex-1 min-h-[38px] rounded-xl border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium"
                  >
                    Погасить купон
                  </button>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}

      {/* Printable Coupon Card Drawer */}
      <Drawer
        open={Boolean(previewCoupon)}
        title="Подарочный купон"
        onClose={() => setPreviewCoupon(null)}
      >
        {previewCoupon && (
          <div className="space-y-4">
            <div className="p-5 rounded-2xl border-2 border-dashed border-[var(--accent)] bg-[var(--soft)] text-center space-y-3">
              <div className="text-xs uppercase tracking-widest text-[var(--muted)]">
                {workspace.name}
              </div>
              <div className="text-2xl font-bold font-mono tracking-wider">
                {previewCoupon.code}
              </div>
              <div className="flex justify-center">
                <SimpleQrSvg value={`${workspace.name}:${previewCoupon.code}`} />
              </div>
              <div className="text-lg font-semibold">
                Скидка{' '}
                {previewCoupon.discountType === 'percent'
                  ? `${previewCoupon.discountValue}%`
                  : formatMoneyCents(previewCoupon.discountValue, false)}
              </div>
              <div className="text-xs text-[var(--muted)]">
                {previewCoupon.clientName ? `Для: ${previewCoupon.clientName} · ` : ''}
                {previewCoupon.minOrderCents
                  ? `При заказе от ${formatMoneyCents(previewCoupon.minOrderCents, false)} · `
                  : ''}
                Действует до {previewCoupon.expiresAt || 'бессрочно'}
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={async () => {
                  try {
                    await navigator.clipboard.writeText(previewCoupon.code);
                    onToast(`Код ${previewCoupon.code} скопирован`);
                  } catch {
                    onToast(`Код: ${previewCoupon.code}`);
                  }
                }}
                className="min-h-[42px] rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs font-medium inline-flex items-center justify-center gap-1.5"
              >
                <Copy className="w-3.5 h-3.5" />
                <span>Скопировать код</span>
              </button>
              <button
                type="button"
                onClick={() => window.print()}
                className="min-h-[42px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium inline-flex items-center justify-center gap-1.5"
              >
                <Printer className="w-3.5 h-3.5" />
                <span>Распечатать</span>
              </button>
            </div>
          </div>
        )}
      </Drawer>

      <Drawer
        open={drawerOpen}
        title="Выпустить одноразовый купон"
        onClose={() => setDrawerOpen(false)}
      >
        <form onSubmit={handleCreate} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Код купона</span>
            <input
              type="text"
              required
              value={code}
              onChange={(e) => setCode(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] font-mono"
            />
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Клиент из базы</span>
            <select
              value={clientId}
              onChange={(e) => {
                setClientId(e.target.value);
                const found = data.clients.find((c) => c.id === e.target.value);
                if (found) setClientName(found.name);
              }}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              <option value="">Любой клиент / указать вручную</option>
              {data.clients.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} {c.phone ? `(${c.phone})` : ''}
                </option>
              ))}
            </select>
          </label>
          {!clientId && (
            <label className="block space-y-1 text-sm font-medium">
              <span>Имя клиента (если не из базы)</span>
              <input
                type="text"
                value={clientName}
                onChange={(e) => setClientName(e.target.value)}
                placeholder="Необязательно"
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          )}
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Тип скидки</span>
              <select
                value={discountType}
                onChange={(e) => {
                  const next = e.target.value as Coupon['discountType'];
                  setDiscountType(next);
                  setDiscountInput(next === 'percent' ? '10' : '500');
                }}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="percent">Процент (%)</option>
                <option value="fixed">Фикс (₽)</option>
              </select>
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>{discountType === 'percent' ? 'Процент, %' : 'Сумма скидки, ₽'}</span>
              <input
                type="text"
                value={discountInput}
                onChange={(e) => setDiscountInput(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          </div>
          <label className="block space-y-1 text-sm font-medium">
            <span>Минимальная сумма заказа, ₽ (необязательно)</span>
            <input
              type="text"
              value={minOrderRub}
              onChange={(e) => setMinOrderRub(e.target.value)}
              placeholder="Например: 3000"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Выпустить
          </button>
        </form>
      </Drawer>
    </div>
  );
}

export function QualityPage({
  workspace,
  data,
  onNavigate,
  onToast,
}: {
  workspace: Workspace;
  data: WorkspaceSnapshot;
  onNavigate?: (page: NavSectionId) => void;
  onToast: (msg: string) => void;
}) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [severity, setSeverity] = useState<'low' | 'medium' | 'high'>('medium');
  const [orderId, setOrderId] = useState('');
  const [lotId, setLotId] = useState('');
  const [resolution, setResolution] = useState('');

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    const payload: Record<string, unknown> = {
      title: title.trim().slice(0, 160),
      severity,
      status: 'open',
      responsibleName: 'Владелец',
      resolution: resolution.trim().slice(0, 400),
    };
    if (orderId) payload.orderId = orderId;
    if (lotId) payload.lotId = lotId;

    await createWorkspaceEntity(workspace, 'complaints', newId('cmp'), payload);
    if (lotId) {
      await updateWorkspaceEntity(workspace, 'stockLots', lotId, {
        status: 'quarantine',
      });
    }
    setTitle('');
    setOrderId('');
    setLotId('');
    setResolution('');
    setDrawerOpen(false);
    onToast(lotId ? 'Жалоба записана, партия переведена в карантин' : 'Запись добавлена');
  };

  const issueCompensationCoupon = async (c: Complaint) => {
    const linkedOrder = c.orderId ? data.orders.find((o) => o.id === c.orderId) : undefined;
    const code = `CARE-${Math.floor(100 + Math.random() * 899)}`;
    const payload: Record<string, unknown> = {
      code,
      clientName: (linkedOrder?.clientName || 'Компенсация качества').slice(0, 140),
      discountType: 'percent',
      discountValue: 15,
      expiresAt: new Date(Date.now() + 45 * 86400000).toISOString().slice(0, 10),
      status: 'active',
    };
    if (linkedOrder?.clientId) payload.clientId = linkedOrder.clientId;
    await createWorkspaceEntity(workspace, 'coupons', newId('cup'), payload);
    await updateWorkspaceEntity(workspace, 'complaints', c.id, {
      resolution: `${c.resolution ? c.resolution + ' · ' : ''}Выдан купон ${code} (15%)`.slice(0, 400),
    });
    onToast(`Выдан компенсационный купон ${code} (-15%)`);
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Контроль качества"
        subtitle="Жалобы, привязка к заказам и блокировка проблемных партий на карантин"
        action={
          <button
            type="button"
            onClick={() => setDrawerOpen(true)}
            className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
          >
            + Новая запись
          </button>
        }
      />

      {data.complaints.length === 0 ? (
        <EmptyState
          title="Замечаний нет"
          description="Здесь фиксируются проверки качества и отзывы, требующие корректировки."
          actionLabel="+ Добавить проверку"
          onAction={() => setDrawerOpen(true)}
        />
      ) : (
        <div className="space-y-3">
          {data.complaints.map((c) => {
            const ord = c.orderId ? data.orders.find((o) => o.id === c.orderId) : undefined;
            const lot = c.lotId ? data.stockLots.find((l) => l.id === c.lotId) : undefined;
            return (
              <Card key={c.id} className="space-y-3">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                  <div className="space-y-1">
                    <div className="text-xs text-[var(--muted)]">
                      Критичность: {c.severity === 'high' ? 'Высокая' : c.severity === 'medium' ? 'Средняя' : 'Низкая'} · Ответственный: {c.responsibleName || '—'}
                      {ord ? ` · Заказ ${ord.orderNumber}` : ''}
                      {lot ? ` · Партия ${lot.lotCode}` : ''}
                    </div>
                    <div className="text-base font-semibold">{c.title}</div>
                    {c.resolution && (
                      <div className="text-sm text-[var(--muted)]">{c.resolution}</div>
                    )}
                  </div>
                  <select
                    aria-label="Статус проверки"
                    value={c.status}
                    onChange={async (e) => {
                      await updateWorkspaceEntity(workspace, 'complaints', c.id, {
                        status: e.target.value,
                      });
                      onToast('Статус проверки обновлён');
                    }}
                    className="min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm shrink-0"
                  >
                    <option value="open">Открыта</option>
                    <option value="investigating">Проверка</option>
                    <option value="resolved">Решена</option>
                  </select>
                </div>
                <div className="flex flex-wrap gap-2 pt-2 border-t border-[var(--line)]">
                  <button
                    type="button"
                    onClick={() => issueCompensationCoupon(c)}
                    className="px-3 py-1.5 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium"
                  >
                    Выдать купон −15%
                  </button>
                  {onNavigate && (
                    <button
                      type="button"
                      onClick={() => onNavigate('recipes')}
                      className="px-3 py-1.5 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium"
                    >
                      Обновить техкарту
                    </button>
                  )}
                </div>
              </Card>
            );
          })}
        </div>
      )}

      <Drawer
        open={drawerOpen}
        title="Новая запись качества"
        onClose={() => setDrawerOpen(false)}
      >
        <form onSubmit={handleCreate} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Суть обращения или проверки</span>
            <input
              type="text"
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Связанный заказ</span>
            <select
              value={orderId}
              onChange={(e) => setOrderId(e.target.value)}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              <option value="">Без заказа</option>
              {data.orders.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.orderNumber} · {o.title} ({o.clientName})
                </option>
              ))}
            </select>
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Критичность</span>
              <select
                value={severity}
                onChange={(e) =>
                  setSeverity(e.target.value as 'low' | 'medium' | 'high')
                }
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="low">Низкая</option>
                <option value="medium">Средняя</option>
                <option value="high">Высокая</option>
              </select>
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Связать с партией (карантин)</span>
              <select
                value={lotId}
                onChange={(e) => setLotId(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="">Без партии</option>
                {data.stockLots
                  .filter((l) => l.status === 'active')
                  .map((l) => (
                    <option key={l.id} value={l.id}>
                      {l.lotCode} · {l.itemName}
                    </option>
                  ))}
              </select>
            </label>
          </div>
          <label className="block space-y-1 text-sm font-medium">
            <span>План действий</span>
            <textarea
              rows={3}
              value={resolution}
              onChange={(e) => setResolution(e.target.value)}
              className="w-full p-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Сохранить
          </button>
        </form>
      </Drawer>
    </div>
  );
}

export function MarketingPage({
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
  const [editingPost, setEditingPost] = useState<ContentPost | null>(null);
  const [channel, setChannel] = useState('Telegram');
  const [channelUrl, setChannelUrl] = useState('');
  const [title, setTitle] = useState('');
  const [scheduledDate, setScheduledDate] = useState(
    new Date().toISOString().slice(0, 10),
  );
  const [budgetRub, setBudgetRub] = useState('0');
  const [spendAccountId, setSpendAccountId] = useState(data.accounts[0]?.id || '');

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    const payload: Record<string, unknown> = {
      channel,
      title: title.trim().slice(0, 160),
      scheduledDate,
      status: 'idea',
      budgetCents: parseRubToCents(budgetRub),
    };
    if (channelUrl.trim()) payload.channelUrl = channelUrl.trim().slice(0, 240);
    await createWorkspaceEntity(workspace, 'contentPosts', newId('post'), payload);
    setTitle('');
    setChannelUrl('');
    setBudgetRub('0');
    setDrawerOpen(false);
    onToast('Публикация добавлена в контент-план');
  };

  const openEditPost = (p: ContentPost) => {
    setEditingPost(p);
    setChannel(p.channel);
    setChannelUrl(p.channelUrl || '');
    setTitle(p.title);
    setScheduledDate(p.scheduledDate);
    setBudgetRub(centsToRubInput(p.budgetCents || 0));
    setSpendAccountId(data.accounts[0]?.id || '');
  };

  const handleSaveEdit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingPost || !title.trim()) return;
    await updateWorkspaceEntity(workspace, 'contentPosts', editingPost.id, {
      channel,
      channelUrl: channelUrl.trim().slice(0, 240),
      title: title.trim().slice(0, 160),
      scheduledDate,
      budgetCents: parseRubToCents(budgetRub),
    });
    setEditingPost(null);
    onToast('Публикация обновлена');
  };

  const handleRecordSpend = async () => {
    if (!editingPost) return;
    const cents = parseRubToCents(budgetRub);
    if (cents <= 0) {
      onToast('Укажите бюджет больше 0 ₽');
      return;
    }
    const acc = data.accounts.find((a) => a.id === spendAccountId) || data.accounts[0];
    if (!acc) {
      onToast('Сначала добавьте счёт в разделе «Финансы»');
      return;
    }
    await addFinancialTransaction({
      workspace,
      account: acc,
      kind: 'expense',
      category: 'Маркетинг и реклама',
      amountCents: cents,
      note: `${channel}: ${title}`.slice(0, 240),
    });
    onToast(`Расход ${formatMoneyCents(cents)} проведён в Финансы`);
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Продвижение и контент-план"
        subtitle="Площадки, расписание публикаций и учёт рекламного бюджета"
        action={
          <button
            type="button"
            onClick={() => {
              setTitle('');
              setChannelUrl('');
              setBudgetRub('0');
              setDrawerOpen(true);
            }}
            className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
          >
            + Публикация
          </button>
        }
      />

      {data.contentPosts.length === 0 ? (
        <EmptyState
          title="Контент-план пуст"
          description="Планируйте съёмки тортов, рилс и посты для привлечения заказов."
          actionLabel="+ Добавить публикацию"
          onAction={() => setDrawerOpen(true)}
        />
      ) : (
        <Card className="p-0 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-xs text-[var(--muted)]">
                  <th className="text-left px-4 py-3 font-medium">Площадка</th>
                  <th className="text-left px-4 py-3 font-medium">Тема</th>
                  <th className="text-left px-4 py-3 font-medium">Дата</th>
                  <th className="text-right px-4 py-3 font-medium">Бюджет</th>
                  <th className="text-right px-4 py-3 font-medium">Статус</th>
                  <th className="text-right px-4 py-3 font-medium">Действие</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--line)]">
                {data.contentPosts.map((p) => (
                  <tr key={p.id}>
                    <td className="px-4 py-3.5 font-medium">{p.channel}</td>
                    <td className="px-4 py-3.5">{p.title}</td>
                    <td className="px-4 py-3.5 tabular-nums text-[var(--muted)]">
                      {p.scheduledDate}
                    </td>
                    <td className="px-4 py-3.5 text-right tabular-nums">
                      {formatMoneyCents(p.budgetCents || 0, hideAmounts)}
                    </td>
                    <td className="px-4 py-3.5 text-right">
                      <select
                        aria-label="Статус публикации"
                        value={p.status}
                        onChange={async (e) => {
                          await updateWorkspaceEntity(workspace, 'contentPosts', p.id, {
                            status: e.target.value as ContentPost['status'],
                          });
                          onToast('Статус публикации обновлён');
                        }}
                        className="px-2.5 py-1.5 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-xs"
                      >
                        <option value="idea">Идея</option>
                        <option value="draft">Черновик</option>
                        <option value="scheduled">Запланировано</option>
                        <option value="published">Опубликовано</option>
                      </select>
                    </td>
                    <td className="px-4 py-3.5 text-right">
                      <button
                        type="button"
                        onClick={() => openEditPost(p)}
                        className="px-2.5 py-1.5 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium"
                      >
                        Изменить
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      <Drawer
        open={drawerOpen}
        title="Новая публикация"
        onClose={() => setDrawerOpen(false)}
      >
        <form onSubmit={handleCreate} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Площадка</span>
            <select
              value={channel}
              onChange={(e) => setChannel(e.target.value)}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              <option value="Telegram">Telegram</option>
              <option value="Instagram">Instagram</option>
              <option value="ВКонтакте">ВКонтакте</option>
              <option value="WhatsApp">WhatsApp</option>
              <option value="Свой сайт">Свой сайт</option>
            </select>
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Тема или заголовок</span>
            <input
              type="text"
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Дата публикации</span>
              <input
                type="date"
                value={scheduledDate}
                onChange={(e) => setScheduledDate(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Бюджет, ₽</span>
              <input
                type="text"
                value={budgetRub}
                onChange={(e) => setBudgetRub(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          </div>
          <label className="block space-y-1 text-sm font-medium">
            <span>Ссылка на пост / канал</span>
            <input
              type="text"
              value={channelUrl}
              onChange={(e) => setChannelUrl(e.target.value)}
              placeholder="https://t.me/..."
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Добавить в план
          </button>
        </form>
      </Drawer>

      <Drawer
        open={Boolean(editingPost)}
        title="Редактировать публикацию"
        onClose={() => setEditingPost(null)}
      >
        {editingPost && (
          <div className="space-y-5">
            <form onSubmit={handleSaveEdit} className="space-y-4">
              <label className="block space-y-1 text-sm font-medium">
                <span>Площадка</span>
                <select
                  value={channel}
                  onChange={(e) => setChannel(e.target.value)}
                  className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                >
                  <option value="Telegram">Telegram</option>
                  <option value="Instagram">Instagram</option>
                  <option value="ВКонтакте">ВКонтакте</option>
                  <option value="WhatsApp">WhatsApp</option>
                  <option value="Свой сайт">Свой сайт</option>
                </select>
              </label>
              <label className="block space-y-1 text-sm font-medium">
                <span>Тема</span>
                <input
                  type="text"
                  required
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                />
              </label>
              <div className="grid grid-cols-2 gap-3">
                <label className="block space-y-1 text-sm font-medium">
                  <span>Дата</span>
                  <input
                    type="date"
                    value={scheduledDate}
                    onChange={(e) => setScheduledDate(e.target.value)}
                    className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                  />
                </label>
                <label className="block space-y-1 text-sm font-medium">
                  <span>Бюджет, ₽</span>
                  <input
                    type="text"
                    value={budgetRub}
                    onChange={(e) => setBudgetRub(e.target.value)}
                    className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
                  />
                </label>
              </div>
              <label className="block space-y-1 text-sm font-medium">
                <span>Ссылка</span>
                <input
                  type="text"
                  value={channelUrl}
                  onChange={(e) => setChannelUrl(e.target.value)}
                  className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                />
              </label>
              <button
                type="submit"
                className="w-full min-h-[44px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
              >
                Сохранить изменения
              </button>
            </form>

            <div className="p-4 rounded-xl border border-[var(--line)] bg-[var(--soft)] space-y-3">
              <div className="text-xs font-semibold">Провести рекламный бюджет в Финансы</div>
              <select
                value={spendAccountId || data.accounts[0]?.id || ''}
                onChange={(e) => setSpendAccountId(e.target.value)}
                className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--card)] text-xs"
              >
                {data.accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name} ({formatMoneyCents(a.balanceCents, hideAmounts)})
                  </option>
                ))}
              </select>
              <button
                type="button"
                onClick={handleRecordSpend}
                className="w-full min-h-[40px] rounded-xl border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--bg)] text-xs font-medium"
              >
                Списать бюджет ({budgetRub || 0} ₽) как расход
              </button>
            </div>
          </div>
        )}
      </Drawer>
    </div>
  );
}
