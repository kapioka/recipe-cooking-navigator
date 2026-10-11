import 'data/profile_history_writer.dart';

import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/preference_controller.dart';
import 'data/preference_store.dart';
import 'data/cooking_profile_cache_store.dart';
import 'domain/feedback_validator.dart';
import 'ui/preference_scope.dart';
import 'platform/feedback_archive_platform.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'application/recipe_library_controller.dart';
import 'data/cooking_store.dart';
import 'data/preparation_checklist_store.dart';
import 'data/recipe_document_store.dart';
import 'data/recipe_archive_store.dart';
import 'data/recipe_inbox_state_store.dart';
import 'data/recipe_tag_store.dart';
import 'data/recipe_version_state_store.dart';
import 'domain/recipe_validator.dart';
import 'platform/recipe_file_picker.dart';
import 'platform/recipe_inbox_platform.dart';
import 'platform/recipe_share_platform.dart';
import 'platform/kitchen_device.dart';
import 'ui/home_screen.dart';
import 'ui/kitchen_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final schemaSource = await rootBundle.loadString(
    'schemas/recipe-v2.schema.json',
  );
  final supportDirectory = await getApplicationSupportDirectory();
  final validator = RecipeValidator.fromSchemaString(schemaSource);
  final legacyDataPresent = [
    'recipes-v1.json',
    'cooking-v1.json',
    'recipe-tags-v1.json',
    'recipe-version-state-v1.json',
  ].any((name) => File('${supportDirectory.path}/$name').existsSync());
  final controller = RecipeLibraryController(
    FileRecipeDocumentStore(File('${supportDirectory.path}/recipes-v2.json')),
    FileRecipeTagStore(File('${supportDirectory.path}/recipe-tags-v2.json')),
    validator,
    pickRecipeSource,
    cookingStore: CookingStore(
      File('${supportDirectory.path}/cooking-v2.json'),
      validator,
    ),
    preparationStore: PreparationChecklistStore(
      File('${supportDirectory.path}/preparation-checklist-v1.json'),
    ),
    recipeInboxPlatform: const AndroidRecipeInboxPlatform(),
    recipeInboxStateStore: FileRecipeInboxStateStore(
      File('${supportDirectory.path}/recipe-inbox-v1.json'),
    ),
    recipeVersionStateStore: FileRecipeVersionStateStore(
      File('${supportDirectory.path}/recipe-version-state-v2.json'),
    ),
    archiveStore: RecipeArchiveStore(
      File('${supportDirectory.path}/recipe-archive-v1.json'),
    ),
    legacyDataPresent: legacyDataPresent,
  );
  await controller.load();

  final preferenceValidator = FeedbackValidator.fromSchemaStrings(
    feedbackSchemaSource: await rootBundle.loadString(
      'schemas/feedback-v2.schema.json',
    ),
    recipeSchemaSource: schemaSource,
  );
  const preferenceArchive = AndroidFeedbackArchivePlatform();
  final preferences = PreferenceController(
    PreferenceStore(
      File('${supportDirectory.path}/preferences-v1.json'),
      preferenceValidator,
    ),
    archive: preferenceArchive,
    profileWriter: ProfileHistoryWriter(
      File('${supportDirectory.path}/profile-write-v1.json'),
      preferenceValidator,
      preferenceArchive,
    ),
    profileCache: CookingProfileCacheStore(
      File('${supportDirectory.path}/cooking-profile-cache-v1.json'),
      await rootBundle.loadString('schemas/cooking-profile-v1.schema.json'),
      explicitSchemaSource: await rootBundle.loadString(
        'schemas/cooking-profile-v1.1.schema.json',
      ),
    ),
  );
  runApp(
    RecipeCookingNavigatorApp(controller: controller, preferences: preferences),
  );
}

class RecipeCookingNavigatorApp extends StatefulWidget {
  const RecipeCookingNavigatorApp({
    required this.controller,
    this.sharePlatform,
    this.preferences,
    super.key,
  });

  final RecipeLibraryController controller;
  final RecipeSharePlatform? sharePlatform;
  final PreferenceController? preferences;

  @override
  State<RecipeCookingNavigatorApp> createState() =>
      _RecipeCookingNavigatorAppState();
}

class _RecipeCookingNavigatorAppState extends State<RecipeCookingNavigatorApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _home = GlobalKey<HomeScreenState>();
  final _notificationTarget = ValueNotifier<String?>(null);
  late final RecipeSharePlatform _sharePlatform;
  bool _drainingShares = false;
  bool _sharesSignalled = false;
  bool _kitchenOpen = false;

  @override
  void initState() {
    super.initState();
    _sharePlatform = widget.sharePlatform ?? AndroidRecipeSharePlatform();
    _sharePlatform.setIncomingHandler(() {
      _sharesSignalled = true;
      unawaited(_drainShares());
    });
    KitchenDevice.setNotificationTapHandler(_openNotificationTimer);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(_drainShares());
      try {
        final timerId = await KitchenDevice.takeNotificationTimerId();
        if (timerId != null) await _openNotificationTimer(timerId);
      } on MissingPluginException {
        // Non-Android/widget-test environments do not provide this channel.
      }
    });
  }

  @override
  void dispose() {
    _sharePlatform.dispose();
    KitchenDevice.clearNotificationTapHandler();
    _notificationTarget.dispose();
    super.dispose();
  }

  Future<void> _openNotificationTimer(String timerId) async {
    _notificationTarget.value = timerId;
    await _openKitchen();
  }

  Future<void> _drainShares() async {
    if (_drainingShares || !mounted) return;
    _drainingShares = true;
    try {
      while (mounted) {
        _sharesSignalled = false;
        final home = _home.currentState;
        if (home == null) return;
        String? source;
        try {
          source = await _sharePlatform.takeNext();
        } on MissingPluginException {
          return;
        } on PlatformException catch (error) {
          home.showSharedImportError('共有されたレシピを読み込めませんでした。');
          if (error.code == 'busy') return;
          continue;
        }
        if (source == null) return;
        await _waitForImportIdle();
        if (!mounted) return;
        await home.importSharedSource(source);
      }
    } finally {
      _drainingShares = false;
      if (_sharesSignalled && mounted) unawaited(_drainShares());
    }
  }

  Future<void> _waitForImportIdle() async {
    if (!widget.controller.isImporting) return;
    final completer = Completer<void>();
    void onChange() {
      if (!widget.controller.isImporting && !completer.isCompleted) {
        completer.complete();
      }
    }

    widget.controller.addListener(onChange);
    try {
      onChange();
      await completer.future;
    } finally {
      widget.controller.removeListener(onChange);
    }
  }

  Future<void> _openKitchen() async {
    if (_kitchenOpen || !mounted) return;
    final navigator = _navigator.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_openKitchen()),
      );
      return;
    }
    _kitchenOpen = true;
    try {
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => KitchenScreen(
            library: widget.controller,
            notificationTarget: _notificationTarget,
          ),
        ),
      );
    } finally {
      _kitchenOpen = false;
      _notificationTarget.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      navigatorKey: _navigator,
      title: 'Recipe Cooking Navigator',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE56A3D)),
        fontFamily: 'sans-serif',
        useMaterial3: true,
      ),
      home: HomeScreen(
        key: _home,
        controller: widget.controller,
        onOpenKitchen: () => unawaited(_openKitchen()),
      ),
    );
    return widget.preferences == null
        ? app
        : PreferenceControllerScope(
            controller: widget.preferences!,
            child: app,
          );
  }
}
