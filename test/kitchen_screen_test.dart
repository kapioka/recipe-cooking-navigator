import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/data/kitchen_timer_file_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/ui/kitchen_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ready preset can be reset to 00:00 and set again', (
    tester,
  ) async {
    late Directory directory;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('kitchen-screen-test-');
    });
    addTearDown(() async {
      await directory.delete(recursive: true);
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const kitchenChannel = MethodChannel('recipe/kitchen');
    const notificationChannel = MethodChannel('recipe/kitchen_notifications');
    messenger.setMockMethodCallHandler(kitchenChannel, (call) async {
      return switch (call.method) {
        'elapsedRealtime' => 100000,
        'bootCount' => 1,
        'setAwake' => null,
        _ => throw MissingPluginException(call.method),
      };
    });
    messenger.setMockMethodCallHandler(notificationChannel, (call) async {
      return <String, Object>{
        'notificationPermission': true,
        'channelEnabled': true,
        'exactAlarmAllowed': true,
        'soundEnabled': true,
        'vibrationEnabled': true,
        'scheduledCount': 0,
      };
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(kitchenChannel, null);
      messenger.setMockMethodCallHandler(notificationChannel, null);
    });

    late RecipeLibraryController controller;
    await tester.runAsync(() async {
      controller = RecipeLibraryController(
        FileRecipeDocumentStore(File('${directory.path}/recipes.json')),
        FileRecipeTagStore(File('${directory.path}/tags.json')),
        RecipeValidator.fromSchemaString(
          await File('schemas/recipe-v2.schema.json').readAsString(),
        ),
        () async => null,
      );
      await controller.load();
    });
    final timerStore = _MemoryTimerStore();
    await tester.pumpWidget(
      MaterialApp(
        home: KitchenScreen(library: controller, timerStore: timerStore),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('timer_preset_10m')))
          .onPressed,
      isNotNull,
    );

    final timerTop = tester.getTopLeft(
      find.byKey(const Key('main_kitchen_timer')),
    );
    final saveGate = Completer<void>();
    timerStore.saveGate = saveGate;
    await tester.tap(find.byKey(const Key('timer_preset_10m')));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('main_kitchen_timer'))),
      timerTop,
    );
    saveGate.complete();
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('main_timer_digits'))).data,
      '10:00',
    );
    await tester.tap(find.byKey(const Key('timer_preset_1m')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('timer_preset_10s')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('main_timer_digits'))).data,
      '11:10',
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('reset_main_timer')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('reset_main_timer')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('main_timer_digits'))).data,
      '00:00',
    );
    await tester.tap(find.byKey(const Key('timer_preset_10s')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('main_timer_digits'))).data,
      '00:10',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _MemoryTimerStore extends KitchenTimerFileStore {
  _MemoryTimerStore() : super(File('unused'));

  KitchenTimerSnapshot? snapshot;
  Completer<void>? saveGate;

  @override
  Future<KitchenTimerSnapshot?> load() async => snapshot;

  @override
  Future<void> save(KitchenTimerSnapshot next) async {
    await saveGate?.future;
    saveGate = null;
    snapshot = next;
  }
}
