import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_cooking_navigator/application/recipe_library_controller.dart';
import 'package:recipe_cooking_navigator/data/recipe_document_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_photo_store.dart';
import 'package:recipe_cooking_navigator/data/recipe_tag_store.dart';
import 'package:recipe_cooking_navigator/domain/recipe_validator.dart';
import 'package:recipe_cooking_navigator/ui/home_screen.dart';
import 'package:recipe_cooking_navigator/ui/recipe_photo_avatar.dart';
import 'package:recipe_cooking_navigator/ui/recipe_photo_crop_screen.dart';

const id = 'ginger-pork-001';
Future<ui.Image> coloredImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 40, 40),
    Paint()..color = const Color(0xffff0000),
  );
  canvas.drawRect(
    const Rect.fromLTWH(40, 0, 40, 40),
    Paint()..color = const Color(0xff0000ff),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(80, 40);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> pngFor(ui.Image image) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

class _Documents implements RecipeDocumentStore, RecipeDocumentDeletionStore {
  _Documents(this.docs);
  final List<Map<String, dynamic>> docs;
  @override
  Future<List<Map<String, dynamic>>> loadDocuments() async => docs;
  @override
  Future<StoreRecipeResult> saveDocument(Map<String, dynamic> document) async {
    docs.add(document);
    return StoreRecipeResult.added;
  }

  @override
  Future<void> deleteRecipe(String recipeId) async {
    docs.removeWhere((d) => (d['recipe'] as Map)['id'] == recipeId);
  }
}

class _Tags implements RecipeTagStore {
  @override
  Future<Map<String, List<String>>> loadTags() async => {};
  @override
  Future<void> saveTags(String recipeId, List<String> tags) async {}
}

class _Photos extends MemoryRecipePhotoStore {
  bool failRead = false, failSave = false;
  Completer<void>? pending;
  @override
  Future<Uint8List?> read(String recipeId) async {
    if (failRead) throw const FileSystemException('test');
    return super.read(recipeId);
  }

  @override
  Future<void> save(String recipeId, Uint8List? png) async {
    if (pending != null) await pending!.future;
    if (failSave) throw const FileSystemException('test');
    await super.save(recipeId, png);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String schema, source;
  late Uint8List sourcePng, croppedPng;
  setUpAll(() async {
    schema = await File('schemas/recipe-v2.schema.json').readAsString();
    source = await File('examples/recipe-example.json').readAsString();
    final image = await coloredImage();
    try {
      sourcePng = await pngFor(image);
      croppedPng = await renderRoundRecipePhoto(
        image,
        recipePhotoCrop(const Size(80, 40), const Offset(.25, .5), 1),
      );
    } finally {
      image.dispose();
    }
  });

  RecipeLibraryController library(
    RecipePhotoStore photos, [
    _Documents? docs,
  ]) => RecipeLibraryController(
    docs ?? _Documents([jsonDecode(source) as Map<String, dynamic>]),
    _Tags(),
    RecipeValidator.fromSchemaString(schema),
    () async => null,
    photoStore: photos,
  );

  test('crop stays inside wide/tall photos and clamps zoom and center', () {
    expect(
      recipePhotoCrop(const Size(80, 40), const Offset(.5, .5), 1),
      const Rect.fromLTWH(20, 0, 40, 40),
    );
    expect(
      recipePhotoCrop(const Size(40, 80), const Offset(-1, 2), 2),
      const Rect.fromLTWH(0, 60, 20, 20),
    );
    expect(
      recipePhotoCrop(const Size(80, 40), const Offset(2, -1), 20),
      const Rect.fromLTWH(70, 0, 10, 10),
    );
  });

  test(
    'saved circle has transparent corners and selected source pixels',
    () async {
      final decoded = await decodeRecipePhoto(croppedPng);
      try {
        expect(decoded.width, 512);
        expect(decoded.height, 512);
        final rgba = (await decoded.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(rgba.getUint8(3), 0);
        expect(rgba.getUint8((511 * 512 + 511) * 4 + 3), 0);
        final center = (256 * 512 + 256) * 4;
        expect(rgba.getUint8(center), 255); // red half selected
        expect(rgba.getUint8(center + 2), 0);
        expect(rgba.getUint8(center + 3), 255);
      } finally {
        decoded.dispose();
      }
    },
  );

  test('oversized and invalid source images are rejected', () async {
    await expectLater(
      decodeRecipePhoto(Uint8List(30 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
    await expectLater(
      decodeRecipePhoto(Uint8List.fromList([1, 2, 3])),
      throwsA(anything),
    );
  });

  test(
    'disk replacement/reopen and removal use safe recipe filenames',
    () async {
      final dir = await Directory.systemTemp.createTemp('rcn-photo-test-');
      try {
        final store = FileRecipePhotoStore(dir);
        const unusualId = '../../recipe/日本語';
        await store.save(unusualId, sourcePng);
        await store.save(unusualId, croppedPng);
        expect(await FileRecipePhotoStore(dir).read(unusualId), croppedPng);
        final entries = await dir.list().toList();
        expect(entries, hasLength(1));
        expect(
          entries.single.uri.pathSegments.last,
          matches(r'^[0-9a-f]{64}\.png$'),
        );
        await store.save(unusualId, null);
        expect(await store.read(unusualId), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'invalid replacement preserves disk photo; interrupted save recovers',
    () async {
      final dir = await Directory.systemTemp.createTemp('rcn-photo-test-');
      try {
        final store = FileRecipePhotoStore(dir);
        await store.save(id, croppedPng);
        await expectLater(store.save(id, Uint8List(9)), throwsFormatException);
        expect(await store.read(id), croppedPng);
        final file = (await dir.list().toList()).single as File;
        await file.rename('${file.path}.bak');
        expect(await FileRecipePhotoStore(dir).read(id), croppedPng);
        await store.save(id, null);
        expect(
          await store.read(id),
          isNull,
        ); // backup cannot resurrect removed photo
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'photos survive reload/revisions/archive without changing Recipe JSON',
    () async {
      final docs = _Documents([jsonDecode(source) as Map<String, dynamic>]);
      final original = jsonEncode(docs.docs);
      final photos = _Photos();
      final controller = library(photos, docs);
      await controller.load();
      expect(await controller.setRecipePhoto(id, croppedPng), isNull);
      expect(jsonEncode(docs.docs), original);
      final revision = jsonDecode(source) as Map<String, dynamic>;
      (revision['recipe'] as Map)['revision'] = 2;
      (revision['recipe'] as Map)['parent_revision'] = 1;
      await controller.importSource(jsonEncode(revision));
      expect(controller.revisionsFor(id), hasLength(2));
      await controller.setArchived(id, true);
      await controller.load();
      expect(controller.photoFor(id), croppedPng);
      expect(controller.archivedRecipes, hasLength(1));
      await controller.deleteArchivedRecipe(id);
      expect(await photos.read(id), isNull);
      expect(docs.docs, isEmpty);
      controller.dispose();
    },
  );

  test(
    'failed replacement/removal keeps current photo and retry succeeds',
    () async {
      final photos = _Photos();
      final controller = library(photos);
      await controller.load();
      await controller.setRecipePhoto(id, croppedPng);
      photos.failSave = true;
      expect(await controller.setRecipePhoto(id, sourcePng), isNotNull);
      expect(await controller.setRecipePhoto(id, null), isNotNull);
      expect(controller.photoFor(id), croppedPng);
      expect(await photos.read(id), croppedPng);
      photos.failSave = false;
      expect(await controller.setRecipePhoto(id, sourcePng), isNull);
      expect(controller.photoFor(id), sourcePng);
      controller.dispose();
    },
  );

  test(
    'corrupt photo does not prevent recipes loading and can be removed',
    () async {
      final photos = _Photos()..failRead = true;
      final controller = library(photos);
      await controller.load();
      expect(controller.recipes, hasLength(1));
      expect(controller.loadError, isNull);
      expect(controller.photoErrorFor(id), isNotNull);
      expect(await controller.setRecipePhoto(id, null), isNull);
      expect(controller.photoErrorFor(id), isNull);
      controller.dispose();
    },
  );

  test(
    'duplicate writes blocked and nonexistent recipes cannot acquire photos',
    () async {
      final photos = _Photos();
      final controller = library(photos);
      await controller.load();
      photos.pending = Completer<void>();
      final saving = controller.setRecipePhoto(id, croppedPng);
      expect(controller.isSavingPhoto(id), isTrue);
      expect(await controller.setRecipePhoto(id, sourcePng), isNotNull);
      photos.pending!.complete();
      expect(await saving, isNull);
      expect(controller.isSavingPhoto(id), isFalse);
      expect(await controller.setRecipePhoto('missing', croppedPng), isNotNull);
      expect(await photos.read('missing'), isNull);
      controller.dispose();
    },
  );

  Future<void> avatar(
    WidgetTester tester,
    RecipeLibraryController controller,
    Future<Uint8List?> Function() picker,
  ) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RecipePhotoAvatar(
          library: controller,
          recipeId: id,
          recipeTitle: '豚の生姜焼き',
          picker: picker,
        ),
      ),
    ),
  );

  testWidgets('picker cancellation and double tap preserve existing state', (
    tester,
  ) async {
    final controller = library(_Photos());
    await controller.load();
    final pending = Completer<Uint8List?>();
    var calls = 0;
    await avatar(tester, controller, () {
      calls++;
      return pending.future;
    });
    await tester.tap(find.byKey(const Key('recipe_photo_ginger-pork-001')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('recipe_photo_ginger-pork-001')));
    expect(calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(controller.photoFor(id), isNull);
    expect(find.byType(RecipePhotoCropScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('crop cancel preserves old photo; remove requires confirmation', (
    tester,
  ) async {
    final controller = library(_Photos());
    await controller.load();
    await controller.setRecipePhoto(id, croppedPng);
    await avatar(tester, controller, () async => sourcePng);
    await tester.tap(find.byKey(const Key('recipe_photo_ginger-pork-001')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('写真を変更'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (
      var i = 0;
      i < 10 && find.byType(RecipePhotoCropScreen).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(find.byType(RecipePhotoCropScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.photoFor(id), croppedPng);
    await tester.tap(find.byKey(const Key('recipe_photo_ginger-pork-001')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写真を外してお皿に戻す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(controller.photoFor(id), croppedPng);
    await tester.tap(find.byKey(const Key('recipe_photo_ginger-pork-001')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写真を外してお皿に戻す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写真を外す'));
    await tester.pumpAndSettle();
    expect(controller.photoFor(id), isNull);
    expect(find.byIcon(Icons.restaurant), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'position/zoom and explicit save yield a round persisted thumbnail',
    (tester) async {
      final controller = library(_Photos());
      await controller.load();
      await avatar(tester, controller, () async => sourcePng);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('recipe_photo_ginger-pork-001')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(RecipePhotoCropScreen), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('recipe_photo_crop_area'))),
      );
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await gesture.up();
      final paintedCrop =
          (tester
                          .widget<CustomPaint>(
                            find.descendant(
                              of: find.byKey(
                                const Key('recipe_photo_crop_area'),
                              ),
                              matching: find.byType(CustomPaint),
                            ),
                          )
                          .painter
                      as dynamic)
                  .crop
              as Rect;
      expect(paintedCrop.center.dx, lessThan(40));
      await tester.pump();
      final slider = tester.widget<Slider>(
        find.byKey(const Key('recipe_photo_zoom')),
      );
      slider.onChanged!(2);
      await tester.pump();
      expect(
        tester.widget<Slider>(find.byKey(const Key('recipe_photo_zoom'))).value,
        2,
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('save_recipe_photo_crop')));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      // Encoding and navigation cross the real engine/fake frame zones.
      for (var i = 0; i < 10 && controller.photoFor(id) == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(RecipePhotoCropScreen), findsNothing);
      expect(controller.photoFor(id), isNotNull);
      await tester.runAsync(() async {
        final image = await decodeRecipePhoto(controller.photoFor(id)!);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(bytes.getUint8(3), 0);
        expect(bytes.getUint8((256 * 512 + 256) * 4), 255);
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('populated home and crop fit narrow screens at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = library(_Photos());
    await controller.load();
    Widget largeText(Widget child) => MaterialApp(
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: widget!,
      ),
      home: child,
    );
    await tester.pumpWidget(largeText(HomeScreen(controller: controller)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(RecipePhotoAvatar), findsOneWidget);
    final image = (await tester.runAsync(coloredImage))!;
    await tester.pumpWidget(largeText(RecipePhotoCropScreen(image: image)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const Key('save_recipe_photo_crop'))).bottom,
      lessThanOrEqualTo(700),
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
