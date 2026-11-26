import {
  arrayUnion,
  collection,
  deleteDoc,
  doc,
  onSnapshot,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  Unsubscribe,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';
import { computeNextBillingDates, SUBSCRIPTION_PRICE_CENTS } from '../core/subscription';
import {
  Account,
  BillingEvent,
  CashShift,
  Client,
  Complaint,
  ContentPost,
  Coupon,
  InventoryItem,
  Lead,
  LocationItem,
  MoneyTransaction,
  Order,
  PayrollPeriod,
  PayType,
  PosSale,
  PosSaleLine,
  ProductionRun,
  Purchase,
  Recipe,
  RecurringPayment,
  StockLot,
  StockMovement,
  StockTransfer,
  Supplier,
  TimeEntry,
  UserRole,
  WorkItem,
  Workspace,
  WorkspaceInvitation,
  WorkspaceMember,
} from '../types/domain';
import { db, handleFirestoreError, OperationType } from './client';

export function newId(prefix = 'id'): string {
  const raw =
    typeof crypto !== 'undefined' && crypto.randomUUID
      ? crypto.randomUUID().replace(/-/g, '').slice(0, 14)
      : Math.random().toString(36).slice(2, 14);
  return `${prefix}_${raw}`;
}

export interface WorkspaceSnapshot {
  members: WorkspaceMember[];
  locations: LocationItem[];
  recipes: Recipe[];
  inventoryItems: InventoryItem[];
  stockLots: StockLot[];
  stockMovements: StockMovement[];
  stockTransfers: StockTransfer[];
  suppliers: Supplier[];
  purchases: Purchase[];
  clients: Client[];
  leads: Lead[];
  orders: Order[];
  workItems: WorkItem[];
  productionRuns: ProductionRun[];
  accounts: Account[];
  transactions: MoneyTransaction[];
  recurringPayments: RecurringPayment[];
  coupons: Coupon[];
  complaints: Complaint[];
  contentPosts: ContentPost[];
  payrollPeriods: PayrollPeriod[];
  timeEntries: TimeEntry[];
  cashShifts: CashShift[];
  posSales: PosSale[];
  billingEvents: BillingEvent[];
}

export function subscribeWorkspaceCollections(
  workspace: Workspace,
  onData: (partial: Partial<WorkspaceSnapshot>) => void,
): () => void {
  const unsubs: Unsubscribe[] = [];
  const sub = <K extends keyof WorkspaceSnapshot>(colName: string, key: K) => {
    const path = `workspaces/${workspace.id}/${colName}`;
    const q = query(collection(db, path), where('ownerId', '==', workspace.ownerId));
    const u = onSnapshot(
      q,
      (snap) => {
        const items = snap.docs.map((d) => ({ id: d.id, ...d.data() })) as WorkspaceSnapshot[K];
        onData({ [key]: items } as Partial<WorkspaceSnapshot>);
      },
      (err) => handleFirestoreError(err, OperationType.LIST, path),
    );
    unsubs.push(u);
  };

  sub('members', 'members');
  sub('locations', 'locations');
  sub('recipes', 'recipes');
  sub('inventoryItems', 'inventoryItems');
  sub('stockLots', 'stockLots');
  sub('stockMovements', 'stockMovements');
  sub('stockTransfers', 'stockTransfers');
  sub('suppliers', 'suppliers');
  sub('purchases', 'purchases');
  sub('clients', 'clients');
  sub('leads', 'leads');
  sub('orders', 'orders');
  sub('workItems', 'workItems');
  sub('productionRuns', 'productionRuns');
  sub('accounts', 'accounts');
  sub('transactions', 'transactions');
  sub('recurringPayments', 'recurringPayments');
  sub('coupons', 'coupons');
  sub('complaints', 'complaints');
  sub('contentPosts', 'contentPosts');
  sub('payrollPeriods', 'payrollPeriods');
  sub('timeEntries', 'timeEntries');
  sub('cashShifts', 'cashShifts');
  sub('posSales', 'posSales');
  sub('billingEvents', 'billingEvents');

  return () => unsubs.forEach((u) => u());
}

export async function createWorkspaceEntity(
  workspace: Workspace,
  colName: string,
  id: string,
  payload: Record<string, unknown>,
) {
  const path = `workspaces/${workspace.id}/${colName}/${id}`;
  try {
    await setDoc(doc(db, 'workspaces', workspace.id, colName, id), {
      ...payload,
      workspaceId: workspace.id,
      ownerId: workspace.ownerId,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.CREATE, path);
  }
}

export async function updateWorkspaceEntity(
  workspace: Workspace,
  colName: string,
  id: string,
  patch: Record<string, unknown>,
) {
  const path = `workspaces/${workspace.id}/${colName}/${id}`;
  try {
    await updateDoc(doc(db, 'workspaces', workspace.id, colName, id), {
      ...patch,
      updatedAt: serverTimestamp(),
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.UPDATE, path);
  }
}

export async function deleteWorkspaceEntity(
  workspace: Workspace,
  colName: string,
  id: string,
) {
  const path = `workspaces/${workspace.id}/${colName}/${id}`;
  try {
    await deleteDoc(doc(db, 'workspaces', workspace.id, colName, id));
  } catch (err) {
    handleFirestoreError(err, OperationType.DELETE, path);
  }
}

export async function updateWorkspacePrefs(
  workspaceId: string,
  patch: Partial<Pick<Workspace, 'name' | 'slogan' | 'businessFormat' | 'themeIndex' | 'density' | 'pins' | 'hiddenModules'>>,
) {
  const path = `workspaces/${workspaceId}`;
  try {
    await updateDoc(doc(db, 'workspaces', workspaceId), {
      ...patch,
      updatedAt: serverTimestamp(),
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.UPDATE, path);
  }
}

/**
 * Atomic single-time conversion of a Lead into an Order + WorkItem + auto-linked Client.
 */
export async function convertLeadToOrder(
  workspace: Workspace,
  lead: Lead,
  orderCount: number,
  existingClients: Client[] = [],
): Promise<string> {
  if (lead.status === 'converted') {
    throw new Error('Заявка уже конвертирована в заказ.');
  }
  const orderId = newId('ord');
  const workId = newId('wi');
  const orderNumber = `№${106 + orderCount}`;
  const priceCents = lead.budgetCents && lead.budgetCents > 0 ? lead.budgetCents : 350000;
  const dueDate = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);

  const normalizedPhone = (lead.phone || '').replace(/\D+/g, '');
  const normalizedName = lead.clientName.trim().toLowerCase();
  const matchedClient = existingClients.find((c) => {
    const cp = (c.phone || '').replace(/\D+/g, '');
    if (normalizedPhone && cp && normalizedPhone === cp) return true;
    return c.name.trim().toLowerCase() === normalizedName;
  });
  const clientId = matchedClient?.id || newId('cli');

  const path = `workspaces/${workspace.id}/leads/${lead.id}`;
  try {
    await runTransaction(db, async (tx) => {
      const leadRef = doc(db, 'workspaces', workspace.id, 'leads', lead.id);
      const snap = await tx.get(leadRef);
      if (!snap.exists() || snap.data().status === 'converted') {
        throw new Error('Заявка уже конвертирована в заказ.');
      }
      const now = serverTimestamp();

      if (matchedClient) {
        const cliRef = doc(db, 'workspaces', workspace.id, 'clients', matchedClient.id);
        const cliSnap = await tx.get(cliRef);
        if (cliSnap.exists()) {
          tx.update(cliRef, {
            ordersCount: Number(cliSnap.data().ordersCount || 0) + 1,
            updatedAt: now,
          });
        }
      } else {
        const cliPayload: Record<string, unknown> = {
          workspaceId: workspace.id,
          ownerId: workspace.ownerId,
          name: lead.clientName.slice(0, 140),
          ordersCount: 1,
          depositCents: 0,
          debtCents: 0,
          favorite: false,
          createdAt: now,
          updatedAt: now,
        };
        if (lead.phone) cliPayload.phone = lead.phone.slice(0, 40);
        if (lead.source) cliPayload.source = lead.source.slice(0, 80);
        tx.set(doc(db, 'workspaces', workspace.id, 'clients', clientId), cliPayload);
      }

      tx.set(doc(db, 'workspaces', workspace.id, 'orders', orderId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        orderNumber,
        title: lead.requestText.slice(0, 160),
        clientId,
        clientName: lead.clientName.slice(0, 140),
        items: [
          {
            id: newId('item'),
            recipeId: '',
            recipeTitle: lead.requestText.slice(0, 160),
            qty: 1,
            weightGrams: 1500,
            priceCents,
            costCents: Math.round(priceCents * 0.52),
          },
        ],
        prepaymentCents: Math.round(priceCents * 0.5),
        paidCents: 0,
        discountCents: 0,
        status: 'confirmed',
        dueDate,
        assigneeName: 'Владелец',
        locationName: 'Основная студия',
        wishes: lead.requestText.slice(0, 400),
        favorite: false,
        createdAt: now,
        updatedAt: now,
      });
      tx.set(doc(db, 'workspaces', workspace.id, 'workItems', workId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        type: 'order',
        sourceId: orderId,
        title: `${orderNumber} · ${lead.requestText.slice(0, 120)}`,
        assigneeName: 'Владелец',
        locationName: 'Основная студия',
        dueDate,
        priority: 'normal',
        stage: 'queue',
        tags: ['из заявки'],
        createdAt: now,
        updatedAt: now,
      });
      tx.update(leadRef, {
        status: 'converted',
        convertedOrderId: orderId,
        updatedAt: now,
      });
    });
    return orderId;
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
    return orderId;
  }
}

/**
 * Record an order payment atomically: creates MoneyTransaction, updates Order.paidCents and Account.balanceCents.
 */
export async function recordOrderPayment(params: {
  workspace: Workspace;
  order: Order;
  account: Account;
  amountCents: number;
  note?: string;
}) {
  const { workspace, order, account, amountCents, note } = params;
  if (amountCents <= 0) return;
  const txId = newId('tx');
  const path = `workspaces/${workspace.id}/orders/${order.id}`;
  try {
    await runTransaction(db, async (tx) => {
      const orderRef = doc(db, 'workspaces', workspace.id, 'orders', order.id);
      const accRef = doc(db, 'workspaces', workspace.id, 'accounts', account.id);
      const [orderSnap, accSnap] = await Promise.all([tx.get(orderRef), tx.get(accRef)]);
      if (!orderSnap.exists() || !accSnap.exists()) {
        throw new Error('Заказ или счёт не найдены');
      }
      const prevPaid = Number(orderSnap.data().paidCents || 0);
      const prevBal = Number(accSnap.data().balanceCents || 0);
      const now = serverTimestamp();

      tx.update(orderRef, {
        paidCents: prevPaid + amountCents,
        updatedAt: now,
      });
      tx.update(accRef, {
        balanceCents: prevBal + amountCents,
        updatedAt: now,
      });
      tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'income',
        category: 'Оплата заказа',
        amountCents,
        accountId: account.id,
        accountName: account.name.slice(0, 100),
        orderId: order.id,
        note: (note || `Оплата по заказу ${order.orderNumber} (${order.clientName})`).slice(0, 240),
        occurredAt: new Date().toISOString().slice(0, 10),
        createdAt: now,
        updatedAt: now,
      });
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Pay an order from a Client's pre-funded deposit atomically (no duplicate cash income).
 */
export async function payOrderWithDeposit(params: {
  workspace: Workspace;
  order: Order;
  client: Client;
  amountCents: number;
}) {
  const { workspace, order, client, amountCents } = params;
  if (amountCents <= 0) return;
  const path = `workspaces/${workspace.id}/orders/${order.id}`;
  try {
    await runTransaction(db, async (tx) => {
      const orderRef = doc(db, 'workspaces', workspace.id, 'orders', order.id);
      const cliRef = doc(db, 'workspaces', workspace.id, 'clients', client.id);
      const [orderSnap, cliSnap] = await Promise.all([tx.get(orderRef), tx.get(cliRef)]);
      if (!orderSnap.exists() || !cliSnap.exists()) {
        throw new Error('Заказ или карточка клиента не найдены');
      }
      const prevPaid = Number(orderSnap.data().paidCents || 0);
      const prevDep = Number(cliSnap.data().depositCents || 0);
      if (prevDep < amountCents) {
        throw new Error('Недостаточно средств на депозите клиента');
      }
      const now = serverTimestamp();
      tx.update(cliRef, {
        depositCents: prevDep - amountCents,
        updatedAt: now,
      });
      tx.update(orderRef, {
        paidCents: prevPaid + amountCents,
        updatedAt: now,
      });
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Refund an order payment atomically: decrements Order.paidCents, Account.balanceCents, and records expense tx.
 */
export async function refundOrderPayment(params: {
  workspace: Workspace;
  order: Order;
  account: Account;
  amountCents: number;
  note?: string;
}) {
  const { workspace, order, account, amountCents, note } = params;
  if (amountCents <= 0) return;
  const txId = newId('tx');
  const path = `workspaces/${workspace.id}/orders/${order.id}`;
  try {
    await runTransaction(db, async (tx) => {
      const orderRef = doc(db, 'workspaces', workspace.id, 'orders', order.id);
      const accRef = doc(db, 'workspaces', workspace.id, 'accounts', account.id);
      const [orderSnap, accSnap] = await Promise.all([tx.get(orderRef), tx.get(accRef)]);
      if (!orderSnap.exists() || !accSnap.exists()) {
        throw new Error('Заказ или счёт не найдены');
      }
      const prevPaid = Number(orderSnap.data().paidCents || 0);
      if (amountCents > prevPaid) {
        throw new Error('Сумма возврата превышает оплаченную сумму по заказу');
      }
      const prevBal = Number(accSnap.data().balanceCents || 0);
      const now = serverTimestamp();
      tx.update(orderRef, {
        paidCents: prevPaid - amountCents,
        updatedAt: now,
      });
      tx.update(accRef, {
        balanceCents: prevBal - amountCents,
        updatedAt: now,
      });
      tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'expense',
        category: 'Возврат по заказу',
        amountCents,
        accountId: account.id,
        accountName: account.name.slice(0, 100),
        orderId: order.id,
        note: (note || `Возврат оплаты по заказу ${order.orderNumber} (${order.clientName})`).slice(0, 240),
        occurredAt: new Date().toISOString().slice(0, 10),
        createdAt: now,
        updatedAt: now,
      });
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Top up Client deposit atomically with cash income transaction.
 */
export async function recordClientDepositTopUp(params: {
  workspace: Workspace;
  client: Client;
  account: Account;
  amountCents: number;
  note?: string;
}) {
  const { workspace, client, account, amountCents, note } = params;
  if (amountCents <= 0) return;
  const txId = newId('tx');
  const path = `workspaces/${workspace.id}/clients/${client.id}`;
  try {
    await runTransaction(db, async (tx) => {
      const cliRef = doc(db, 'workspaces', workspace.id, 'clients', client.id);
      const accRef = doc(db, 'workspaces', workspace.id, 'accounts', account.id);
      const [cliSnap, accSnap] = await Promise.all([tx.get(cliRef), tx.get(accRef)]);
      if (!cliSnap.exists() || !accSnap.exists()) {
        throw new Error('Клиент или счёт не найдены');
      }
      const prevDep = Number(cliSnap.data().depositCents || 0);
      const prevBal = Number(accSnap.data().balanceCents || 0);
      const now = serverTimestamp();
      tx.update(cliRef, {
        depositCents: prevDep + amountCents,
        updatedAt: now,
      });
      tx.update(accRef, {
        balanceCents: prevBal + amountCents,
        updatedAt: now,
      });
      tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'income',
        category: 'Депозит клиента',
        amountCents,
        accountId: account.id,
        accountName: account.name.slice(0, 100),
        note: (note || `Пополнение депозита: ${client.name}`).slice(0, 240),
        occurredAt: new Date().toISOString().slice(0, 10),
        createdAt: now,
        updatedAt: now,
      });
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * FEFO consumption across active, non-quarantined, non-expired StockLots.
 * Returns consumed cost and updated lots array for sequential multi-ingredient chaining.
 */
export async function consumeInventoryFefo(params: {
  workspace: Workspace;
  item: InventoryItem;
  lots: StockLot[];
  qtyToConsume: number;
  reason: string;
}): Promise<{ totalCostCents: number; updatedLots: StockLot[]; updatedItemQty: number }> {
  const { workspace, item, lots, qtyToConsume, reason } = params;
  if (qtyToConsume <= 0) {
    return { totalCostCents: 0, updatedLots: lots, updatedItemQty: item.qtyOnHand };
  }
  const today = new Date().toISOString().slice(0, 10);
  const eligible = lots
    .filter(
      (l) =>
        l.itemId === item.id &&
        l.status === 'active' &&
        l.remainingQty > 0 &&
        (!l.expiresAt || l.expiresAt >= today),
    )
    .sort((a, b) => (a.expiresAt || '9999-12-31').localeCompare(b.expiresAt || '9999-12-31'));

  const totalAvail = eligible.reduce((s, l) => s + l.remainingQty, 0);
  if (totalAvail + 1e-9 < qtyToConsume) {
    throw new Error(`Недостаточно годных партий «${item.name}» (доступно ${totalAvail} ${item.unit})`);
  }

  const batch = writeBatch(db);
  const now = serverTimestamp();
  let remaining = qtyToConsume;
  let totalCostCents = 0;
  const updatedById = new Map<string, StockLot>();

  for (const lot of eligible) {
    if (remaining <= 0) break;
    const take = Math.min(lot.remainingQty, remaining);
    const nextLotQty = Math.max(0, Math.round((lot.remainingQty - take) * 1000) / 1000);
    const nextStatus: StockLot['status'] = nextLotQty <= 0 ? 'depleted' : 'active';
    const lineCost = Math.round(take * lot.unitCostCents);
    totalCostCents += lineCost;

    batch.update(doc(db, 'workspaces', workspace.id, 'stockLots', lot.id), {
      remainingQty: nextLotQty,
      status: nextStatus,
      updatedAt: now,
    });
    updatedById.set(lot.id, { ...lot, remainingQty: nextLotQty, status: nextStatus });

    const movId = newId('mov');
    batch.set(doc(db, 'workspaces', workspace.id, 'stockMovements', movId), {
      workspaceId: workspace.id,
      ownerId: workspace.ownerId,
      kind: 'issue',
      itemId: item.id,
      itemName: item.name.slice(0, 140),
      lotId: lot.id,
      qty: take,
      unit: item.unit,
      totalCents: lineCost,
      reason: reason.slice(0, 200),
      createdAt: now,
      updatedAt: now,
    });
    remaining = Math.round((remaining - take) * 1000) / 1000;
  }

  const nextItemQty = Math.max(0, Math.round((item.qtyOnHand - qtyToConsume) * 1000) / 1000);
  batch.update(doc(db, 'workspaces', workspace.id, 'inventoryItems', item.id), {
    qtyOnHand: nextItemQty,
    updatedAt: now,
  });

  try {
    await batch.commit();
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, `workspaces/${workspace.id}/inventoryItems/${item.id}`);
  }

  const updatedLots = lots.map((l) => updatedById.get(l.id) ?? l);
  return { totalCostCents, updatedLots, updatedItemQty: nextItemQty };
}

/**
 * Write off spoilage / expired / damaged stock lot or manual stocktake adjustment.
 */
export async function writeOffStockLot(params: {
  workspace: Workspace;
  lot: StockLot;
  item?: InventoryItem;
  qty: number;
  kind?: 'issue' | 'adjustment';
  reason: string;
}) {
  const { workspace, lot, item, qty, kind = 'issue', reason } = params;
  if (qty <= 0) return;
  const take = Math.min(lot.remainingQty, qty);
  const nextLotQty = Math.max(0, Math.round((lot.remainingQty - take) * 1000) / 1000);
  const nextStatus: StockLot['status'] = nextLotQty <= 0 ? 'depleted' : lot.status;
  const lossCostCents = Math.round(take * lot.unitCostCents);
  const movId = newId('mov');
  const now = serverTimestamp();

  const batch = writeBatch(db);
  batch.update(doc(db, 'workspaces', workspace.id, 'stockLots', lot.id), {
    remainingQty: nextLotQty,
    status: nextStatus,
    updatedAt: now,
  });
  if (item) {
    batch.update(doc(db, 'workspaces', workspace.id, 'inventoryItems', item.id), {
      qtyOnHand: Math.max(0, Math.round((item.qtyOnHand - take) * 1000) / 1000),
      updatedAt: now,
    });
  }
  batch.set(doc(db, 'workspaces', workspace.id, 'stockMovements', movId), {
    workspaceId: workspace.id,
    ownerId: workspace.ownerId,
    kind,
    itemId: lot.itemId,
    itemName: lot.itemName.slice(0, 140),
    lotId: lot.id,
    qty: take,
    unit: lot.unit,
    totalCents: lossCostCents,
    reason: reason.slice(0, 200),
    createdAt: now,
    updatedAt: now,
  });
  try {
    await batch.commit();
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, `workspaces/${workspace.id}/stockLots/${lot.id}`);
  }
}

/**
 * Upsert inventory receipt (used by QuickCreateDrawer and ProductionRun completion to avoid duplicate items).
 */
export async function upsertInventoryReceipt(params: {
  workspace: Workspace;
  items: InventoryItem[];
  existingItemId?: string;
  name: string;
  kind: InventoryItem['kind'];
  category?: string;
  unit: string;
  qty: number;
  totalCostCents: number;
  expiresAt?: string;
  reason: string;
  movementKind?: StockMovement['kind'];
  account?: Account;
  locationId?: string;
}): Promise<string> {
  const {
    workspace,
    items,
    existingItemId,
    name,
    kind,
    category,
    unit,
    qty,
    totalCostCents,
    expiresAt,
    reason,
    movementKind = 'receipt',
    account,
    locationId,
  } = params;
  const matched =
    (existingItemId ? items.find((i) => i.id === existingItemId) : undefined) ||
    items.find(
      (i) =>
        i.name.trim().toLowerCase() === name.trim().toLowerCase() &&
        i.unit.trim().toLowerCase() === unit.trim().toLowerCase() &&
        (locationId ? i.locationId === locationId : !i.locationId),
    ) ||
    (!locationId
      ? items.find(
          (i) =>
            i.name.trim().toLowerCase() === name.trim().toLowerCase() &&
            i.unit.trim().toLowerCase() === unit.trim().toLowerCase(),
        )
      : undefined);

  const itemId = matched?.id || newId('inv');
  const lotId = newId('lot');
  const movId = newId('mov');
  const unitCostCents = Math.round(totalCostCents / Math.max(qty, 0.001));
  const path = `workspaces/${workspace.id}/inventoryItems/${itemId}`;

  try {
    await runTransaction(db, async (tx) => {
      const now = serverTimestamp();
      const itemRef = doc(db, 'workspaces', workspace.id, 'inventoryItems', itemId);
      const itemSnap = matched ? await tx.get(itemRef) : null;
      const accRef = account ? doc(db, 'workspaces', workspace.id, 'accounts', account.id) : null;
      const accSnap = accRef ? await tx.get(accRef) : null;

      if (itemSnap && itemSnap.exists()) {
        const curQty = Number(itemSnap.data().qtyOnHand || 0);
        const curAvg = Number(itemSnap.data().avgCostCents || 0);
        const nextQty = Math.round((curQty + qty) * 1000) / 1000;
        const nextAvg =
          nextQty > 0 ? Math.round((curQty * curAvg + totalCostCents) / nextQty) : unitCostCents;
        tx.update(itemRef, {
          qtyOnHand: nextQty,
          avgCostCents: nextAvg,
          updatedAt: now,
        });
      } else {
        const itemPayload: Record<string, unknown> = {
          workspaceId: workspace.id,
          ownerId: workspace.ownerId,
          name: name.slice(0, 140),
          kind,
          category: (category || 'Поступление').slice(0, 80),
          unit,
          qtyOnHand: qty,
          minQty: 1,
          avgCostCents: unitCostCents,
          createdAt: now,
          updatedAt: now,
        };
        if (locationId) itemPayload.locationId = locationId;
        tx.set(itemRef, itemPayload);
      }

      const lotPayload: Record<string, unknown> = {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        itemId,
        itemName: (matched?.name || name).slice(0, 140),
        lotCode: `${movementKind === 'production_in' ? 'ВП' : 'ПР'}-${new Date().toISOString().slice(5, 10).replace('-', '')}`,
        unit,
        initialQty: qty,
        remainingQty: qty,
        unitCostCents,
        expiresAt: expiresAt || new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      };
      if (locationId || matched?.locationId) {
        lotPayload.locationId = locationId || matched?.locationId;
      }
      tx.set(doc(db, 'workspaces', workspace.id, 'stockLots', lotId), lotPayload);

      tx.set(doc(db, 'workspaces', workspace.id, 'stockMovements', movId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: movementKind,
        itemId,
        itemName: (matched?.name || name).slice(0, 140),
        lotId,
        qty,
        unit,
        totalCents: totalCostCents,
        reason: reason.slice(0, 200),
        createdAt: now,
        updatedAt: now,
      });

      if (accRef && accSnap && accSnap.exists() && totalCostCents > 0) {
        const txId = newId('tx');
        const prevBal = Number(accSnap.data().balanceCents || 0);
        tx.update(accRef, {
          balanceCents: prevBal - totalCostCents,
          updatedAt: now,
        });
        tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
          workspaceId: workspace.id,
          ownerId: workspace.ownerId,
          kind: 'expense',
          category: 'Закупка сырья',
          amountCents: totalCostCents,
          accountId: account!.id,
          accountName: account!.name.slice(0, 100),
          note: `${name} · ${qty} ${unit}`.slice(0, 240),
          occurredAt: new Date().toISOString().slice(0, 10),
          createdAt: now,
          updatedAt: now,
        });
      }
    });
    return itemId;
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
    return itemId;
  }
}

/**
 * Atomic receipt of a Purchase order with optional immediate payment or supplier debt tracking.
 */
export async function receivePurchaseOrder(params: {
  workspace: Workspace;
  purchase: Purchase;
  item?: InventoryItem;
  expiresAt?: string;
  paymentMode?: 'paid' | 'debt' | 'none';
  account?: Account;
  supplier?: Supplier;
}) {
  const {
    workspace,
    purchase,
    item,
    expiresAt,
    paymentMode = 'none',
    account,
    supplier,
  } = params;
  if (purchase.status === 'received') return;
  const lotId = newId('lot');
  const movId = newId('mov');
  const itemId = item?.id || purchase.itemId || newId('inv');
  const totalPurchaseCents = purchase.priceCents + (purchase.deliveryCents || 0);
  const unitCostCents = Math.round(totalPurchaseCents / Math.max(purchase.qty, 0.001));
  const path = `workspaces/${workspace.id}/purchases/${purchase.id}`;

  try {
    await runTransaction(db, async (tx) => {
      const purRef = doc(db, 'workspaces', workspace.id, 'purchases', purchase.id);
      const purSnap = await tx.get(purRef);
      if (!purSnap.exists() || purSnap.data().status === 'received') return;

      const itemRef = doc(db, 'workspaces', workspace.id, 'inventoryItems', itemId);
      const itemSnap = item ? await tx.get(itemRef) : null;
      const accRef =
        paymentMode === 'paid' && account
          ? doc(db, 'workspaces', workspace.id, 'accounts', account.id)
          : null;
      const accSnap = accRef ? await tx.get(accRef) : null;
      const supRef =
        paymentMode === 'debt' && supplier
          ? doc(db, 'workspaces', workspace.id, 'suppliers', supplier.id)
          : null;
      const supSnap = supRef ? await tx.get(supRef) : null;

      const now = serverTimestamp();
      tx.update(purRef, {
        status: 'received',
        updatedAt: now,
      });

      if (itemSnap && itemSnap.exists()) {
        const curQty = Number(itemSnap.data().qtyOnHand || 0);
        const curAvg = Number(itemSnap.data().avgCostCents || 0);
        const nextQty = Math.round((curQty + purchase.qty) * 1000) / 1000;
        const nextAvg =
          nextQty > 0
            ? Math.round((curQty * curAvg + totalPurchaseCents) / nextQty)
            : unitCostCents;
        tx.update(itemRef, {
          qtyOnHand: nextQty,
          avgCostCents: nextAvg,
          updatedAt: now,
        });
      } else {
        tx.set(itemRef, {
          workspaceId: workspace.id,
          ownerId: workspace.ownerId,
          name: purchase.itemName.slice(0, 140),
          kind: 'raw',
          category: 'Закупка',
          unit: purchase.unit,
          qtyOnHand: purchase.qty,
          minQty: 1,
          avgCostCents: unitCostCents,
          createdAt: now,
          updatedAt: now,
        });
      }

      tx.set(doc(db, 'workspaces', workspace.id, 'stockLots', lotId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        itemId,
        itemName: purchase.itemName.slice(0, 140),
        lotCode: `П-${new Date().toISOString().slice(5, 10).replace('-', '')}`,
        unit: purchase.unit,
        initialQty: purchase.qty,
        remainingQty: purchase.qty,
        unitCostCents,
        expiresAt: expiresAt || new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      });

      tx.set(doc(db, 'workspaces', workspace.id, 'stockMovements', movId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'receipt',
        itemId,
        itemName: purchase.itemName.slice(0, 140),
        lotId,
        qty: purchase.qty,
        unit: purchase.unit,
        totalCents: totalPurchaseCents,
        reason: `Поставка от ${purchase.supplierName}`.slice(0, 200),
        createdAt: now,
        updatedAt: now,
      });

      if (accRef && accSnap && accSnap.exists() && totalPurchaseCents > 0) {
        const txId = newId('tx');
        tx.update(accRef, {
          balanceCents: Number(accSnap.data().balanceCents || 0) - totalPurchaseCents,
          updatedAt: now,
        });
        tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
          workspaceId: workspace.id,
          ownerId: workspace.ownerId,
          kind: 'expense',
          category: 'Закупка сырья',
          amountCents: totalPurchaseCents,
          accountId: account!.id,
          accountName: account!.name.slice(0, 100),
          note: `Поставка ${purchase.itemName} (${purchase.supplierName})`.slice(0, 240),
          occurredAt: new Date().toISOString().slice(0, 10),
          createdAt: now,
          updatedAt: now,
        });
      }

      if (supRef && supSnap && supSnap.exists() && totalPurchaseCents > 0) {
        tx.update(supRef, {
          debtCents: Number(supSnap.data().debtCents || 0) + totalPurchaseCents,
          updatedAt: now,
        });
      }
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Pay down supplier debt atomically from an Account.
 */
export async function paySupplierDebt(params: {
  workspace: Workspace;
  supplier: Supplier;
  account: Account;
  amountCents: number;
  note?: string;
}) {
  const { workspace, supplier, account, amountCents, note } = params;
  if (amountCents <= 0) return;
  const txId = newId('tx');
  const path = `workspaces/${workspace.id}/suppliers/${supplier.id}`;
  try {
    await runTransaction(db, async (tx) => {
      const supRef = doc(db, 'workspaces', workspace.id, 'suppliers', supplier.id);
      const accRef = doc(db, 'workspaces', workspace.id, 'accounts', account.id);
      const [supSnap, accSnap] = await Promise.all([tx.get(supRef), tx.get(accRef)]);
      if (!supSnap.exists() || !accSnap.exists()) {
        throw new Error('Поставщик или счёт не найдены');
      }
      const prevDebt = Number(supSnap.data().debtCents || 0);
      const prevBal = Number(accSnap.data().balanceCents || 0);
      const now = serverTimestamp();

      tx.update(supRef, {
        debtCents: Math.max(0, prevDebt - amountCents),
        updatedAt: now,
      });
      tx.update(accRef, {
        balanceCents: prevBal - amountCents,
        updatedAt: now,
      });
      tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'expense',
        category: 'Оплата поставщику',
        amountCents,
        accountId: account.id,
        accountName: account.name.slice(0, 100),
        note: (note || `Погашение долга: ${supplier.name}`).slice(0, 240),
        occurredAt: new Date().toISOString().slice(0, 10),
        createdAt: now,
        updatedAt: now,
      });
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Sync linked WorkItems stage whenever an Order status changes.
 */
export async function syncOrderWorkItemsStatus(
  workspace: Workspace,
  workItems: WorkItem[],
  orderId: string,
  nextOrderStatus: Order['status'],
) {
  const linked = workItems.filter((w) => w.sourceId === orderId);
  if (linked.length === 0) return;
  const nextStage: WorkItem['stage'] =
    nextOrderStatus === 'delivered' || nextOrderStatus === 'closed' || nextOrderStatus === 'cancelled'
      ? 'done'
      : nextOrderStatus === 'in_progress' || nextOrderStatus === 'ready'
        ? 'in_progress'
        : 'queue';
  const batch = writeBatch(db);
  const now = serverTimestamp();
  let changed = false;
  for (const w of linked) {
    if (w.stage !== nextStage) {
      batch.update(doc(db, 'workspaces', workspace.id, 'workItems', w.id), {
        stage: nextStage,
        updatedAt: now,
      });
      changed = true;
    }
  }
  if (!changed) return;
  try {
    await batch.commit();
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, `workspaces/${workspace.id}/workItems`);
  }
}

/**
 * Record standalone income/expense transaction + update account balance atomically.
 */
export async function addFinancialTransaction(params: {
  workspace: Workspace;
  account: Account;
  kind: 'income' | 'expense';
  category: string;
  amountCents: number;
  note?: string;
}) {
  const { workspace, account, kind, category, amountCents, note } = params;
  const txId = newId('tx');
  const delta = kind === 'income' ? amountCents : -amountCents;
  const path = `workspaces/${workspace.id}/transactions/${txId}`;
  try {
    await runTransaction(db, async (tx) => {
      const accRef = doc(db, 'workspaces', workspace.id, 'accounts', account.id);
      const accSnap = await tx.get(accRef);
      if (!accSnap.exists()) throw new Error('Счёт не найден');
      const prevBal = Number(accSnap.data().balanceCents || 0);
      const now = serverTimestamp();

      tx.update(accRef, {
        balanceCents: prevBal + delta,
        updatedAt: now,
      });
      tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind,
        category: category.slice(0, 80),
        amountCents: Math.abs(amountCents),
        accountId: account.id,
        accountName: account.name.slice(0, 100),
        note: (note || '').slice(0, 240),
        occurredAt: new Date().toISOString().slice(0, 10),
        createdAt: now,
        updatedAt: now,
      });
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Atomic storno (reversal) honoring original tx kind and guarding against double-storno.
 */
export async function reverseFinancialTransaction(params: {
  workspace: Workspace;
  account: Account;
  originalTx: MoneyTransaction;
  existingTransactions: MoneyTransaction[];
}) {
  const { workspace, account, originalTx, existingTransactions } = params;
  if (originalTx.kind === 'transfer' || originalTx.kind === 'reversal') {
    throw new Error('Эту операцию нельзя сторнировать напрямую');
  }
  if (existingTransactions.some((t) => t.reversesId === originalTx.id)) {
    throw new Error('Эта проводка уже сторнирована');
  }
  const txId = newId('tx');
  const delta = originalTx.kind === 'expense' ? originalTx.amountCents : -originalTx.amountCents;
  const path = `workspaces/${workspace.id}/transactions/${txId}`;
  try {
    await runTransaction(db, async (tx) => {
      const accRef = doc(db, 'workspaces', workspace.id, 'accounts', account.id);
      const accSnap = await tx.get(accRef);
      if (!accSnap.exists()) throw new Error('Счёт не найден');
      const prevBal = Number(accSnap.data().balanceCents || 0);
      const now = serverTimestamp();

      tx.update(accRef, {
        balanceCents: prevBal + delta,
        updatedAt: now,
      });
      tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'reversal',
        category: `Сторно: ${originalTx.category}`.slice(0, 80),
        amountCents: Math.abs(originalTx.amountCents),
        accountId: account.id,
        accountName: account.name.slice(0, 100),
        reversesId: originalTx.id,
        note: `Отмена операции (${originalTx.note || originalTx.category})`.slice(0, 240),
        occurredAt: new Date().toISOString().slice(0, 10),
        createdAt: now,
        updatedAt: now,
      });
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Atomic transfer between two accounts (does not inflate income/expense).
 */
export async function transferBetweenAccounts(params: {
  workspace: Workspace;
  fromAccount: Account;
  toAccount: Account;
  amountCents: number;
  note?: string;
}) {
  const { workspace, fromAccount, toAccount, amountCents, note } = params;
  if (amountCents <= 0 || fromAccount.id === toAccount.id) return;
  const txId = newId('tx');
  const path = `workspaces/${workspace.id}/transactions/${txId}`;
  try {
    await runTransaction(db, async (tx) => {
      const fromRef = doc(db, 'workspaces', workspace.id, 'accounts', fromAccount.id);
      const toRef = doc(db, 'workspaces', workspace.id, 'accounts', toAccount.id);
      const [fromSnap, toSnap] = await Promise.all([tx.get(fromRef), tx.get(toRef)]);
      if (!fromSnap.exists() || !toSnap.exists()) {
        throw new Error('Один из счетов не найден');
      }
      const fromBal = Number(fromSnap.data().balanceCents || 0);
      const toBal = Number(toSnap.data().balanceCents || 0);
      const now = serverTimestamp();

      tx.update(fromRef, {
        balanceCents: fromBal - amountCents,
        updatedAt: now,
      });
      tx.update(toRef, {
        balanceCents: toBal + amountCents,
        updatedAt: now,
      });
      tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'transfer',
        category: `Перевод: ${fromAccount.name} → ${toAccount.name}`.slice(0, 80),
        amountCents,
        accountId: fromAccount.id,
        accountName: `${fromAccount.name} → ${toAccount.name}`.slice(0, 100),
        note: (note || '').slice(0, 240),
        occurredAt: new Date().toISOString().slice(0, 10),
        createdAt: now,
        updatedAt: now,
      });
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Open a POS cash shift.
 */
export async function openCashShift(params: {
  workspace: Workspace;
  locationId?: string;
  locationName: string;
  accountId: string;
  cashierName: string;
  openingCashCents: number;
}): Promise<string> {
  const { workspace, locationId, locationName, accountId, cashierName, openingCashCents } = params;
  const shiftId = newId('shf');
  const payload: Record<string, unknown> = {
    locationName: locationName.slice(0, 120),
    accountId,
    cashierName: cashierName.slice(0, 120),
    openedAt: new Date().toISOString(),
    openingCashCents: Math.max(0, Math.round(openingCashCents)),
    cashSalesCents: 0,
    cardSalesCents: 0,
    refundsCents: 0,
    cashInCents: 0,
    cashOutCents: 0,
    salesCount: 0,
    status: 'open',
  };
  if (locationId) payload.locationId = locationId;
  await createWorkspaceEntity(workspace, 'cashShifts', shiftId, payload);
  return shiftId;
}

/**
 * Close a POS cash shift with Z-report discrepancy.
 */
export async function closeCashShift(params: {
  workspace: Workspace;
  shift: CashShift;
  closingActualCashCents: number;
  closingDiscrepancyCents: number;
}) {
  const { workspace, shift, closingActualCashCents, closingDiscrepancyCents } = params;
  await updateWorkspaceEntity(workspace, 'cashShifts', shift.id, {
    status: 'closed',
    closedAt: new Date().toISOString(),
    closingActualCashCents: Math.round(closingActualCashCents),
    closingDiscrepancyCents: Math.round(closingDiscrepancyCents),
  });
}

/**
 * Complete a POS sale: records PosSale, updates active CashShift, updates Account + MoneyTransaction,
 * deducts finished/inventory stock (FEFO when lots exist, otherwise direct qty decrement), and redeems coupon.
 */
export async function recordPosSale(params: {
  workspace: Workspace;
  shift?: CashShift | null;
  location?: LocationItem | null;
  account: Account;
  cashierName: string;
  paymentMethod: 'cash' | 'card';
  lines: PosSaleLine[];
  subtotalCents: number;
  discountCents: number;
  totalCents: number;
  costCents: number;
  receiptNumber: string;
  client?: Client;
  coupon?: Coupon;
  inventoryItems: InventoryItem[];
  stockLots: StockLot[];
}): Promise<string> {
  const {
    workspace,
    shift,
    location,
    account,
    cashierName,
    paymentMethod,
    lines,
    subtotalCents,
    discountCents,
    totalCents,
    costCents,
    receiptNumber,
    client,
    coupon,
    inventoryItems,
    stockLots,
  } = params;

  // Step 1: Deduct stock for linked inventory items (FEFO if eligible lots exist, else direct decrement)
  let workingLots = stockLots;
  const qtyByItem = new Map<string, number>();
  for (const item of inventoryItems) {
    qtyByItem.set(item.id, item.qtyOnHand);
  }
  for (const line of lines) {
    if (!line.itemId || line.qty <= 0) continue;
    const baseItem = inventoryItems.find((i) => i.id === line.itemId);
    if (!baseItem) continue;
    const currentQty = qtyByItem.get(baseItem.id) ?? baseItem.qtyOnHand;
    const item = { ...baseItem, qtyOnHand: currentQty };
    const today = new Date().toISOString().slice(0, 10);
    const eligibleLots = workingLots.filter(
      (l) =>
        l.itemId === item.id &&
        l.status === 'active' &&
        l.remainingQty > 0 &&
        (!l.expiresAt || l.expiresAt >= today),
    );
    const totalLotAvail = eligibleLots.reduce((s, l) => s + l.remainingQty, 0);
    if (totalLotAvail + 1e-9 >= line.qty) {
      const res = await consumeInventoryFefo({
        workspace,
        item,
        lots: workingLots,
        qtyToConsume: line.qty,
        reason: `Продажа POS ${receiptNumber}`,
      });
      workingLots = res.updatedLots;
      qtyByItem.set(item.id, Math.max(0, Math.round((currentQty - line.qty) * 1000) / 1000));
    } else {
      const nextQty = Math.max(0, Math.round((currentQty - line.qty) * 1000) / 1000);
      qtyByItem.set(item.id, nextQty);
      await updateWorkspaceEntity(workspace, 'inventoryItems', item.id, {
        qtyOnHand: nextQty,
      });
      await createWorkspaceEntity(workspace, 'stockMovements', newId('mov'), {
        kind: 'sale',
        itemId: item.id,
        itemName: item.name.slice(0, 140),
        qty: line.qty,
        unit: item.unit.slice(0, 24),
        totalCents: Math.round(line.qty * line.unitCostCents),
        reason: `Продажа POS ${receiptNumber}`.slice(0, 200),
      });
    }
  }

  // Step 2: Atomic financial + shift + POS sale + coupon write
  const saleId = newId('pos');
  const txId = newId('tx');
  const path = `workspaces/${workspace.id}/posSales/${saleId}`;
  try {
    await runTransaction(db, async (tx) => {
      const accRef = doc(db, 'workspaces', workspace.id, 'accounts', account.id);
      const accSnap = await tx.get(accRef);
      if (!accSnap.exists()) throw new Error('Счёт не найден');

      const shiftRef = shift
        ? doc(db, 'workspaces', workspace.id, 'cashShifts', shift.id)
        : null;
      const shiftSnap = shiftRef ? await tx.get(shiftRef) : null;

      const couponRef = coupon
        ? doc(db, 'workspaces', workspace.id, 'coupons', coupon.id)
        : null;
      const couponSnap = couponRef ? await tx.get(couponRef) : null;

      const now = serverTimestamp();
      const prevBal = Number(accSnap.data().balanceCents || 0);
      if (totalCents > 0) {
        tx.update(accRef, {
          balanceCents: prevBal + totalCents,
          updatedAt: now,
        });
        tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
          workspaceId: workspace.id,
          ownerId: workspace.ownerId,
          kind: 'income',
          category: 'Продажа на кассе',
          amountCents: totalCents,
          accountId: account.id,
          accountName: account.name.slice(0, 100),
          note: `Чек ${receiptNumber}${client ? ` (${client.name})` : ''}`.slice(0, 240),
          occurredAt: new Date().toISOString().slice(0, 10),
          createdAt: now,
          updatedAt: now,
        });
      }

      if (shiftRef && shiftSnap && shiftSnap.exists() && shiftSnap.data().status === 'open') {
        const sData = shiftSnap.data();
        tx.update(shiftRef, {
          cashSalesCents:
            Number(sData.cashSalesCents || 0) + (paymentMethod === 'cash' ? totalCents : 0),
          cardSalesCents:
            Number(sData.cardSalesCents || 0) + (paymentMethod === 'card' ? totalCents : 0),
          salesCount: Number(sData.salesCount || 0) + 1,
          updatedAt: now,
        });
      }

      if (couponRef && couponSnap && couponSnap.exists() && couponSnap.data().status === 'active') {
        tx.update(couponRef, {
          status: 'redeemed',
          redeemedOrderId: saleId,
          updatedAt: now,
        });
      }

      const salePayload: Record<string, unknown> = {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        receiptNumber: receiptNumber.slice(0, 40),
        cashierName: cashierName.slice(0, 120),
        paymentMethod,
        accountId: account.id,
        lines,
        subtotalCents: Math.round(subtotalCents),
        discountCents: Math.round(discountCents),
        totalCents: Math.round(totalCents),
        costCents: Math.round(costCents),
        status: 'completed',
        occurredAt: new Date().toISOString(),
        createdAt: now,
        updatedAt: now,
      };
      const saleLocationId = shift?.locationId || location?.id;
      const saleLocationName = shift?.locationName || location?.name;
      if (shift?.id) salePayload.shiftId = shift.id;
      if (saleLocationId) salePayload.locationId = saleLocationId;
      if (saleLocationName) salePayload.locationName = saleLocationName.slice(0, 120);
      if (client?.id) salePayload.clientId = client.id;
      if (client?.name) salePayload.clientName = client.name.slice(0, 140);
      if (coupon?.code) salePayload.couponCode = coupon.code.slice(0, 40);

      tx.set(doc(db, 'workspaces', workspace.id, 'posSales', saleId), salePayload);
    });
    return saleId;
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
    return saleId;
  }
}

/**
 * Refund a completed POS sale atomically.
 */
export async function refundPosSale(params: {
  workspace: Workspace;
  sale: PosSale;
  account: Account;
  shift?: CashShift | null;
}) {
  const { workspace, sale, account, shift } = params;
  if (sale.status === 'refunded') return;
  const txId = newId('tx');
  const path = `workspaces/${workspace.id}/posSales/${sale.id}`;
  try {
    await runTransaction(db, async (tx) => {
      const saleRef = doc(db, 'workspaces', workspace.id, 'posSales', sale.id);
      const accRef = doc(db, 'workspaces', workspace.id, 'accounts', account.id);
      const [saleSnap, accSnap] = await Promise.all([tx.get(saleRef), tx.get(accRef)]);
      if (!saleSnap.exists() || saleSnap.data().status === 'refunded') return;
      if (!accSnap.exists()) throw new Error('Счёт не найден');

      const shiftRef = shift
        ? doc(db, 'workspaces', workspace.id, 'cashShifts', shift.id)
        : null;
      const shiftSnap = shiftRef ? await tx.get(shiftRef) : null;

      const now = serverTimestamp();
      tx.update(saleRef, {
        status: 'refunded',
        updatedAt: now,
      });
      if (sale.totalCents > 0) {
        tx.update(accRef, {
          balanceCents: Number(accSnap.data().balanceCents || 0) - sale.totalCents,
          updatedAt: now,
        });
        tx.set(doc(db, 'workspaces', workspace.id, 'transactions', txId), {
          workspaceId: workspace.id,
          ownerId: workspace.ownerId,
          kind: 'expense',
          category: 'Возврат по чеку',
          amountCents: sale.totalCents,
          accountId: account.id,
          accountName: account.name.slice(0, 100),
          note: `Возврат чека ${sale.receiptNumber}`.slice(0, 240),
          occurredAt: new Date().toISOString().slice(0, 10),
          createdAt: now,
          updatedAt: now,
        });
      }
      if (
        sale.paymentMethod === 'cash' &&
        shiftRef &&
        shiftSnap &&
        shiftSnap.exists() &&
        shiftSnap.data().status === 'open'
      ) {
        tx.update(shiftRef, {
          refundsCents: Number(shiftSnap.data().refundsCents || 0) + sale.totalCents,
          updatedAt: now,
        });
      }
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Create a single-use employee invitation in top-level /invitations collection.
 */
export async function createWorkspaceInvitation(params: {
  workspace: Workspace;
  email: string;
  invitedByName: string;
  role: Exclude<UserRole, 'owner'>;
  payType: PayType;
  rateCents?: number;
  percent?: number;
}): Promise<string> {
  const { workspace, email, invitedByName, role, payType, rateCents, percent } = params;
  const inviteId = newId('inv');
  const cleanEmail = email.trim().toLowerCase().slice(0, 200);
  const path = `invitations/${inviteId}`;
  try {
    await setDoc(doc(db, 'invitations', inviteId), {
      workspaceId: workspace.id,
      workspaceName: workspace.name.slice(0, 120),
      ownerId: workspace.ownerId,
      email: cleanEmail,
      invitedByName: (invitedByName || 'Владелец').slice(0, 120),
      role,
      payType,
      rateCents: Math.max(0, Math.round(rateCents || 0)),
      percent: Math.max(0, Number(percent || 0)),
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    return inviteId;
  } catch (err) {
    handleFirestoreError(err, OperationType.CREATE, path);
    return inviteId;
  }
}

export async function revokeWorkspaceInvitation(inviteId: string) {
  const path = `invitations/${inviteId}`;
  try {
    await updateDoc(doc(db, 'invitations', inviteId), {
      status: 'revoked',
      updatedAt: serverTimestamp(),
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.UPDATE, path);
  }
}

/**
 * Atomically accept an invitation: creates /workspaces/{wsId}/members/{uid},
 * appends uid to workspace.memberUids, marks invitation accepted, and sets activeWorkspaceId.
 */
export async function acceptWorkspaceInvitation(params: {
  invitation: WorkspaceInvitation;
  userUid: string;
  userName: string;
  userEmail: string;
}) {
  const { invitation, userUid, userName, userEmail } = params;
  const path = `invitations/${invitation.id}`;
  try {
    const batch = writeBatch(db);
    const now = serverTimestamp();

    const memberRef = doc(db, 'workspaces', invitation.workspaceId, 'members', userUid);
    const memberPayload: Record<string, unknown> = {
      workspaceId: invitation.workspaceId,
      ownerId: invitation.ownerId,
      uid: userUid,
      inviteId: invitation.id,
      name: (userName || userEmail || 'Сотрудник').slice(0, 120),
      email: userEmail.trim().toLowerCase().slice(0, 200),
      role: invitation.role,
      payType: invitation.payType,
      rateCents: invitation.rateCents || 0,
      percent: invitation.percent || 0,
      active: true,
      createdAt: now,
      updatedAt: now,
    };
    if (invitation.allowedRecipeIds) memberPayload.allowedRecipeIds = invitation.allowedRecipeIds;
    if (invitation.locationId) memberPayload.locationId = invitation.locationId;

    batch.set(memberRef, memberPayload);
    batch.update(doc(db, 'workspaces', invitation.workspaceId), {
      memberUids: arrayUnion(userUid),
      updatedAt: now,
    });
    batch.update(doc(db, 'invitations', invitation.id), {
      status: 'accepted',
      acceptedByUid: userUid,
      updatedAt: now,
    });
    batch.set(
      doc(db, 'users', userUid),
      {
        uid: userUid,
        displayName: (userName || userEmail || 'Сотрудник').slice(0, 120),
        email: userEmail.trim().toLowerCase().slice(0, 200),
        activeWorkspaceId: invitation.workspaceId,
        createdAt: now,
        updatedAt: now,
      },
      { merge: true },
    );

    await batch.commit();
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Record SaaS subscription payment & extend workspace period using subscription.ts.
 */
export async function recordSubscriptionPayment(params: {
  workspace: Workspace;
  months?: number;
  provider?: string;
}) {
  const { workspace, months = 1, provider = 'manual_pilot' } = params;
  const eventId = newId('bil');
  const { currentPeriodEnd, graceEndsAt } = computeNextBillingDates(
    workspace.currentPeriodEnd,
    months,
  );
  const amountCents = SUBSCRIPTION_PRICE_CENTS * Math.max(1, months);
  const path = `workspaces/${workspace.id}/billingEvents/${eventId}`;

  try {
    const batch = writeBatch(db);
    const now = serverTimestamp();
    batch.set(doc(db, 'workspaces', workspace.id, 'billingEvents', eventId), {
      workspaceId: workspace.id,
      ownerId: workspace.ownerId,
      idempotencyKey: eventId,
      plan: 'pro',
      amountCents,
      periodMonths: Math.max(1, months),
      status: 'paid',
      provider: provider.slice(0, 60),
      occurredAt: new Date().toISOString().slice(0, 10),
      createdAt: now,
      updatedAt: now,
    });
    batch.update(doc(db, 'workspaces', workspace.id), {
      plan: 'pro',
      subscriptionStatus: 'active',
      currentPeriodEnd,
      graceEndsAt,
      lastPaymentId: eventId,
      updatedAt: now,
    });
    await batch.commit();
    return { currentPeriodEnd, graceEndsAt, amountCents };
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
    return { currentPeriodEnd, graceEndsAt, amountCents };
  }
}

/**
 * Send stock (raw, semi-finished, packaging, or finished goods) from one location to another.
 * Atomically deducts source inventory & lot and creates an `in_transit` StockTransfer record.
 */
export async function createStockTransfer(params: {
  workspace: Workspace;
  sourceItem: InventoryItem;
  sourceLot?: StockLot;
  fromLocation: LocationItem;
  toLocation: LocationItem;
  qty: number;
  note?: string;
}): Promise<string> {
  const { workspace, sourceItem, sourceLot, fromLocation, toLocation, qty, note } = params;
  const cleanQty = Math.round(qty * 1000) / 1000;
  if (cleanQty <= 0) {
    throw new Error('Укажите положительное количество для перемещения');
  }
  if (fromLocation.id === toLocation.id) {
    throw new Error('Точка отправления и точка назначения должны отличаться');
  }

  const transferId = newId('trf');
  const movId = newId('mov');
  const path = `workspaces/${workspace.id}/stockTransfers/${transferId}`;

  try {
    await runTransaction(db, async (tx) => {
      const itemRef = doc(db, 'workspaces', workspace.id, 'inventoryItems', sourceItem.id);
      const lotRef = sourceLot
        ? doc(db, 'workspaces', workspace.id, 'stockLots', sourceLot.id)
        : null;

      const [itemSnap, lotSnap] = await Promise.all([
        tx.get(itemRef),
        lotRef ? tx.get(lotRef) : Promise.resolve(null),
      ]);
      if (!itemSnap.exists()) {
        throw new Error('Позиция склада не найдена');
      }

      const curItemQty = Number(itemSnap.data().qtyOnHand || 0);
      if (curItemQty + 1e-9 < cleanQty) {
        throw new Error(`Недостаточно остатка «${sourceItem.name}» (доступно ${curItemQty} ${sourceItem.unit})`);
      }

      let unitCostCents = Math.max(0, Math.round(Number(itemSnap.data().avgCostCents || 0)));
      const now = serverTimestamp();

      if (lotRef && lotSnap && lotSnap.exists()) {
        const curLotQty = Number(lotSnap.data().remainingQty || 0);
        if (curLotQty + 1e-9 < cleanQty) {
          throw new Error(
            `В выбранной партии ${sourceLot?.lotCode || ''} недостаточно остатка (${curLotQty} ${sourceItem.unit})`,
          );
        }
        unitCostCents = Math.max(0, Math.round(Number(lotSnap.data().unitCostCents || unitCostCents)));
        const nextLotQty = Math.max(0, Math.round((curLotQty - cleanQty) * 1000) / 1000);
        tx.update(lotRef, {
          remainingQty: nextLotQty,
          status: nextLotQty <= 0 ? 'depleted' : 'active',
          updatedAt: now,
        });
      }

      const nextItemQty = Math.max(0, Math.round((curItemQty - cleanQty) * 1000) / 1000);
      tx.update(itemRef, {
        qtyOnHand: nextItemQty,
        updatedAt: now,
      });

      const transferPayload: Record<string, unknown> = {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        itemId: sourceItem.id,
        itemName: sourceItem.name.slice(0, 140),
        fromLocationId: fromLocation.id,
        fromLocationName: fromLocation.name.slice(0, 120),
        toLocationId: toLocation.id,
        toLocationName: toLocation.name.slice(0, 120),
        qty: cleanQty,
        unit: sourceItem.unit.slice(0, 24),
        unitCostCents,
        status: 'in_transit',
        sentAt: new Date().toISOString(),
        createdAt: now,
        updatedAt: now,
      };
      if (sourceLot?.id) transferPayload.lotId = sourceLot.id;
      if (note && note.trim()) transferPayload.note = note.trim().slice(0, 200);

      tx.set(doc(db, 'workspaces', workspace.id, 'stockTransfers', transferId), transferPayload);

      const movPayload: Record<string, unknown> = {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'transfer',
        itemId: sourceItem.id,
        itemName: sourceItem.name.slice(0, 140),
        qty: cleanQty,
        unit: sourceItem.unit.slice(0, 24),
        totalCents: Math.round(cleanQty * unitCostCents),
        reason: `Отправка: ${fromLocation.name} → ${toLocation.name}`.slice(0, 200),
        createdAt: now,
        updatedAt: now,
      };
      if (sourceLot?.id) movPayload.lotId = sourceLot.id;
      tx.set(doc(db, 'workspaces', workspace.id, 'stockMovements', movId), movPayload);
    });
    return transferId;
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
    return transferId;
  }
}

/**
 * Accept an `in_transit` StockTransfer at the destination location.
 * Creates/updates InventoryItem & StockLot at `toLocationId` and marks transfer `received`.
 */
export async function receiveStockTransfer(params: {
  workspace: Workspace;
  transfer: StockTransfer;
  inventoryItems: InventoryItem[];
  stockLots: StockLot[];
}) {
  const { workspace, transfer, inventoryItems, stockLots } = params;
  if (transfer.status !== 'in_transit') return;

  const sourceItem = inventoryItems.find((i) => i.id === transfer.itemId);
  const sourceLot = transfer.lotId
    ? stockLots.find((l) => l.id === transfer.lotId)
    : undefined;

  const destExisting = inventoryItems.find(
    (i) =>
      i.name.trim().toLowerCase() === transfer.itemName.trim().toLowerCase() &&
      i.unit.trim().toLowerCase() === transfer.unit.trim().toLowerCase() &&
      (transfer.toLocationId ? i.locationId === transfer.toLocationId : !i.locationId),
  );

  const destItemId = destExisting?.id || newId('inv');
  const destLotId = newId('lot');
  const movId = newId('mov');
  const totalCents = Math.round(transfer.qty * transfer.unitCostCents);
  const path = `workspaces/${workspace.id}/stockTransfers/${transfer.id}`;

  try {
    await runTransaction(db, async (tx) => {
      const trfRef = doc(db, 'workspaces', workspace.id, 'stockTransfers', transfer.id);
      const destItemRef = doc(db, 'workspaces', workspace.id, 'inventoryItems', destItemId);
      const [trfSnap, destSnap] = await Promise.all([
        tx.get(trfRef),
        destExisting ? tx.get(destItemRef) : Promise.resolve(null),
      ]);
      if (!trfSnap.exists() || trfSnap.data().status !== 'in_transit') {
        throw new Error('Перемещение уже обработано');
      }

      const now = serverTimestamp();

      if (destSnap && destSnap.exists()) {
        const curQty = Number(destSnap.data().qtyOnHand || 0);
        const curAvg = Number(destSnap.data().avgCostCents || 0);
        const nextQty = Math.round((curQty + transfer.qty) * 1000) / 1000;
        const nextAvg =
          nextQty > 0
            ? Math.round((curQty * curAvg + totalCents) / nextQty)
            : transfer.unitCostCents;
        tx.update(destItemRef, {
          qtyOnHand: nextQty,
          avgCostCents: nextAvg,
          updatedAt: now,
        });
      } else {
        const itemPayload: Record<string, unknown> = {
          workspaceId: workspace.id,
          ownerId: workspace.ownerId,
          name: transfer.itemName.slice(0, 140),
          kind: sourceItem?.kind || 'finished',
          category: (sourceItem?.category || 'Перемещение').slice(0, 80),
          unit: transfer.unit.slice(0, 24),
          qtyOnHand: transfer.qty,
          minQty: sourceItem?.minQty ?? 1,
          avgCostCents: transfer.unitCostCents,
          createdAt: now,
          updatedAt: now,
        };
        if (sourceItem?.density && sourceItem.density > 0) {
          itemPayload.density = sourceItem.density;
        }
        if (transfer.toLocationId) {
          itemPayload.locationId = transfer.toLocationId;
        }
        tx.set(destItemRef, itemPayload);
      }

      const lotPayload: Record<string, unknown> = {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        itemId: destItemId,
        itemName: transfer.itemName.slice(0, 140),
        lotCode: `ТР-${new Date().toISOString().slice(5, 10).replace('-', '')}`,
        unit: transfer.unit.slice(0, 24),
        initialQty: transfer.qty,
        remainingQty: transfer.qty,
        unitCostCents: transfer.unitCostCents,
        expiresAt:
          sourceLot?.expiresAt ||
          new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      };
      if (transfer.toLocationId) lotPayload.locationId = transfer.toLocationId;
      tx.set(doc(db, 'workspaces', workspace.id, 'stockLots', destLotId), lotPayload);

      tx.set(doc(db, 'workspaces', workspace.id, 'stockMovements', movId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'transfer',
        itemId: destItemId,
        itemName: transfer.itemName.slice(0, 140),
        lotId: destLotId,
        qty: transfer.qty,
        unit: transfer.unit.slice(0, 24),
        totalCents,
        reason: `Приёмка: ${transfer.fromLocationName} → ${transfer.toLocationName}`.slice(0, 200),
        createdAt: now,
        updatedAt: now,
      });

      tx.update(trfRef, {
        status: 'received',
        receivedAt: new Date().toISOString(),
        updatedAt: now,
      });
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

/**
 * Cancel an `in_transit` StockTransfer and return quantity back to the source location.
 */
export async function cancelStockTransfer(params: {
  workspace: Workspace;
  transfer: StockTransfer;
  note?: string;
}) {
  const { workspace, transfer, note } = params;
  if (transfer.status !== 'in_transit') return;

  const movId = newId('mov');
  const path = `workspaces/${workspace.id}/stockTransfers/${transfer.id}`;

  try {
    await runTransaction(db, async (tx) => {
      const trfRef = doc(db, 'workspaces', workspace.id, 'stockTransfers', transfer.id);
      const itemRef = doc(db, 'workspaces', workspace.id, 'inventoryItems', transfer.itemId);
      const lotRef = transfer.lotId
        ? doc(db, 'workspaces', workspace.id, 'stockLots', transfer.lotId)
        : null;

      const [trfSnap, itemSnap, lotSnap] = await Promise.all([
        tx.get(trfRef),
        tx.get(itemRef),
        lotRef ? tx.get(lotRef) : Promise.resolve(null),
      ]);
      if (!trfSnap.exists() || trfSnap.data().status !== 'in_transit') {
        throw new Error('Перемещение уже обработано');
      }

      const now = serverTimestamp();

      if (itemSnap.exists()) {
        const curQty = Number(itemSnap.data().qtyOnHand || 0);
        tx.update(itemRef, {
          qtyOnHand: Math.round((curQty + transfer.qty) * 1000) / 1000,
          updatedAt: now,
        });
      }
      if (lotRef && lotSnap && lotSnap.exists()) {
        const curLotQty = Number(lotSnap.data().remainingQty || 0);
        tx.update(lotRef, {
          remainingQty: Math.round((curLotQty + transfer.qty) * 1000) / 1000,
          status: 'active',
          updatedAt: now,
        });
      }

      tx.set(doc(db, 'workspaces', workspace.id, 'stockMovements', movId), {
        workspaceId: workspace.id,
        ownerId: workspace.ownerId,
        kind: 'transfer',
        itemId: transfer.itemId,
        itemName: transfer.itemName.slice(0, 140),
        ...(transfer.lotId ? { lotId: transfer.lotId } : {}),
        qty: transfer.qty,
        unit: transfer.unit.slice(0, 24),
        totalCents: Math.round(transfer.qty * transfer.unitCostCents),
        reason: `Возврат отменённого перемещения на ${transfer.fromLocationName}`.slice(0, 200),
        createdAt: now,
        updatedAt: now,
      });

      const trfPatch: Record<string, unknown> = {
        status: 'cancelled',
        updatedAt: now,
      };
      if (note && note.trim()) trfPatch.note = note.trim().slice(0, 200);
      tx.update(trfRef, trfPatch);
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, path);
  }
}

