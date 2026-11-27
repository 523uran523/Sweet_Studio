import { doc, getDoc, serverTimestamp, setDoc, writeBatch } from 'firebase/firestore';
import { BusinessFormat } from '../types/domain';
import { db, handleFirestoreError, OperationType } from './client';

export const RECIPE_IMAGES = {
  berryCake: '/src/assets/images/recipe_berry_cake_1795687066009.jpg',
  pistachioRoll: '/src/assets/images/recipe_pistachio_roll_1795687066095.jpg',
  cupcakesVanilla: '/src/assets/images/recipe_cupcakes_vanilla_1795687066311.jpg',
  chocolateTart: '/src/assets/images/recipe_chocolate_tart_1795687066995.jpg',
  cheesecakeBasque: '/src/assets/images/recipe_cheesecake_basque_1795687068009.jpg',
};

function addDaysIso(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

export async function createWorkspaceWithOptionalDemo(params: {
  workspaceId: string;
  ownerId: string;
  ownerName: string;
  ownerEmail: string;
  workspaceName: string;
  slogan: string;
  businessFormat: BusinessFormat;
  themeIndex: number;
  withDemo: boolean;
}) {
  const {
    workspaceId,
    ownerId,
    ownerName,
    ownerEmail,
    workspaceName,
    slogan,
    businessFormat,
    themeIndex,
    withDemo,
  } = params;

  const hiddenModules =
    businessFormat === 'home'
      ? ['production', 'team', 'quality', 'marketing']
      : [];

  // Step 1: Create the root workspace document FIRST so subcollection security rules
  // (exists(/workspaces/{workspaceId}) & matchesWorkspaceOwner) pass on the server.
  try {
    await setDoc(doc(db, 'workspaces', workspaceId), {
      name: workspaceName.slice(0, 120),
      slogan: slogan.slice(0, 200),
      businessFormat,
      ownerId,
      memberUids: [ownerId],
      themeIndex,
      density: 'standard',
      pins: ['work', 'orders', 'recipes'],
      hiddenModules,
      demoLoaded: withDemo,
      plan: 'trial',
      subscriptionStatus: 'trialing',
      trialEndsAt: addDaysIso(14),
      graceEndsAt: addDaysIso(21),
      ...(ownerEmail ? { billingEmail: ownerEmail.slice(0, 200) } : {}),
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  } catch (err) {
    handleFirestoreError(err, OperationType.CREATE, `workspaces/${workspaceId}`);
  }

  // Step 2: Seed all subcollection documents in a batch (without extra `id` keys in data).
  const batch = writeBatch(db);
  const now = serverTimestamp();

  const locId = 'loc_main';
  batch.set(doc(db, 'workspaces', workspaceId, 'locations', locId), {
    workspaceId,
    ownerId,
    name: businessFormat === 'home' ? 'Домашняя кухня' : 'Основная студия',
    kind: 'kitchen',
    address: 'ул. Кондитерская, 12',
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  });

  batch.set(doc(db, 'workspaces', workspaceId, 'members', ownerId), {
    workspaceId,
    ownerId,
    uid: ownerId,
    name: (ownerName || 'Владелец').slice(0, 120),
    email: ownerEmail.slice(0, 200),
    role: 'owner',
    payType: 'percent',
    rateCents: 0,
    percent: 0,
    active: true,
    createdAt: now,
    updatedAt: now,
  });

  batch.set(doc(db, 'workspaces', workspaceId, 'accounts', 'acc_cash'), {
    workspaceId,
    ownerId,
    name: 'Касса студии',
    type: 'cash',
    balanceCents: withDemo ? 2450000 : 0,
    createdAt: now,
    updatedAt: now,
  });

  batch.set(doc(db, 'workspaces', workspaceId, 'accounts', 'acc_bank'), {
    workspaceId,
    ownerId,
    name: 'Расчётный счёт / Карта',
    type: 'bank',
    balanceCents: withDemo ? 8640000 : 0,
    createdAt: now,
    updatedAt: now,
  });

  if (withDemo) {
    const recipes = [
      {
        id: 'rec_berry_cake',
        title: 'Медовик с малиной и крем-чиз',
        category: 'Торты',
        version: 3,
        status: 'approved',
        yieldGrams: 2000,
        yieldPortions: 12,
        formSize: 'D18 · 2 кг',
        photoUrl: RECIPE_IMAGES.berryCake,
        ingredients: [
          { itemId: 'inv_cheese', name: 'Сливочный сыр Cremette', qty: 650, unit: 'г', lossPercent: 3, priceCents: 95000, priceUnit: 'за кг' },
          { itemId: 'inv_cream', name: 'Сливки 33%', qty: 400, unit: 'мл', lossPercent: 2, priceCents: 68000, priceUnit: 'за л' },
          { itemId: 'inv_berry', name: 'Малина свежая', qty: 350, unit: 'г', lossPercent: 8, priceCents: 140000, priceUnit: 'за кг' },
          { itemId: 'inv_flour', name: 'Мука пшеничная в/с', qty: 420, unit: 'г', lossPercent: 1, priceCents: 8500, priceUnit: 'за кг' },
          { itemId: 'inv_honey', name: 'Цветочный мёд', qty: 180, unit: 'г', lossPercent: 5, priceCents: 72000, priceUnit: 'за кг' },
        ],
        steps: [
          'Прогреть мёд со сливочным маслом на водяной бане до 65 °C, ввести соду и яйца.',
          'Выпечь 8 тонких коржей при 180 °C по 4 минуты, остудить на решётке.',
          'Взбить холодный сливочный сыр со сливками и сахарной пудрой до плотных пиков.',
          'Собрать торт в кольце, прослоить свежей малиной и стабилизировать 8 часов при +4 °C.',
        ],
        allergens: ['Молочные продукты', 'Глютен', 'Яйца', 'Мёд'],
        laborHours: 2.5,
        laborRateCents: 65000,
        packagingCents: 28000,
        overheadPercent: 12,
        marginPercent: 65,
        costCents: 245000,
        recommendedPriceCents: 450000,
        shelfLifeHours: 72,
        storageCondition: '+2…+4 °C в закрытой коробке',
        favorite: true,
      },
      {
        id: 'rec_pistachio_roll',
        title: 'Фисташковый меренговый рулет',
        category: 'Десерты',
        version: 2,
        status: 'approved',
        yieldGrams: 1100,
        yieldPortions: 8,
        formSize: 'Противень 30×40',
        photoUrl: RECIPE_IMAGES.pistachioRoll,
        ingredients: [
          { itemId: 'inv_pistachio', name: 'Фисташка дроблёная', qty: 140, unit: 'г', lossPercent: 2, priceCents: 290000, priceUnit: 'за кг' },
          { itemId: 'inv_cheese', name: 'Маскарпоне / сливочный сыр', qty: 350, unit: 'г', lossPercent: 2, priceCents: 95000, priceUnit: 'за кг' },
          { itemId: 'inv_berry', name: 'Малина свежая', qty: 220, unit: 'г', lossPercent: 5, priceCents: 140000, priceUnit: 'за кг' },
        ],
        steps: [
          'Взбить белки с сахарной пудрой и кукурузным крахмалом до устойчивой меренги.',
          'Отпечь корж 25 минут при 150 °C с посыпкой дроблёной фисташкой.',
          'Нанести крем из маскарпоне, выложить малину и аккуратно свернуть рулет.',
        ],
        allergens: ['Орехи (фисташка)', 'Молочные продукты', 'Яйца'],
        laborHours: 1.5,
        laborRateCents: 65000,
        packagingCents: 19000,
        overheadPercent: 10,
        marginPercent: 70,
        costCents: 148000,
        recommendedPriceCents: 290000,
        shelfLifeHours: 48,
        storageCondition: '+2…+4 °C',
        favorite: true,
      },
      {
        id: 'rec_cupcakes',
        title: 'Ванильные капкейки с инжиром (6 шт)',
        category: 'Капкейки',
        version: 1,
        status: 'approved',
        yieldGrams: 720,
        yieldPortions: 6,
        formSize: 'Коробка 6 шт',
        photoUrl: RECIPE_IMAGES.cupcakesVanilla,
        ingredients: [
          { itemId: 'inv_flour', name: 'Мука пшеничная в/с', qty: 210, unit: 'г', lossPercent: 1, priceCents: 8500, priceUnit: 'за кг' },
          { itemId: 'inv_cheese', name: 'Сливочный сыр Cremette', qty: 300, unit: 'г', lossPercent: 3, priceCents: 95000, priceUnit: 'за кг' },
          { itemId: 'inv_cream', name: 'Сливки 33%', qty: 150, unit: 'мл', lossPercent: 2, priceCents: 68000, priceUnit: 'за л' },
        ],
        steps: [
          'Замесить ванильное тесто на сливочном масле с натуральной ванилью.',
          'Выпекать 18 минут при 175 °C, вырезать сердцевину и наполнить ягодным конфи.',
          'Отсадить шапочки из крем-чиза и декорировать голубикой и инжиром.',
        ],
        allergens: ['Молочные продукты', 'Глютен', 'Яйца'],
        laborHours: 1.2,
        laborRateCents: 65000,
        packagingCents: 16000,
        overheadPercent: 10,
        marginPercent: 68,
        costCents: 112000,
        recommendedPriceCents: 240000,
        shelfLifeHours: 48,
        storageCondition: '+2…+5 °C',
        favorite: false,
      },
      {
        id: 'rec_choc_tart',
        title: 'Шоколадный тарт с ганашом',
        category: 'Десерты',
        version: 2,
        status: 'approved',
        yieldGrams: 1300,
        yieldPortions: 10,
        formSize: 'Кольцо D22',
        photoUrl: RECIPE_IMAGES.chocolateTart,
        ingredients: [
          { itemId: 'inv_choc', name: 'Шоколад тёмный 70%', qty: 360, unit: 'г', lossPercent: 3, priceCents: 185000, priceUnit: 'за кг' },
          { itemId: 'inv_cream', name: 'Сливки 33%', qty: 320, unit: 'мл', lossPercent: 2, priceCents: 68000, priceUnit: 'за л' },
          { itemId: 'inv_flour', name: 'Мука пшеничная в/с', qty: 240, unit: 'г', lossPercent: 1, priceCents: 8500, priceUnit: 'за кг' },
        ],
        steps: [
          'Приготовить шоколадное песочное тесто сабле, охладить 2 часа.',
          'Выпечь тарталетку в перфорированном кольце при 165 °C.',
          'Залить эмульсией тёмного шоколада и горячих сливок, украсить темперированной стружкой.',
        ],
        allergens: ['Молочные продукты', 'Глютен', 'Соевый лецитин'],
        laborHours: 1.8,
        laborRateCents: 65000,
        packagingCents: 22000,
        overheadPercent: 12,
        marginPercent: 60,
        costCents: 179000,
        recommendedPriceCents: 350000,
        shelfLifeHours: 96,
        storageCondition: '+4…+6 °C',
        favorite: false,
      },
      {
        id: 'rec_basque',
        title: 'Баскский чизкейк Сан-Себастьян',
        category: 'Торты',
        version: 1,
        status: 'review',
        yieldGrams: 1450,
        yieldPortions: 10,
        formSize: 'D20 высокая',
        photoUrl: RECIPE_IMAGES.cheesecakeBasque,
        ingredients: [
          { itemId: 'inv_cheese', name: 'Сливочный сыр Cremette', qty: 750, unit: 'г', lossPercent: 2, priceCents: 95000, priceUnit: 'за кг' },
          { itemId: 'inv_cream', name: 'Сливки 33%', qty: 380, unit: 'мл', lossPercent: 2, priceCents: 68000, priceUnit: 'за л' },
        ],
        steps: [
          'Пробить творожный сыр с сахаром на низкой скорости без лишнего воздуха.',
          'Поочерёдно ввести яйца комнатной температуры и сливки.',
          'Выпекать при 235 °C ровно 24 минуты до характерной карамельной корочки и дрожащей середины.',
        ],
        allergens: ['Молочные продукты', 'Яйца'],
        laborHours: 1.0,
        laborRateCents: 65000,
        packagingCents: 20000,
        overheadPercent: 10,
        marginPercent: 65,
        costCents: 162000,
        recommendedPriceCents: 320000,
        shelfLifeHours: 72,
        storageCondition: '+2…+4 °C',
        favorite: false,
      },
    ];

    for (const { id, ...rest } of recipes) {
      batch.set(doc(db, 'workspaces', workspaceId, 'recipes', id), {
        ...rest,
        workspaceId,
        ownerId,
        createdAt: now,
        updatedAt: now,
      });
    }

    const invItems = [
      { id: 'inv_cheese', name: 'Сливочный сыр Cremette', kind: 'raw', category: 'Молочные продукты', unit: 'кг', qtyOnHand: 2.4, minQty: 2.0, avgCostCents: 95000 },
      { id: 'inv_cream', name: 'Сливки 33%', kind: 'raw', category: 'Молочные продукты', unit: 'л', qtyOnHand: 3.5, minQty: 2.0, avgCostCents: 68000 },
      { id: 'inv_berry', name: 'Малина свежая', kind: 'raw', category: 'Ягоды', unit: 'кг', qtyOnHand: 0.9, minQty: 1.0, avgCostCents: 140000 },
      { id: 'inv_flour', name: 'Мука пшеничная в/с', kind: 'raw', category: 'Бакалея', unit: 'кг', qtyOnHand: 8.0, minQty: 3.0, avgCostCents: 8500 },
      { id: 'inv_pistachio', name: 'Фисташка дроблёная', kind: 'raw', category: 'Орехи', unit: 'кг', qtyOnHand: 0.65, minQty: 0.5, avgCostCents: 290000 },
      { id: 'inv_choc', name: 'Шоколад тёмный 70%', kind: 'raw', category: 'Шоколад', unit: 'кг', qtyOnHand: 2.2, minQty: 1.0, avgCostCents: 185000 },
      { id: 'inv_honey', name: 'Цветочный мёд', kind: 'raw', category: 'Бакалея', unit: 'кг', qtyOnHand: 1.5, minQty: 0.5, avgCostCents: 72000 },
      { id: 'inv_semi_cream', name: 'Крем-чиз база (полуфабрикат)', kind: 'semi', category: 'Полуфабрикаты', unit: 'кг', qtyOnHand: 2.7, minQty: 1.0, avgCostCents: 60000 },
      { id: 'inv_box_cake', name: 'Коробка для торта 26×26 см', kind: 'packaging', category: 'Упаковка', unit: 'шт', qtyOnHand: 18, minQty: 10, avgCostCents: 18000 },
    ];

    for (const { id, ...rest } of invItems) {
      batch.set(doc(db, 'workspaces', workspaceId, 'inventoryItems', id), {
        ...rest,
        workspaceId,
        ownerId,
        locationId: locId,
        createdAt: now,
        updatedAt: now,
      });
    }

    const lots = [
      { id: 'lot_cheese_1', itemId: 'inv_cheese', itemName: 'Сливочный сыр Cremette', lotCode: 'CREM-1120', unit: 'кг', initialQty: 2.0, remainingQty: 0.45, unitCostCents: 95000, expiresAt: addDaysIso(2), status: 'active' },
      { id: 'lot_cheese_2', itemId: 'inv_cheese', itemName: 'Сливочный сыр Cremette', lotCode: 'CREM-1125', unit: 'кг', initialQty: 2.0, remainingQty: 1.95, unitCostCents: 95000, expiresAt: addDaysIso(14), status: 'active' },
      { id: 'lot_berry_1', itemId: 'inv_berry', itemName: 'Малина свежая', lotCode: 'BRY-1126', unit: 'кг', initialQty: 1.5, remainingQty: 0.9, unitCostCents: 140000, expiresAt: addDaysIso(1), status: 'active' },
      { id: 'lot_semi_1', itemId: 'inv_semi_cream', itemName: 'Крем-чиз база (полуфабрикат)', lotCode: 'ПФ-032', unit: 'кг', initialQty: 3.0, remainingQty: 2.7, unitCostCents: 60000, expiresAt: addDaysIso(3), status: 'active' },
      { id: 'lot_flour_1', itemId: 'inv_flour', itemName: 'Мука пшеничная в/с', lotCode: 'FLR-1015', unit: 'кг', initialQty: 10.0, remainingQty: 8.0, unitCostCents: 8500, expiresAt: addDaysIso(45), status: 'active' },
    ];

    for (const { id, ...rest } of lots) {
      batch.set(doc(db, 'workspaces', workspaceId, 'stockLots', id), {
        ...rest,
        workspaceId,
        ownerId,
        locationId: locId,
        createdAt: now,
        updatedAt: now,
      });
    }

    batch.set(doc(db, 'workspaces', workspaceId, 'stockMovements', 'mov_1'), {
      workspaceId,
      ownerId,
      kind: 'production_out',
      itemId: 'inv_semi_cream',
      itemName: 'Крем-чиз база (полуфабрикат)',
      lotId: 'lot_semi_1',
      qty: 0.3,
      unit: 'кг',
      totalCents: 18000,
      reason: 'Сборка заказа №104 (Медовик)',
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'suppliers', 'sup_1'), {
      workspaceId,
      ownerId,
      name: 'Молочный дом',
      contactName: 'Алексей (менеджер)',
      phone: '+7 (999) 240-18-30',
      email: 'orders@milkhouse.example',
      category: 'Молочные продукты',
      debtCents: 0,
      createdAt: now,
      updatedAt: now,
    });
    batch.set(doc(db, 'workspaces', workspaceId, 'suppliers', 'sup_2'), {
      workspaceId,
      ownerId,
      name: 'КондитерБакалея',
      contactName: 'Отдел опта',
      phone: '+7 (999) 412-00-11',
      email: 'opt@bakaleya.example',
      category: 'Шоколад и сырьё',
      debtCents: 200000,
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'purchases', 'pur_1'), {
      workspaceId,
      ownerId,
      supplierId: 'sup_1',
      supplierName: 'Молочный дом',
      itemId: 'inv_cheese',
      itemName: 'Сливочный сыр Cremette',
      qty: 3,
      unit: 'кг',
      priceCents: 285000,
      deliveryCents: 30000,
      expectedDate: addDaysIso(1),
      status: 'ordered',
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'clients', 'cli_anna'), {
      workspaceId,
      ownerId,
      name: 'Анна Петрова',
      phone: '+7 (916) 334-12-89',
      email: 'anna.p@example.com',
      source: 'Telegram',
      address: 'ул. Садовая, 18, кв. 42',
      preferences: 'Меньше сахара, любит ягодную кислинку',
      allergens: 'Без грецких орехов',
      depositCents: 150000,
      ordersCount: 8,
      debtCents: 225000,
      favorite: true,
      createdAt: now,
      updatedAt: now,
    });
    batch.set(doc(db, 'workspaces', workspaceId, 'clients', 'cli_maria'), {
      workspaceId,
      ownerId,
      name: 'Мария Соколова',
      phone: '+7 (925) 881-44-09',
      email: 'maria.s@example.com',
      source: 'Рекомендация',
      address: 'пр. Мира, 102',
      preferences: 'Классическая ваниль и фисташка',
      allergens: 'Нет',
      depositCents: 0,
      ordersCount: 3,
      debtCents: 0,
      favorite: false,
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'leads', 'lead_1'), {
      workspaceId,
      ownerId,
      clientName: 'Елена Морозова',
      phone: '+7 (903) 510-77-12',
      requestText: 'Свадебный ягодный торт 3 кг на субботу',
      source: 'Telegram',
      budgetCents: 680000,
      nextStep: 'Согласовать начинку и предоплату',
      status: 'contacted',
      createdAt: now,
      updatedAt: now,
    });
    batch.set(doc(db, 'workspaces', workspaceId, 'leads', 'lead_2'), {
      workspaceId,
      ownerId,
      clientName: 'Ирина Волкова',
      phone: '+7 (915) 709-21-65',
      requestText: 'Две коробки ванильных капкейков на день рождения',
      source: 'Instagram',
      budgetCents: 480000,
      nextStep: 'Уточнить декор и время доставки',
      status: 'new',
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'orders', 'ord_104'), {
      workspaceId,
      ownerId,
      orderNumber: '№104',
      title: 'Медовик с малиной 2 кг',
      clientId: 'cli_anna',
      clientName: 'Анна Петрова',
      recipeId: 'rec_berry_cake',
      recipeTitle: 'Медовик с малиной и крем-чиз',
      weightGrams: 2000,
      priceCents: 450000,
      costCents: 245000,
      items: [
        {
          id: 'item_104_1',
          recipeId: 'rec_berry_cake',
          recipeTitle: 'Медовик с малиной и крем-чиз',
          qty: 1,
          weightGrams: 2000,
          priceCents: 450000,
          costCents: 245000,
        },
      ],
      prepaymentCents: 225000,
      paidCents: 225000,
      discountCents: 0,
      status: 'in_progress',
      dueDate: addDaysIso(1),
      assigneeName: ownerName || 'Владелец',
      locationName: 'Основная студия',
      deliveryAddress: 'ул. Садовая, 18, кв. 42',
      wishes: 'Надпись «С днём рождения!» белым шоколадом',
      allergens: 'Без грецких орехов',
      favorite: true,
      createdAt: now,
      updatedAt: now,
    });
    batch.set(doc(db, 'workspaces', workspaceId, 'orders', 'ord_105'), {
      workspaceId,
      ownerId,
      orderNumber: '№105',
      title: 'Набор: капкейки + медовик мини',
      clientId: 'cli_maria',
      clientName: 'Мария Соколова',
      recipeId: 'rec_cupcakes',
      recipeTitle: 'Ванильные капкейки + мини-медовик',
      weightGrams: 1720,
      priceCents: 240000,
      costCents: 112000,
      items: [
        {
          id: 'item_105_1',
          recipeId: 'rec_cupcakes',
          recipeTitle: 'Ванильные капкейки с инжиром (6 шт)',
          qty: 1,
          weightGrams: 720,
          priceCents: 140000,
          costCents: 62000,
        },
        {
          id: 'item_105_2',
          recipeId: 'rec_berry_cake',
          recipeTitle: 'Медовик с малиной (мини 1 кг)',
          qty: 1,
          weightGrams: 1000,
          priceCents: 100000,
          costCents: 50000,
        },
      ],
      prepaymentCents: 120000,
      paidCents: 240000,
      discountCents: 0,
      status: 'ready',
      dueDate: addDaysIso(0),
      assigneeName: ownerName || 'Владелец',
      locationName: 'Основная студия',
      deliveryAddress: 'Самовывоз',
      wishes: 'Перевязать атласной лентой',
      allergens: '',
      favorite: false,
      createdAt: now,
      updatedAt: now,
    });

    const workItems = [
      { id: 'wi_1', type: 'order', sourceId: 'ord_104', title: 'Сборка и выравнивание торта №104', assigneeName: ownerName || 'Владелец', locationName: 'Основная студия', dueDate: addDaysIso(1), priority: 'high', stage: 'in_progress', tags: ['торт', 'срочно'] },
      { id: 'wi_2', type: 'production', sourceId: 'run_1', title: 'Замес базы крем-чиз 3 кг', assigneeName: ownerName || 'Владелец', locationName: 'Основная студия', dueDate: addDaysIso(0), priority: 'normal', stage: 'queue', tags: ['полуфабрикат'] },
      { id: 'wi_3', type: 'purchase', sourceId: 'pur_1', title: 'Приёмка сливочного сыра (Молочный дом)', assigneeName: ownerName || 'Владелец', locationName: 'Основная студия', dueDate: addDaysIso(1), priority: 'normal', stage: 'queue', tags: ['закупка'] },
      { id: 'wi_4', type: 'promo', sourceId: 'post_1', title: 'Рилс и разрез фисташкового рулета', assigneeName: ownerName || 'Владелец', locationName: 'Основная студия', dueDate: addDaysIso(2), priority: 'low', stage: 'queue', tags: ['контент'] },
      { id: 'wi_5', type: 'order', sourceId: 'ord_105', title: 'Упаковка и выдача капкейков №105', assigneeName: ownerName || 'Владелец', locationName: 'Основная студия', dueDate: addDaysIso(0), priority: 'high', stage: 'done', tags: ['выдача'] },
    ];
    for (const { id, ...rest } of workItems) {
      batch.set(doc(db, 'workspaces', workspaceId, 'workItems', id), {
        ...rest,
        workspaceId,
        ownerId,
        createdAt: now,
        updatedAt: now,
      });
    }

    batch.set(doc(db, 'workspaces', workspaceId, 'productionRuns', 'run_1'), {
      workspaceId,
      ownerId,
      recipeId: 'rec_berry_cake',
      recipeTitle: 'Крем-чиз база (партия №033)',
      plannedGrams: 3000,
      locationName: 'Основная студия',
      assigneeName: ownerName || 'Владелец',
      totalCostCents: 180000,
      status: 'in_progress',
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'transactions', 'tx_1'), {
      workspaceId,
      ownerId,
      kind: 'income',
      category: 'Предоплата за заказ',
      amountCents: 225000,
      accountId: 'acc_bank',
      accountName: 'Расчётный счёт / Карта',
      orderId: 'ord_104',
      note: 'Аванс 50% по заказу №104 (Анна Петрова)',
      occurredAt: addDaysIso(-1),
      createdAt: now,
      updatedAt: now,
    });
    batch.set(doc(db, 'workspaces', workspaceId, 'transactions', 'tx_2'), {
      workspaceId,
      ownerId,
      kind: 'income',
      category: 'Оплата заказа',
      amountCents: 240000,
      accountId: 'acc_cash',
      accountName: 'Касса студии',
      orderId: 'ord_105',
      note: 'Полная оплата заказа №105 (Мария Соколова)',
      occurredAt: addDaysIso(0),
      createdAt: now,
      updatedAt: now,
    });
    batch.set(doc(db, 'workspaces', workspaceId, 'transactions', 'tx_3'), {
      workspaceId,
      ownerId,
      kind: 'expense',
      category: 'Закупка ингредиентов',
      amountCents: 198000,
      accountId: 'acc_bank',
      accountName: 'Расчётный счёт / Карта',
      note: 'Ягоды, малина и упаковка на неделю',
      occurredAt: addDaysIso(-2),
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'recurringPayments', 'rp_1'), {
      workspaceId,
      ownerId,
      title: 'Аренда кондитерской студии',
      amountCents: 3500000,
      cadence: 'monthly',
      nextDueDate: addDaysIso(5),
      category: 'Аренда',
      active: true,
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'coupons', 'cup_104'), {
      workspaceId,
      ownerId,
      code: 'SWEET-104',
      clientId: 'cli_anna',
      clientName: 'Анна Петрова',
      discountType: 'percent',
      discountValue: 10,
      minOrderCents: 250000,
      expiresAt: addDaysIso(30),
      status: 'active',
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'complaints', 'cmp_1'), {
      workspaceId,
      ownerId,
      title: 'Проверка сладости медовых коржей по отзыву',
      orderId: 'ord_104',
      severity: 'low',
      status: 'investigating',
      responsibleName: ownerName || 'Владелец',
      resolution: 'Снизить сахар в пропитке на 10% в следующей версии v4',
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'contentPosts', 'post_1'), {
      workspaceId,
      ownerId,
      channel: 'Telegram',
      channelUrl: 'https://t.me/sweet_studio_atelier',
      title: 'Подборка осенних медовиков и фисташковых рулетов',
      scheduledDate: addDaysIso(2),
      status: 'scheduled',
      budgetCents: 150000,
      createdAt: now,
      updatedAt: now,
    });

    batch.set(doc(db, 'workspaces', workspaceId, 'timeEntries', 'te_1'), {
      workspaceId,
      ownerId,
      employeeId: ownerId,
      employeeName: ownerName || 'Владелец',
      orderTitle: 'Медовик с малиной №104',
      startedAt: new Date(Date.now() - 95 * 60000).toISOString(),
      endedAt: new Date().toISOString(),
      minutes: 95,
      createdAt: now,
      updatedAt: now,
    });
  }

  try {
    await batch.commit();
  } catch (err) {
    handleFirestoreError(
      err,
      OperationType.WRITE,
      `workspaces/${workspaceId}/subcollections`,
    );
  }

  // Step 3: Link activeWorkspaceId on user profile LAST so App.tsx's user listener
  // only subscribes after the workspace and all initial data are persisted on server.
  const userRef = doc(db, 'users', ownerId);
  try {
    const userSnap = await getDoc(userRef);
    const userBatch = writeBatch(db);
    if (userSnap.exists()) {
      userBatch.update(userRef, {
        email: ownerEmail.slice(0, 200),
        displayName: (ownerName || 'Кондитер').slice(0, 120),
        activeWorkspaceId: workspaceId,
        updatedAt: serverTimestamp(),
      });
    } else {
      userBatch.set(userRef, {
        uid: ownerId,
        email: ownerEmail.slice(0, 200),
        displayName: (ownerName || 'Кондитер').slice(0, 120),
        activeWorkspaceId: workspaceId,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    }
    await userBatch.commit();
  } catch (err) {
    handleFirestoreError(err, OperationType.WRITE, `users/${ownerId}`);
  }
}
