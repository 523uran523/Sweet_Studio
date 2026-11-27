import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sweet_studio_personal/core/media_store.dart';
import 'package:sweet_studio_personal/data/app_database.dart';
import 'package:sweet_studio_personal/data/draft_storage.dart';
import 'package:sweet_studio_personal/main.dart';
import 'package:sweet_studio_personal/state/studio_store.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('onboarding -> clean workspace -> shell navigation at 1.5x text scale',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final tmpDir = await Directory.systemTemp.createTemp('ss_widget_test_');
    addTearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    final db = await AppDatabase.openAtPath(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final store = StudioStore(
      db: db,
      mediaStore: MediaStore(tmpDir),
      drafts: DraftStorage(),
    );
    await store.loadAll();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(412, 915),
          textScaler: TextScaler.linear(1.5),
        ),
        child: SweetStudioPersonalApp(store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SweetStudio Personal'), findsOneWidget);
    expect(find.text('Начать с чистой базы'), findsOneWidget);

    await tester.ensureVisible(find.text('Начать с чистой базы'));
    await tester.tap(find.text('Начать с чистой базы'));
    await tester.pumpAndSettle();

    expect(find.text('Денежный поток'), findsOneWidget);
    expect(find.text('Заказы'), findsOneWidget);

    await tester.tap(find.text('Заказы').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Заказов пока нет'), findsOneWidget);

    await tester.tap(find.text('Рецепты').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Техкарты не найдены'), findsOneWidget);
  });
}
