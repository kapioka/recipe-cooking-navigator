import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'application/recipe_library_controller.dart';
import 'data/recipe_document_store.dart';
import 'domain/recipe_validator.dart';
import 'platform/recipe_file_picker.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final schemaSource = await rootBundle.loadString(
    'schemas/recipe-v1.schema.json',
  );
  final supportDirectory = await getApplicationSupportDirectory();
  final controller = RecipeLibraryController(
    FileRecipeDocumentStore(File('${supportDirectory.path}/recipes-v1.json')),
    RecipeValidator.fromSchemaString(schemaSource),
    pickRecipeSource,
  );
  await controller.load();

  runApp(RecipeCookingNavigatorApp(controller: controller));
}

class RecipeCookingNavigatorApp extends StatelessWidget {
  const RecipeCookingNavigatorApp({required this.controller, super.key});

  final RecipeLibraryController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recipe Cooking Navigator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE56A3D)),
        useMaterial3: true,
      ),
      home: HomeScreen(controller: controller),
    );
  }
}
