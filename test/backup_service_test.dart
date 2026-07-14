import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cookbook_app/data/backup/backup_models.dart';
import 'package:cookbook_app/data/backup/cookbook_backup_service.dart';
import 'package:cookbook_app/data/database/app_database.dart';
import 'package:cookbook_app/data/images/recipe_image_service.dart';
import 'package:cookbook_app/data/repositories/recipe_repository.dart';
import 'package:cookbook_app/features/backup/controllers/backup_transfer_controller.dart';
import 'package:cookbook_app/features/recipes/controllers/recipe_controller.dart';
import 'package:cookbook_app/features/recipes/models/recipe_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  late Directory temp;
  late AppDatabase database;
  late RecipeRepository repository;
  late RecipeImageService images;
  late CookbookBackupService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      RecipeController.gridPreferenceKey: false,
      RecipeController.sortPreferenceKey:
          RecipeSortOption.alphabeticalAscending.name,
    });
    root = await Directory.systemTemp.createTemp('cookbook_backup_root_');
    temp = await Directory.systemTemp.createTemp('cookbook_backup_temp_');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = RecipeRepository(database);
    images = RecipeImageService(documentsDirectory: () async => root);
    service = CookbookBackupService(
      repository: repository,
      imageService: images,
      documentsDirectory: () async => root,
      temporaryDirectory: () async => temp,
    );
  });
  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<String> seedAndExport({Set<String>? selected}) async {
    final first = await repository.createRecipe(
      const RecipeInput(
        title: 'Adobo',
        notes: 'Family recipe',
        tagNames: ['Dinner'],
        ingredients: [IngredientInput(name: 'Chicken')],
        instructions: [InstructionInput(text: 'Simmer')],
      ),
    );
    await repository.createRecipe(
      const RecipeInput(title: 'Pancakes', tagNames: ['Breakfast']),
    );
    return (await service.exportCookbook(
      recipeIds: selected ?? {first},
    )).filePath;
  }

  test(
    'exports and validates individual recipe with versioned manifest and relationships',
    () async {
      final path = await seedAndExport();
      expect(p.extension(path), '.recipe');
      final parsed = await service.readAndValidate(path);
      expect(parsed.manifest.formatVersion, 1);
      expect(parsed.manifest.type, BackupType.recipe);
      expect(parsed.manifest.recipeCount, 1);
      expect(parsed.tags.single['normalizedName'], 'dinner');
      expect(parsed.ingredients.single['name'], 'Chicken');
      expect(parsed.instructions.single['text'], 'Simmer');
      expect(parsed.manifest.checksums, isNotEmpty);
    },
  );

  test(
    'full and selected exports include only relevant recipes and tags',
    () async {
      final one = await repository.createRecipe(
        const RecipeInput(title: 'One', tagNames: ['Used']),
      );
      await repository.createRecipe(
        const RecipeInput(title: 'Two', tagNames: ['Other']),
      );
      final selected = await service.readAndValidate(
        (await service.exportCookbook(recipeIds: {one})).filePath,
      );
      expect(selected.recipes, hasLength(1));
      expect(selected.tags.single['name'], 'Used');
      final full = await service.readAndValidate(
        (await service.exportCookbook()).filePath,
      );
      expect(full.recipes, hasLength(2));
      expect(full.manifest.type, BackupType.full);
    },
  );

  test(
    'rejects missing manifest, unsafe paths and checksum mismatch',
    () async {
      final missing = File(p.join(temp.path, 'missing.zip'));
      await missing.writeAsBytes(
        ZipEncoder().encode(
          Archive()..add(ArchiveFile('data/recipes.json', 2, '[]'.codeUnits)),
        ),
      );
      await expectLater(
        service.readAndValidate(missing.path),
        throwsA(isA<BackupValidationException>()),
      );

      final unsafe = File(p.join(temp.path, 'unsafe.zip'));
      await unsafe.writeAsBytes(
        ZipEncoder().encode(Archive()..add(ArchiveFile('../evil.txt', 1, [1]))),
      );
      await expectLater(
        service.readAndValidate(unsafe.path),
        throwsA(isA<BackupValidationException>()),
      );

      final validPath = await seedAndExport();
      final archive = ZipDecoder().decodeBytes(
        await File(validPath).readAsBytes(),
      );
      archive.add(ArchiveFile('data/tags.json', 2, '[]'.codeUnits));
      final corrupt = File(p.join(temp.path, 'corrupt.recipe'));
      await corrupt.writeAsBytes(ZipEncoder().encode(archive));
      await expectLater(
        service.readAndValidate(corrupt.path),
        throwsA(isA<BackupValidationException>()),
      );
    },
  );

  test(
    'imports new, skips existing, and imports copies with new UUIDs',
    () async {
      final path = await seedAndExport();
      final parsed = await service.readAndValidate(path);
      await database.delete(database.recipes).go();
      final added = await repository.applyBackupImport(
        parsed,
        mode: ImportMode.merge,
        conflictPolicy: ConflictPolicy.useImported,
        images: {},
      );
      expect(added.added, 1);
      final skipped = await repository.applyBackupImport(
        parsed,
        mode: ImportMode.skipExisting,
        conflictPolicy: ConflictPolicy.keepLocal,
        images: {},
      );
      expect(skipped.skipped, 1);
      final copied = await repository.applyBackupImport(
        parsed,
        mode: ImportMode.copies,
        conflictPolicy: ConflictPolicy.keepLocal,
        images: {},
      );
      expect(copied.copied, 1);
      expect(await repository.getAllCompleteRecipes(), hasLength(2));
    },
  );

  test('merge policies and tag normalization reuse work', () async {
    final id = await repository.createRecipe(
      const RecipeInput(title: 'Imported title', tagNames: ['DINNER']),
    );
    final parsed = await service.readAndValidate(
      (await service.exportCookbook(recipeIds: {id})).filePath,
    );
    await repository.updateRecipe(
      RecipeInput(id: id, title: 'Local title', tagNames: const ['Dinner']),
    );
    final keep = await repository.applyBackupImport(
      parsed,
      mode: ImportMode.merge,
      conflictPolicy: ConflictPolicy.keepLocal,
      images: {},
    );
    expect(keep.skipped, 1);
    await repository.applyBackupImport(
      parsed,
      mode: ImportMode.merge,
      conflictPolicy: ConflictPolicy.useImported,
      images: {},
    );
    expect((await repository.getRecipe(id))!.recipe.title, 'Imported title');
    expect(await repository.getAllTags(), hasLength(1));
  });

  test('replace cookbook removes unrelated recipes transactionally', () async {
    final id = await repository.createRecipe(
      const RecipeInput(title: 'Backup recipe'),
    );
    final parsed = await service.readAndValidate(
      (await service.exportCookbook()).filePath,
    );
    await repository.createRecipe(const RecipeInput(title: 'Unrelated local'));
    await repository.applyBackupImport(
      parsed,
      mode: ImportMode.replaceCookbook,
      conflictPolicy: ConflictPolicy.useImported,
      images: {},
    );
    final recipes = await repository.getAllCompleteRecipes();
    expect(recipes.map((r) => r.recipe.id), [id]);
  });

  test('local backup create, list, and delete lifecycle', () async {
    await repository.createRecipe(
      const RecipeInput(title: 'Local backup recipe'),
    );
    final result = await service.exportCookbook(localBackup: true);
    expect(await File(result.filePath).exists(), isTrue);
    final listed = await service.listLocalBackups();
    expect(listed.single.recipeCount, 1);
    await service.deleteLocalBackup(listed.single.path);
    expect(await service.listLocalBackups(), isEmpty);
  });

  test('preview detects UUID conflicts and title-only duplicates', () async {
    final sourceId = await repository.createRecipe(
      const RecipeInput(title: 'Same title'),
    );
    final path = (await service.exportCookbook(recipeIds: {sourceId})).filePath;
    final controller = BackupTransferController(
      service: service,
      repository: repository,
      imageService: images,
    );
    final existing = await controller.buildPreview(path);
    expect(existing.existingRecipes, 1);
    await database.delete(database.recipes).go();
    await repository.createRecipe(const RecipeInput(title: 'Same title'));
    final titleMatch = await controller.buildPreview(path);
    expect(titleMatch.possibleDuplicates, 1);
  });
}
