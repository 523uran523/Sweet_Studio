import {
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
import {
  Account,
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
  ProductionRun,
  Purchase,
  Recipe,
  RecurringPayment,
  StockLot,
  StockMovement,
  Supplier,
  TimeEntry,
  WorkItem,
  Workspace,
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
        priceCents,
        costCents: Math.round(priceCents * 0.52),
        prepaymentCents: Math.round(priceCents * 0.5),
        paidCents: 0,
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
  } = params;
  const matched =
    (existingItemId ? items.find((i) => i.id === existingItemId) : undefined) ||
    items.find(
      (i) =>
        i.name.trim().toLowerCase() === name.trim().toLowerCase() &&
        i.unit.trim().toLowerCase() === unit.trim().toLowerCase(),
    );

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
        tx.set(itemRef, {
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
        });
      }

      tx.set(doc(db, 'workspaces', workspace.id, 'stockLots', lotId), {
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
      });

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
