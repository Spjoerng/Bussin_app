import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/recipes/models/recipe_models.dart';
import '../backup/backup_models.dart';
import '../database/app_database.dart';

class CompleteRecipe {
  const CompleteRecipe(
    this.recipe,
    this.ingredients,
    this.instructions, [
    this.tags = const [],
  ]);
  final Recipe recipe;
  final List<Ingredient> ingredients;
  final List<Instruction> instructions;
  final List<Tag> tags;

  int? get totalMinutes {
    if (recipe.preparationMinutes == null || recipe.cookingMinutes == null) {
      return null;
    }
    return (recipe.preparationMinutes ?? 0) + (recipe.cookingMinutes ?? 0);
  }
}

class DuplicateTagException implements Exception {
  const DuplicateTagException(this.name);
  final String name;
  @override
  String toString() => 'A tag named “$name” already exists.';
}

String normalizeTagName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class RecipeRepository {
  RecipeRepository(this.database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final AppDatabase database;
  final Uuid _uuid;

  Stream<List<CompleteRecipe>> watchAllRecipes() => database
      .customSelect(
        'SELECT id FROM recipes',
        readsFrom: {
          database.recipes,
          database.ingredients,
          database.instructions,
          database.tags,
          database.recipeTags,
        },
      )
      .watch()
      .asyncMap((_) => getAllCompleteRecipes());

  Stream<List<Tag>> watchAllTags() => (database.select(
    database.tags,
  )..orderBy([(t) => OrderingTerm.asc(t.normalizedName)])).watch();

  Future<List<Tag>> getAllTags() => (database.select(
    database.tags,
  )..orderBy([(t) => OrderingTerm.asc(t.normalizedName)])).get();

  Future<List<CompleteRecipe>> getAllCompleteRecipes() async {
    final recipes = await database.select(database.recipes).get();
    return Future.wait(recipes.map((recipe) => _complete(recipe)));
  }

  Future<List<CompleteRecipe>> searchRecipes(String rawQuery) async {
    final words = rawQuery
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final recipes = await getAllCompleteRecipes();
    if (words.isEmpty) return recipes;
    return recipes.where((item) {
      final searchable = [
        item.recipe.title,
        item.recipe.description,
        item.recipe.notes,
        ...item.ingredients.map((ingredient) => ingredient.name),
        ...item.tags.map((tag) => tag.name),
      ].whereType<String>().join(' ').toLowerCase();
      return words.every(searchable.contains);
    }).toList();
  }

  Future<CompleteRecipe?> getRecipe(String id) async {
    final recipe = await (database.select(
      database.recipes,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    return recipe == null ? null : _complete(recipe);
  }

  Future<CompleteRecipe> _complete(Recipe recipe) async {
    final ingredients =
        await (database.select(database.ingredients)
              ..where((i) => i.recipeId.equals(recipe.id))
              ..orderBy([(i) => OrderingTerm.asc(i.position)]))
            .get();
    final instructions =
        await (database.select(database.instructions)
              ..where((i) => i.recipeId.equals(recipe.id))
              ..orderBy([(i) => OrderingTerm.asc(i.position)]))
            .get();
    final tagRows = await (database.select(database.recipeTags).join([
      innerJoin(
        database.tags,
        database.tags.id.equalsExp(database.recipeTags.tagId),
      ),
    ])..where(database.recipeTags.recipeId.equals(recipe.id))).get();
    final tags = tagRows.map((row) => row.readTable(database.tags)).toList()
      ..sort((a, b) => a.normalizedName.compareTo(b.normalizedName));
    return CompleteRecipe(recipe, ingredients, instructions, tags);
  }

  Future<String> createRecipe(RecipeInput input) async {
    final id = input.id ?? _uuid.v4();
    final now = DateTime.now();
    await database.transaction(() async {
      await database
          .into(database.recipes)
          .insert(_recipeCompanion(input, id, now, now));
      await _insertChildren(id, input);
      await _replaceTagsByNames(id, input.tagNames);
    });
    return id;
  }

  Future<void> updateRecipe(RecipeInput input) async {
    final id = input.id;
    if (id == null) throw ArgumentError('An id is required when updating.');
    final old = await getRecipe(id);
    if (old == null) throw StateError('Recipe not found.');
    await database.transaction(() async {
      await database
          .update(database.recipes)
          .replace(
            _recipeCompanion(input, id, old.recipe.createdAt, DateTime.now()),
          );
      await (database.delete(
        database.ingredients,
      )..where((i) => i.recipeId.equals(id))).go();
      await (database.delete(
        database.instructions,
      )..where((i) => i.recipeId.equals(id))).go();
      await _insertChildren(id, input);
      await _replaceTagsByNames(id, input.tagNames);
    });
  }

  Future<CompleteRecipe?> deleteRecipe(String id) async {
    final deleted = await getRecipe(id);
    await database.transaction(() async {
      await (database.delete(
        database.recipes,
      )..where((r) => r.id.equals(id))).go();
    });
    return deleted;
  }

  Future<void> restoreRecipe(CompleteRecipe value) async {
    await database.transaction(() async {
      await database.into(database.recipes).insert(value.recipe);
      await database.batch((batch) {
        batch.insertAll(database.ingredients, value.ingredients);
        batch.insertAll(database.instructions, value.instructions);
      });
      await replaceRecipeTags(
        value.recipe.id,
        value.tags.map((t) => t.id).toSet(),
      );
    });
  }

  Future<Tag> createTag(String rawName) async {
    final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalized = normalizeTagName(name);
    if (normalized.isEmpty) throw ArgumentError('Tag name cannot be empty.');
    final existing = await _tagByNormalized(normalized);
    if (existing != null) throw DuplicateTagException(name);
    final tag = Tag(
      id: _uuid.v4(),
      name: name,
      normalizedName: normalized,
      createdAt: DateTime.now(),
    );
    await database.into(database.tags).insert(tag);
    return tag;
  }

  Future<void> renameTag(String id, String rawName) async {
    final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalized = normalizeTagName(name);
    if (normalized.isEmpty) throw ArgumentError('Tag name cannot be empty.');
    final existing = await _tagByNormalized(normalized);
    if (existing != null && existing.id != id) {
      throw DuplicateTagException(name);
    }
    await (database.update(database.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(name: Value(name), normalizedName: Value(normalized)),
    );
  }

  Future<void> deleteTag(String id) => database.transaction(() async {
    await (database.delete(database.tags)..where((t) => t.id.equals(id))).go();
  });

  Future<void> assignTag(String recipeId, String tagId) => database
      .into(database.recipeTags)
      .insert(
        RecipeTagsCompanion.insert(recipeId: recipeId, tagId: tagId),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> removeTag(String recipeId, String tagId) => (database.delete(
    database.recipeTags,
  )..where((r) => r.recipeId.equals(recipeId) & r.tagId.equals(tagId))).go();

  Future<void> replaceRecipeTags(String recipeId, Set<String> tagIds) async {
    await (database.delete(
      database.recipeTags,
    )..where((r) => r.recipeId.equals(recipeId))).go();
    if (tagIds.isNotEmpty) {
      await database.batch(
        (batch) => batch.insertAll(database.recipeTags, [
          for (final tagId in tagIds)
            RecipeTagsCompanion.insert(recipeId: recipeId, tagId: tagId),
        ]),
      );
    }
  }

  Future<int> removeUnusedTags() => database.customUpdate(
    'DELETE FROM tags WHERE NOT EXISTS (SELECT 1 FROM recipe_tags WHERE recipe_tags.tag_id = tags.id)',
    updates: {database.tags},
    updateKind: UpdateKind.delete,
  );

  Future<Map<String, int>> getTagCounts() async {
    final rows = await database
        .customSelect(
          'SELECT tag_id, COUNT(*) AS amount FROM recipe_tags GROUP BY tag_id',
          readsFrom: {database.recipeTags},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('tag_id'): row.read<int>('amount'),
    };
  }

  Future<Set<String>> getReferencedImagePaths() async {
    final rows = await database.select(database.recipes).get();
    return {
      for (final recipe in rows)
        ...[recipe.imagePath, recipe.imageThumbnailPath].whereType<String>(),
    };
  }

  Future<ImportResult> applyBackupImport(
    ParsedBackup backup, {
    required ImportMode mode,
    required ConflictPolicy conflictPolicy,
    required Map<String, ({String imagePath, String thumbnailPath})> images,
  }) async {
    var added = 0, updated = 0, skipped = 0, copied = 0;
    final tagById = {
      for (final tag in backup.tags) tag['id'] as String: tag['name'] as String,
    };
    final localNormalizedTags = (await getAllTags())
        .map((tag) => tag.normalizedName)
        .toSet();
    final importedNormalizedTags = backup.tags
        .map((tag) => tag['normalizedName'] as String)
        .toSet();
    final tagIdsByRecipe = <String, List<String>>{};
    for (final row in backup.recipeTags) {
      tagIdsByRecipe
          .putIfAbsent(row['recipeId'] as String, () => [])
          .add(row['tagId'] as String);
    }
    final localBefore = {
      for (final recipe in await database.select(database.recipes).get())
        recipe.id: recipe,
    };
    await database.transaction(() async {
      if (mode == ImportMode.replaceCookbook) {
        await database.delete(database.recipes).go();
        await database.delete(database.tags).go();
      }
      for (final row in backup.recipes) {
        final importedId = row['id'] as String;
        final existing = mode == ImportMode.replaceCookbook
            ? null
            : localBefore[importedId];
        if (existing != null && mode == ImportMode.skipExisting) {
          skipped++;
          continue;
        }
        if (existing != null && mode == ImportMode.merge) {
          final importedUpdated = DateTime.parse(row['updatedAt'] as String);
          final useImported =
              conflictPolicy == ConflictPolicy.useImported ||
              (conflictPolicy == ConflictPolicy.keepNewer &&
                  importedUpdated.isAfter(existing.updatedAt));
          if (!useImported) {
            skipped++;
            continue;
          }
        }
        final asCopy = mode == ImportMode.copies;
        final finalId = asCopy ? _uuid.v4() : importedId;
        final ingredientRows =
            backup.ingredients
                .where((v) => v['recipeId'] == importedId)
                .toList()
              ..sort(
                (a, b) =>
                    (a['position'] as int).compareTo(b['position'] as int),
              );
        final ingredients = ingredientRows
            .map(
              (v) => IngredientInput(
                id: asCopy ? null : v['id'] as String,
                name: v['name'] as String,
                quantity: v['quantity'] as String?,
                unit: v['unit'] as String?,
                notes: v['notes'] as String?,
              ),
            )
            .toList();
        final instructions =
            backup.instructions
                .where((v) => v['recipeId'] == importedId)
                .toList()
              ..sort(
                (a, b) =>
                    (a['position'] as int).compareTo(b['position'] as int),
              );
        final image = images[importedId];
        final keepExistingImage = existing != null && image == null;
        final input = RecipeInput(
          id: finalId,
          title: row['title'] as String,
          description: row['description'] as String?,
          servings: row['servings'] as int?,
          preparationMinutes: row['preparationMinutes'] as int?,
          cookingMinutes: row['cookingMinutes'] as int?,
          notes: row['notes'] as String?,
          isFavorite: row['isFavorite'] as bool,
          isPinned: asCopy ? false : row['isPinned'] as bool,
          isFinished: row['isFinished'] as bool,
          ingredients: ingredients,
          instructions: instructions
              .map(
                (v) => InstructionInput(
                  id: asCopy ? null : v['id'] as String,
                  text: v['text'] as String,
                ),
              )
              .toList(),
          tagNames: (tagIdsByRecipe[importedId] ?? [])
              .map((id) => tagById[id]!)
              .toList(),
          imagePath: keepExistingImage ? existing.imagePath : image?.imagePath,
          imageThumbnailPath: keepExistingImage
              ? existing.imageThumbnailPath
              : image?.thumbnailPath,
          imageUpdatedAt: keepExistingImage
              ? existing.imageUpdatedAt
              : image == null
              ? null
              : DateTime.now(),
        );
        final created = DateTime.parse(row['createdAt'] as String);
        final updatedAt = DateTime.parse(row['updatedAt'] as String);
        if (existing != null && !asCopy) {
          await database
              .update(database.recipes)
              .replace(_recipeCompanion(input, finalId, created, updatedAt));
          await (database.delete(
            database.ingredients,
          )..where((v) => v.recipeId.equals(finalId))).go();
          await (database.delete(
            database.instructions,
          )..where((v) => v.recipeId.equals(finalId))).go();
          await _insertChildren(finalId, input);
          await _replaceTagsByNames(finalId, input.tagNames);
          updated++;
        } else {
          await database
              .into(database.recipes)
              .insert(
                _recipeCompanion(
                  input,
                  finalId,
                  asCopy ? DateTime.now() : created,
                  asCopy ? DateTime.now() : updatedAt,
                ),
              );
          await _insertChildren(finalId, input);
          await _replaceTagsByNames(finalId, input.tagNames);
          if (asCopy) {
            copied++;
          } else {
            added++;
          }
        }
      }
    });
    return ImportResult(
      added: added,
      updated: updated,
      skipped: skipped,
      copied: copied,
      imagesImported: images.length,
      tagsCreated: mode == ImportMode.replaceCookbook
          ? importedNormalizedTags.length
          : importedNormalizedTags.difference(localNormalizedTags).length,
      tagsReused: mode == ImportMode.replaceCookbook
          ? 0
          : importedNormalizedTags.intersection(localNormalizedTags).length,
    );
  }

  Future<Tag?> _tagByNormalized(String value) => (database.select(
    database.tags,
  )..where((t) => t.normalizedName.equals(value))).getSingleOrNull();

  Future<Tag> _findOrCreateTag(String rawName) async {
    final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalized = normalizeTagName(name);
    if (normalized.isEmpty) throw ArgumentError('Tag name cannot be empty.');
    final existing = await _tagByNormalized(normalized);
    if (existing != null) return existing;
    final tag = Tag(
      id: _uuid.v4(),
      name: name,
      normalizedName: normalized,
      createdAt: DateTime.now(),
    );
    await database.into(database.tags).insert(tag);
    return tag;
  }

  Future<void> _replaceTagsByNames(String recipeId, List<String> names) async {
    final ids = <String>{};
    for (final name in names) {
      if (normalizeTagName(name).isNotEmpty) {
        ids.add((await _findOrCreateTag(name)).id);
      }
    }
    await replaceRecipeTags(recipeId, ids);
  }

  Future<void> toggleFavorite(String id) => _toggle(id, favorite: true);
  Future<void> togglePinned(String id) => _toggle(id, favorite: false);
  Future<void> _toggle(String id, {required bool favorite}) async {
    final row = await (database.select(
      database.recipes,
    )..where((r) => r.id.equals(id))).getSingle();
    await (database.update(
      database.recipes,
    )..where((r) => r.id.equals(id))).write(
      RecipesCompanion(
        isFavorite: favorite ? Value(!row.isFavorite) : const Value.absent(),
        isPinned: favorite ? const Value.absent() : Value(!row.isPinned),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<String> duplicateRecipe(
    String id, {
    String? imagePath,
    String? imageThumbnailPath,
    DateTime? imageUpdatedAt,
  }) async {
    final source = await getRecipe(id);
    if (source == null) throw StateError('Recipe not found.');
    return createRecipe(
      RecipeInput(
        title: '${source.recipe.title} Copy',
        description: source.recipe.description,
        servings: source.recipe.servings,
        preparationMinutes: source.recipe.preparationMinutes,
        cookingMinutes: source.recipe.cookingMinutes,
        notes: source.recipe.notes,
        isFavorite: source.recipe.isFavorite,
        isFinished: source.recipe.isFinished,
        ingredients: source.ingredients
            .map(
              (i) => IngredientInput(
                name: i.name,
                quantity: i.quantity,
                unit: i.unit,
                notes: i.notes,
              ),
            )
            .toList(),
        instructions: source.instructions
            .map((i) => InstructionInput(text: i.instructionText))
            .toList(),
        tagNames: source.tags.map((t) => t.name).toList(),
        imagePath: imagePath,
        imageThumbnailPath: imageThumbnailPath,
        imageUpdatedAt: imageUpdatedAt,
      ),
    );
  }

  RecipesCompanion _recipeCompanion(
    RecipeInput value,
    String id,
    DateTime created,
    DateTime updated,
  ) => RecipesCompanion.insert(
    id: id,
    title: value.title.trim(),
    description: Value(_emptyToNull(value.description)),
    servings: Value(value.servings),
    preparationMinutes: Value(value.preparationMinutes),
    cookingMinutes: Value(value.cookingMinutes),
    notes: Value(_emptyToNull(value.notes)),
    isFavorite: Value(value.isFavorite),
    isPinned: Value(value.isPinned),
    isFinished: Value(value.isFinished),
    createdAt: created,
    updatedAt: updated,
    imagePath: Value(value.imagePath),
    imageThumbnailPath: Value(value.imageThumbnailPath),
    imageUpdatedAt: Value(value.imageUpdatedAt),
  );

  Future<void> _insertChildren(String recipeId, RecipeInput input) =>
      database.batch((batch) {
        batch.insertAll(database.ingredients, [
          for (var i = 0; i < input.ingredients.length; i++)
            IngredientsCompanion.insert(
              id: input.ingredients[i].id ?? _uuid.v4(),
              recipeId: recipeId,
              name: input.ingredients[i].name.trim(),
              quantity: Value(_emptyToNull(input.ingredients[i].quantity)),
              unit: Value(_emptyToNull(input.ingredients[i].unit)),
              notes: Value(_emptyToNull(input.ingredients[i].notes)),
              position: i,
            ),
        ]);
        batch.insertAll(database.instructions, [
          for (var i = 0; i < input.instructions.length; i++)
            InstructionsCompanion.insert(
              id: input.instructions[i].id ?? _uuid.v4(),
              recipeId: recipeId,
              instructionText: input.instructions[i].text.trim(),
              position: i,
            ),
        ]);
      });
}

String? _emptyToNull(String? value) =>
    value?.trim().isEmpty ?? true ? null : value!.trim();
