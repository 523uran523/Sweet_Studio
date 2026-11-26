import React, { useMemo, useState } from 'react';
import { History, Pencil, RefreshCw, Scale, Trash2 } from 'lucide-react';
import {
  Card,
  Drawer,
  EmptyState,
  PageHeader,
  SegmentedTabs,
} from '../components/UiPrimitives';
import {
  computeCalculatorTotals,
  effectiveQuantity,
  resourceLineTotalCents,
} from '../core/calculatorCore';
import { centsToRubInput, formatMoneyCents, parseRubToCents } from '../core/moneyFormat';
import { convertQtyWithDensity, formatQty, QTY_UNITS } from '../core/units';
import {
  consumeInventoryFefo,
  createWorkspaceEntity,
  newId,
  paySupplierDebt,
  receivePurchaseOrder,
  updateWorkspaceEntity,
  upsertInventoryReceipt,
  WorkspaceSnapshot,
  writeOffStockLot,
} from '../firebase/workspaceService';
import {
  InventoryItem,
  ProductionRun,
  Purchase,
  Recipe,
  RecipeIngredientLine,
  StockLot,
  Supplier,
  Workspace,
} from '../types/domain';

function expectedIngredientPriceCents(
  item: InventoryItem,
  priceUnit: string,
): number | null {
  const is100g = priceUnit === 'за 100 г';
  const targetUnit = is100g ? 'г' : priceUnit.replace(/^за\s+/, '').trim();
  const baseQty = is100g ? 100 : 1;
  const qtyInItemUnit = convertQtyWithDensity(
    baseQty,
    targetUnit,
    item.unit,
    item.density,
  );
  if (qtyInItemUnit === null || qtyInItemUnit <= 0) return null;
  return Math.round(item.avgCostCents * qtyInItemUnit);
}

function formatMovementDate(raw: unknown): string {
  if (!raw) return '—';
  if (typeof raw === 'string') return raw.slice(0, 10);
  if (
    typeof raw === 'object' &&
    raw !== null &&
    'toDate' in raw &&
    typeof (raw as { toDate: () => Date }).toDate === 'function'
  ) {
    return (raw as { toDate: () => Date }).toDate().toISOString().slice(0, 10);
  }
  return '—';
}

export function InventoryPage({
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
  const todayIso = useMemo(() => new Date().toISOString().slice(0, 10), []);
  const [tab, setTab] = useState<'items' | 'lots' | 'movements' | 'purchases'>('items');
  const [itemDrawer, setItemDrawer] = useState(false);
  const [consumeTarget, setConsumeTarget] = useState<InventoryItem | null>(null);
  const [consumeQty, setConsumeQty] = useState('0.5');
  const [consumeReason, setConsumeReason] = useState('Списание в производство');

  // Edit Item state
  const [editItem, setEditItem] = useState<InventoryItem | null>(null);
  const [editName, setEditName] = useState('');
  const [editCategory, setEditCategory] = useState('');
  const [editMinQty, setEditMinQty] = useState('1');
  const [editDensity, setEditDensity] = useState('');

  // Stocktake (Инвентаризация) state
  const [stocktakeItem, setStocktakeItem] = useState<InventoryItem | null>(null);
  const [stocktakeActualQty, setStocktakeActualQty] = useState('0');
  const [stocktakeReason, setStocktakeReason] = useState('Плановая инвентаризация');
  const [stocktakeBusy, setStocktakeBusy] = useState(false);

  // Price history drawer
  const [historyItem, setHistoryItem] = useState<InventoryItem | null>(null);

  // Bulk recipe price sync drawer
  const [syncDrawerOpen, setSyncDrawerOpen] = useState(false);
  const [syncBusy, setSyncBusy] = useState(false);

  // Lot write-off (spoilage/expired/quarantine)
  const [writeOffLot, setWriteOffLot] = useState<StockLot | null>(null);
  const [writeOffQty, setWriteOffQty] = useState('0');
  const [writeOffReason, setWriteOffReason] = useState('Брак / истечение срока годности');

  const [newName, setNewName] = useState('');
  const [newKind, setNewKind] = useState<InventoryItem['kind']>('raw');
  const [newUnit, setNewUnit] = useState('кг');
  const [newQty, setNewQty] = useState('1');
  const [newCostRub, setNewCostRub] = useState('800');
  const [newDensity, setNewDensity] = useState('');
  const [newExpires, setNewExpires] = useState(
    new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10),
  );

  const [supplierDrawer, setSupplierDrawer] = useState(false);
  const [supName, setSupName] = useState('');
  const [supContact, setSupContact] = useState('');
  const [supPhone, setSupPhone] = useState('');
  const [supCategory, setSupCategory] = useState('Сырьё и упаковка');

  // Pay supplier debt
  const [payDebtSupplier, setPayDebtSupplier] = useState<Supplier | null>(null);
  const [payDebtAccountId, setPayDebtAccountId] = useState(data.accounts[0]?.id || '');
  const [payDebtRub, setPayDebtRub] = useState('');

  // Receive Purchase modal
  const [receiveTarget, setReceiveTarget] = useState<Purchase | null>(null);
  const [receiveExpires, setReceiveExpires] = useState(
    new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10),
  );
  const [receivePaymentMode, setReceivePaymentMode] = useState<'paid' | 'debt' | 'none'>('paid');
  const [receiveAccountId, setReceiveAccountId] = useState(data.accounts[0]?.id || '');
  const [receiveBusy, setReceiveBusy] = useState(false);

  const [purchaseDrawer, setPurchaseDrawer] = useState(false);
  const [purSupplierId, setPurSupplierId] = useState(data.suppliers[0]?.id || '');
  const [purItemId, setPurItemId] = useState('');
  const [purItemName, setPurItemName] = useState('');
  const [purQty, setPurQty] = useState('2');
  const [purUnit, setPurUnit] = useState('кг');
  const [purPriceRub, setPurPriceRub] = useState('1800');
  const [purDeliveryRub, setPurDeliveryRub] = useState('0');
  const [purExpectedDate, setPurExpectedDate] = useState(
    new Date(Date.now() + 2 * 86400000).toISOString().slice(0, 10),
  );

  const [importDrawer, setImportDrawer] = useState(false);
  const [importCsvText, setImportCsvText] = useState(
    'Наименование;Тип;Единица;Количество;Цена;Срок\nМасло сливочное 82.5%;raw;кг;3;1150;2026-12-15\nКоробка 24x24;packaging;шт;25;120;',
  );
  const [importingCsv, setImportingCsv] = useState(false);

  const recipePriceSyncPreview = useMemo(() => {
    const updates: Array<{
      recipe: Recipe;
      nextIngredients: RecipeIngredientLine[];
      oldCostCents: number;
      newCostCents: number;
      changedLines: number;
    }> = [];

    for (const rec of data.recipes) {
      if (!rec.ingredients || rec.ingredients.length === 0) continue;
      let changedLines = 0;
      const nextIngredients = rec.ingredients.map((ing) => {
        if (ing.subRecipeId) return ing;
        const matched = ing.itemId
          ? data.inventoryItems.find((i) => i.id === ing.itemId)
          : data.inventoryItems.find(
              (i) => i.name.trim().toLowerCase() === ing.name.trim().toLowerCase(),
            );
        if (!matched) return ing;
        const expected = expectedIngredientPriceCents(matched, ing.priceUnit);
        if (expected === null || Math.abs(expected - ing.priceCents) < 2) {
          return ing;
        }
        changedLines += 1;
        return { ...ing, itemId: matched.id, priceCents: expected };
      });

      if (changedLines === 0) continue;

      const materialsCents = nextIngredients.reduce((sum, r) => {
        const eff = effectiveQuantity(r.qty, r.lossPercent) ?? r.qty;
        return (
          sum +
          resourceLineTotalCents({
            qty: eff,
            qtyUnit: r.unit,
            priceCents: r.priceCents,
            priceUnit: r.priceUnit,
          })
        );
      }, 0);
      const totals = computeCalculatorTotals({
        materialsCents,
        laborHours: rec.laborHours ?? 0,
        laborRateCents: rec.laborRateCents ?? 0,
        otherCents: 0,
        overheadPercent: rec.overheadPercent ?? 0,
        marginPercent: rec.marginPercent ?? 50,
        pricingMode: 'markup',
        packagingCents: rec.packagingCents ?? 0,
      });

      updates.push({
        recipe: rec,
        nextIngredients,
        oldCostCents: rec.costCents,
        newCostCents: totals.costCents,
        changedLines,
      });
    }
    return updates;
  }, [data.recipes, data.inventoryItems]);

  const handleApplyRecipePriceSync = async () => {
    if (recipePriceSyncPreview.length === 0 || syncBusy) return;
    setSyncBusy(true);
    try {
      for (const u of recipePriceSyncPreview) {
        await updateWorkspaceEntity(workspace, 'recipes', u.recipe.id, {
          ingredients: u.nextIngredients,
          costCents: Math.max(0, u.newCostCents),
        });
      }
      setSyncDrawerOpen(false);
      onToast(`Цены обновлены в техкартах: ${recipePriceSyncPreview.length}`);
    } finally {
      setSyncBusy(false);
    }
  };

  const importPreview = useMemo(() => {
    const lines = importCsvText
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter(Boolean);
    if (lines.length === 0) return { rows: [], errors: 0 };
    const existingNames = new Set(
      data.inventoryItems.map((i) => i.name.trim().toLowerCase()),
    );
    const rows: Array<{
      name: string;
      kind: InventoryItem['kind'];
      unit: string;
      qty: number;
      priceCents: number;
      expiresAt: string;
      duplicate: boolean;
      valid: boolean;
      error?: string;
    }> = [];
    let errors = 0;

    for (let idx = 0; idx < lines.length; idx++) {
      const sep = lines[idx].includes(';') ? ';' : ',';
      const cols = lines[idx].split(sep).map((c) => c.trim().replace(/^"|"$/g, ''));
      if (idx === 0 && /наименован|назван|name/i.test(cols[0] || '')) {
        continue;
      }
      const nameVal = (cols[0] || '').slice(0, 140);
      const kindRaw = (cols[1] || 'raw').toLowerCase();
      const kindVal: InventoryItem['kind'] =
        kindRaw === 'semi' || kindRaw === 'полуфабрикат'
          ? 'semi'
          : kindRaw === 'finished' || kindRaw === 'готовое'
            ? 'finished'
            : kindRaw === 'packaging' || kindRaw === 'упаковка'
              ? 'packaging'
              : 'raw';
      const unitVal = cols[2] || 'кг';
      const qtyVal = Number((cols[3] || '0').replace(',', '.'));
      const priceCents = parseRubToCents(cols[4] || '0');
      const expiresAt =
        cols[5] ||
        new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10);
      const validQty = Number.isFinite(qtyVal) && qtyVal >= 0;
      const validUnit = QTY_UNITS.includes(unitVal as (typeof QTY_UNITS)[number]);
      const duplicate = existingNames.has(nameVal.toLowerCase());
      const valid = Boolean(nameVal) && validQty && validUnit;
      if (!valid) errors += 1;
      rows.push({
        name: nameVal || '—',
        kind: kindVal,
        unit: unitVal,
        qty: validQty ? qtyVal : 0,
        priceCents,
        expiresAt,
        duplicate,
        valid,
        error: !nameVal
          ? 'Пустое название'
          : !validUnit
            ? `Неизвестная ед. (${unitVal})`
            : !validQty
              ? 'Неверное количество'
              : undefined,
      });
    }
    return { rows, errors };
  }, [importCsvText, data.inventoryItems]);

  const handleRunCsvImport = async () => {
    const ready = importPreview.rows.filter((r) => r.valid && !r.duplicate);
    if (ready.length === 0 || importingCsv) return;
    setImportingCsv(true);
    try {
      for (const r of ready) {
        const itemId = newId('inv');
        await createWorkspaceEntity(workspace, 'inventoryItems', itemId, {
          name: r.name,
          kind: r.kind,
          category:
            r.kind === 'semi'
              ? 'Полуфабрикаты'
              : r.kind === 'packaging'
                ? 'Упаковка'
                : 'Сырьё',
          unit: r.unit,
          qtyOnHand: r.qty,
          minQty: 1,
          avgCostCents: r.priceCents,
        });
        if (r.qty > 0) {
          const lotId = newId('lot');
          await createWorkspaceEntity(workspace, 'stockLots', lotId, {
            itemId,
            itemName: r.name,
            lotCode: `И-${Date.now().toString().slice(-4)}`,
            unit: r.unit,
            initialQty: r.qty,
            remainingQty: r.qty,
            unitCostCents: r.priceCents,
            expiresAt: r.expiresAt,
            status: 'active',
          });
          await createWorkspaceEntity(workspace, 'stockMovements', newId('mov'), {
            kind: 'receipt',
            itemId,
            itemName: r.name,
            lotId,
            qty: r.qty,
            unit: r.unit,
            totalCents: Math.round(r.qty * r.priceCents),
            reason: 'Импорт CSV',
          });
        }
      }
      setImportDrawer(false);
      onToast(`Импортировано позиций: ${ready.length}`);
    } finally {
      setImportingCsv(false);
    }
  };

  const sortedLots = useMemo(
    () =>
      [...data.stockLots].sort((a, b) =>
        (a.expiresAt || '9999-12-31').localeCompare(b.expiresAt || '9999-12-31'),
      ),
    [data.stockLots],
  );

  const historyMovements = useMemo(() => {
    if (!historyItem) return [];
    return data.stockMovements.filter(
      (m) => m.itemId === historyItem.id && (m.kind === 'receipt' || m.kind === 'production_in'),
    );
  }, [data.stockMovements, historyItem]);

  const handleAddItem = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newName.trim()) return;
    const itemId = newId('inv');
    const qty = Math.max(0, Number(newQty.replace(',', '.')) || 0);
    const unitCostCents = parseRubToCents(newCostRub);
    const dens = Number(newDensity.replace(',', '.'));

    const payload: Record<string, unknown> = {
      name: newName.trim().slice(0, 140),
      kind: newKind,
      category:
        newKind === 'semi'
          ? 'Полуфабрикаты'
          : newKind === 'packaging'
            ? 'Упаковка'
            : newKind === 'finished'
              ? 'Готовое'
              : 'Сырьё',
      unit: newUnit,
      qtyOnHand: qty,
      minQty: 1,
      avgCostCents: unitCostCents,
    };
    if (Number.isFinite(dens) && dens > 0) payload.density = dens;

    await createWorkspaceEntity(workspace, 'inventoryItems', itemId, payload);
    if (qty > 0) {
      const lotId = newId('lot');
      await createWorkspaceEntity(workspace, 'stockLots', lotId, {
        itemId,
        itemName: newName.trim().slice(0, 140),
        lotCode: `П-${Date.now().toString().slice(-4)}`,
        unit: newUnit,
        initialQty: qty,
        remainingQty: qty,
        unitCostCents,
        expiresAt: newExpires,
        status: 'active',
      });
      await createWorkspaceEntity(workspace, 'stockMovements', newId('mov'), {
        kind: 'receipt',
        itemId,
        itemName: newName.trim().slice(0, 140),
        lotId,
        qty,
        unit: newUnit,
        totalCents: Math.round(qty * unitCostCents),
        reason: 'Начальный приход',
      });
    }
    setNewName('');
    setNewDensity('');
    setItemDrawer(false);
    onToast('Позиция и партия добавлены на склад');
  };

  const openEditItem = (item: InventoryItem) => {
    setEditItem(item);
    setEditName(item.name);
    setEditCategory(item.category || '');
    setEditMinQty(String(item.minQty ?? 1));
    setEditDensity(item.density ? String(item.density) : '');
  };

  const handleSaveEditItem = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editItem || !editName.trim()) return;
    const minVal = Math.max(0, Number(editMinQty.replace(',', '.')) || 0);
    const densVal = Number(editDensity.replace(',', '.'));
    const patch: Record<string, unknown> = {
      name: editName.trim().slice(0, 140),
      category: (editCategory.trim() || 'Сырьё').slice(0, 80),
      minQty: minVal,
    };
    if (Number.isFinite(densVal) && densVal > 0) {
      patch.density = densVal;
    }
    await updateWorkspaceEntity(workspace, 'inventoryItems', editItem.id, patch);
    setEditItem(null);
    onToast('Параметры позиции обновлены');
  };

  const openStocktake = (item: InventoryItem) => {
    setStocktakeItem(item);
    setStocktakeActualQty(String(item.qtyOnHand));
    setStocktakeReason('Инвентаризация склада');
  };

  const handleApplyStocktake = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!stocktakeItem || stocktakeBusy) return;
    const actual = Math.max(0, Math.round((Number(stocktakeActualQty.replace(',', '.')) || 0) * 1000) / 1000);
    const delta = Math.round((actual - stocktakeItem.qtyOnHand) * 1000) / 1000;
    if (Math.abs(delta) < 0.0005) {
      setStocktakeItem(null);
      onToast('Фактический остаток совпадает с учётным');
      return;
    }
    setStocktakeBusy(true);
    try {
      if (delta > 0) {
        await upsertInventoryReceipt({
          workspace,
          items: data.inventoryItems,
          existingItemId: stocktakeItem.id,
          name: stocktakeItem.name,
          kind: stocktakeItem.kind,
          category: stocktakeItem.category,
          unit: stocktakeItem.unit,
          qty: delta,
          totalCostCents: Math.round(delta * stocktakeItem.avgCostCents),
          reason: stocktakeReason.trim() || 'Излишек по инвентаризации',
          movementKind: 'adjustment',
        });
      } else {
        let toDeduct = Math.abs(delta);
        const activeLots = data.stockLots
          .filter((l) => l.itemId === stocktakeItem.id && l.remainingQty > 0 && l.status !== 'depleted')
          .sort((a, b) => (a.expiresAt || '9999-12-31').localeCompare(b.expiresAt || '9999-12-31'));

        let remainingItemQty = stocktakeItem.qtyOnHand;
        for (const lot of activeLots) {
          if (toDeduct <= 0) break;
          const take = Math.min(lot.remainingQty, toDeduct);
          await writeOffStockLot({
            workspace,
            lot,
            item: { ...stocktakeItem, qtyOnHand: remainingItemQty },
            qty: take,
            kind: 'adjustment',
            reason: stocktakeReason.trim() || 'Недостача по инвентаризации',
          });
          remainingItemQty = Math.max(0, Math.round((remainingItemQty - take) * 1000) / 1000);
          toDeduct = Math.round((toDeduct - take) * 1000) / 1000;
        }
        if (toDeduct > 0.0005) {
          await updateWorkspaceEntity(workspace, 'inventoryItems', stocktakeItem.id, {
            qtyOnHand: actual,
          });
          await createWorkspaceEntity(workspace, 'stockMovements', newId('mov'), {
            kind: 'adjustment',
            itemId: stocktakeItem.id,
            itemName: stocktakeItem.name,
            qty: toDeduct,
            unit: stocktakeItem.unit,
            totalCents: Math.round(toDeduct * stocktakeItem.avgCostCents),
            reason: stocktakeReason.trim() || 'Корректировка остатка',
          });
        }
      }
      setStocktakeItem(null);
      onToast(`Инвентаризация проведена: ${formatQty(actual, stocktakeItem.unit)}`);
    } finally {
      setStocktakeBusy(false);
    }
  };

  const handleFefoConsume = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!consumeTarget) return;
    const qty = Number(consumeQty.replace(',', '.')) || 0;
    try {
      await consumeInventoryFefo({
        workspace,
        item: consumeTarget,
        lots: data.stockLots,
        qtyToConsume: qty,
        reason: consumeReason,
      });
      setConsumeTarget(null);
      onToast(`Списано по FEFO: ${formatQty(qty, consumeTarget.unit)}`);
    } catch (err) {
      onToast(err instanceof Error ? err.message : 'Ошибка списания FEFO');
    }
  };

  const handleWriteOffLotSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!writeOffLot) return;
    const qty = Math.min(
      writeOffLot.remainingQty,
      Math.max(0.001, Number(writeOffQty.replace(',', '.')) || 0),
    );
    const matchedItem = data.inventoryItems.find((i) => i.id === writeOffLot.itemId);
    await writeOffStockLot({
      workspace,
      lot: writeOffLot,
      item: matchedItem,
      qty,
      kind: 'issue',
      reason: writeOffReason.trim() || 'Списание брака / просрочки',
    });
    setWriteOffLot(null);
    onToast(`Списано с партии ${writeOffLot.lotCode}: ${formatQty(qty, writeOffLot.unit)}`);
  };

  const toggleQuarantine = async (lot: StockLot) => {
    const nextStatus = lot.status === 'quarantine' ? 'active' : 'quarantine';
    await updateWorkspaceEntity(workspace, 'stockLots', lot.id, {
      status: nextStatus,
    });
    onToast(
      nextStatus === 'quarantine'
        ? `Партия ${lot.lotCode} переведена в карантин`
        : `Партия ${lot.lotCode} возвращена в работу`,
    );
  };

  const handleAddSupplier = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!supName.trim()) return;
    await createWorkspaceEntity(workspace, 'suppliers', newId('sup'), {
      name: supName.trim().slice(0, 140),
      contactName: supContact.trim().slice(0, 120),
      phone: supPhone.trim().slice(0, 40),
      category: supCategory.trim().slice(0, 80),
      debtCents: 0,
    });
    setSupName('');
    setSupContact('');
    setSupPhone('');
    setSupplierDrawer(false);
    onToast('Поставщик добавлен');
  };

  const handlePaySupplierDebt = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!payDebtSupplier) return;
    const acc = data.accounts.find((a) => a.id === payDebtAccountId) || data.accounts[0];
    if (!acc) {
      onToast('Добавьте счёт в разделе Финансы');
      return;
    }
    const amountCents = parseRubToCents(payDebtRub);
    if (amountCents <= 0) return;
    await paySupplierDebt({
      workspace,
      supplier: payDebtSupplier,
      account: acc,
      amountCents,
    });
    setPayDebtSupplier(null);
    onToast(`Долг поставщику погашен: ${formatMoneyCents(amountCents, hideAmounts)}`);
  };

  const handleAddPurchase = async (e: React.FormEvent) => {
    e.preventDefault();
    const sup = data.suppliers.find((s) => s.id === purSupplierId) || data.suppliers[0];
    const item = data.inventoryItems.find((i) => i.id === purItemId);
    const resolvedItemName = (item?.name || purItemName).trim();
    if (!resolvedItemName) return;
    const qtyVal = Math.max(0.01, Number(purQty.replace(',', '.')) || 1);
    const priceCents = parseRubToCents(purPriceRub);
    const deliveryCents = parseRubToCents(purDeliveryRub);
    const payload: Record<string, unknown> = {
      supplierName: (sup?.name || 'Поставщик').slice(0, 140),
      itemName: resolvedItemName.slice(0, 140),
      qty: qtyVal,
      unit: item?.unit || purUnit,
      priceCents,
      deliveryCents,
      expectedDate: purExpectedDate,
      status: 'ordered',
    };
    if (sup?.id) payload.supplierId = sup.id;
    if (item?.id) payload.itemId = item.id;
    await createWorkspaceEntity(workspace, 'purchases', newId('pur'), payload);
    setPurItemName('');
    setPurItemId('');
    setPurDeliveryRub('0');
    setPurchaseDrawer(false);
    onToast(`Закупка «${resolvedItemName}» оформлена`);
  };

  const handleConfirmReceivePurchase = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!receiveTarget || receiveBusy) return;
    setReceiveBusy(true);
    try {
      const invItem = data.inventoryItems.find(
        (i) => i.id === receiveTarget.itemId || i.name === receiveTarget.itemName,
      );
      const acc = data.accounts.find((a) => a.id === receiveAccountId) || data.accounts[0];
      const sup = data.suppliers.find(
        (s) => s.id === receiveTarget.supplierId || s.name === receiveTarget.supplierName,
      );
      await receivePurchaseOrder({
        workspace,
        purchase: receiveTarget,
        item: invItem,
        expiresAt: receiveExpires,
        paymentMode: receivePaymentMode,
        account: receivePaymentMode === 'paid' ? acc : undefined,
        supplier: receivePaymentMode === 'debt' ? sup : undefined,
      });
      onToast(`Поставка «${receiveTarget.itemName}» оприходована в партию FEFO`);
      setReceiveTarget(null);
    } finally {
      setReceiveBusy(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Кладовая и партии FEFO"
        subtitle="Сырьё, полуфабрикаты, партии со сроками годности, движения и закупки"
        action={
          <div className="flex flex-wrap items-center gap-2">
            {recipePriceSyncPreview.length > 0 && (
              <button
                type="button"
                onClick={() => setSyncDrawerOpen(true)}
                className="min-h-[44px] px-3.5 py-2 rounded-xl border border-[var(--accent)] bg-[var(--soft)] text-sm font-medium inline-flex items-center gap-1.5 whitespace-nowrap shrink-0"
              >
                <RefreshCw className="w-4 h-4" />
                <span>Обновить цены в рецептах ({recipePriceSyncPreview.length})</span>
              </button>
            )}
            <button
              type="button"
              onClick={() => setImportDrawer(true)}
              className="min-h-[44px] px-3.5 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm font-medium hover:bg-[var(--soft)] whitespace-nowrap shrink-0"
            >
              Импорт CSV
            </button>
            <button
              type="button"
              onClick={() => setItemDrawer(true)}
              className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
            >
              + Оприходовать
            </button>
          </div>
        }
      />

      <SegmentedTabs
        value={tab}
        onChange={setTab}
        options={[
          { id: 'items', label: 'Остатки', count: data.inventoryItems.length },
          { id: 'lots', label: 'Партии FEFO', count: sortedLots.length },
          { id: 'movements', label: 'Движения', count: data.stockMovements.length },
          { id: 'purchases', label: 'Закупки', count: data.purchases.length },
        ]}
      />

      {tab === 'items' && (
        <Card className="p-0 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-xs text-[var(--muted)]">
                  <th className="text-left px-4 py-3 font-medium">Позиция</th>
                  <th className="text-left px-4 py-3 font-medium">Тип</th>
                  <th className="text-right px-4 py-3 font-medium">Остаток</th>
                  <th className="text-right px-4 py-3 font-medium">Цена за ед.</th>
                  <th className="text-right px-4 py-3 font-medium">Действия</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--line)]">
                {data.inventoryItems.map((item) => {
                  const low =
                    item.minQty !== undefined && item.qtyOnHand <= item.minQty;
                  return (
                    <tr key={item.id} className="hover:bg-[var(--soft)]/30">
                      <td className="px-4 py-3.5">
                        <div className="font-medium">
                          {item.name}
                          {item.density ? (
                            <span className="ml-1.5 text-[11px] font-normal text-[var(--muted)]">
                              ({item.density} г/мл)
                            </span>
                          ) : null}
                        </div>
                        {low && (
                          <div className="text-xs text-[var(--danger)]">
                            Ниже минимума ({item.minQty} {item.unit})
                          </div>
                        )}
                      </td>
                      <td className="px-4 py-3.5 text-[var(--muted)]">
                        {item.kind === 'raw'
                          ? 'Сырьё'
                          : item.kind === 'semi'
                            ? 'Полуфабрикат'
                            : item.kind === 'packaging'
                              ? 'Упаковка'
                              : 'Готовое'}
                      </td>
                      <td className="px-4 py-3.5 text-right tabular-nums font-medium">
                        {formatQty(item.qtyOnHand, item.unit)}
                      </td>
                      <td className="px-4 py-3.5 text-right tabular-nums">
                        {formatMoneyCents(item.avgCostCents, hideAmounts)}
                      </td>
                      <td className="px-4 py-3.5 text-right">
                        <div className="inline-flex items-center gap-1.5">
                          <button
                            type="button"
                            onClick={() => openEditItem(item)}
                            title="Редактировать"
                            className="p-1.5 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)]"
                          >
                            <Pencil className="w-3.5 h-3.5" />
                          </button>
                          <button
                            type="button"
                            onClick={() => setHistoryItem(item)}
                            title="История закупочных цен"
                            className="p-1.5 rounded-lg border border-[var(--line)] hover:bg-[var(--soft)]"
                          >
                            <History className="w-3.5 h-3.5" />
                          </button>
                          <button
                            type="button"
                            onClick={() => openStocktake(item)}
                            title="Инвентаризация"
                            className="px-2.5 py-1.5 rounded-lg border border-[var(--line)] text-xs font-medium hover:bg-[var(--soft)] inline-flex items-center gap-1 whitespace-nowrap"
                          >
                            <Scale className="w-3.5 h-3.5" />
                            <span className="hidden sm:inline">Сверка</span>
                          </button>
                          <button
                            type="button"
                            onClick={() => setConsumeTarget(item)}
                            className="px-3 py-1.5 rounded-lg border border-[var(--line)] text-xs font-medium hover:bg-[var(--soft)] whitespace-nowrap"
                          >
                            Списать по FEFO
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {tab === 'lots' && (
        <Card className="p-0 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-xs text-[var(--muted)]">
                  <th className="text-left px-4 py-3 font-medium">Партия</th>
                  <th className="text-left px-4 py-3 font-medium">Позиция</th>
                  <th className="text-right px-4 py-3 font-medium">Остаток / Выход</th>
                  <th className="text-left px-4 py-3 font-medium">Годен до</th>
                  <th className="text-left px-4 py-3 font-medium">Статус</th>
                  <th className="text-right px-4 py-3 font-medium">Действия</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--line)]">
                {sortedLots.map((lot) => {
                  const expiredByDate =
                    Boolean(lot.expiresAt && lot.expiresAt < todayIso) &&
                    lot.status !== 'depleted';
                  return (
                    <tr
                      key={lot.id}
                      className={expiredByDate ? 'bg-[var(--danger-bg)]/35' : ''}
                    >
                      <td className="px-4 py-3.5 font-mono text-xs">{lot.lotCode}</td>
                      <td className="px-4 py-3.5 font-medium">{lot.itemName}</td>
                      <td className="px-4 py-3.5 text-right tabular-nums">
                        {formatQty(lot.remainingQty, lot.unit)} /{' '}
                        {formatQty(lot.initialQty, lot.unit)}
                      </td>
                      <td
                        className={`px-4 py-3.5 tabular-nums ${
                          expiredByDate
                            ? 'text-[var(--danger)] font-medium'
                            : 'text-[var(--muted)]'
                        }`}
                      >
                        {lot.expiresAt || '—'}
                      </td>
                      <td className="px-4 py-3.5 text-xs">
                        {lot.status === 'depleted'
                          ? 'Исчерпана'
                          : expiredByDate || lot.status === 'expired'
                            ? 'Истекла'
                            : lot.status === 'quarantine'
                              ? 'Карантин (блокирована)'
                              : 'Активна'}
                      </td>
                      <td className="px-4 py-3.5 text-right">
                        {lot.status !== 'depleted' && lot.remainingQty > 0 && (
                          <div className="inline-flex items-center gap-1.5">
                            <button
                              type="button"
                              onClick={() => toggleQuarantine(lot)}
                              className="px-2.5 py-1.5 rounded-lg border border-[var(--line)] text-xs hover:bg-[var(--soft)] whitespace-nowrap"
                            >
                              {lot.status === 'quarantine' ? 'Снять карантин' : 'В карантин'}
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                setWriteOffLot(lot);
                                setWriteOffQty(String(lot.remainingQty));
                                setWriteOffReason(
                                  expiredByDate || lot.status === 'expired'
                                    ? 'Списание просроченной партии'
                                    : lot.status === 'quarantine'
                                      ? 'Списание брака из карантина'
                                      : 'Списание порчи',
                                );
                              }}
                              className="px-2.5 py-1.5 rounded-lg border border-[var(--line)] text-xs text-[var(--danger)] hover:bg-[var(--danger-bg)] inline-flex items-center gap-1 whitespace-nowrap"
                            >
                              <Trash2 className="w-3 h-3" />
                              <span>Списать брак</span>
                            </button>
                          </div>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {tab === 'movements' && (
        <Card className="p-0 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[var(--line)] text-xs text-[var(--muted)]">
                  <th className="text-left px-4 py-3 font-medium">Операция</th>
                  <th className="text-left px-4 py-3 font-medium">Позиция</th>
                  <th className="text-right px-4 py-3 font-medium">Количество</th>
                  <th className="text-right px-4 py-3 font-medium">Сумма</th>
                  <th className="text-left px-4 py-3 font-medium">Причина</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--line)]">
                {data.stockMovements.map((m) => (
                  <tr key={m.id}>
                    <td className="px-4 py-3 text-xs">
                      {m.kind === 'receipt'
                        ? 'Приход'
                        : m.kind === 'issue'
                          ? 'Списание'
                          : m.kind === 'production_in'
                            ? 'Выпуск +'
                            : m.kind === 'adjustment'
                              ? 'Сверка'
                              : m.kind}
                    </td>
                    <td className="px-4 py-3 font-medium">{m.itemName}</td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      {formatQty(m.qty, m.unit)}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      {formatMoneyCents(m.totalCents, hideAmounts)}
                    </td>
                    <td className="px-4 py-3 text-[var(--muted)]">{m.reason || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {tab === 'purchases' && (
        <div className="grid md:grid-cols-2 gap-6">
          <Card>
            <div className="flex items-center justify-between gap-2 pb-3 border-b border-[var(--line)]">
              <h3 className="text-base font-semibold">Закупки и приёмка</h3>
              <button
                type="button"
                onClick={() => {
                  setPurSupplierId(data.suppliers[0]?.id || '');
                  setPurchaseDrawer(true);
                }}
                className="px-3 py-1.5 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium whitespace-nowrap"
              >
                + Закупка
              </button>
            </div>
            <div className="divide-y divide-[var(--line)] mt-2">
              {data.purchases.length === 0 ? (
                <div className="py-6 text-sm text-[var(--muted)]">
                  Закупок пока нет. Создайте заявку поставщику, чтобы принять её на склад.
                </div>
              ) : (
                data.purchases.map((p) => (
                  <div key={p.id} className="py-3 flex items-center justify-between gap-3">
                    <div>
                      <div className="text-sm font-medium">
                        {p.itemName} · {formatQty(p.qty, p.unit)}
                      </div>
                      <div className="text-xs text-[var(--muted)]">
                        {p.supplierName} ·{' '}
                        {formatMoneyCents(
                          p.priceCents + (p.deliveryCents || 0),
                          hideAmounts,
                        )}{' '}
                        {(p.deliveryCents || 0) > 0
                          ? `(доставка ${formatMoneyCents(p.deliveryCents || 0, hideAmounts)}) `
                          : ''}
                        · {p.status === 'received' ? 'Принято' : `Ожидается ${p.expectedDate || ''}`}
                      </div>
                    </div>
                    {p.status !== 'received' && (
                      <button
                        type="button"
                        onClick={() => {
                          setReceiveTarget(p);
                          setReceiveExpires(
                            new Date(Date.now() + 14 * 86400000).toISOString().slice(0, 10),
                          );
                          setReceiveAccountId(data.accounts[0]?.id || '');
                          setReceivePaymentMode(data.accounts.length > 0 ? 'paid' : 'none');
                        }}
                        className="min-h-[38px] px-3 py-1.5 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium whitespace-nowrap"
                      >
                        Принять поставку
                      </button>
                    )}
                  </div>
                ))
              )}
            </div>
          </Card>

          <Card>
            <div className="flex items-center justify-between gap-2 pb-3 border-b border-[var(--line)]">
              <h3 className="text-base font-semibold">Поставщики</h3>
              <button
                type="button"
                onClick={() => setSupplierDrawer(true)}
                className="px-3 py-1.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-xs font-medium hover:bg-[var(--soft)] whitespace-nowrap"
              >
                + Поставщик
              </button>
            </div>
            <div className="divide-y divide-[var(--line)] mt-2">
              {data.suppliers.length === 0 ? (
                <div className="py-6 text-sm text-[var(--muted)]">
                  Добавьте поставщиков сырья и упаковки.
                </div>
              ) : (
                data.suppliers.map((s) => (
                  <div key={s.id} className="py-3 flex items-center justify-between gap-3">
                    <div>
                      <div className="text-sm font-medium">{s.name}</div>
                      <div className="text-xs text-[var(--muted)]">
                        {s.contactName || 'Контакт'} · {s.phone || s.category}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="text-sm font-semibold tabular-nums">
                        {formatMoneyCents(s.debtCents || 0, hideAmounts)}
                      </div>
                      {(s.debtCents || 0) > 0 && (
                        <button
                          type="button"
                          onClick={() => {
                            setPayDebtSupplier(s);
                            setPayDebtAccountId(data.accounts[0]?.id || '');
                            setPayDebtRub(centsToRubInput(s.debtCents || 0));
                          }}
                          className="px-2.5 py-1.5 rounded-lg border border-[var(--line)] bg-[var(--bg)] text-xs font-medium hover:bg-[var(--soft)] whitespace-nowrap"
                        >
                          Погасить долг
                        </button>
                      )}
                    </div>
                  </div>
                ))
              )}
            </div>
          </Card>
        </div>
      )}

      {/* Add Inventory Drawer */}
      <Drawer
        open={itemDrawer}
        title="Оприходовать позицию"
        subtitle="Создаст позицию и активную партию FEFO"
        onClose={() => setItemDrawer(false)}
      >
        <form onSubmit={handleAddItem} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Название</span>
            <input
              type="text"
              required
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              placeholder="Например: Масло сливочное 82,5%"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Тип</span>
              <select
                value={newKind}
                onChange={(e) => setNewKind(e.target.value as InventoryItem['kind'])}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                <option value="raw">Сырьё</option>
                <option value="semi">Полуфабрикат</option>
                <option value="finished">Готовое изделие</option>
                <option value="packaging">Упаковка</option>
              </select>
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Единица</span>
              <select
                value={newUnit}
                onChange={(e) => setNewUnit(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                {QTY_UNITS.map((u) => (
                  <option key={u} value={u}>
                    {u}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Количество</span>
              <input
                type="text"
                value={newQty}
                onChange={(e) => setNewQty(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Цена за единицу, ₽</span>
              <input
                type="text"
                value={newCostRub}
                onChange={(e) => setNewCostRub(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Срок годности партии</span>
              <input
                type="date"
                value={newExpires}
                onChange={(e) => setNewExpires(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Плотность, г/мл (для мл↔г)</span>
              <input
                type="text"
                value={newDensity}
                onChange={(e) => setNewDensity(e.target.value)}
                placeholder="Напр. 1.03"
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          </div>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Провести приход
          </button>
        </form>
      </Drawer>

      {/* Edit Item Drawer */}
      <Drawer
        open={Boolean(editItem)}
        title={`Редактировать: ${editItem?.name || ''}`}
        subtitle="Название, минимальный порог и плотность для перевода мл ↔ г"
        onClose={() => setEditItem(null)}
      >
        <form onSubmit={handleSaveEditItem} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Название</span>
            <input
              type="text"
              required
              value={editName}
              onChange={(e) => setEditName(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Категория</span>
              <input
                type="text"
                value={editCategory}
                onChange={(e) => setEditCategory(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Мин. остаток ({editItem?.unit})</span>
              <input
                type="text"
                value={editMinQty}
                onChange={(e) => setEditMinQty(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          </div>
          <label className="block space-y-1 text-sm font-medium">
            <span>Плотность (г/мл, необязательно)</span>
            <input
              type="text"
              value={editDensity}
              onChange={(e) => setEditDensity(e.target.value)}
              placeholder="Напр. сливки 1.01, мёд 1.42, масло раст. 0.92"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Сохранить параметры
          </button>
        </form>
      </Drawer>

      {/* Stocktake Drawer */}
      <Drawer
        open={Boolean(stocktakeItem)}
        title={`Инвентаризация: ${stocktakeItem?.name || ''}`}
        subtitle={
          stocktakeItem
            ? `Учётный остаток: ${formatQty(stocktakeItem.qtyOnHand, stocktakeItem.unit)}`
            : ''
        }
        onClose={() => setStocktakeItem(null)}
      >
        <form onSubmit={handleApplyStocktake} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Фактический остаток ({stocktakeItem?.unit})</span>
            <input
              type="text"
              required
              value={stocktakeActualQty}
              onChange={(e) => setStocktakeActualQty(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
            />
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Комментарий к акту сверки</span>
            <input
              type="text"
              value={stocktakeReason}
              onChange={(e) => setStocktakeReason(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            disabled={stocktakeBusy}
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium disabled:opacity-60"
          >
            {stocktakeBusy ? 'Проводим сверку...' : 'Зафиксировать факт'}
          </button>
        </form>
      </Drawer>

      {/* Price History Drawer */}
      <Drawer
        open={Boolean(historyItem)}
        title={`История цен: ${historyItem?.name || ''}`}
        subtitle={
          historyItem
            ? `Текущая средняя: ${formatMoneyCents(historyItem.avgCostCents, hideAmounts)} за ${historyItem.unit}`
            : ''
        }
        onClose={() => setHistoryItem(null)}
      >
        {historyMovements.length === 0 ? (
          <div className="py-8 text-sm text-[var(--muted)] text-center">
            Зафиксированных приходов по этой позиции пока нет.
          </div>
        ) : (
          <div className="divide-y divide-[var(--line)] text-sm">
            {historyMovements.map((m) => {
              const unitCost = m.qty > 0 ? Math.round(m.totalCents / m.qty) : 0;
              return (
                <div key={m.id} className="py-3 flex items-center justify-between gap-3">
                  <div>
                    <div className="font-medium">{m.reason || 'Поступление'}</div>
                    <div className="text-xs text-[var(--muted)]">
                      {formatMovementDate(m.createdAt)} · {formatQty(m.qty, m.unit)} на{' '}
                      {formatMoneyCents(m.totalCents, hideAmounts)}
                    </div>
                  </div>
                  <div className="text-right tabular-nums font-semibold shrink-0">
                    {formatMoneyCents(unitCost, hideAmounts)}/{m.unit}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Drawer>

      {/* Bulk Recipe Price Sync Drawer */}
      <Drawer
        open={syncDrawerOpen}
        wide
        title="Обновить закупочные цены в рецептах"
        subtitle="Сверка ингредиентов техкарт с актуальной средней ценой в Кладовой"
        onClose={() => setSyncDrawerOpen(false)}
      >
        <div className="space-y-4">
          {recipePriceSyncPreview.length === 0 ? (
            <div className="py-6 text-sm text-[var(--muted)]">
              Все цены в техкартах уже актуальны.
            </div>
          ) : (
            <>
              <div className="divide-y divide-[var(--line)] border border-[var(--line)] rounded-xl overflow-hidden text-sm">
                {recipePriceSyncPreview.map((u) => {
                  const diff = u.newCostCents - u.oldCostCents;
                  return (
                    <div key={u.recipe.id} className="p-3.5 flex items-center justify-between gap-3 bg-[var(--bg)]">
                      <div>
                        <div className="font-medium">{u.recipe.title}</div>
                        <div className="text-xs text-[var(--muted)]">
                          Обновится строк: {u.changedLines}
                        </div>
                      </div>
                      <div className="text-right tabular-nums">
                        <div className="font-medium">
                          {formatMoneyCents(u.oldCostCents, hideAmounts)} →{' '}
                          {formatMoneyCents(u.newCostCents, hideAmounts)}
                        </div>
                        <div
                          className={`text-xs ${
                            diff > 0 ? 'text-[var(--danger)]' : 'text-emerald-700'
                          }`}
                        >
                          {diff > 0 ? '+' : ''}
                          {formatMoneyCents(diff, hideAmounts)} себестоимость
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
              <button
                type="button"
                disabled={syncBusy}
                onClick={handleApplyRecipePriceSync}
                className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium disabled:opacity-60"
              >
                {syncBusy
                  ? 'Обновляем техкарты...'
                  : `Обновить ${recipePriceSyncPreview.length} техкарт`}
              </button>
            </>
          )}
        </div>
      </Drawer>

      {/* Lot Spoilage / Quarantine Write-off Drawer */}
      <Drawer
        open={Boolean(writeOffLot)}
        title={`Списание с партии ${writeOffLot?.lotCode || ''}`}
        subtitle={
          writeOffLot
            ? `${writeOffLot.itemName} · Остаток ${formatQty(writeOffLot.remainingQty, writeOffLot.unit)}`
            : ''
        }
        onClose={() => setWriteOffLot(null)}
      >
        <form onSubmit={handleWriteOffLotSubmit} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Количество к списанию ({writeOffLot?.unit})</span>
            <input
              type="text"
              required
              value={writeOffQty}
              onChange={(e) => setWriteOffQty(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
            />
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Причина списания</span>
            <input
              type="text"
              required
              value={writeOffReason}
              onChange={(e) => setWriteOffReason(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--danger)] text-white text-sm font-medium"
          >
            Списать брак / просрочку
          </button>
        </form>
      </Drawer>

      {/* FEFO Write-off Drawer */}
      <Drawer
        open={Boolean(consumeTarget)}
        title={`Списание по FEFO: ${consumeTarget?.name || ''}`}
        subtitle="Списываются пригодные некарантинные партии с ближайшим сроком"
        onClose={() => setConsumeTarget(null)}
      >
        <form onSubmit={handleFefoConsume} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Количество ({consumeTarget?.unit})</span>
            <input
              type="text"
              required
              value={consumeQty}
              onChange={(e) => setConsumeQty(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
            />
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Причина</span>
            <input
              type="text"
              required
              value={consumeReason}
              onChange={(e) => setConsumeReason(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Списать
          </button>
        </form>
      </Drawer>

      {/* Receive Purchase Drawer */}
      <Drawer
        open={Boolean(receiveTarget)}
        title={`Принять поставку: ${receiveTarget?.itemName || ''}`}
        subtitle={
          receiveTarget
            ? `Поставщик: ${receiveTarget.supplierName} · Сумма с доставкой: ${formatMoneyCents(
                receiveTarget.priceCents + (receiveTarget.deliveryCents || 0),
                hideAmounts,
              )}`
            : ''
        }
        onClose={() => setReceiveTarget(null)}
      >
        <form onSubmit={handleConfirmReceivePurchase} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Срок годности партии FEFO</span>
            <input
              type="date"
              required
              value={receiveExpires}
              onChange={(e) => setReceiveExpires(e.target.value)}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="space-y-2 text-sm">
            <span className="font-medium block">Оплата поставки</span>
            <div className="grid grid-cols-1 gap-2">
              <label className="flex items-center gap-2 p-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] cursor-pointer">
                <input
                  type="radio"
                  name="recPay"
                  checked={receivePaymentMode === 'paid'}
                  onChange={() => setReceivePaymentMode('paid')}
                  className="accent-[var(--accent)]"
                />
                <span>Оплатить сейчас со счёта (расход в Финансах)</span>
              </label>
              <label className="flex items-center gap-2 p-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] cursor-pointer">
                <input
                  type="radio"
                  name="recPay"
                  checked={receivePaymentMode === 'debt'}
                  onChange={() => setReceivePaymentMode('debt')}
                  className="accent-[var(--accent)]"
                />
                <span>В долг поставщику (увеличит задолженность)</span>
              </label>
              <label className="flex items-center gap-2 p-2.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] cursor-pointer">
                <input
                  type="radio"
                  name="recPay"
                  checked={receivePaymentMode === 'none'}
                  onChange={() => setReceivePaymentMode('none')}
                  className="accent-[var(--accent)]"
                />
                <span>Только оприходовать на склад</span>
              </label>
            </div>
          </div>
          {receivePaymentMode === 'paid' && data.accounts.length > 0 && (
            <label className="block space-y-1 text-sm font-medium">
              <span>Счёт списания</span>
              <select
                value={receiveAccountId}
                onChange={(e) => setReceiveAccountId(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                {data.accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name} ({formatMoneyCents(a.balanceCents, hideAmounts)})
                  </option>
                ))}
              </select>
            </label>
          )}
          <button
            type="submit"
            disabled={receiveBusy}
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium disabled:opacity-60"
          >
            {receiveBusy ? 'Оприходуем...' : 'Принять на склад'}
          </button>
        </form>
      </Drawer>

      {/* Pay Supplier Debt Drawer */}
      <Drawer
        open={Boolean(payDebtSupplier)}
        title={`Погасить долг: ${payDebtSupplier?.name || ''}`}
        subtitle={
          payDebtSupplier
            ? `Текущий долг: ${formatMoneyCents(payDebtSupplier.debtCents || 0, hideAmounts)}`
            : ''
        }
        onClose={() => setPayDebtSupplier(null)}
      >
        <form onSubmit={handlePaySupplierDebt} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Сумма оплаты, ₽</span>
            <input
              type="text"
              required
              value={payDebtRub}
              onChange={(e) => setPayDebtRub(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
            />
          </label>
          {data.accounts.length > 0 && (
            <label className="block space-y-1 text-sm font-medium">
              <span>Счёт оплаты</span>
              <select
                value={payDebtAccountId}
                onChange={(e) => setPayDebtAccountId(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                {data.accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name} ({formatMoneyCents(a.balanceCents, hideAmounts)})
                  </option>
                ))}
              </select>
            </label>
          )}
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Оплатить поставщику
          </button>
        </form>
      </Drawer>

      {/* New Supplier Drawer */}
      <Drawer
        open={supplierDrawer}
        title="Новый поставщик"
        onClose={() => setSupplierDrawer(false)}
      >
        <form onSubmit={handleAddSupplier} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Название компании / поставщика</span>
            <input
              type="text"
              required
              value={supName}
              onChange={(e) => setSupName(e.target.value)}
              placeholder="Например: Ягодный фермер"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Контактное лицо</span>
              <input
                type="text"
                value={supContact}
                onChange={(e) => setSupContact(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Телефон</span>
              <input
                type="text"
                value={supPhone}
                onChange={(e) => setSupPhone(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          </div>
          <label className="block space-y-1 text-sm font-medium">
            <span>Категория поставок</span>
            <input
              type="text"
              value={supCategory}
              onChange={(e) => setSupCategory(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Сохранить поставщика
          </button>
        </form>
      </Drawer>

      {/* New Purchase Drawer */}
      <Drawer
        open={purchaseDrawer}
        title="Новая закупка"
        subtitle="После доставки нажмите «Принять поставку» для оприходования в партию FEFO"
        onClose={() => setPurchaseDrawer(false)}
      >
        <form onSubmit={handleAddPurchase} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Поставщик</span>
            <select
              value={purSupplierId}
              onChange={(e) => setPurSupplierId(e.target.value)}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              {data.suppliers.length === 0 ? (
                <option value="">Без поставщика</option>
              ) : (
                data.suppliers.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))
              )}
            </select>
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Позиция со склада (или введите новую ниже)</span>
            <select
              value={purItemId}
              onChange={(e) => {
                const id = e.target.value;
                setPurItemId(id);
                const found = data.inventoryItems.find((i) => i.id === id);
                if (found) {
                  setPurItemName(found.name);
                  setPurUnit(found.unit);
                }
              }}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              <option value="">Новая позиция...</option>
              {data.inventoryItems.map((i) => (
                <option key={i.id} value={i.id}>
                  {i.name} ({i.unit})
                </option>
              ))}
            </select>
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Наименование товара *</span>
            <input
              type="text"
              required
              value={purItemName}
              onChange={(e) => setPurItemName(e.target.value)}
              placeholder="Например: Сливки 33%"
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            />
          </label>
          <div className="grid grid-cols-3 gap-2">
            <label className="block space-y-1 text-sm font-medium">
              <span>Кол-во</span>
              <input
                type="text"
                required
                value={purQty}
                onChange={(e) => setPurQty(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Ед.</span>
              <select
                value={purUnit}
                onChange={(e) => setPurUnit(e.target.value)}
                className="w-full min-h-[44px] px-2 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              >
                {QTY_UNITS.map((u) => (
                  <option key={u} value={u}>
                    {u}
                  </option>
                ))}
              </select>
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Сумма, ₽</span>
              <input
                type="text"
                required
                value={purPriceRub}
                onChange={(e) => setPurPriceRub(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <label className="block space-y-1 text-sm font-medium">
              <span>Доставка, ₽</span>
              <input
                type="text"
                value={purDeliveryRub}
                onChange={(e) => setPurDeliveryRub(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
              />
            </label>
            <label className="block space-y-1 text-sm font-medium">
              <span>Ожидаемая дата доставки</span>
              <input
                type="date"
                value={purExpectedDate}
                onChange={(e) => setPurExpectedDate(e.target.value)}
                className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
              />
            </label>
          </div>
          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Создать закупку
          </button>
        </form>
      </Drawer>

      {/* CSV Import Drawer */}
      <Drawer
        open={importDrawer}
        wide
        title="Импорт склада из CSV"
        subtitle="Предпросмотр (dry-run), проверка единиц измерения и защита от дублей"
        onClose={() => setImportDrawer(false)}
      >
        <div className="space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-[var(--muted)]">
            <span>Колонки: Наименование;Тип(raw/semi/packaging);Единица;Количество;Цена;Срок</span>
            <label className="px-3 py-1.5 rounded-lg border border-[var(--line)] bg-[var(--card)] text-[var(--ink)] font-medium cursor-pointer hover:bg-[var(--soft)]">
              Загрузить .csv
              <input
                type="file"
                accept=".csv,.txt"
                className="sr-only"
                onChange={async (e) => {
                  const file = e.target.files?.[0];
                  if (!file) return;
                  const txt = await file.text();
                  setImportCsvText(txt);
                  e.target.value = '';
                }}
              />
            </label>
          </div>

          <textarea
            rows={5}
            value={importCsvText}
            onChange={(e) => setImportCsvText(e.target.value)}
            className="w-full p-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] font-mono text-xs"
          />

          <div className="p-3 rounded-xl bg-[var(--soft)] flex flex-wrap items-center justify-between gap-2 text-xs">
            <span>
              Распознано строк: <strong>{importPreview.rows.length}</strong> · Готово к импорту:{' '}
              <strong>
                {importPreview.rows.filter((r) => r.valid && !r.duplicate).length}
              </strong>
            </span>
            <span className="text-[var(--muted)]">
              Дублей: {importPreview.rows.filter((r) => r.duplicate).length} · Ошибок:{' '}
              {importPreview.errors}
            </span>
          </div>

          {importPreview.rows.length > 0 && (
            <div className="max-h-56 overflow-y-auto rounded-xl border border-[var(--line)]">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b border-[var(--line)] text-[var(--muted)]">
                    <th className="text-left px-3 py-2">Позиция</th>
                    <th className="text-left px-3 py-2">Кол-во</th>
                    <th className="text-right px-3 py-2">Цена</th>
                    <th className="text-right px-3 py-2">Статус</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--line)]">
                  {importPreview.rows.map((r, i) => (
                    <tr key={i}>
                      <td className="px-3 py-2 font-medium">{r.name}</td>
                      <td className="px-3 py-2 tabular-nums">
                        {r.qty} {r.unit}
                      </td>
                      <td className="px-3 py-2 text-right tabular-nums">
                        {formatMoneyCents(r.priceCents, hideAmounts)}
                      </td>
                      <td className="px-3 py-2 text-right">
                        {!r.valid ? (
                          <span className="text-[var(--danger)]">{r.error}</span>
                        ) : r.duplicate ? (
                          <span className="text-[var(--muted)]">Дубль (пропуск)</span>
                        ) : (
                          <span className="text-emerald-700 font-medium">ОК</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <button
            type="button"
            disabled={
              importingCsv ||
              importPreview.rows.filter((r) => r.valid && !r.duplicate).length === 0
            }
            onClick={handleRunCsvImport}
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium disabled:opacity-50"
          >
            {importingCsv
              ? 'Импортируем...'
              : `Импортировать (${importPreview.rows.filter((r) => r.valid && !r.duplicate).length})`}
          </button>
        </div>
      </Drawer>
    </div>
  );
}

export function ProductionPage({
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
  const [recipeId, setRecipeId] = useState(data.recipes[0]?.id || '');
  const [plannedGrams, setPlannedGrams] = useState(3000);
  const [completeTarget, setCompleteTarget] = useState<ProductionRun | null>(null);
  const [actualGramsInput, setActualGramsInput] = useState(3000);
  const [deductFefo, setDeductFefo] = useState(true);
  const [completing, setCompleting] = useState(false);

  const selectedRec = useMemo(
    () => data.recipes.find((r) => r.id === recipeId) || data.recipes[0],
    [data.recipes, recipeId],
  );

  const bomPreview = useMemo(() => {
    if (!selectedRec?.ingredients?.length) return [];
    const factor = plannedGrams / Math.max(selectedRec.yieldGrams || 1, 1);
    return selectedRec.ingredients.map((ing) => {
      const needed = ing.qty * factor;
      const inv = ing.itemId
        ? data.inventoryItems.find((i) => i.id === ing.itemId)
        : data.inventoryItems.find(
            (i) => i.name.toLowerCase() === ing.name.toLowerCase(),
          );
      const neededInInv = inv
        ? convertQtyWithDensity(needed, ing.unit, inv.unit, inv.density)
        : null;
      const shortage =
        inv && neededInInv !== null ? inv.qtyOnHand + 1e-6 < neededInInv : false;
      return {
        name: ing.name,
        neededStr: formatQty(needed, ing.unit),
        stockStr: inv ? formatQty(inv.qtyOnHand, inv.unit) : 'нет на складе',
        shortage,
      };
    });
  }, [selectedRec, plannedGrams, data.inventoryItems]);

  const handleStartRun = async (e: React.FormEvent) => {
    e.preventDefault();
    const rec = selectedRec;
    const title = rec ? rec.title : 'Производственная партия';
    const costCents = rec
      ? Math.round((rec.costCents * plannedGrams) / Math.max(rec.yieldGrams, 1))
      : 150000;
    await createWorkspaceEntity(workspace, 'productionRuns', newId('run'), {
      recipeId: rec?.id || '',
      recipeTitle: title,
      plannedGrams,
      locationName: data.locations[0]?.name || 'Основная студия',
      assigneeName: 'Владелец',
      totalCostCents: costCents,
      status: 'in_progress',
    });
    setDrawerOpen(false);
    onToast('Производственное задание запущено');
  };

  const handleCompleteRun = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!completeTarget || completing) return;
    setCompleting(true);
    try {
      const run = completeTarget;
      const actualG = Math.max(10, Math.round(actualGramsInput) || run.plannedGrams);
      const rec = data.recipes.find((r) => r.id === run.recipeId);
      let deductedCount = 0;
      let actualTotalCostCents = 0;
      const skippedNames: string[] = [];
      let workingLots = [...data.stockLots];

      if (deductFefo && rec?.ingredients?.length) {
        const factor = run.plannedGrams / Math.max(rec.yieldGrams || 1, 1);
        for (const ing of rec.ingredients) {
          const inv = ing.itemId
            ? data.inventoryItems.find((i) => i.id === ing.itemId)
            : data.inventoryItems.find(
                (i) => i.name.toLowerCase() === ing.name.toLowerCase(),
              );
          if (!inv) continue;
          const qtyInInvUnit = convertQtyWithDensity(
            ing.qty * factor,
            ing.unit,
            inv.unit,
            inv.density,
          );
          if (qtyInInvUnit === null || qtyInInvUnit <= 0) continue;
          try {
            const res = await consumeInventoryFefo({
              workspace,
              item: inv,
              lots: workingLots,
              qtyToConsume: Math.round(qtyInInvUnit * 1000) / 1000,
              reason: `Выпуск партии: ${run.recipeTitle}`,
            });
            workingLots = res.updatedLots;
            actualTotalCostCents += res.totalCostCents;
            deductedCount += 1;
          } catch {
            skippedNames.push(inv.name);
          }
        }
      }

      const resolvedCostCents =
        actualTotalCostCents > 0
          ? actualTotalCostCents
          : run.totalCostCents ||
            (rec
              ? Math.round((rec.costCents * actualG) / Math.max(rec.yieldGrams, 1))
              : 120000);

      await updateWorkspaceEntity(workspace, 'productionRuns', run.id, {
        status: 'completed',
        actualGrams: actualG,
        totalCostCents: resolvedCostCents,
      });

      const qtyKg = Math.round((actualG / 1000) * 1000) / 1000;
      const isSemiCategory = Boolean(
        rec &&
          /полуфабрикат|крем|бисквит|начинк/i.test(rec.category),
      );
      await upsertInventoryReceipt({
        workspace,
        items: data.inventoryItems,
        name: run.recipeTitle,
        kind: isSemiCategory ? 'semi' : 'finished',
        category: isSemiCategory ? 'Полуфабрикаты' : 'Выпуск кухни',
        unit: 'кг',
        qty: qtyKg,
        totalCostCents: resolvedCostCents,
        expiresAt: new Date(
          Date.now() + Math.max(1, Math.ceil((rec?.shelfLifeHours || 72) / 24)) * 86400000,
        )
          .toISOString()
          .slice(0, 10),
        reason: `Выпуск партии: ${run.recipeTitle} (${actualG} г)`,
        movementKind: 'production_in',
      });

      setCompleteTarget(null);
      if (skippedNames.length > 0) {
        onToast(
          `Выпуск ${qtyKg} кг завершён (списано позиций: ${deductedCount}, не хватило FEFO: ${skippedNames.join(', ')})`,
        );
      } else {
        onToast(
          deductedCount > 0
            ? `Выпуск ${qtyKg} кг завершён, списано сырья по FEFO: ${deductedCount}`
            : `Выпуск завершён: ${qtyKg} кг оприходовано в Кладовую`,
        );
      }
    } finally {
      setCompleting(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Производство и выпуск партий"
        subtitle="План-факт выпуска, проверка потребности сырья и списание FEFO"
        action={
          <button
            type="button"
            onClick={() => setDrawerOpen(true)}
            className="min-h-[44px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
          >
            + Новая партия
          </button>
        }
      />

      {data.productionRuns.length === 0 ? (
        <EmptyState
          title="Производственных заданий нет"
          description="Запустите замес полуфабриката или партию десертов."
          actionLabel="+ Запустить партию"
          onAction={() => setDrawerOpen(true)}
        />
      ) : (
        <div className="grid md:grid-cols-2 gap-4">
          {data.productionRuns.map((run) => (
            <Card key={run.id} className="space-y-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="text-xs text-[var(--muted)]">
                    {run.locationName || 'Кухня'} · {run.assigneeName || 'Владелец'}
                  </div>
                  <h3 className="text-base font-semibold mt-0.5">{run.recipeTitle}</h3>
                </div>
                <span className="text-xs font-medium">
                  {run.status === 'completed'
                    ? 'Выпущена'
                    : run.status === 'in_progress'
                      ? 'В работе'
                      : 'Запланирована'}
                </span>
              </div>
              <div className="flex justify-between text-sm tabular-nums">
                <span>
                  План: {run.plannedGrams} г{' '}
                  {run.actualGrams ? `· Факт: ${run.actualGrams} г` : ''}
                </span>
                <span className="font-semibold">
                  {formatMoneyCents(run.totalCostCents || 0, hideAmounts)}
                </span>
              </div>
              {run.status !== 'completed' && (
                <button
                  type="button"
                  onClick={() => {
                    setCompleteTarget(run);
                    setActualGramsInput(run.plannedGrams);
                    setDeductFefo(true);
                  }}
                  className="w-full min-h-[40px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium"
                >
                  Завершить выпуск и оприходовать
                </button>
              )}
            </Card>
          ))}
        </div>
      )}

      <Drawer
        open={drawerOpen}
        title="Запустить производственную партию"
        onClose={() => setDrawerOpen(false)}
      >
        <form onSubmit={handleStartRun} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Рецепт / полуфабрикат</span>
            <select
              value={recipeId}
              onChange={(e) => setRecipeId(e.target.value)}
              className="w-full min-h-[44px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)]"
            >
              {data.recipes.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.title}
                </option>
              ))}
            </select>
          </label>
          <label className="block space-y-1 text-sm font-medium">
            <span>Плановый выход, г</span>
            <input
              type="number"
              min={100}
              step={100}
              value={plannedGrams}
              onChange={(e) => setPlannedGrams(Number(e.target.value) || 1000)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
            />
          </label>

          {bomPreview.length > 0 && (
            <div className="p-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] space-y-1.5 text-xs">
              <div className="font-semibold text-[var(--ink)]">Потребность в сырье:</div>
              {bomPreview.map((row, idx) => (
                <div key={idx} className="flex justify-between gap-2 tabular-nums">
                  <span className={row.shortage ? 'text-[var(--danger)]' : ''}>
                    {row.name} ({row.stockStr})
                  </span>
                  <span className="font-medium shrink-0">{row.neededStr}</span>
                </div>
              ))}
            </div>
          )}

          <button
            type="submit"
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
          >
            Создать задание
          </button>
        </form>
      </Drawer>

      <Drawer
        open={Boolean(completeTarget)}
        title={`Завершить выпуск: ${completeTarget?.recipeTitle || ''}`}
        subtitle="Фиксация фактического выхода и списание сырья"
        onClose={() => setCompleteTarget(null)}
      >
        <form onSubmit={handleCompleteRun} className="space-y-4">
          <label className="block space-y-1 text-sm font-medium">
            <span>Фактический выход, г</span>
            <input
              type="number"
              min={10}
              step={10}
              required
              value={actualGramsInput}
              onChange={(e) => setActualGramsInput(Number(e.target.value) || 100)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] tabular-nums"
            />
          </label>
          <label className="flex items-start gap-2.5 text-sm cursor-pointer">
            <input
              type="checkbox"
              checked={deductFefo}
              onChange={(e) => setDeductFefo(e.target.checked)}
              className="mt-1 accent-[var(--accent)]"
            />
            <span>
              Списать ингредиенты рецепта со склада по FEFO (с учётом плотности мл↔г)
            </span>
          </label>
          <button
            type="submit"
            disabled={completing}
            className="w-full min-h-[46px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium disabled:opacity-60"
          >
            {completing ? 'Проводим выпуск...' : 'Оприходовать выпуск на склад'}
          </button>
        </form>
      </Drawer>
    </div>
  );
}
