import 'package:cookbook_app/data/database/app_database.dart';
import 'package:cookbook_app/data/repositories/recipe_repository.dart';
import 'package:cookbook_app/features/recipes/models/recipe_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late RecipeRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = RecipeRepository(database);
  });
  tearDown(() => database.close());

  test('creates a recipe with ordered children', () async {
    final id = await repository.createRecipe(
      const RecipeInput(
        title: 'Soup',
        ingredients: [
          IngredientInput(name: 'Water'),
          IngredientInput(name: 'Salt'),
        ],
        instructions: [
          InstructionInput(text: 'Boil'),
          InstructionInput(text: 'Season'),
        ],
      ),
    );
    final result = await repository.getRecipe(id);
    expect(result?.recipe.title, 'Soup');
    expect(result?.ingredients.map((e) => e.position), [0, 1]);
    expect(result?.instructions.map((e) => e.instructionText), [
      'Boil',
      'Season',
    ]);
  });

  test('updates recipe and replaces child rows', () async {
    final id = await repository.createRecipe(
      const RecipeInput(
        title: 'Old',
        ingredients: [IngredientInput(name: 'Old item')],
      ),
    );
    await repository.updateRecipe(
      RecipeInput(
        id: id,
        title: 'New',
        ingredients: const [IngredientInput(name: 'New item')],
      ),
    );
    final result = await repository.getRecipe(id);
    expect(result?.recipe.title, 'New');
    expect(result?.ingredients.single.name, 'New item');
  });

  test('deleting recipe cascades to ingredients and instructions', () async {
    final id = await repository.createRecipe(
      const RecipeInput(
        title: 'Toast',
        ingredients: [IngredientInput(name: 'Bread')],
        instructions: [InstructionInput(text: 'Toast it')],
      ),
    );
    await repository.deleteRecipe(id);
    expect(await database.select(database.ingredients).get(), isEmpty);
    expect(await database.select(database.instructions).get(), isEmpty);
  });

  test(
    'duplicates complete recipe with fresh ids and unpinned state',
    () async {
      final id = await repository.createRecipe(
        const RecipeInput(
          title: 'Pie',
          isPinned: true,
          isFinished: true,
          ingredients: [IngredientInput(name: 'Apple')],
          instructions: [InstructionInput(text: 'Bake')],
        ),
      );
      final copyId = await repository.duplicateRecipe(id);
      final original = await repository.getRecipe(id);
      final copy = await repository.getRecipe(copyId);
      expect(copyId, isNot(id));
      expect(copy?.recipe.title, 'Pie Copy');
      expect(copy?.recipe.isPinned, isFalse);
      expect(copy?.recipe.isFinished, isTrue);
      expect(
        copy?.ingredients.single.id,
        isNot(original?.ingredients.single.id),
      );
      expect(
        copy?.instructions.single.id,
        isNot(original?.instructions.single.id),
      );
    },
  );

  test('recipe title validation rejects whitespace', () {
    expect(const RecipeInput(title: '   ').validateTitle(), isNotNull);
    expect(const RecipeInput(title: 'Cake').validateTitle(), isNull);
  });
}
