import React, { useMemo, useState } from 'react';
import {
  Cake,
  ChevronLeft,
  ChevronRight,
  CookingPot,
  ExternalLink,
  Megaphone,
  Plus,
  Repeat,
  ShieldCheck,
  ShoppingBasket,
  Trash2,
  UserRound,
  Wallet,
} from 'lucide-react';
import {
  Card,
  Drawer,
  EmptyState,
  PageHeader,
  SegmentedTabs,
} from '../components/UiPrimitives';
import { formatMoneyCents } from '../core/moneyFormat';
import { summarizeOrderItems } from '../core/ordersCore';
import { planNextRecurringWorkItem, RECURRENCE_LABELS_RU } from '../core/workRecurrence';
import {
  createWorkspaceEntity,
  deleteWorkspaceEntity,
  newId,
  syncOrderWorkItemsStatus,
  updateWorkspaceEntity,
  WorkspaceSnapshot,
} from '../firebase/workspaceService';
import {
  OrderStatus,
  WorkItem,
  WorkItemType,
  WorkRecurrence,
  Workspace,
} from '../types/domain';

const WORK_TYPE_META: Record<
  WorkItemType,
  { label: string; color: string; icon: React.ComponentType<{ className?: string }> }
> = {
  order: { label: 'Заказ', color: '#A45C7A', icon: Cake },
  production: { label: 'Производство', color: '#748B64', icon: CookingPot },
  promo: { label: 'Продвижение', color: '#9275BA', icon: Megaphone },
  quality: { label: 'Качество', color: '#B67B4E', icon: ShieldCheck },
  task: { label: 'Поручение', color: '#647B9D', icon: UserRound },
  purchase: { label: 'Закупка', color: '#9B8055', icon: ShoppingBasket },
  finance: { label: 'Финансы', color: '#548D80', icon: Wallet },
};

const STAGES: Array<{ id: WorkItem['stage']; label: string }> = [
  { id: 'queue', label: 'Очередь' },
  { id: 'in_progress', label: 'В работе' },
  { id: 'done', label: 'Готово' },
];

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

const WEEKDAYS_RU = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

const MONTHS_NOMINATIVE_RU = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

const MONTHS_GENITIVE_RU = [
  'Января',
  'Февраля',
  'Марта',
  'Апреля',
  'Мая',
  'Июня',
  'Июля',
  'Августа',
  'Сентября',
  'Октября',
  'Ноября',
  'Декабря',
];

const WEEKDAYS_FULL_RU = [
  'Воскресенье',
  'Понедельник',
  'Вторник',
  'Среда',
  'Четверг',
  'Пятница',
  'Суббота',
];

function toIsoDate(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function formatSelectedDayTitle(isoDate: string): string {
  const [y, m, d] = isoDate.split('-').map(Number);
  if (!y || !m || !d) return isoDate;
  const dt = new Date(y, m - 1, d);
  const weekday = WEEKDAYS_FULL_RU[dt.getDay()];
  const monthGen = MONTHS_GENITIVE_RU[dt.getMonth()];
  return `${weekday}, ${d} ${monthGen}`;
}

export function WorkHubPage({
  workspace,
  data,
  hideAmounts = false,
  onOpenOrder,
  onToast,
}: {
  workspace: Workspace;
  data: WorkspaceSnapshot;
  hideAmounts?: boolean;
  onOpenOrder?: (orderId: string) => void;
  onToast: (msg: string) => void;
}) {
  const todayIso = useMemo(() => toIsoDate(new Date()), []);
  const [view, setView] = useState<'list' | 'kanban' | 'calendar'>('kanban');
  const [typeFilter, setTypeFilter] = useState<'all' | WorkItemType>('all');
  const [preset, setPreset] = useState<'all' | 'today' | 'overdue'>('all');
  const [drawerOpen, setDrawerOpen] = useState(false);

  // Drag & Drop state
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [dragOverStage, setDragOverStage] = useState<WorkItem['stage'] | null>(null);

  // Edit Task drawer state
  const [editingItem, setEditingItem] = useState<WorkItem | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const [editStage, setEditStage] = useState<WorkItem['stage']>('queue');
  const [editPriority, setEditPriority] = useState<WorkItem['priority']>('normal');
  const [editDueDate, setEditDueDate] = useState(todayIso);
  const [editAssignee, setEditAssignee] = useState('Владелец');
  const [editRecurrence, setEditRecurrence] = useState<WorkRecurrence>('none');

  // Month calendar state
  const [calendarMonth, setCalendarMonth] = useState(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), 1);
  });
  const [selectedDate, setSelectedDate] = useState(todayIso);

  const [title, setTitle] = useState('');
  const [type, setType] = useState<WorkItemType>('task');
  const [priority, setPriority] = useState<WorkItem['priority']>('normal');
  const [dueDate, setDueDate] = useState(todayIso);
  const [assignee, setAssignee] = useState('Владелец');
  const [recurrence, setRecurrence] = useState<WorkRecurrence>('none');

  const isOverdue = (w: WorkItem) =>
    Boolean(w.dueDate && w.dueDate < todayIso && w.stage !== 'done');

  const overdueCount = useMemo(
    () => data.workItems.filter(isOverdue).length,
    [data.workItems, todayIso],
  );

  const todayCount = useMemo(
    () => data.workItems.filter((w) => w.dueDate === todayIso && w.stage !== 'done').length,
    [data.workItems, todayIso],
  );

  const filtered = useMemo(
    () =>
      data.workItems.filter((w) => {
        if (typeFilter !== 'all' && w.type !== typeFilter) return false;
        if (preset === 'today' && w.dueDate !== todayIso) return false;
        if (preset === 'overdue' && !isOverdue(w)) return false;
        return true;
      }),
    [data.workItems, typeFilter, preset, todayIso],
  );

  const applyUpdateAndSpawnRecurrence = async (
    item: WorkItem,
    nextStage: WorkItem['stage'],
    patchOverrides: Record<string, unknown>,
  ): Promise<string | null> => {
    const nextRecurrence = (patchOverrides.recurrence as WorkRecurrence | undefined) ?? item.recurrence ?? 'none';
    const nextDue = (patchOverrides.dueDate as string | undefined) ?? item.dueDate;
    const candidateItem: WorkItem = {
      ...item,
      stage: nextStage,
      dueDate: nextDue,
      recurrence: nextRecurrence,
      title: typeof patchOverrides.title === 'string' ? patchOverrides.title : item.title,
      priority: (patchOverrides.priority as WorkItem['priority'] | undefined) ?? item.priority,
      assigneeName:
        typeof patchOverrides.assigneeName === 'string'
          ? patchOverrides.assigneeName
          : item.assigneeName,
    };

    const plan =
      item.stage !== 'done' && nextStage === 'done'
        ? planNextRecurringWorkItem(candidateItem, data.workItems, todayIso)
        : null;

    const finalPatch: Record<string, unknown> = {
      ...patchOverrides,
      stage: nextStage,
    };
    if (plan) {
      finalPatch.seriesId = plan.seriesId;
      finalPatch.occurrenceIndex = plan.currentIndex;
    }

    await updateWorkspaceEntity(workspace, 'workItems', item.id, finalPatch);

    if (plan) {
      await createWorkspaceEntity(workspace, 'workItems', newId('wi'), plan.nextPayload);
      return plan.nextDueDate;
    }
    return null;
  };

  const handleStageChange = async (item: WorkItem, nextStage: WorkItem['stage']) => {
    if (item.stage === nextStage) return;
    const spawnedDate = await applyUpdateAndSpawnRecurrence(item, nextStage, {});
    if (spawnedDate) {
      onToast(`Выполнено · создана следующая задача на ${spawnedDate}`);
    } else {
      onToast(`Статус обновлён: ${STAGES.find((s) => s.id === nextStage)?.label}`);
    }
  };

  const handleOrderStatusChange = async (orderId: string, nextStatus: OrderStatus) => {
    await updateWorkspaceEntity(workspace, 'orders', orderId, { status: nextStatus });
    await syncOrderWorkItemsStatus(workspace, data.workItems, orderId, nextStatus);
    onToast(`Статус заказа: ${ORDER_STATUS_LABELS[nextStatus]}`);
  };

  const openNewTaskForDate = (targetDate: string) => {
    setDueDate(targetDate);
    setRecurrence('none');
    setDrawerOpen(true);
  };

  const openEditTask = (item: WorkItem) => {
    setEditingItem(item);
    setEditTitle(item.title);
    setEditStage(item.stage);
    setEditPriority(item.priority);
    setEditDueDate(item.dueDate || todayIso);
    setEditAssignee(item.assigneeName || 'Владелец');
    setEditRecurrence(item.recurrence || 'none');
  };

  const handleSaveEditTask = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingItem || !editTitle.trim()) return;
    const patch: Record<string, unknown> = {
      title: editTitle.trim().slice(0, 160),
      priority: editPriority,
      dueDate: editDueDate,
      assigneeName: editAssignee.trim().slice(0, 120) || 'Владелец',
      recurrence: editRecurrence,
    };
    if (editRecurrence !== 'none') {
      patch.seriesId = editingItem.seriesId || editingItem.id;
      patch.occurrenceIndex = editingItem.occurrenceIndex ?? 1;
    }
    const spawnedDate = await applyUpdateAndSpawnRecurrence(editingItem, editStage, patch);
    setEditingItem(null);
    onToast(
      spawnedDate
        ? `Задача обновлена · создан повтор на ${spawnedDate}`
        : 'Задача обновлена',
    );
  };

  const handleDeleteTask = async () => {
    if (!editingItem) return;
    await deleteWorkspaceEntity(workspace, 'workItems', editingItem.id);
    setEditingItem(null);
    onToast('Задача удалена');
  };

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    const payload: Record<string, unknown> = {
      type,
      title: title.trim().slice(0, 160),
      assigneeName: assignee.trim().slice(0, 120) || 'Владелец',
      locationName: data.locations[0]?.name || 'Основная студия',
      dueDate,
      priority,
      stage: 'queue',
      tags: [],
      recurrence,
    };
    if (recurrence !== 'none') {
      payload.seriesId = newId('ser');
      payload.occurrenceIndex = 1;
    }
    await createWorkspaceEntity(workspace, 'workItems', newId('wi'), payload);
    setTitle('');
    setRecurrence('none');
    setDrawerOpen(false);
    onToast(
      recurrence !== 'none'
        ? `Повторяющаяся задача добавлена (${RECURRENCE_LABELS_RU[recurrence]})`
        : 'Задача добавлена в Работу',
    );
  };

  const monthData = useMemo(() => {
    const year = calendarMonth.getFullYear();
    const month = calendarMonth.getMonth();
    const firstDay = new Date(year, month, 1);
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const leadingBlanks = (firstDay.getDay() + 6) % 7; // Monday = 0

    const cells: Array<{
      key: string;
      day: number | null;
      iso: string | null;
    }> = [];

    for (let i = 0; i < leadingBlanks; i++) {
      cells.push({ key: `blank_${i}`, day: null, iso: null });
    }
    for (let day = 1; day <= daysInMonth; day++) {
      const iso = toIsoDate(new Date(year, month, day));
      cells.push({ key: iso, day, iso });
    }
    const trailing = (7 - (cells.length % 7)) % 7;
    for (let i = 0; i < trailing; i++) {
      cells.push({ key: `trail_${i}`, day: null, iso: null });
    }

    return {
      title: `${MONTHS_NOMINATIVE_RU[month]} ${year}`,
      cells,
    };
  }, [calendarMonth]);

  // Pre-index orders & work items by date for O(1) lookup across the month grid
  const daySummaryMap = useMemo(() => {
    const map = new Map<
      string,
      {
        orders: typeof data.orders;
        productionItems: WorkItem[];
        otherItems: WorkItem[];
      }
    >();

    const ensure = (iso: string) => {
      let entry = map.get(iso);
      if (!entry) {
        entry = { orders: [], productionItems: [], otherItems: [] };
        map.set(iso, entry);
      }
      return entry;
    };

    for (const ord of data.orders) {
      if (ord.status === 'cancelled' || !ord.dueDate) continue;
      if (typeFilter !== 'all' && typeFilter !== 'order') continue;
      ensure(ord.dueDate).orders.push(ord);
    }

    for (const wi of filtered) {
      if (!wi.dueDate) continue;
      if (wi.type === 'production') {
        ensure(wi.dueDate).productionItems.push(wi);
      } else if (wi.type !== 'order' || !wi.sourceId) {
        ensure(wi.dueDate).otherItems.push(wi);
      } else {
        const hasOrder = data.orders.some((o) => o.id === wi.sourceId);
        if (!hasOrder) {
          ensure(wi.dueDate).otherItems.push(wi);
        }
      }
    }

    return map;
  }, [data.orders, filtered, typeFilter]);

  const selectedDayInfo = useMemo(() => {
    const entry = daySummaryMap.get(selectedDate) || {
      orders: [],
      productionItems: [],
      otherItems: [],
    };
    const allWorkItems = filtered.filter((w) => w.dueDate === selectedDate);
    return {
      orders: entry.orders,
      productionCount: entry.productionItems.length,
      tasksCount: entry.otherItems.length,
      workItems: allWorkItems.filter((w) => {
        if (w.type !== 'order' || !w.sourceId) return true;
        return !entry.orders.some((o) => o.id === w.sourceId);
      }),
    };
  }, [daySummaryMap, selectedDate, filtered]);

  const shiftMonth = (delta: number) => {
    setCalendarMonth((prev) => new Date(prev.getFullYear(), prev.getMonth() + delta, 1));
  };

  const jumpToToday = () => {
    const now = new Date();
    setCalendarMonth(new Date(now.getFullYear(), now.getMonth(), 1));
    setSelectedDate(toIsoDate(now));
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Работа"
        subtitle="Единое пространство заказов, производства, закупок, качества и контента"
        action={
          <>
            <SegmentedTabs
              value={view}
              onChange={setView}
              options={[
                { id: 'kanban', label: 'Канбан' },
                { id: 'list', label: 'Список' },
                { id: 'calendar', label: 'Календарь' },
              ]}
            />
            <button
              type="button"
              onClick={() => openNewTaskForDate(view === 'calendar' ? selectedDate : todayIso)}
              className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
            >
              + Задача
            </button>
          </>
        }
      />

      {/* Saved Presets + Type Filter Bar */}
      <div className="space-y-2.5">
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => setPreset('all')}
            className={`px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors ${
              preset === 'all'
                ? 'border-[var(--accent)] bg-[var(--accent)] text-[var(--accent-ink)]'
                : 'border-[var(--line)] bg-[var(--card)] text-[var(--muted)]'
            }`}
          >
            Все ({data.workItems.length})
          </button>
          <button
            type="button"
            onClick={() => setPreset('today')}
            className={`px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors ${
              preset === 'today'
                ? 'border-[var(--accent)] bg-[var(--accent)] text-[var(--accent-ink)]'
                : 'border-[var(--line)] bg-[var(--card)] text-[var(--muted)]'
            }`}
          >
            На сегодня ({todayCount})
          </button>
          <button
            type="button"
            onClick={() => setPreset('overdue')}
            className={`px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors ${
              preset === 'overdue'
                ? 'border-[var(--danger)] bg-[var(--danger)] text-white'
                : overdueCount > 0
                  ? 'border-[var(--danger)]/50 bg-[var(--danger-bg)] text-[var(--danger)]'
                  : 'border-[var(--line)] bg-[var(--card)] text-[var(--muted)]'
            }`}
          >
            Просроченные ({overdueCount})
          </button>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => setTypeFilter('all')}
            className={`px-3 py-2 rounded-xl text-xs font-medium border transition-colors whitespace-nowrap shrink-0 ${
              typeFilter === 'all'
                ? 'border-[var(--accent)] bg-[var(--soft)]'
                : 'border-[var(--line)] bg-[var(--card)] text-[var(--muted)]'
            }`}
          >
            Все типы
          </button>
          {(Object.keys(WORK_TYPE_META) as WorkItemType[]).map((t) => {
            const meta = WORK_TYPE_META[t];
            return (
              <button
                key={t}
                type="button"
                onClick={() => setTypeFilter(t)}
                className={`px-3 py-2 rounded-xl text-xs font-medium border flex items-center gap-2 transition-colors whitespace-nowrap shrink-0 ${
                  typeFilter === t
                    ? 'border-[var(--accent)] bg-[var(--soft)]'
                    : 'border-[var(--line)] bg-[var(--card)] text-[var(--muted)]'
                }`}
              >
                <span
                  className="w-2.5 h-2.5 rounded-sm shrink-0"
                  style={{ backgroundColor: meta.color }}
                />
                <span>{meta.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {view === 'calendar' ? (
        <div className="grid lg:grid-cols-12 gap-5 items-start">
          {/* Left: Full Month Calendar Grid */}
          <Card className="lg:col-span-7 p-4 sm:p-5 space-y-4">
            <div className="flex items-center justify-between gap-3">
              <h2 className="text-lg font-semibold tracking-tight">{monthData.title}</h2>
              <div className="flex items-center gap-2 shrink-0">
                <button
                  type="button"
                  onClick={jumpToToday}
                  className="px-3 py-1.5 rounded-lg text-xs font-medium text-[var(--accent)] hover:bg-[var(--soft)] transition-colors whitespace-nowrap"
                >
                  Сегодня
                </button>
                <button
                  type="button"
                  onClick={() => shiftMonth(-1)}
                  aria-label="Предыдущий месяц"
                  className="w-9 h-9 rounded-xl border border-[var(--line)] bg-[var(--bg)] hover:bg-[var(--soft)] inline-flex items-center justify-center transition-colors"
                >
                  <ChevronLeft className="w-4 h-4" />
                </button>
                <button
                  type="button"
                  onClick={() => shiftMonth(1)}
                  aria-label="Следующий месяц"
                  className="w-9 h-9 rounded-xl border border-[var(--line)] bg-[var(--bg)] hover:bg-[var(--soft)] inline-flex items-center justify-center transition-colors"
                >
                  <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>

            {/* Weekday Header */}
            <div className="grid grid-cols-7 gap-1 sm:gap-1.5 text-center text-xs font-medium text-[var(--muted)] pt-1">
              {WEEKDAYS_RU.map((wd) => (
                <div key={wd} className="py-1">
                  {wd}
                </div>
              ))}
            </div>

            {/* Day Grid */}
            <div className="grid grid-cols-7 gap-1 sm:gap-1.5">
              {monthData.cells.map((cell) => {
                if (!cell.iso || cell.day === null) {
                  return <div key={cell.key} className="min-h-[58px] sm:min-h-[78px]" />;
                }

                const iso = cell.iso;
                const isSelected = iso === selectedDate;
                const isToday = iso === todayIso;
                const summary = daySummaryMap.get(iso);
                const ordersCount = summary?.orders.length || 0;
                const prodCount = summary?.productionItems.length || 0;
                const otherCount = summary?.otherItems.length || 0;

                return (
                  <button
                    key={iso}
                    type="button"
                    onClick={() => setSelectedDate(iso)}
                    className={`min-h-[58px] sm:min-h-[78px] p-1 sm:p-2 rounded-lg sm:rounded-xl border text-left flex flex-col justify-between transition-colors ${
                      isSelected
                        ? 'bg-[var(--accent)] text-[var(--accent-ink)] border-[var(--accent)]'
                        : isToday
                          ? 'bg-[var(--soft)] text-[var(--ink)] border-[var(--accent)]/40 hover:border-[var(--accent)]'
                          : 'bg-[var(--bg)]/50 text-[var(--ink)] border-transparent hover:border-[var(--line)] hover:bg-[var(--bg)]'
                    }`}
                  >
                    <div className="w-full flex justify-end">
                      <span
                        className={`text-xs sm:text-sm font-semibold tabular-nums ${
                          isSelected ? 'text-[var(--accent-ink)]' : ''
                        }`}
                      >
                        {cell.day}
                      </span>
                    </div>

                    {(ordersCount > 0 || prodCount > 0 || otherCount > 0) && (
                      <div className="flex flex-wrap items-center gap-1 mt-1">
                        {ordersCount > 0 && (
                          <span
                            className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[10px] font-semibold tabular-nums ${
                              isSelected
                                ? 'bg-white/20 text-[var(--accent-ink)]'
                                : 'bg-[var(--soft)] text-[var(--ink)]'
                            }`}
                            title={`Заказы: ${ordersCount}`}
                          >
                            <span
                              className="w-1.5 h-1.5 rounded-sm shrink-0"
                              style={{
                                backgroundColor: isSelected ? 'currentColor' : '#A45C7A',
                              }}
                            />
                            {ordersCount}
                          </span>
                        )}
                        {prodCount > 0 && (
                          <span
                            className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[10px] font-semibold tabular-nums ${
                              isSelected
                                ? 'bg-white/20 text-[var(--accent-ink)]'
                                : 'bg-[var(--green)] text-[var(--green-ink)]'
                            }`}
                            title={`Производство: ${prodCount}`}
                          >
                            <span
                              className="w-1.5 h-1.5 rounded-sm shrink-0"
                              style={{
                                backgroundColor: isSelected ? 'currentColor' : '#748B64',
                              }}
                            />
                            {prodCount}
                          </span>
                        )}
                        {otherCount > 0 && (
                          <span
                            className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-[10px] font-semibold tabular-nums ${
                              isSelected
                                ? 'bg-white/20 text-[var(--accent-ink)]'
                                : 'bg-[var(--warm)] text-[var(--warm-ink)]'
                            }`}
                            title={`Задачи: ${otherCount}`}
                          >
                            <span
                              className="w-1.5 h-1.5 rounded-sm shrink-0"
                              style={{
                                backgroundColor: isSelected ? 'currentColor' : '#647B9D',
                              }}
                            />
                            {otherCount}
                          </span>
                        )}
                      </div>
                    )}
                  </button>
                );
              })}
            </div>

            {/* Compact Legend */}
            <div className="pt-3 border-t border-[var(--line)] flex flex-wrap items-center gap-2 text-xs">
              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[var(--soft)] text-[var(--ink)] font-medium">
                <span className="w-2 h-2 rounded-sm bg-[#A45C7A]" />
                Заказы на выдачу
              </span>
              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[var(--green)] text-[var(--green-ink)] font-medium">
                <span className="w-2 h-2 rounded-sm bg-[#748B64]" />
                Производство
              </span>
              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[var(--warm)] text-[var(--warm-ink)] font-medium">
                <span className="w-2 h-2 rounded-sm bg-[#647B9D]" />
                Задачи и закупки
              </span>
            </div>
          </Card>

          {/* Right: Selected Day Orders & Tasks Panel */}
          <Card className="lg:col-span-5 p-4 sm:p-5 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-2 pb-3 border-b border-[var(--line)]">
              <h2 className="text-base sm:text-lg font-semibold tracking-tight">
                {formatSelectedDayTitle(selectedDate)}
              </h2>
              <div className="text-xs text-[var(--muted)] tabular-nums">
                Заказы: {selectedDayInfo.orders.length} · Произв.:{' '}
                {selectedDayInfo.productionCount} · Задачи: {selectedDayInfo.tasksCount}
              </div>
            </div>

            {selectedDayInfo.orders.length === 0 &&
            selectedDayInfo.workItems.length === 0 ? (
              <div className="rounded-xl border border-dashed border-[var(--line)] p-8 text-center space-y-3">
                <p className="text-sm text-[var(--muted)]">
                  На выбранный день заказов, партий и задач нет
                </p>
                <button
                  type="button"
                  onClick={() => openNewTaskForDate(selectedDate)}
                  className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-xl border border-[var(--line)] bg-[var(--bg)] hover:bg-[var(--soft)] text-xs font-medium transition-colors"
                >
                  <Plus className="w-3.5 h-3.5" />
                  <span>Запланировать на этот день</span>
                </button>
              </div>
            ) : (
              <div className="space-y-4">
                {selectedDayInfo.orders.length > 0 && (
                  <div className="space-y-2.5">
                    <div className="text-xs font-semibold text-[var(--muted)]">
                      Заказы на день ({selectedDayInfo.orders.length})
                    </div>
                    {selectedDayInfo.orders.map((ord) => (
                      <div
                        key={ord.id}
                        onClick={() => onOpenOrder?.(ord.id)}
                        className={`p-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] space-y-2 ${
                          onOpenOrder ? 'cursor-pointer hover:border-[var(--accent)]' : ''
                        }`}
                      >
                        <div className="flex items-start justify-between gap-2">
                          <div className="min-w-0">
                            <div className="text-sm font-semibold leading-snug">
                              {ord.orderNumber} · {ord.title}
                            </div>
                            <div className="text-xs text-[var(--muted)] mt-0.5">
                              {(() => {
                                const summary = summarizeOrderItems(ord);
                                return summary.summaryText
                                  ? `${ord.clientName} · ${summary.summaryText}`
                                  : ord.clientName;
                              })()}
                            </div>
                          </div>
                          <div className="text-right tabular-nums shrink-0">
                            <div className="text-sm font-semibold">
                              {formatMoneyCents(ord.priceCents, hideAmounts)}
                            </div>
                            <div className="text-[11px] text-[var(--muted)]">
                              оплачено {formatMoneyCents(ord.paidCents, hideAmounts)}
                            </div>
                          </div>
                        </div>

                        {ord.allergens && (
                          <div className="text-xs px-2.5 py-1 rounded-lg bg-[var(--warm)] text-[var(--warm-ink)]">
                            Аллергены: {ord.allergens}
                          </div>
                        )}
                        {ord.wishes && (
                          <div className="text-xs text-[var(--muted)]">{ord.wishes}</div>
                        )}

                        <div
                          className="flex items-center justify-between gap-2 pt-1.5 border-t border-[var(--line)]"
                          onClick={(e) => e.stopPropagation()}
                        >
                          <span className="text-xs text-[var(--muted)] truncate">
                            {ord.deliveryAddress || ord.locationName || 'Студия'}
                          </span>
                          <select
                            aria-label="Статус заказа"
                            value={ord.status}
                            onChange={(e) =>
                              handleOrderStatusChange(
                                ord.id,
                                e.target.value as OrderStatus,
                              )
                            }
                            className="px-2.5 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs"
                          >
                            {(Object.keys(ORDER_STATUS_LABELS) as OrderStatus[]).map(
                              (st) => (
                                <option key={st} value={st}>
                                  {ORDER_STATUS_LABELS[st]}
                                </option>
                              ),
                            )}
                          </select>
                        </div>
                      </div>
                    ))}
                  </div>
                )}

                {selectedDayInfo.workItems.length > 0 && (
                  <div className="space-y-2.5">
                    <div className="text-xs font-semibold text-[var(--muted)]">
                      Задачи и производство ({selectedDayInfo.workItems.length})
                    </div>
                    {selectedDayInfo.workItems.map((item) => {
                      const meta = WORK_TYPE_META[item.type] || WORK_TYPE_META.task;
                      const Icon = meta.icon;
                      const overdue = isOverdue(item);
                      return (
                        <div
                          key={item.id}
                          onClick={() => openEditTask(item)}
                          className={`p-3 rounded-xl border space-y-2 cursor-pointer transition-colors ${
                            overdue
                              ? 'border-[var(--danger)]/60 bg-[var(--danger-bg)]/35'
                              : 'border-[var(--line)] bg-[var(--bg)] hover:border-[var(--accent)]'
                          }`}
                        >
                          <div className="flex items-center justify-between gap-2">
                            <span className="text-xs font-medium text-[var(--muted)] flex items-center gap-1.5">
                              <span
                                className="w-5 h-5 rounded-md inline-flex items-center justify-center text-white shrink-0"
                                style={{ backgroundColor: meta.color }}
                              >
                                <Icon className="w-3 h-3" />
                              </span>
                              <span>{meta.label}</span>
                              {item.recurrence && item.recurrence !== 'none' && (
                                <span
                                  title={RECURRENCE_LABELS_RU[item.recurrence]}
                                  className="inline-flex items-center gap-0.5 text-[11px] font-medium text-[var(--accent)]"
                                >
                                  <Repeat className="w-3 h-3" />
                                  <span>{RECURRENCE_LABELS_RU[item.recurrence]}</span>
                                </span>
                              )}
                            </span>
                            <span className="text-xs text-[var(--muted)] truncate">
                              {item.assigneeName || 'Владелец'}
                            </span>
                          </div>
                          <div className="flex items-center justify-between gap-2">
                            <span className="text-sm font-medium leading-snug">
                              {item.title}
                            </span>
                            <select
                              aria-label="Этап задачи"
                              value={item.stage}
                              onClick={(e) => e.stopPropagation()}
                              onChange={(e) =>
                                handleStageChange(
                                  item,
                                  e.target.value as WorkItem['stage'],
                                )
                              }
                              className="px-2 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-xs shrink-0"
                            >
                              {STAGES.map((opt) => (
                                <option key={opt.id} value={opt.id}>
                                  {opt.label}
                                </option>
                              ))}
                            </select>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}

                <button
                  type="button"
                  onClick={() => openNewTaskForDate(selectedDate)}
                  className="w-full min-h-[40px] rounded-xl border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium inline-flex items-center justify-center gap-1.5 transition-colors"
                >
                  <Plus className="w-3.5 h-3.5" />
                  <span>Добавить задачу на {selectedDate}</span>
                </button>
              </div>
            )}
          </Card>
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState
          title="Задач по выбранному фильтру пока нет"
          description="Создайте задачу вручную или выберите другой пресет / тип задач."
          actionLabel="+ Новая задача"
          onAction={() => openNewTaskForDate(todayIso)}
        />
      ) : view === 'kanban' ? (
        <div className="grid md:grid-cols-3 gap-4">
          {STAGES.map((st) => {
            const items = filtered.filter((w) => w.stage === st.id);
            const dropActive = dragOverStage === st.id;
            return (
              <div
                key={st.id}
                onDragOver={(e) => {
                  e.preventDefault();
                  if (dragOverStage !== st.id) setDragOverStage(st.id);
                }}
                onDragLeave={() => {
                  if (dragOverStage === st.id) setDragOverStage(null);
                }}
                onDrop={async (e) => {
                  e.preventDefault();
                  const id = e.dataTransfer.getData('text/plain') || draggingId;
                  setDragOverStage(null);
                  setDraggingId(null);
                  const found = data.workItems.find((x) => x.id === id);
                  if (found && found.stage !== st.id) {
                    await handleStageChange(found, st.id);
                  }
                }}
                className={`rounded-2xl border bg-[var(--card)] p-4 space-y-3 transition-all min-h-[260px] ${
                  dropActive
                    ? 'border-[var(--accent)] ring-2 ring-[var(--accent)]/40 bg-[var(--soft)]/25'
                    : 'border-[var(--line)]'
                }`}
              >
                <div className="flex items-center justify-between pb-2 border-b border-[var(--line)]">
                  <span className="text-sm font-semibold">{st.label}</span>
                  <span className="text-xs text-[var(--muted)] tabular-nums">
                    {items.length}
                  </span>
                </div>
                <div className="space-y-3">
                  {items.map((item) => {
                    const meta = WORK_TYPE_META[item.type] || WORK_TYPE_META.task;
                    const Icon = meta.icon;
                    const overdue = isOverdue(item);
                    return (
                      <div
                        key={item.id}
                        draggable
                        onDragStart={(e) => {
                          e.dataTransfer.setData('text/plain', item.id);
                          e.dataTransfer.effectAllowed = 'move';
                          setDraggingId(item.id);
                        }}
                        onDragEnd={() => {
                          setDraggingId(null);
                          setDragOverStage(null);
                        }}
                        onClick={() => openEditTask(item)}
                        className={`rounded-xl border p-3.5 space-y-2.5 cursor-pointer transition-all ${
                          draggingId === item.id ? 'opacity-50' : ''
                        } ${
                          overdue
                            ? 'border-[var(--danger)]/60 bg-[var(--danger-bg)]/35'
                            : 'border-[var(--line)] bg-[var(--bg)] hover:border-[var(--accent)]'
                        }`}
                      >
                        <div className="flex items-start justify-between gap-2">
                          <span className="text-xs font-medium text-[var(--muted)] flex items-center gap-1.5">
                            <span
                              className="w-5 h-5 rounded-md inline-flex items-center justify-center text-white shrink-0"
                              style={{ backgroundColor: meta.color }}
                            >
                              <Icon className="w-3 h-3" />
                            </span>
                            <span>{meta.label}</span>
                            {item.recurrence && item.recurrence !== 'none' && (
                              <span
                                title={RECURRENCE_LABELS_RU[item.recurrence]}
                                className="inline-flex items-center gap-0.5 text-[11px] font-medium text-[var(--accent)]"
                              >
                                <Repeat className="w-3 h-3" />
                                <span>{RECURRENCE_LABELS_RU[item.recurrence]}</span>
                              </span>
                            )}
                            {item.priority === 'high' && (
                              <span className="text-[11px] font-semibold text-[var(--danger)]">
                                · Важно
                              </span>
                            )}
                          </span>
                          <span
                            className={`text-xs tabular-nums ${
                              overdue
                                ? 'text-[var(--danger)] font-semibold'
                                : 'text-[var(--muted)]'
                            }`}
                          >
                            {item.dueDate || 'Без срока'}
                          </span>
                        </div>
                        <div className="text-sm font-medium leading-snug">
                          {item.title}
                        </div>
                        <div
                          className="flex items-center justify-between gap-2 pt-1 text-xs text-[var(--muted)]"
                          onClick={(e) => e.stopPropagation()}
                        >
                          <span className="truncate">{item.assigneeName || 'Владелец'}</span>
                          <div className="flex items-center gap-1.5">
                            {item.type === 'order' && item.sourceId && onOpenOrder && (
                              <button
                                type="button"
                                onClick={() => onOpenOrder(item.sourceId!)}
                                title="Открыть заказ"
                                className="p-1 rounded-lg border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)]"
                              >
                                <ExternalLink className="w-3 h-3" />
                              </button>
                            )}
                            <select
                              aria-label="Этап задачи"
                              value={item.stage}
                              onChange={(e) =>
                                handleStageChange(item, e.target.value as WorkItem['stage'])
                              }
                              className="px-2 py-1 rounded-lg border border-[var(--line)] bg-[var(--card)] text-[var(--ink)] text-xs"
                            >
                              {STAGES.map((opt) => (
                                <option key={opt.id} value={opt.id}>
                                  {opt.label}
                                </option>
                              ))}
                            </select>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <Card className="p-0 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-xs text-[var(--muted)]">
                  <th className="text-left px-4 py-3 font-medium">Тип</th>
                  <th className="text-left px-4 py-3 font-medium">Задача</th>
                  <th className="text-left px-4 py-3 font-medium">Исполнитель</th>
                  <th className="text-left px-4 py-3 font-medium">Срок</th>
                  <th className="text-left px-4 py-3 font-medium">Этап</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--line)]">
                {filtered.map((item) => {
                  const meta = WORK_TYPE_META[item.type] || WORK_TYPE_META.task;
                  const overdue = isOverdue(item);
                  return (
                    <tr
                      key={item.id}
                      onClick={() => openEditTask(item)}
                      className={`cursor-pointer transition-colors ${
                        overdue
                          ? 'bg-[var(--danger-bg)]/35 hover:bg-[var(--danger-bg)]/50'
                          : 'hover:bg-[var(--soft)]/30'
                      }`}
                    >
                      <td className="px-4 py-3 whitespace-nowrap">
                        <span className="inline-flex items-center gap-2 text-xs font-medium">
                          <span
                            className="w-2.5 h-2.5 rounded-sm"
                            style={{ backgroundColor: meta.color }}
                          />
                          {meta.label}
                        </span>
                      </td>
                      <td className="px-4 py-3 font-medium">
                        <div>{item.title}</div>
                        {item.recurrence && item.recurrence !== 'none' && (
                          <div className="inline-flex items-center gap-1 text-[11px] text-[var(--accent)] mt-0.5">
                            <Repeat className="w-3 h-3" />
                            <span>
                              {RECURRENCE_LABELS_RU[item.recurrence]}
                              {item.occurrenceIndex ? ` · #${item.occurrenceIndex}` : ''}
                            </span>
                          </div>
                        )}
                      </td>
                      <td className="px-4 py-3 text-[var(--muted)]">
                        {item.assigneeName || '—'}
                      </td>
                      <td
                        className={`px-4 py-3 tabular-nums ${
                          overdue
                            ? 'text-[var(--danger)] font-semibold'
                            : 'text-[var(--muted)]'
                        }`}
                      >
                        {item.dueDate || '—'}
                      </td>
                      <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                        <select
                          aria-label="Этап"
                          value={item.stage}
                          onChange={(e) =>
                            handleStageChange(item, e.target.value as WorkItem['stage'])
                          }
                          className="px-2.5 py-1.5 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-xs"
                        >
                          {STAGES.map((opt) => (
                            <option key={opt.id} value={opt.id}>
                              {opt.label}
                            </option>
                          ))}
                        </select>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* Create Task Drawer */}
      <Drawer
        open={drawerOpen}
        title="Новая задача в Работу"
        subtitle="Перемещение задачи не проводит финансы и списания автоматически"
        onClose={() => setDrawerOpen(false)}
      >
        <form onSubmit={handleCreate} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Название задачи</span>
            <input
              type="text"
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Например: Сборка ягодного торта"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Тип</span>
              <select
                value={type}
                onChange={(e) => setType(e.target.value as WorkItemType)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                {(Object.keys(WORK_TYPE_META) as WorkItemType[]).map((t) => (
                  <option key={t} value={t}>
                    {WORK_TYPE_META[t].label}
                  </option>
                ))}
              </select>
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Срок</span>
              <input
                type="date"
                value={dueDate}
                onChange={(e) => setDueDate(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Исполнитель</span>
              <input
                type="text"
                value={assignee}
                onChange={(e) => setAssignee(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Приоритет</span>
              <select
                value={priority}
                onChange={(e) =>
                  setPriority(e.target.value as WorkItem['priority'])
                }
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="low">Низкий</option>
                <option value="normal">Стандартный</option>
                <option value="high">Высокий</option>
              </select>
            </label>
          </div>
          <label className="block space-y-1 text-sm font-medium">
            <span>Повтор задачи</span>
            <select
              value={recurrence}
              onChange={(e) => setRecurrence(e.target.value as WorkRecurrence)}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              {(Object.keys(RECURRENCE_LABELS_RU) as WorkRecurrence[]).map((r) => (
                <option key={r} value={r}>
                  {RECURRENCE_LABELS_RU[r]}
                </option>
              ))}
            </select>
            {recurrence !== 'none' && (
              <span className="block text-xs text-[var(--muted)] font-normal">
                При переводе в «Готово» следующая задача создастся автоматически.
              </span>
            )}
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Создать задачу
          </button>
        </form>
      </Drawer>

      {/* Edit Task Drawer */}
      <Drawer
        open={Boolean(editingItem)}
        title="Редактировать задачу"
        subtitle={
          editingItem
            ? `Тип: ${WORK_TYPE_META[editingItem.type]?.label || 'Задача'}`
            : ''
        }
        onClose={() => setEditingItem(null)}
      >
        {editingItem && (
          <form onSubmit={handleSaveEditTask} className="space-y-4">
            <label className="block space-y-1 text-sm font-medium">
              <span>Название задачи</span>
              <input
                type="text"
                required
                value={editTitle}
                onChange={(e) => setEditTitle(e.target.value)}
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <div className="grid grid-cols-2 gap-3">
              <label className="block space-y-1 text-sm font-medium">
                <span>Этап</span>
                <select
                  value={editStage}
                  onChange={(e) => setEditStage(e.target.value as WorkItem['stage'])}
                  className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                >
                  {STAGES.map((st) => (
                    <option key={st.id} value={st.id}>
                      {st.label}
                    </option>
                  ))}
                </select>
              </label>
              <label className="block space-y-1 text-sm font-medium">
                <span>Срок</span>
                <input
                  type="date"
                  value={editDueDate}
                  onChange={(e) => setEditDueDate(e.target.value)}
                  className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                />
              </label>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <label className="block space-y-1 text-sm font-medium">
                <span>Исполнитель</span>
                <input
                  type="text"
                  value={editAssignee}
                  onChange={(e) => setEditAssignee(e.target.value)}
                  className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                />
              </label>
              <label className="block space-y-1 text-sm font-medium">
                <span>Приоритет</span>
                <select
                  value={editPriority}
                  onChange={(e) =>
                    setEditPriority(e.target.value as WorkItem['priority'])
                  }
                  className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
                >
                  <option value="low">Низкий</option>
                  <option value="normal">Стандартный</option>
                  <option value="high">Высокий</option>
                </select>
              </label>
            </div>

            <label className="block space-y-1 text-sm font-medium">
              <span>Повтор задачи</span>
              <select
                value={editRecurrence}
                onChange={(e) => setEditRecurrence(e.target.value as WorkRecurrence)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                {(Object.keys(RECURRENCE_LABELS_RU) as WorkRecurrence[]).map((r) => (
                  <option key={r} value={r}>
                    {RECURRENCE_LABELS_RU[r]}
                  </option>
                ))}
              </select>
              {editRecurrence !== 'none' && (
                <span className="block text-xs text-[var(--muted)] font-normal">
                  При завершении («Готово») создаётся следующий повтор серии
                  {editingItem.occurrenceIndex ? ` (#${editingItem.occurrenceIndex + 1})` : ''}.
                </span>
              )}
            </label>

            {editingItem.type === 'order' && editingItem.sourceId && onOpenOrder && (
              <button
                type="button"
                onClick={() => {
                  const sid = editingItem.sourceId!;
                  setEditingItem(null);
                  onOpenOrder(sid);
                }}
                className="w-full min-h-[42px] rounded-xl border border-[var(--line)] bg-[var(--soft)] text-xs font-medium inline-flex items-center justify-center gap-1.5"
              >
                <ExternalLink className="w-3.5 h-3.5" />
                <span>Открыть связанный заказ</span>
              </button>
            )}

            <div className="flex gap-2">
              <button
                type="submit"
                className="flex-1 min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
              >
                Сохранить
              </button>
              <button
                type="button"
                onClick={handleDeleteTask}
                title="Удалить задачу"
                className="min-h-[46px] px-4 rounded-xl border border-[var(--line)] text-[var(--danger)] hover:bg-[var(--danger-bg)] inline-flex items-center justify-center"
              >
                <Trash2 className="w-4 h-4" />
              </button>
            </div>
          </form>
        )}
      </Drawer>
    </div>
  );
}
