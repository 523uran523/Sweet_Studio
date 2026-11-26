import React, { useEffect, useMemo, useState } from 'react';
import {
  BarChart3,
  Bell,
  BookOpen,
  Briefcase,
  Calculator,
  Cake,
  CookingPot,
  Eye,
  EyeOff,
  Gift,
  Home,
  Inbox,
  LogOut,
  Megaphone,
  Menu,
  Package,
  Plus,
  Search,
  Settings,
  ShieldCheck,
  Users,
  Wallet,
  X,
} from 'lucide-react';
import { NavSectionId, Workspace } from '../types/domain';
import { WorkspaceSnapshot } from '../firebase/workspaceService';
import { formatMoneyCents } from '../core/moneyFormat';

export interface NavItemDef {
  id: NavSectionId;
  label: string;
  group: 'main' | 'ops' | 'manage';
  icon: React.ComponentType<{ className?: string }>;
}

export const NAV_ITEMS: NavItemDef[] = [
  { id: 'dashboard', label: 'Главная', group: 'main', icon: Home },
  { id: 'work', label: 'Работа', group: 'main', icon: Briefcase },
  { id: 'orders', label: 'Заказы', group: 'ops', icon: Cake },
  { id: 'leads', label: 'Заявки', group: 'ops', icon: Inbox },
  { id: 'recipes', label: 'Рецепты', group: 'ops', icon: BookOpen },
  { id: 'calculator', label: 'Калькулятор', group: 'ops', icon: Calculator },
  { id: 'inventory', label: 'Кладовая', group: 'ops', icon: Package },
  { id: 'production', label: 'Производство', group: 'ops', icon: CookingPot },
  { id: 'clients', label: 'Клиенты', group: 'manage', icon: Users },
  { id: 'loyalty', label: 'Лояльность', group: 'manage', icon: Gift },
  { id: 'quality', label: 'Качество', group: 'manage', icon: ShieldCheck },
  { id: 'marketing', label: 'Продвижение', group: 'manage', icon: Megaphone },
  { id: 'money', label: 'Финансы', group: 'manage', icon: Wallet },
  { id: 'analytics', label: 'Аналитика', group: 'manage', icon: BarChart3 },
  { id: 'team', label: 'Команда', group: 'manage', icon: Users },
  { id: 'academy', label: 'Академия', group: 'manage', icon: BookOpen },
  { id: 'settings', label: 'Настройки', group: 'manage', icon: Settings },
];

export type QuickActionKind =
  | 'order'
  | 'lead'
  | 'recipe'
  | 'expense'
  | 'income'
  | 'client'
  | 'receipt'
  | 'task'
  | 'coupon'
  | 'complaint';

export function AppShell({
  workspace,
  userName,
  activePage,
  onNavigate,
  hideAmounts,
  onToggleHideAmounts,
  onSignOut,
  data,
  onQuickCreate,
  toastMessage,
  children,
}: {
  workspace: Workspace;
  userName: string;
  activePage: NavSectionId;
  onNavigate: (page: NavSectionId) => void;
  hideAmounts: boolean;
  onToggleHideAmounts: () => void;
  onSignOut: () => void;
  data: WorkspaceSnapshot;
  onQuickCreate: (kind: QuickActionKind) => void;
  toastMessage: string | null;
  children: React.ReactNode;
}) {
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [quickMenuOpen, setQuickMenuOpen] = useState(false);
  const [bellOpen, setBellOpen] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const hiddenSet = useMemo(
    () => new Set(workspace.hiddenModules || []),
    [workspace.hiddenModules],
  );

  const visibleNav = useMemo(
    () =>
      NAV_ITEMS.filter(
        (n) =>
          n.id === 'dashboard' ||
          n.id === 'settings' ||
          n.id === 'academy' ||
          !hiddenSet.has(n.id),
      ),
    [hiddenSet],
  );

  const pinnedIds = useMemo(() => {
    const raw = (workspace.pins || ['work', 'orders', 'recipes']).filter((id) =>
      visibleNav.some((v) => v.id === id),
    );
    return raw.slice(0, 3) as NavSectionId[];
  }, [workspace.pins, visibleNav]);

  const notifications = useMemo(() => {
    const today = new Date().toISOString().slice(0, 10);
    const soon = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);
    const alerts: Array<{ id: string; title: string; detail: string; page: NavSectionId }> = [];

    for (const item of data.inventoryItems) {
      if (item.minQty && item.qtyOnHand <= item.minQty) {
        alerts.push({
          id: `low_${item.id}`,
          title: `Низкий остаток: ${item.name}`,
          detail: `${item.qtyOnHand} ${item.unit} (мин. ${item.minQty})`,
          page: 'inventory',
        });
      }
    }
    for (const lot of data.stockLots) {
      if (lot.status === 'active' && lot.expiresAt && lot.expiresAt <= soon) {
        alerts.push({
          id: `exp_${lot.id}`,
          title:
            lot.expiresAt < today
              ? `Просрочена партия: ${lot.itemName}`
              : `Истекает срок партии: ${lot.itemName}`,
          detail: `${lot.lotCode} · до ${lot.expiresAt}`,
          page: 'inventory',
        });
      }
    }
    for (const ord of data.orders) {
      if (ord.status !== 'closed' && ord.status !== 'cancelled' && ord.dueDate && ord.dueDate <= today) {
        alerts.push({
          id: `ord_${ord.id}`,
          title: `Выдача сегодня: ${ord.orderNumber} ${ord.title}`,
          detail: ord.clientName,
          page: 'orders',
        });
      }
    }
    return alerts;
  }, [data.inventoryItems, data.stockLots, data.orders]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setSearchOpen((v) => !v);
      } else if (e.altKey && e.key.toLowerCase() === 'n') {
        e.preventDefault();
        setQuickMenuOpen((v) => !v);
      } else if (e.key === 'Escape') {
        setSearchOpen(false);
        setQuickMenuOpen(false);
        setBellOpen(false);
        setMobileMenuOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const searchResults = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    const match = (s?: string) => !q || (s || '').toLowerCase().includes(q);
    return {
      orders: data.orders.filter((o) => match(`${o.orderNumber} ${o.title} ${o.clientName}`)).slice(0, 5),
      recipes: data.recipes.filter((r) => match(`${r.title} ${r.category}`)).slice(0, 5),
      clients: data.clients.filter((c) => match(`${c.name} ${c.phone} ${c.preferences}`)).slice(0, 5),
      items: data.inventoryItems.filter((i) => match(`${i.name} ${i.category}`)).slice(0, 5),
    };
  }, [searchQuery, data.orders, data.recipes, data.clients, data.inventoryItems]);

  const densityClass =
    workspace.density === 'compact'
      ? 'text-[14px]'
      : workspace.density === 'spacious'
        ? 'leading-relaxed'
        : '';

  const formatLabel =
    workspace.businessFormat === 'home'
      ? 'Домашний кондитер'
      : workspace.businessFormat === 'network'
        ? 'Сеть кондитерских'
        : 'Кондитерская студия';

  const groupLabels: Record<NavItemDef['group'], string> = {
    main: 'Основное',
    ops: 'Операции',
    manage: 'Управление',
  };

  return (
    <div className={`min-h-screen bg-[var(--bg)] text-[var(--ink)] flex ${densityClass}`}>
      {/* Desktop & Tablet Sidebar */}
      <aside className="hidden md:flex flex-col w-[76px] lg:w-[256px] shrink-0 border-r border-[var(--line)] bg-[var(--card)] sticky top-0 h-screen overflow-y-auto px-2.5 lg:px-4 py-5">
        <div className="flex items-center gap-3 px-2 pb-5 border-b border-[var(--line)]">
          <img
            src="/Sweet_Studio_icon.png"
            alt="Sweet Studio"
            className="w-9 h-9 rounded-xl object-cover shrink-0"
          />
          <div className="hidden lg:block min-w-0">
            <div className="font-semibold text-base tracking-tight font-display truncate">
              sweet studio.
            </div>
            <div className="text-xs text-[var(--muted)] truncate">{formatLabel}</div>
          </div>
        </div>

        <nav className="mt-4 flex-1 space-y-5" aria-label="Основная навигация">
          {(['main', 'ops', 'manage'] as const).map((grp) => {
            const items = visibleNav.filter((n) => n.group === grp);
            if (items.length === 0) return null;
            return (
              <div key={grp} className="space-y-1">
                <div className="hidden lg:block px-2.5 text-xs font-medium text-[var(--muted)] pb-1">
                  {groupLabels[grp]}
                </div>
                {items.map((item) => {
                  const Icon = item.icon;
                  const active = activePage === item.id;
                  return (
                    <button
                      key={item.id}
                      type="button"
                      onClick={() => onNavigate(item.id)}
                      title={item.label}
                      className={`w-full min-h-[42px] px-2.5 py-2 rounded-xl flex items-center justify-center lg:justify-start gap-3 text-sm font-medium transition-colors whitespace-nowrap ${
                        active
                          ? 'bg-[var(--soft)] text-[var(--ink)]'
                          : 'text-[var(--muted)] hover:text-[var(--ink)] hover:bg-[var(--bg)]'
                      }`}
                    >
                      <Icon className="w-[18px] h-[18px] shrink-0" />
                      <span className="hidden lg:inline truncate">{item.label}</span>
                    </button>
                  );
                })}
              </div>
            );
          })}
        </nav>

        <div className="hidden lg:block pt-4 border-t border-[var(--line)] text-xs text-[var(--muted)] px-2 truncate">
          {workspace.name}
        </div>
      </aside>

      {/* Main Column */}
      <div className="flex-1 min-w-0 flex flex-col pb-20 md:pb-0">
        {/* Top Bar */}
        <header className="sticky top-0 z-30 bg-[var(--bg)]/95 backdrop-blur border-b border-[var(--line)] px-4 sm:px-8 h-16 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0">
            <img
              src="/Sweet_Studio_icon.png"
              alt="Sweet Studio"
              className="md:hidden w-8 h-8 rounded-lg object-cover shrink-0"
            />
            <span className="font-semibold text-sm sm:text-base truncate font-display">
              {workspace.name}
            </span>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <button
              type="button"
              onClick={() => setSearchOpen(true)}
              aria-label="Глобальный поиск"
              className="min-h-[40px] px-3 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] hover:border-[var(--accent)] text-sm text-[var(--muted)] flex items-center gap-2 whitespace-nowrap shrink-0"
            >
              <Search className="w-4 h-4 shrink-0" />
              <span className="hidden sm:inline">Поиск · Ctrl+K</span>
            </button>

            <div className="relative">
              <button
                type="button"
                onClick={() => {
                  setQuickMenuOpen((v) => !v);
                  setBellOpen(false);
                }}
                className="min-h-[40px] px-3.5 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium flex items-center gap-1.5 whitespace-nowrap shrink-0"
              >
                <Plus className="w-4 h-4 shrink-0" />
                <span>Создать</span>
              </button>

              {quickMenuOpen && (
                <div className="absolute right-0 mt-2 w-60 rounded-2xl border border-[var(--line)] bg-[var(--card)] p-2 shadow-lg z-40">
                  <div className="px-2.5 py-1.5 text-xs font-medium text-[var(--muted)]">
                    Быстрые действия (Alt+N)
                  </div>
                  {(
                    [
                      ['order', 'Новый заказ'],
                      ['lead', 'Новая заявка'],
                      ['recipe', 'Новый рецепт'],
                      ['task', 'Задача в Работу'],
                      ['expense', 'Расход'],
                      ['income', 'Поступление'],
                      ['receipt', 'Приход на склад'],
                      ['client', 'Новый клиент'],
                      ['coupon', 'Купон лояльности'],
                      ['complaint', 'Запись контроля качества'],
                    ] as Array<[QuickActionKind, string]>
                  ).map(([kind, label]) => (
                    <button
                      key={kind}
                      type="button"
                      onClick={() => {
                        setQuickMenuOpen(false);
                        onQuickCreate(kind);
                      }}
                      className="w-full text-left px-3 py-2 rounded-lg text-sm hover:bg-[var(--soft)] transition-colors"
                    >
                      {label}
                    </button>
                  ))}
                </div>
              )}
            </div>

            <button
              type="button"
              onClick={onToggleHideAmounts}
              aria-label={hideAmounts ? 'Показать суммы' : 'Скрыть суммы'}
              title={hideAmounts ? 'Показать суммы' : 'Скрыть суммы'}
              className="min-w-[40px] min-h-[40px] inline-flex items-center justify-center rounded-xl border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)] transition-colors shrink-0"
            >
              {hideAmounts ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            </button>

            <div className="relative">
              <button
                type="button"
                onClick={() => {
                  setBellOpen((v) => !v);
                  setQuickMenuOpen(false);
                }}
                aria-label="Уведомления"
                className="min-w-[40px] min-h-[40px] px-2.5 inline-flex items-center justify-center gap-1 rounded-xl border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)] transition-colors shrink-0"
              >
                <Bell className="w-4 h-4" />
                {notifications.length > 0 && (
                  <span className="text-xs font-semibold tabular-nums text-[var(--accent)]">
                    {notifications.length}
                  </span>
                )}
              </button>

              {bellOpen && (
                <div className="absolute right-0 mt-2 w-80 rounded-2xl border border-[var(--line)] bg-[var(--card)] p-3 shadow-lg z-40 space-y-2">
                  <div className="flex items-center justify-between pb-2 border-b border-[var(--line)]">
                    <span className="text-sm font-semibold">Уведомления</span>
                    <span className="text-xs text-[var(--muted)] tabular-nums">
                      {notifications.length}
                    </span>
                  </div>
                  {notifications.length === 0 ? (
                    <p className="text-xs text-[var(--muted)] py-3">
                      Нет срочных предупреждений
                    </p>
                  ) : (
                    <div className="max-h-72 overflow-y-auto space-y-1.5">
                      {notifications.map((n) => (
                        <button
                          key={n.id}
                          type="button"
                          onClick={() => {
                            setBellOpen(false);
                            onNavigate(n.page);
                          }}
                          className="w-full text-left p-2.5 rounded-xl hover:bg-[var(--soft)] transition-colors"
                        >
                          <div className="text-xs font-semibold">{n.title}</div>
                          <div className="text-xs text-[var(--muted)] mt-0.5">
                            {n.detail}
                          </div>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>

            <button
              type="button"
              onClick={onSignOut}
              title={`Выйти (${userName})`}
              aria-label="Выйти из аккаунта"
              className="hidden sm:inline-flex min-w-[40px] min-h-[40px] items-center justify-center rounded-xl border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)] transition-colors shrink-0"
            >
              <LogOut className="w-4 h-4" />
            </button>
          </div>
        </header>

        {/* Main Content */}
        <main className="flex-1 px-4 sm:px-8 py-6 max-w-[1280px] w-full mx-auto">
          {children}
        </main>
      </div>

      {/* Mobile 5-tab Bottom Bar */}
      <nav
        aria-label="Нижняя навигация"
        className="md:hidden fixed bottom-0 left-0 right-0 z-30 bg-[var(--card)] border-t border-[var(--line)] flex items-center justify-around px-1 py-1.5"
      >
        {(['dashboard', ...pinnedIds] as NavSectionId[]).map((id) => {
          const item = NAV_ITEMS.find((n) => n.id === id);
          if (!item) return null;
          const Icon = item.icon;
          const active = activePage === item.id;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => {
                setMobileMenuOpen(false);
                onNavigate(item.id);
              }}
              className={`flex-1 min-h-[46px] flex flex-col items-center justify-center gap-0.5 rounded-xl text-[11px] font-medium ${
                active ? 'text-[var(--accent)]' : 'text-[var(--muted)]'
              }`}
            >
              <Icon className="w-4 h-4" />
              <span className="truncate max-w-[68px]">{item.label}</span>
            </button>
          );
        })}
        <button
          type="button"
          onClick={() => setMobileMenuOpen((v) => !v)}
          className={`flex-1 min-h-[46px] flex flex-col items-center justify-center gap-0.5 rounded-xl text-[11px] font-medium ${
            mobileMenuOpen ? 'text-[var(--accent)]' : 'text-[var(--muted)]'
          }`}
        >
          <Menu className="w-4 h-4" />
          <span>Меню</span>
        </button>
      </nav>

      {/* Mobile All-Sections Drawer */}
      {mobileMenuOpen && (
        <div className="md:hidden fixed inset-0 z-40 bg-[var(--bg)] p-4 pb-24 overflow-y-auto">
          <div className="flex items-center justify-between pb-4 border-b border-[var(--line)]">
            <span className="text-lg font-semibold">Разделы Sweet Studio</span>
            <button
              type="button"
              onClick={() => setMobileMenuOpen(false)}
              className="min-w-[44px] min-h-[44px] inline-flex items-center justify-center rounded-xl border border-[var(--line)] bg-[var(--card)]"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
          <div className="grid grid-cols-2 gap-2.5 mt-4">
            {visibleNav.map((item) => {
              const Icon = item.icon;
              return (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => {
                    setMobileMenuOpen(false);
                    onNavigate(item.id);
                  }}
                  className={`p-3.5 rounded-xl border text-left flex items-center gap-2.5 ${
                    activePage === item.id
                      ? 'border-[var(--accent)] bg-[var(--soft)]'
                      : 'border-[var(--line)] bg-[var(--card)]'
                  }`}
                >
                  <Icon className="w-4 h-4 shrink-0" />
                  <span className="text-sm font-medium truncate">{item.label}</span>
                </button>
              );
            })}
          </div>
          <button
            type="button"
            onClick={onSignOut}
            className="mt-6 w-full min-h-[44px] rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm font-medium flex items-center justify-center gap-2"
          >
            <LogOut className="w-4 h-4" />
            <span>Выйти ({userName})</span>
          </button>
        </div>
      )}

      {/* Command Search Modal */}
      {searchOpen && (
        <div
          className="fixed inset-0 z-50 bg-black/45 flex items-start justify-center p-4 pt-16"
          onClick={(e) => {
            if (e.target === e.currentTarget) setSearchOpen(false);
          }}
        >
          <div className="w-full max-w-xl rounded-2xl border border-[var(--line)] bg-[var(--card)] p-4 shadow-xl space-y-4">
            <div className="flex items-center gap-2 border-b border-[var(--line)] pb-3">
              <Search className="w-4 h-4 text-[var(--muted)] shrink-0" />
              <input
                autoFocus
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Поиск по заказам, рецептам, клиентам и складу..."
                className="w-full bg-transparent text-sm focus:outline-none"
              />
              <button
                type="button"
                onClick={() => setSearchOpen(false)}
                className="text-xs text-[var(--muted)] px-2 py-1 rounded-lg border border-[var(--line)]"
              >
                Esc
              </button>
            </div>

            <div className="max-h-96 overflow-y-auto space-y-4 text-sm">
              {searchResults.orders.length > 0 && (
                <div>
                  <div className="text-xs font-medium text-[var(--muted)] mb-1">Заказы</div>
                  {searchResults.orders.map((o) => (
                    <button
                      key={o.id}
                      type="button"
                      onClick={() => {
                        setSearchOpen(false);
                        onNavigate('orders');
                      }}
                      className="w-full flex items-center justify-between px-3 py-2 rounded-xl hover:bg-[var(--soft)] text-left"
                    >
                      <span>
                        {o.orderNumber} {o.title} · {o.clientName}
                      </span>
                      <span className="tabular-nums text-[var(--muted)]">
                        {formatMoneyCents(o.priceCents, hideAmounts)}
                      </span>
                    </button>
                  ))}
                </div>
              )}

              {searchResults.recipes.length > 0 && (
                <div>
                  <div className="text-xs font-medium text-[var(--muted)] mb-1">Рецепты</div>
                  {searchResults.recipes.map((r) => (
                    <button
                      key={r.id}
                      type="button"
                      onClick={() => {
                        setSearchOpen(false);
                        onNavigate('recipes');
                      }}
                      className="w-full flex items-center justify-between px-3 py-2 rounded-xl hover:bg-[var(--soft)] text-left"
                    >
                      <span>{r.title}</span>
                      <span className="text-xs text-[var(--muted)]">{r.category}</span>
                    </button>
                  ))}
                </div>
              )}

              {searchResults.clients.length > 0 && (
                <div>
                  <div className="text-xs font-medium text-[var(--muted)] mb-1">Клиенты</div>
                  {searchResults.clients.map((c) => (
                    <button
                      key={c.id}
                      type="button"
                      onClick={() => {
                        setSearchOpen(false);
                        onNavigate('clients');
                      }}
                      className="w-full flex items-center justify-between px-3 py-2 rounded-xl hover:bg-[var(--soft)] text-left"
                    >
                      <span>{c.name}</span>
                      <span className="text-xs text-[var(--muted)]">{c.phone || '—'}</span>
                    </button>
                  ))}
                </div>
              )}

              {searchResults.items.length > 0 && (
                <div>
                  <div className="text-xs font-medium text-[var(--muted)] mb-1">Кладовая</div>
                  {searchResults.items.map((i) => (
                    <button
                      key={i.id}
                      type="button"
                      onClick={() => {
                        setSearchOpen(false);
                        onNavigate('inventory');
                      }}
                      className="w-full flex items-center justify-between px-3 py-2 rounded-xl hover:bg-[var(--soft)] text-left"
                    >
                      <span>{i.name}</span>
                      <span className="tabular-nums text-xs text-[var(--muted)]">
                        {i.qtyOnHand} {i.unit}
                      </span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Toast */}
      {toastMessage && (
        <div className="fixed bottom-20 md:bottom-6 right-4 sm:right-6 z-50 px-4 py-3 rounded-xl bg-[var(--ink)] text-[var(--bg)] text-sm font-medium shadow-lg">
          {toastMessage}
        </div>
      )}
    </div>
  );
}
