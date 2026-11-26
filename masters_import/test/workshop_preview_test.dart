import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/inventory_composition.dart';
import 'package:masters/features/inventory/inventory_composition_screen.dart';
import 'package:masters/features/jobs/cost_calculator_screen.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The «Применить»/«Сохранить» button in the calculator's navigation bar.
CupertinoButton _applyButton(WidgetTester tester) =>
    tester.widget<CupertinoButton>(
      find.ancestor(
        of: find.text('Применить'),
        matching: find.byType(CupertinoButton),
      ).first,
    );

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('calculator opens and lets the user select pricing mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    late AppDatabase db;
    late MastersStore store;
    await tester.runAsync(() async {
      db = await AppDatabase.open(path: inMemoryDatabasePath);
      store = MastersStore(db, await SettingsController.load());
      await store.load();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const CupertinoApp(
          home: CostCalculatorScreen(initialMaterialsCents: 10000),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Target the pricing segmented control itself so we tap its «Маржа»
    // segment, not the «Маржа» label in the summary card, and make sure the
    // segment is actually on-screen before tapping it.
    final segmented = find.byWidgetPredicate(
      (widget) => widget is CupertinoSlidingSegmentedControl,
    );
    final marginSegment = find.descendant(
      of: segmented,
      matching: find.text('Маржа'),
    );
    await tester.scrollUntilVisible(
      marginSegment,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(marginSegment);
    await tester.pump();
    expect(find.text('Доля прибыли в цене'), findsOneWidget);

    // Resource loss input: it must exist, default to 0, reject 100% with an
    // error and disable «Применить». Bring it into view first (it sits above
    // the pricing controls), then restore it to 0 before the defect check.
    final lossField = find.byWidgetPredicate(
      (widget) =>
          widget is CupertinoTextField && widget.placeholder == 'Потери, %',
    );
    await tester.scrollUntilVisible(
      lossField,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(lossField, findsOneWidget);
    expect(
      tester.widget<CupertinoTextField>(lossField).controller?.text,
      '0',
    );
    await tester.enterText(lossField, '100');
    await tester.pump();
    expect(
      find.textContaining('Укажите количество и потери'),
      findsOneWidget,
    );
    expect(_applyButton(tester).onPressed, isNull);
    await tester.enterText(lossField, '0');
    await tester.pump();

    // Finished-product defect input must be on-screen before entering a value.
    final defectLabel = find.text('Брак готовых изделий');
    await tester.scrollUntilVisible(
      defectLabel,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final defectRow = find.ancestor(
      of: defectLabel,
      matching: find.byType(Row),
    ).first;
    await tester.enterText(
      find.descendant(of: defectRow, matching: find.byType(CupertinoTextField)),
      '100',
    );
    await tester.pump();
    expect(find.textContaining('Укажите процент брака'), findsOneWidget);
    expect(_applyButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    await tester.runAsync(db.close);
  });

  testWidgets(
    'batch preview combines repeated materials without changing stock',
    (tester) async {
      late AppDatabase db;
      late MastersStore store;
      late String productId;
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        db = await AppDatabase.open(path: inMemoryDatabasePath);
        store = MastersStore(db, await SettingsController.load());
        await store.load();
        final wood = await store.createInventoryItem(
          name: 'Доска',
          unit: 'м',
          stockQty: 2,
        );
        final product = await store.createInventoryItem(
          name: 'Полка',
          sellPriceCents: 10000,
        );
        productId = product.id;
        await store.saveItemComposition(product.id, [
          InventoryCompositionLine(
            id: '',
            itemId: product.id,
            componentId: wood.id,
            qty: 0.5,
            priceCents: 1000,
          ),
          InventoryCompositionLine(
            id: '',
            itemId: product.id,
            componentId: wood.id,
            qty: 0.75,
            priceCents: 1000,
          ),
        ]);
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: CupertinoApp(
            home: InventoryCompositionScreen(itemId: productId),
          ),
        ),
      );
      expect(find.textContaining('нужно 1.25 м'), findsOneWidget);
      final quantity = find.byType(CupertinoTextField).first;
      await tester.enterText(quantity, '2');
      await tester.pump();
      expect(find.textContaining('не хватает 0.5 м'), findsOneWidget);
      expect(
        store.inventoryItems
            .firstWhere((item) => item.name == 'Доска')
            .stockQty,
        2,
      );
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      await tester.runAsync(db.close);
    },
  );

  testWidgets(
    'batch preview estimates max whole units from combined stock',
    (tester) async {
      late AppDatabase db;
      late MastersStore store;
      late String productId;
      late String woodId;
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        db = await AppDatabase.open(path: inMemoryDatabasePath);
        store = MastersStore(db, await SettingsController.load());
        await store.load();
        final wood = await store.createInventoryItem(
          name: 'Доска',
          unit: 'м',
          stockQty: 2,
        );
        woodId = wood.id;
        final product = await store.createInventoryItem(
          name: 'Полка',
          sellPriceCents: 10000,
        );
        productId = product.id;
        await store.saveItemComposition(product.id, [
          InventoryCompositionLine(
            id: '',
            itemId: product.id,
            componentId: wood.id,
            qty: 0.5,
            priceCents: 1000,
          ),
          InventoryCompositionLine(
            id: '',
            itemId: product.id,
            componentId: wood.id,
            qty: 0.75,
            priceCents: 1000,
          ),
        ]);
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: CupertinoApp(
            home: InventoryCompositionScreen(itemId: productId),
          ),
        ),
      );
      // 0.5 + 0.75 = 1.25 per finished item, floor(2 / 1.25) = 1. Without
      // aggregating the duplicate rows the minimum would wrongly be 2.
      expect(find.textContaining('Максимум по складу: 1 шт'), findsOneWidget);
      expect(find.textContaining('Максимум по складу: 2 шт'), findsNothing);
      // Preview only: the tracked stock must be untouched.
      expect(
        store.inventoryItems.firstWhere((item) => item.id == woodId).stockQty,
        2,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      await tester.runAsync(db.close);
    },
  );
}
