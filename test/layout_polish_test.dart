import 'dart:io';

import 'package:cookbook_app/core/theme/app_theme.dart';
import 'package:cookbook_app/data/database/app_database.dart';
import 'package:cookbook_app/data/images/recipe_image_service.dart';
import 'package:cookbook_app/data/repositories/recipe_repository.dart';
import 'package:cookbook_app/features/recipes/controllers/recipe_controller.dart';
import 'package:cookbook_app/features/recipes/models/recipe_models.dart';
import 'package:cookbook_app/features/recipes/screens/recipe_editor_screen.dart';
import 'package:cookbook_app/features/recipes/screens/recipe_library_screen.dart';
import 'package:cookbook_app/features/recipes/widgets/recipe_card.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(
    () => drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true,
  );
  tearDownAll(
    () => drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
  );
  late Directory directory;
  late RecipeImageService images;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('layout_test_');
    images = RecipeImageService(documentsDirectory: () async => directory);
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  CompleteRecipe longRecipe({
    bool finished = false,
    bool pinned = false,
  }) => CompleteRecipe(
    Recipe(
      id: '8d31a600-2717-4e71-8e3e-a3be07d8f104',
      title: 'A very long and wonderfully descriptive family recipe title',
      description:
          'This description is intentionally long so the card must truncate it gracefully without pushing metadata outside its available bounds.',
      preparationMinutes: 20,
      cookingMinutes: 35,
      isFavorite: true,
      isPinned: pinned,
      isFinished: finished,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    const [],
    const [],
    [
      Tag(
        id: '1',
        name: 'Weeknight dinner',
        normalizedName: 'weeknight dinner',
        createdAt: DateTime(2026),
      ),
      Tag(
        id: '2',
        name: 'Family favorite',
        normalizedName: 'family favorite',
        createdAt: DateTime(2026),
      ),
      Tag(
        id: '3',
        name: 'Comfort food',
        normalizedName: 'comfort food',
        createdAt: DateTime(2026),
      ),
      Tag(
        id: '4',
        name: 'Extra tag',
        normalizedName: 'extra tag',
        createdAt: DateTime(2026),
      ),
    ],
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required bool grid,
    required double width,
    bool finished = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: const TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child: RecipeCard(
                  recipe: longRecipe(finished: finished),
                  imageService: images,
                  compact: grid,
                  onTap: () {},
                  onFavorite: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'long grid card with tags and Draft status has no overflow at 165px',
    (tester) async {
      await pumpCard(tester, grid: true, width: 165);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'list card with Complete status has no overflow at narrow width',
    (tester) async {
      await pumpCard(tester, grid: false, width: 320, finished: true);
      expect(find.text('Complete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets("narrow library shows Bussin' and readable two-row toolbar", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = RecipeRepository(database);
    await repository.createRecipe(
      const RecipeInput(title: 'Pinned recipe', isPinned: true),
    );
    await repository.createRecipe(const RecipeInput(title: 'Regular recipe'));
    final controller = RecipeController(
      repository,
      preferences: await SharedPreferences.getInstance(),
      imageService: images,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: const RecipeLibraryScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text("Bussin'"), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Search recipes'), findsOneWidget);
    expect(find.text('Pinned'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('All recipes'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('All recipes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });

  testWidgets('editor remains overflow-free at 320px and 1.5 text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final controller = RecipeController(
      RecipeRepository(database),
      preferences: await SharedPreferences.getInstance(),
      imageService: images,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: const RecipeEditorScreen(recoverLostImage: false),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Basic information'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });
}
