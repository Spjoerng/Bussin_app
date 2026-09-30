import 'dart:async';

import 'package:cookbook_app/core/theme/app_theme.dart';
import 'package:cookbook_app/core/theme/page_content.dart';
import 'package:cookbook_app/data/database/app_database.dart';
import 'package:cookbook_app/data/repositories/recipe_repository.dart';
import 'package:cookbook_app/features/recipes/controllers/recipe_controller.dart';
import 'package:cookbook_app/features/recipes/screens/recipe_editor_screen.dart';
import 'package:cookbook_app/features/recipes/screens/recipe_library_screen.dart';
import 'package:cookbook_app/features/recipes/screens/recipe_viewer_screen.dart';
import 'package:cookbook_app/features/recipes/screens/tag_management_screen.dart';
import 'package:cookbook_app/features/recipes/widgets/favorite_button.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository extends RecipeRepository {
  _Repository(super.database);
  CompleteRecipe value = CompleteRecipe(
    Recipe(
      id: 'recipe',
      title: 'Mackerel Sotanghon',
      imagePath: 'recipe_images/missing.jpg',
      isFavorite: false,
      isPinned: false,
      isFinished: false,
      preparationMinutes: 5,
      cookingMinutes: 30,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    const [],
    const [],
  );
  Completer<void>? pending;
  int writes = 0;
  @override
  Stream<List<CompleteRecipe>> watchAllRecipes() => Stream.value([value]);
  @override
  Stream<List<Tag>> watchAllTags() => Stream.value([]);
  @override
  Future<CompleteRecipe?> getRecipe(String id) async => value;
  @override
  Future<void> toggleFavorite(String id) async {
    writes++;
    await pending?.future;
    value = CompleteRecipe(
      value.recipe.copyWith(isFavorite: !value.recipe.isFavorite),
      [],
      [],
    );
  }
}

void main() {
  late AppDatabase database;
  late _Repository repository;
  late RecipeController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = _Repository(database);
    controller = RecipeController(
      repository,
      preferences: await SharedPreferences.getInstance(),
    );
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(320, 640),
    double scale = 1.5,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'detail favorite animates immediately, persists, and toggles back',
    (tester) async {
      await mount(tester, const RecipeViewerScreen(recipeId: 'recipe'));
      repository.pending = Completer<void>();
      await tester.tap(find.byTooltip('Favorite recipe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.text('Mackerel Sotanghon'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final button = find.descendant(
        of: find.byType(FavoriteButton),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(button).onPressed, isNull);
      repository.pending!.complete();
      await tester.pumpAndSettle();
      expect(repository.value.recipe.isFavorite, isTrue);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      await tester.tap(find.byTooltip('Remove from favorites'));
      await tester.pumpAndSettle();
      expect(repository.value.recipe.isFavorite, isFalse);
      expect(repository.writes, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed favorite save rolls back and reports the error', (
    tester,
  ) async {
    await mount(tester, const RecipeViewerScreen(recipeId: 'recipe'));
    repository.pending = Completer<void>();
    await tester.tap(find.byTooltip('Favorite recipe'));
    await tester.pump();
    repository.pending!.completeError(StateError('Storage unavailable'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.text('Could not save the change. Try again.'), findsOneWidget);
    expect(repository.value.recipe.isFavorite, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor photo actions and lower sections fit with large text', (
    tester,
  ) async {
    await mount(
      tester,
      RecipeEditorScreen(recipe: repository.value, recoverLostImage: false),
    );
    expect(find.text('Replace photo'), findsOneWidget);
    expect(find.text('Remove photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Instructions'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('export dialog fits short landscape screen with enlarged text', (
    tester,
  ) async {
    await mount(
      tester,
      const RecipeLibraryScreen(),
      size: const Size(640, 360),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export selected recipes'));
    await tester.pumpAndSettle();
    expect(find.text('Select recipes to export'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final screen in <Widget>[
    const RecipeViewerScreen(recipeId: 'recipe'),
    const RecipeEditorScreen(recoverLostImage: false),
    const TagManagementScreen(),
  ]) {
    testWidgets('${screen.runtimeType} uses a readable tablet content width', (
      tester,
    ) async {
      await mount(tester, screen, size: const Size(1280, 900), scale: 1);
      final content = find
          .descendant(
            of: find.byType(PageContent),
            matching: find.byType(SizedBox),
          )
          .first;
      expect(tester.getSize(content).width, lessThanOrEqualTo(840));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
