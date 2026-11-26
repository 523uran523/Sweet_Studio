/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useCallback, useEffect, useState } from 'react';
import { onAuthStateChanged, signOut, User } from 'firebase/auth';
import {
  collection,
  doc,
  getDocs,
  onSnapshot,
  query,
  serverTimestamp,
  updateDoc,
  where,
} from 'firebase/firestore';
import { AppShell, NAV_ITEMS, QuickActionKind } from './components/AppShell';
import { AuthScreen, WorkspaceOnboarding } from './components/AuthOnboarding';
import { ErrorBoundary } from './components/ErrorBoundary';
import { QuickCreateDrawer } from './components/QuickCreateDrawer';
import { auth, db, handleFirestoreError, OperationType } from './firebase/client';
import {
  createWorkspaceEntity,
  newId,
  subscribeWorkspaceCollections,
  WorkspaceSnapshot,
} from './firebase/workspaceService';
import { AnalyticsPage } from './pages/AnalyticsPage';
import {
  ClientsPage,
  LoyaltyPage,
  MarketingPage,
  QualityPage,
} from './pages/ClientsQualityMarketingPage';
import { DashboardPage } from './pages/DashboardPage';
import { InventoryPage, ProductionPage } from './pages/InventoryAndProductionPage';
import {
  AcademyPage,
  MoneyPage,
  SettingsPage,
  TeamPage,
} from './pages/MoneyTeamSettingsPage';
import { LeadsPage, OrdersPage } from './pages/OrdersAndLeadsPage';
import { CalculatorPage, RecipesPage } from './pages/RecipesAndCalculatorPage';
import { WorkHubPage } from './pages/WorkHubPage';
import { NavSectionId, Recipe, UserProfile, Workspace } from './types/domain';

const EMPTY_SNAPSHOT: WorkspaceSnapshot = {
  members: [],
  locations: [],
  recipes: [],
  inventoryItems: [],
  stockLots: [],
  stockMovements: [],
  suppliers: [],
  purchases: [],
  clients: [],
  leads: [],
  orders: [],
  workItems: [],
  productionRuns: [],
  accounts: [],
  transactions: [],
  recurringPayments: [],
  coupons: [],
  complaints: [],
  contentPosts: [],
  payrollPeriods: [],
  timeEntries: [],
};

function parseHashPage(): NavSectionId {
  const raw = window.location.hash.replace(/^#/, '') as NavSectionId;
  return NAV_ITEMS.some((n) => n.id === raw) ? raw : 'dashboard';
}

interface StoredTimerState {
  running: boolean;
  startMs: number | null;
  label: string;
}

function readStoredTimer(workspaceId: string): StoredTimerState {
  try {
    const raw = localStorage.getItem(`sweet_timer_${workspaceId}`);
    if (!raw) return { running: false, startMs: null, label: 'Сборка заказа' };
    const parsed = JSON.parse(raw) as Partial<StoredTimerState>;
    return {
      running: Boolean(parsed.running && parsed.startMs),
      startMs: typeof parsed.startMs === 'number' ? parsed.startMs : null,
      label: typeof parsed.label === 'string' && parsed.label ? parsed.label : 'Сборка заказа',
    };
  } catch {
    return { running: false, startMs: null, label: 'Сборка заказа' };
  }
}

function SweetStudioRoot() {
  const [user, setUser] = useState<User | null>(null);
  const [authReady, setAuthReady] = useState(false);

  const [workspaceId, setWorkspaceId] = useState<string | null>(null);
  const [workspaceResolved, setWorkspaceResolved] = useState(false);
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [allWorkspaces, setAllWorkspaces] = useState<Workspace[]>([]);
  const [createWsOpen, setCreateWsOpen] = useState(false);
  const [data, setData] = useState<WorkspaceSnapshot>(EMPTY_SNAPSHOT);

  const [onboardingTheme, setOnboardingTheme] = useState(0);
  const [activePage, setActivePage] = useState<NavSectionId>(parseHashPage);
  const [hideAmounts, setHideAmounts] = useState(false);
  const [calculatorSeedRecipe, setCalculatorSeedRecipe] = useState<Recipe | null>(null);
  const [selectedOrderId, setSelectedOrderId] = useState<string | null>(null);
  const [quickCreateKind, setQuickCreateKind] = useState<QuickActionKind | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  // Lifted persistent Work Timer state
  const [timerRunning, setTimerRunning] = useState(false);
  const [timerStartMs, setTimerStartMs] = useState<number | null>(null);
  const [timerLabel, setTimerLabel] = useState('Сборка заказа');
  const [elapsedSec, setElapsedSec] = useState(0);

  const showToast = useCallback((msg: string) => {
    setToastMessage(msg);
  }, []);

  useEffect(() => {
    if (!toastMessage) return;
    const t = window.setTimeout(() => setToastMessage(null), 3200);
    return () => window.clearTimeout(t);
  }, [toastMessage]);

  useEffect(() => {
    const onHash = () => setActivePage(parseHashPage());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  const navigate = useCallback((page: NavSectionId) => {
    setActivePage(page);
    if (window.location.hash !== `#${page}`) {
      window.location.hash = page;
    }
  }, []);

  // Auth listener
  useEffect(() => {
    const unsub = onAuthStateChanged(auth, (u) => {
      setUser(u);
      setAuthReady(true);
      if (!u) {
        setWorkspaceId(null);
        setWorkspace(null);
        setAllWorkspaces([]);
        setWorkspaceResolved(false);
        setData(EMPTY_SNAPSHOT);
      }
    });
    return unsub;
  }, []);

  // Subscribe to all workspaces owned by user (for Settings workspace switcher)
  useEffect(() => {
    if (!authReady || !user) {
      setAllWorkspaces([]);
      return;
    }
    const q = query(collection(db, 'workspaces'), where('ownerId', '==', user.uid));
    const unsub = onSnapshot(
      q,
      (snap) => {
        const list = snap.docs.map((d) => ({
          id: d.id,
          ...(d.data() as Omit<Workspace, 'id'>),
        }));
        setAllWorkspaces(list);
      },
      (err) => handleFirestoreError(err, OperationType.LIST, 'workspaces'),
    );
    return unsub;
  }, [authReady, user]);

  // Resolve active workspace ID after auth is ready
  useEffect(() => {
    if (!authReady || !user) return;
    let active = true;
    setWorkspaceResolved(false);

    const userRef = doc(db, 'users', user.uid);
    const unsubUser = onSnapshot(
      userRef,
      async (snap) => {
        if (!active) return;
        const profile = snap.exists() ? (snap.data() as UserProfile) : null;
        if (profile?.activeWorkspaceId) {
          setWorkspaceId(profile.activeWorkspaceId);
          setWorkspaceResolved(true);
          return;
        }
        try {
          const wsSnap = await getDocs(
            query(collection(db, 'workspaces'), where('ownerId', '==', user.uid)),
          );
          if (!active) return;
          if (!wsSnap.empty) {
            setWorkspaceId(wsSnap.docs[0].id);
          } else {
            setWorkspaceId(null);
          }
          setWorkspaceResolved(true);
        } catch (err) {
          handleFirestoreError(err, OperationType.LIST, 'workspaces');
        }
      },
      (err) => handleFirestoreError(err, OperationType.GET, `users/${user.uid}`),
    );

    return () => {
      active = false;
      unsubUser();
    };
  }, [authReady, user]);

  // Subscribe to workspace root document
  useEffect(() => {
    if (!authReady || !user || !workspaceId) {
      setWorkspace(null);
      return;
    }
    let active = true;
    const wsRef = doc(db, 'workspaces', workspaceId);
    const unsub = onSnapshot(
      wsRef,
      (snap) => {
        if (!active) return;
        if (snap.exists()) {
          setWorkspace({ id: snap.id, ...(snap.data() as Omit<Workspace, 'id'>) });
        } else {
          setWorkspace(null);
          setWorkspaceId(null);
        }
      },
      async (err) => {
        if (!active) return;
        try {
          const wsSnap = await getDocs(
            query(collection(db, 'workspaces'), where('ownerId', '==', user.uid)),
          );
          if (!active) return;
          if (!wsSnap.empty && wsSnap.docs[0].id !== workspaceId) {
            setWorkspaceId(wsSnap.docs[0].id);
            return;
          }
          if (wsSnap.empty) {
            setWorkspace(null);
            setWorkspaceId(null);
            setWorkspaceResolved(true);
            return;
          }
        } catch {
          // fall through to structured error reporter
        }
        handleFirestoreError(err, OperationType.GET, `workspaces/${workspaceId}`);
      },
    );
    return () => {
      active = false;
      unsub();
    };
  }, [authReady, user, workspaceId]);

  // Subscribe to all 21 workspace collections once workspace is loaded
  useEffect(() => {
    if (!authReady || !user || !workspace) {
      setData(EMPTY_SNAPSHOT);
      return;
    }
    const unsub = subscribeWorkspaceCollections(workspace, (partial) => {
      setData((prev) => ({ ...prev, ...partial }));
    });
    return unsub;
  }, [authReady, user, workspace?.id, workspace?.ownerId]);

  // Restore timer state when active workspace changes
  useEffect(() => {
    if (!workspace?.id) return;
    const stored = readStoredTimer(workspace.id);
    setTimerRunning(stored.running);
    setTimerStartMs(stored.startMs);
    setTimerLabel(stored.label);
    if (stored.running && stored.startMs) {
      setElapsedSec(Math.max(0, Math.floor((Date.now() - stored.startMs) / 1000)));
    } else {
      setElapsedSec(0);
    }
  }, [workspace?.id]);

  // Tick timer every second while running
  useEffect(() => {
    if (!timerRunning || !timerStartMs) return;
    const tick = () => {
      setElapsedSec(Math.max(0, Math.floor((Date.now() - timerStartMs) / 1000)));
    };
    tick();
    const t = window.setInterval(tick, 1000);
    return () => window.clearInterval(t);
  }, [timerRunning, timerStartMs]);

  // Sync Soft Atelier theme on root HTML element
  useEffect(() => {
    const idx = workspace && !createWsOpen ? (workspace.themeIndex ?? 0) : onboardingTheme;
    document.documentElement.setAttribute('data-theme', String(idx));
  }, [workspace, onboardingTheme, createWsOpen]);

  // Fallback if current page is hidden by workspace module settings
  useEffect(() => {
    if (!workspace) return;
    const hidden = new Set(workspace.hiddenModules || []);
    if (
      activePage !== 'dashboard' &&
      activePage !== 'settings' &&
      activePage !== 'academy' &&
      hidden.has(activePage)
    ) {
      navigate('dashboard');
    }
  }, [workspace, activePage, navigate]);

  const handleOpenInCalculator = useCallback(
    (recipe: Recipe) => {
      setCalculatorSeedRecipe(recipe);
      navigate('calculator');
    },
    [navigate],
  );

  const handleOpenOrder = useCallback(
    (orderId: string) => {
      setSelectedOrderId(orderId);
      navigate('orders');
    },
    [navigate],
  );

  const handleSwitchWorkspace = useCallback(
    async (targetId: string) => {
      if (!user || targetId === workspaceId) return;
      try {
        await updateDoc(doc(db, 'users', user.uid), {
          activeWorkspaceId: targetId,
          updatedAt: serverTimestamp(),
        });
        setWorkspaceId(targetId);
        navigate('dashboard');
        showToast('Рабочее пространство переключено');
      } catch (err) {
        handleFirestoreError(err, OperationType.UPDATE, `users/${user.uid}`);
      }
    },
    [user, workspaceId, navigate, showToast],
  );

  const persistTimer = useCallback(
    (wsId: string, next: StoredTimerState) => {
      try {
        localStorage.setItem(`sweet_timer_${wsId}`, JSON.stringify(next));
      } catch {
        // ignore storage quota errors
      }
    },
    [],
  );

  const handleTimerLabelChange = useCallback(
    (val: string) => {
      setTimerLabel(val);
      if (workspace?.id) {
        persistTimer(workspace.id, {
          running: timerRunning,
          startMs: timerStartMs,
          label: val,
        });
      }
    },
    [workspace?.id, timerRunning, timerStartMs, persistTimer],
  );

  const userName = user?.displayName || user?.email || 'Кондитер';

  const handleToggleTimer = useCallback(async () => {
    if (!workspace) return;
    if (!timerRunning) {
      const startMs = Date.now();
      setTimerStartMs(startMs);
      setTimerRunning(true);
      setElapsedSec(0);
      persistTimer(workspace.id, {
        running: true,
        startMs,
        label: timerLabel,
      });
      showToast('Таймер смены запущен');
    } else {
      const startMs = timerStartMs || Date.now();
      const minutes = Math.max(1, Math.round((Date.now() - startMs) / 60000));
      const cleanLabel = timerLabel.trim() || 'Работа на кухне';
      setTimerRunning(false);
      setTimerStartMs(null);
      setElapsedSec(0);
      persistTimer(workspace.id, {
        running: false,
        startMs: null,
        label: timerLabel,
      });
      await createWorkspaceEntity(workspace, 'timeEntries', newId('te'), {
        employeeName: userName.slice(0, 120),
        orderTitle: cleanLabel.slice(0, 160),
        startedAt: new Date(startMs).toISOString(),
        endedAt: new Date().toISOString(),
        minutes,
      });
      showToast(`Зафиксировано в табель: ${minutes} мин`);
    }
  }, [workspace, timerRunning, timerStartMs, timerLabel, userName, persistTimer, showToast]);

  if (!authReady) {
    return (
      <div className="min-h-screen bg-[var(--bg)] text-[var(--ink)] flex items-center justify-center p-6">
        <div className="text-sm text-[var(--muted)]">Загрузка Sweet Studio...</div>
      </div>
    );
  }

  if (!user) {
    return <AuthScreen />;
  }

  if (!workspaceResolved || (workspaceId && !workspace)) {
    return (
      <div className="min-h-screen bg-[var(--bg)] text-[var(--ink)] flex items-center justify-center p-6">
        <div className="text-sm text-[var(--muted)]">
          Открываем рабочее пространство...
        </div>
      </div>
    );
  }

  if (!workspace || createWsOpen) {
    return (
      <div>
        {createWsOpen && workspace && (
          <div className="bg-[var(--card)] border-b border-[var(--line)] px-4 py-3 flex justify-center">
            <button
              type="button"
              onClick={() => setCreateWsOpen(false)}
              className="text-sm font-medium text-[var(--accent)] hover:underline"
            >
              ← Вернуться в «{workspace.name}»
            </button>
          </div>
        )}
        <WorkspaceOnboarding
          user={user}
          themeIndex={onboardingTheme}
          onSelectTheme={setOnboardingTheme}
          onCreated={(id) => {
            setCreateWsOpen(false);
            setWorkspaceId(id);
            navigate('dashboard');
          }}
        />
      </div>
    );
  }

  const renderPage = () => {
    switch (activePage) {
      case 'dashboard':
        return (
          <DashboardPage
            workspace={workspace}
            userName={userName}
            data={data}
            hideAmounts={hideAmounts}
            onNavigate={navigate}
            onOpenOrder={handleOpenOrder}
            onQuickCreate={setQuickCreateKind}
            onToast={showToast}
            timerRunning={timerRunning}
            elapsedSec={elapsedSec}
            timerLabel={timerLabel}
            onTimerLabelChange={handleTimerLabelChange}
            onToggleTimer={handleToggleTimer}
          />
        );
      case 'work':
        return (
          <WorkHubPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onOpenOrder={handleOpenOrder}
            onToast={showToast}
          />
        );
      case 'orders':
        return (
          <OrdersPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            initialOrderId={selectedOrderId}
            onClearInitialOrder={() => setSelectedOrderId(null)}
            onToast={showToast}
          />
        );
      case 'leads':
        return (
          <LeadsPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'recipes':
        return (
          <RecipesPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onOpenInCalculator={handleOpenInCalculator}
            onToast={showToast}
          />
        );
      case 'calculator':
        return (
          <CalculatorPage
            workspace={workspace}
            data={data}
            initialRecipe={calculatorSeedRecipe}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'inventory':
        return (
          <InventoryPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'production':
        return (
          <ProductionPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'clients':
        return (
          <ClientsPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'loyalty':
        return (
          <LoyaltyPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'quality':
        return (
          <QualityPage
            workspace={workspace}
            data={data}
            onNavigate={navigate}
            onToast={showToast}
          />
        );
      case 'marketing':
        return (
          <MarketingPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'money':
        return (
          <MoneyPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'analytics':
        return (
          <AnalyticsPage
            data={data}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'team':
        return (
          <TeamPage
            workspace={workspace}
            data={data}
            hideAmounts={hideAmounts}
            onToast={showToast}
          />
        );
      case 'settings':
        return (
          <SettingsPage
            workspace={workspace}
            allWorkspaces={allWorkspaces}
            data={data}
            onSwitchWorkspace={handleSwitchWorkspace}
            onCreateWorkspace={() => setCreateWsOpen(true)}
            onToast={showToast}
          />
        );
      case 'academy':
        return <AcademyPage />;
      default:
        return null;
    }
  };

  return (
    <AppShell
      workspace={workspace}
      userName={userName}
      activePage={activePage}
      onNavigate={navigate}
      hideAmounts={hideAmounts}
      onToggleHideAmounts={() => setHideAmounts((v) => !v)}
      onSignOut={() => void signOut(auth)}
      data={data}
      onQuickCreate={setQuickCreateKind}
      toastMessage={toastMessage}
    >
      {renderPage()}
      <QuickCreateDrawer
        kind={quickCreateKind}
        workspace={workspace}
        data={data}
        onClose={() => setQuickCreateKind(null)}
        onToast={showToast}
      />
    </AppShell>
  );
}

export default function App() {
  return (
    <ErrorBoundary>
      <SweetStudioRoot />
    </ErrorBoundary>
  );
}
