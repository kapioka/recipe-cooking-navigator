import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/main.dart';

void main() {
  late String schemaSource;
  late String recipeSource;

  setUpAll(() async {
    schemaSource = await File('schemas/recipe-v1.schema.json').readAsString();
    recipeSource = await File('examples/recipe-example.json').readAsString();
  });

  testWidgets('imports a recipe, lists it, and opens its details', (
    tester,
  ) async {
    final controller = RecipeLibraryController(
      _MemoryRecipeDocumentStore(),
      RecipeValidator.fromSchemaString(schemaSource),
      () async => recipeSource,
    );
    await controller.load();

    await tester.pumpWidget(RecipeCookingNavigatorApp(controller: controller));

    expect(find.text('まだレシピがありません'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import_recipe_button')));
    await tester.pumpAndSettle();

    expect(find.text('豚の生姜焼き'), findsOneWidget);
    expect(find.textContaining('2人分'), findsOneWidget);

    await tester.tap(find.text('豚の生姜焼き'));
    await tester.pumpAndSettle();

    expect(find.text('レシピ詳細'), findsOneWidget);
    expect(find.text('材料'), findsOneWidget);
    expect(find.text('豚こま切れ肉'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('全体工程'), 300);
    expect(find.text('全体工程'), findsOneWidget);
  });
}

class _MemoryRecipeDocumentStore implements RecipeDocumentStore {
  final List<Map<String, dynamic>> documents = [];

  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => [...documents];

  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    documents.add(document);
    return StoreRecipeResult.added;
  }
}
