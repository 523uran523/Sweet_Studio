import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sweet_studio_personal/data/app_database.dart';
import 'package:sweet_studio_personal/data/models.dart';

void main() {
  sqfliteFfiInit();

  Future<AppDatabase> openTestDb() async {
    return AppDatabase.openAtPath(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  }

  test('clean vs demo seed & reset preserves integrity', () async {
    final db = await openTestDb();
    addTearDown(db.close);

    expect(await db.checkIntegrity(), isEmpty);
    expect(await db.getRecipes(), isEmpty);

    await db.seedDemoData(todayIso: '2026-05-01');
    final prof = await db.getProfile();
    expect(prof.isDemoMode, isTrue);
    expect((await db.getRecipes()).length, 3);
    expect((await db.getOrders()).length, 2);

    await db.clearAllBusinessData(isDemoMode: false);
    final profAfter = await db.getProfile();
    expect(profAfter.isDemoMode, isFalse);
    expect(await db.getRecipes(), isEmpty);
    expect((await db.getAccounts()).length, 1);
    expect(await db.checkIntegrity(), isEmpty);
  });

  test('multi-item order preserves price snapshot, deposit, refund, and atomic FEFO', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    await db.ensureDefaultCashAccount();

    await db.upsertInventoryItem(
      const InventoryItem(
        id: 'inv_choc',
        name: 'Шоколад',
        kind: InventoryKind.raw,
        unit: 'г',
        qtyOnHand: 0,
        avgCostCents: 100,
      ),
    );
    // Expired lot (must be skipped by FEFO!)
    await db.addStockLotReceipt(
      itemId: 'inv_choc',
      qty: 500,
      unit: 'г',
      totalCostCents: 50000,
      expiresAt: '2026-04-01',
    );
    // Active non-expired lot: only 300 g
    await db.addStockLotReceipt(
      itemId: 'inv_choc',
      qty: 300,
      unit: 'г',
      totalCostCents: 30000,
      expiresAt: '2026-06-01',
    );

    const recipe = Recipe(
      id: 'rec_1',
      title: 'Брауни',
      category: 'Десерты',
      yieldGrams: 1000,
      ingredients: [
        RecipeIngredientLine(
          itemId: 'inv_choc',
          name: 'Шоколад',
          qty: 400,
          unit: 'г',
          priceCents: 100000,
          priceUnit: 'за кг',
        ),
      ],
      costCents: 80000,
      recommendedPriceCents: 160000,
    );
    await db.upsertRecipe(recipe);

    await db.upsertClient(
      const Client(
        id: 'cli_1',
        name: 'Ольга',
        depositCents: 50000,
      ),
    );

    await db.upsertOrder(
      const Order(
        id: 'ord_1',
        orderNumber: '№1',
        title: 'Брауни',
        clientId: 'cli_1',
        clientName: 'Ольга',
        items: [
          OrderItem(
            id: 'oi_1',
            recipeId: 'rec_1',
            recipeTitle: 'Брауни',
            qty: 1,
            weightGrams: 1000,
            priceCents: 160000,
            costCents: 80000,
          ),
        ],
        priceCents: 160000,
        costCents: 80000,
        createdAt: '2026-05-01T10:00:00',
      ),
    );

    // Update recipe price afterward — order price snapshot stays 160000!
    await db.upsertRecipe(recipe.copyWith(recommendedPriceCents: 240000));
    final fetchedOrd = (await db.getOrders()).first;
    expect(fetchedOrd.priceCents, 160000);

    // FEFO deduction fails cleanly because expired lot (500g) cannot be used and active lot is 300g < 400g!
    await expectLater(
      () => db.deductOrderStockFefo('ord_1', todayIso: '2026-05-01'),
      throwsA(isA<StateError>()),
    );
    expect((await db.getOrders()).first.stockDeducted, isFalse);

    // Add 200 g fresh lot -> total non-expired = 500 g >= 400 g -> succeeds!
    await db.addStockLotReceipt(
      itemId: 'inv_choc',
      qty: 200,
      unit: 'г',
      totalCostCents: 22000,
      expiresAt: '2026-07-01',
    );
    await db.deductOrderStockFefo('ord_1', todayIso: '2026-05-01');
    expect((await db.getOrders()).first.stockDeducted, isTrue);

    // Double deduction blocked
    await expectLater(
      () => db.deductOrderStockFefo('ord_1', todayIso: '2026-05-01'),
      throwsA(isA<StateError>()),
    );

    // Pay with deposit + cash + refund
    await db.payOrderWithDeposit(orderId: 'ord_1');
    expect((await db.getClients()).first.depositCents, 0);
    expect((await db.getOrders()).first.paidCents, 50000);

    await db.recordOrderPayment(
      orderId: 'ord_1',
      accountId: 'acc_cash',
      amountCents: 110000,
    );
    expect((await db.getOrders()).first.balanceDueCents, 0);
    expect((await db.getAccounts()).first.balanceCents, 110000);

    await db.refundOrderPayment(
      orderId: 'ord_1',
      accountId: 'acc_cash',
      amountCents: 20000,
    );
    expect((await db.getOrders()).first.paidCents, 140000);
    expect((await db.getAccounts()).first.balanceCents, 90000);
  });

  test('purchase receipt, production run & safe reversal guard, and tx reversal idempotency', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    await db.ensureDefaultCashAccount();

    await db.addMoneyTransaction(
      kind: TransactionKind.income,
      category: 'Стартовый капитал',
      amountCents: 200000,
      accountId: 'acc_cash',
    );
    final txId = (await db.getMoneyTransactions()).first.id;
    await db.reverseMoneyTransaction(txId);
    expect((await db.getAccounts()).first.balanceCents, 0);
    // Double reversal blocked
    await expectLater(
      () => db.reverseMoneyTransaction(txId),
      throwsA(isA<StateError>()),
    );

    // Purchase without double expense
    await db.upsertPurchase(
      const Purchase(
        id: 'pur_1',
        supplierName: 'База',
        itemName: 'Мука',
        qty: 2,
        unit: 'кг',
        priceCents: 20000,
        deliveryCents: 5000,
      ),
    );
    await db.receivePurchase(
      purchaseId: 'pur_1',
      accountId: 'acc_cash',
      payFromAccount: true,
    );
    final flour = (await db.getInventoryItems()).first;
    expect(flour.qtyOnHand, closeTo(2, 1e-6));
    expect((await db.getAccounts()).first.balanceCents, -25000);

    // Production run creates finished stock
    await db.upsertRecipe(
      Recipe(
        id: 'rec_bread',
        title: 'Корж бисквитный',
        category: 'Полуфабрикаты',
        yieldGrams: 1000,
        ingredients: [
          RecipeIngredientLine(
            itemId: flour.id,
            name: 'Мука',
            qty: 500,
            unit: 'г',
            priceCents: 12500,
            priceUnit: 'за кг',
          ),
        ],
        costCents: 12500,
        recommendedPriceCents: 25000,
      ),
    );

    final run = await db.completeProductionRun(
      recipeId: 'rec_bread',
      plannedGrams: 1000,
      actualGrams: 950,
      todayIso: '2026-05-01',
    );
    final flourAfter = (await db.getInventoryItems())
        .firstWhere((e) => e.id == flour.id);
    expect(flourAfter.qtyOnHand, closeTo(1.5, 1e-6));

    // Reversal succeeds while output lot is untouched
    await db.reverseProductionRun(run.id);
    final flourRestored = (await db.getInventoryItems())
        .firstWhere((e) => e.id == flour.id);
    expect(flourRestored.qtyOnHand, closeTo(2.0, 1e-6));
    expect((await db.getProductionRuns()).first.status, ProductionStatus.reversed);
  });
}
