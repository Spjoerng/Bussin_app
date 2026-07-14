import 'package:cookbook_app/data/database/app_database.dart';
import 'package:cookbook_app/data/repositories/recipe_repository.dart';
import 'package:cookbook_app/features/recipes/controllers/recipe_controller.dart';
import 'package:cookbook_app/features/recipes/models/recipe_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CompleteRecipe complete({
  required String id,
  required String title,
  bool favorite = false,
  bool pinned = false,
  bool finished = false,
  int? prep,
  int? cook,
  int createdMinute = 0,
  int updatedMinute = 0,
  List<String> ingredients = const [],
  List<Tag> tags = const [],
}) => CompleteRecipe(
  Recipe(
    id: id,
    title: title,
    isFavorite: favorite,
    isPinned: pinned,
    isFinished: finished,
    preparationMinutes: prep,
    cookingMinutes: cook,
    createdAt: DateTime(2026, 1, 1, 0, createdMinute),
    updatedAt: DateTime(2026, 1, 1, 0, updatedMinute),
  ),
  [
    for (var i = 0; i < ingredients.length; i++)
      Ingredient(
        id: '$id-i$i',
        recipeId: id,
        name: ingredients[i],
        position: i,
      ),
  ],
  const [],
  tags,
);

Tag tag(String id, String name) => Tag(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  createdAt: DateTime(2026),
);

void main() {
  group('tag repository', () {
    late AppDatabase database;
    late RecipeRepository repository;
    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = RecipeRepository(database);
    });
    tearDown(() => database.close());

    test('normalizes unique tags and rejects normalized duplicates', () async {
      final created = await repository.createTag('  Weeknight   Dinner ');
      expect(created.name, 'Weeknight Dinner');
      expect(created.normalizedName, 'weeknight dinner');
      expect(
        () => repository.createTag('weeknight dinner'),
        throwsA(isA<DuplicateTagException>()),
      );
    });

    test('assigns, removes, and transactionally saves recipe tags', () async {
      final tag = await repository.createTag('Quick');
      final id = await repository.createRecipe(
        const RecipeInput(title: 'Toast', tagNames: [' quick ', 'QUICK']),
      );
      expect((await repository.getRecipe(id))!.tags.map((t) => t.id), [tag.id]);
      await repository.removeTag(id, tag.id);
      expect((await repository.getRecipe(id))!.tags, isEmpty);
      await repository.assignTag(id, tag.id);
      expect((await repository.getRecipe(id))!.tags.single.name, 'Quick');
    });

    test('deleting a tag leaves its recipe intact', () async {
      final id = await repository.createRecipe(
        const RecipeInput(title: 'Salad', tagNames: ['Fresh']),
      );
      final assigned = (await repository.getRecipe(id))!.tags.single;
      await repository.deleteTag(assigned.id);
      expect((await repository.getRecipe(id))?.recipe.title, 'Salad');
      expect((await repository.getRecipe(id))?.tags, isEmpty);
    });
  });

  group('combined query', () {
    final quick = tag('quick', 'Quick');
    final dinner = tag('dinner', 'Dinner');
    late List<CompleteRecipe> values;
    setUp(
      () => values = [
        complete(
          id: 'a',
          title: 'Apple Pie',
          favorite: true,
          finished: true,
          prep: 10,
          cook: 20,
          ingredients: ['Cinnamon'],
          tags: [quick, dinner],
          updatedMinute: 1,
        ),
        complete(
          id: 'b',
          title: 'Soup',
          prep: 40,
          cook: 30,
          ingredients: ['Tomato'],
          tags: [dinner],
          updatedMinute: 2,
        ),
        complete(id: 'c', title: 'Toast', pinned: true, ingredients: ['Bread']),
        complete(id: 'd', title: 'Mystery', finished: true),
      ],
    );

    test('searches ingredients and tags', () {
      expect(
        applyRecipeQuery(
          values,
          'cinnamon',
          const RecipeFilterState(),
          RecipeSortOption.recentlyUpdated,
        ).single.recipe.id,
        'a',
      );
      expect(
        applyRecipeQuery(
          values,
          'dinner',
          const RecipeFilterState(),
          RecipeSortOption.recentlyUpdated,
        ).map((r) => r.recipe.id).toSet(),
        {'a', 'b'},
      );
    });

    test('combines search, favorite, status and multiple-tag AND filters', () {
      final filters = RecipeFilterState(
        favoritesOnly: true,
        status: RecipeStatusFilter.complete,
        selectedTagIds: {quick.id, dinner.id},
      );
      expect(
        applyRecipeQuery(
          values,
          'apple',
          filters,
          RecipeSortOption.recentlyUpdated,
        ).single.recipe.id,
        'a',
      );
    });

    test('filters maximum time and treats unknown as not matching', () {
      final result = applyRecipeQuery(
        values,
        '',
        const RecipeFilterState(maximumTotalMinutes: 30),
        RecipeSortOption.recentlyUpdated,
      );
      expect(result.map((r) => r.recipe.id), ['a']);
    });

    test('filters untagged recipes', () {
      final result = applyRecipeQuery(
        values,
        '',
        const RecipeFilterState(untaggedOnly: true),
        RecipeSortOption.recentlyUpdated,
      );
      expect(result.map((r) => r.recipe.id).toSet(), {'c', 'd'});
    });

    test('supports every sort and leaves unknown times last', () {
      expect(
        applyRecipeQuery(
          values,
          '',
          const RecipeFilterState(),
          RecipeSortOption.recentlyCreated,
        ).first.recipe.id,
        'a',
      );
      expect(
        applyRecipeQuery(
          values,
          '',
          const RecipeFilterState(),
          RecipeSortOption.alphabeticalAscending,
        ).first.recipe.id,
        'a',
      );
      expect(
        applyRecipeQuery(
          values,
          '',
          const RecipeFilterState(),
          RecipeSortOption.alphabeticalDescending,
        ).first.recipe.id,
        'c',
      );
      expect(
        applyRecipeQuery(
          values,
          '',
          const RecipeFilterState(),
          RecipeSortOption.shortestTime,
        ).last.totalMinutes,
        isNull,
      );
      expect(
        applyRecipeQuery(
          values,
          '',
          const RecipeFilterState(),
          RecipeSortOption.longestTime,
        ).first.recipe.id,
        'b',
      );
      expect(
        applyRecipeQuery(
          values,
          '',
          const RecipeFilterState(),
          RecipeSortOption.longestTime,
        ).last.totalMinutes,
        isNull,
      );
    });
  });

  test('active count and clear cover every filter category', () {
    final filters = RecipeFilterState(
      favoritesOnly: true,
      pinnedOnly: true,
      status: RecipeStatusFilter.draft,
      selectedTagIds: {'a', 'b'},
      maximumTotalMinutes: 30,
      untaggedOnly: true,
    );
    expect(filters.activeCount, 6);
    expect(filters.clear(), const RecipeFilterState());
    expect(filters.clear().isActive, isFalse);
  });

  test('persists grid and sort preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final controller = RecipeController(
      RecipeRepository(database),
      preferences: prefs,
    );
    await controller.toggleLayout();
    await controller.setSortOption(RecipeSortOption.alphabeticalDescending);
    expect(prefs.getBool(RecipeController.gridPreferenceKey), isFalse);
    expect(
      prefs.getString(RecipeController.sortPreferenceKey),
      RecipeSortOption.alphabeticalDescending.name,
    );
    controller.dispose();
    await database.close();
  });
}
