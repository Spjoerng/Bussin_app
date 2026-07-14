import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/database/app_database.dart';
import '../../../data/images/recipe_image_service.dart';
import '../../../data/repositories/recipe_repository.dart';
import '../models/recipe_models.dart';

class RecipeController extends ChangeNotifier {
  RecipeController(
    this.repository, {
    this._preferences,
    RecipeImageService? imageService,
  }) : imageService = imageService ?? RecipeImageService() {
    _recipeSubscription = repository.watchAllRecipes().listen(
      _receiveRecipes,
      onError: _receiveError,
    );
    _tagSubscription = repository.watchAllTags().listen((value) {
      availableTags = value;
      notifyListeners();
    }, onError: _receiveError);
    _restorePreferences();
  }

  static const gridPreferenceKey = 'recipe_library_grid';
  static const sortPreferenceKey = 'recipe_library_sort';
  final RecipeRepository repository;
  final RecipeImageService imageService;
  SharedPreferences? _preferences;
  final Map<String, Timer> _imageDeletionTimers = {};
  final Map<String, CompleteRecipe> _pendingImageDeletions = {};
  late final StreamSubscription<List<CompleteRecipe>> _recipeSubscription;
  late final StreamSubscription<List<Tag>> _tagSubscription;
  List<CompleteRecipe> _allRecipes = [];
  List<CompleteRecipe> _visibleRecipes = [];
  List<Tag> availableTags = [];
  RecipeFilterState filterState = const RecipeFilterState();
  RecipeSortOption sortOption = RecipeSortOption.recentlyUpdated;
  String searchQuery = '';
  bool isGrid = true;
  bool isLoading = true;
  bool isBusy = false;
  Object? error;

  List<CompleteRecipe> get recipes => _visibleRecipes;
  List<CompleteRecipe> get pinnedRecipes =>
      recipes.where((r) => r.recipe.isPinned).toList();
  List<CompleteRecipe> get unpinnedRecipes =>
      recipes.where((r) => !r.recipe.isPinned).toList();
  int get activeFilterCount => filterState.activeCount;
  bool get hasAnyRecipes => _allRecipes.isNotEmpty;

  Future<void> _restorePreferences() async {
    final prefs = _preferences ??= await SharedPreferences.getInstance();
    isGrid = prefs.getBool(gridPreferenceKey) ?? true;
    final stored = prefs.getString(sortPreferenceKey);
    sortOption =
        RecipeSortOption.values.where((v) => v.name == stored).firstOrNull ??
        RecipeSortOption.recentlyUpdated;
    _recompute();
  }

  void _receiveRecipes(List<CompleteRecipe> value) {
    _allRecipes = value;
    isLoading = false;
    error = null;
    _recompute();
  }

  void _receiveError(Object value) {
    error = value;
    isLoading = false;
    notifyListeners();
  }

  void _recompute() {
    _visibleRecipes = applyRecipeQuery(
      _allRecipes,
      searchQuery,
      filterState,
      sortOption,
    );
    notifyListeners();
  }

  void setSearchQuery(String value) {
    searchQuery = value;
    _recompute();
  }

  void clearSearch() {
    searchQuery = '';
    _recompute();
  }

  void setFilters(RecipeFilterState value) {
    filterState = value;
    _recompute();
  }

  void clearFilters() {
    filterState = filterState.clear();
    _recompute();
  }

  Future<void> toggleLayout() async {
    isGrid = !isGrid;
    notifyListeners();
    await _preferences?.setBool(gridPreferenceKey, isGrid);
  }

  Future<void> setSortOption(RecipeSortOption value) async {
    sortOption = value;
    _recompute();
    await _preferences?.setString(sortPreferenceKey, value.name);
  }

  Future<String> save(RecipeInput input) => _run(() async {
    if (input.validateTitle() != null) {
      throw ArgumentError(input.validateTitle());
    }
    if (input.id == null) return repository.createRecipe(input);
    await repository.updateRecipe(input);
    return input.id!;
  });

  Future<RecipeImageFiles> prepareImage(String sourcePath) =>
      imageService.importImage(sourcePath);

  Future<void> discardPendingImage(RecipeImageFiles? files) async {
    if (files != null) {
      await imageService.deletePair(files.imagePath, files.thumbnailPath);
    }
  }

  Future<String> saveWithImage(
    RecipeInput input, {
    CompleteRecipe? previous,
    RecipeImageFiles? pendingImage,
  }) async {
    try {
      final id = await save(input);
      final old = previous?.recipe;
      if (old != null &&
          (old.imagePath != input.imagePath ||
              old.imageThumbnailPath != input.imageThumbnailPath)) {
        await imageService.deletePair(old.imagePath, old.imageThumbnailPath);
      }
      return id;
    } catch (_) {
      await discardPendingImage(pendingImage);
      rethrow;
    }
  }

  Future<CompleteRecipe?> loadRecipe(String id) => repository.getRecipe(id);
  Future<void> toggleFavorite(String id) =>
      _run(() => repository.toggleFavorite(id));
  Future<void> togglePinned(String id) =>
      _run(() => repository.togglePinned(id));
  Future<CompleteRecipe?> delete(String id) => _run(() async {
    final deleted = await repository.deleteRecipe(id);
    if (deleted != null && deleted.recipe.imagePath != null) {
      _pendingImageDeletions[id] = deleted;
      _imageDeletionTimers[id]?.cancel();
      _imageDeletionTimers[id] = Timer(
        const Duration(seconds: 6),
        () => finalizeDeletion(id),
      );
    }
    return deleted;
  });
  Future<void> restore(CompleteRecipe recipe) => _run(() async {
    _imageDeletionTimers.remove(recipe.recipe.id)?.cancel();
    _pendingImageDeletions.remove(recipe.recipe.id);
    await repository.restoreRecipe(recipe);
  });
  Future<void> finalizeDeletion(String id) async {
    _imageDeletionTimers.remove(id)?.cancel();
    final deleted = _pendingImageDeletions.remove(id);
    if (deleted != null) {
      await imageService.deletePair(
        deleted.recipe.imagePath,
        deleted.recipe.imageThumbnailPath,
      );
    }
  }

  Future<String> duplicate(String id) => _run(() async {
    final source = await repository.getRecipe(id);
    if (source == null) throw StateError('Recipe not found.');
    RecipeImageFiles? copied;
    try {
      copied = await imageService.copyPair(
        source.recipe.imagePath,
        source.recipe.imageThumbnailPath,
      );
      return await repository.duplicateRecipe(
        id,
        imagePath: copied?.imagePath,
        imageThumbnailPath: copied?.thumbnailPath,
        imageUpdatedAt: copied == null ? null : DateTime.now(),
      );
    } catch (_) {
      await discardPendingImage(copied);
      rethrow;
    }
  });
  Future<int> removeOrphanImages() async {
    final referenced = await repository.getReferencedImagePaths();
    return imageService.removeOrphans(referenced);
  }

  Future<Tag> createTag(String name) => _run(() => repository.createTag(name));
  Future<void> renameTag(String id, String name) =>
      _run(() => repository.renameTag(id, name));
  Future<void> deleteTag(String id) => _run(() => repository.deleteTag(id));
  Future<int> removeUnusedTags() => _run(repository.removeUnusedTags);
  Future<Map<String, int>> getTagCounts() => repository.getTagCounts();

  Future<void> seedSamples() async {
    if (_allRecipes.isNotEmpty) return;
    await save(
      const RecipeInput(
        title: 'Sunday Pancakes',
        description: 'Soft, golden pancakes for a slow morning.',
        servings: 4,
        preparationMinutes: 10,
        cookingMinutes: 15,
        isFinished: true,
        tagNames: ['Breakfast', 'Quick'],
        ingredients: [
          IngredientInput(name: 'Flour', quantity: '2', unit: 'cups'),
          IngredientInput(name: 'Milk', quantity: '1 1/2', unit: 'cups'),
        ],
        instructions: [
          InstructionInput(text: 'Whisk the dry ingredients.'),
          InstructionInput(text: 'Add milk and cook until golden.'),
        ],
      ),
    );
    await save(
      const RecipeInput(
        title: 'Cozy Tomato Pasta',
        description: 'A simple pantry-friendly dinner.',
        preparationMinutes: 10,
        cookingMinutes: 25,
        isPinned: true,
        tagNames: ['Dinner'],
        ingredients: [
          IngredientInput(name: 'Pasta', quantity: '250', unit: 'g'),
        ],
        instructions: [
          InstructionInput(text: 'Boil pasta and toss with tomato sauce.'),
        ],
      ),
    );
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      return await action();
    } catch (value) {
      error = value;
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final timer in _imageDeletionTimers.values) {
      timer.cancel();
    }
    for (final id in _pendingImageDeletions.keys.toList()) {
      finalizeDeletion(id);
    }
    _recipeSubscription.cancel();
    _tagSubscription.cancel();
    super.dispose();
  }
}

/// Filter categories combine with AND. Selected tags also use AND: a recipe
/// must contain every selected tag.
List<CompleteRecipe> applyRecipeQuery(
  List<CompleteRecipe> source,
  String query,
  RecipeFilterState filters,
  RecipeSortOption sort,
) {
  final words = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  final result = source.where((item) {
    final recipe = item.recipe;
    final searchable = [
      recipe.title,
      recipe.description,
      recipe.notes,
      ...item.ingredients.map((i) => i.name),
      ...item.tags.map((t) => t.name),
    ].whereType<String>().join(' ').toLowerCase();
    if (!words.every(searchable.contains)) return false;
    if (filters.favoritesOnly && !recipe.isFavorite) return false;
    if (filters.pinnedOnly && !recipe.isPinned) return false;
    if (filters.status == RecipeStatusFilter.draft && recipe.isFinished) {
      return false;
    }
    if (filters.status == RecipeStatusFilter.complete && !recipe.isFinished) {
      return false;
    }
    final tagIds = item.tags.map((t) => t.id).toSet();
    if (!tagIds.containsAll(filters.selectedTagIds)) return false;
    if (filters.untaggedOnly && item.tags.isNotEmpty) return false;
    if (filters.maximumTotalMinutes != null &&
        (item.totalMinutes == null ||
            item.totalMinutes! > filters.maximumTotalMinutes!)) {
      return false;
    }
    return true;
  }).toList();
  result.sort((a, b) => compareRecipes(a, b, sort));
  return result;
}

int compareRecipes(CompleteRecipe a, CompleteRecipe b, RecipeSortOption sort) {
  switch (sort) {
    case RecipeSortOption.recentlyUpdated:
      return b.recipe.updatedAt.compareTo(a.recipe.updatedAt);
    case RecipeSortOption.recentlyCreated:
      return b.recipe.createdAt.compareTo(a.recipe.createdAt);
    case RecipeSortOption.alphabeticalAscending:
      return a.recipe.title.toLowerCase().compareTo(
        b.recipe.title.toLowerCase(),
      );
    case RecipeSortOption.alphabeticalDescending:
      return b.recipe.title.toLowerCase().compareTo(
        a.recipe.title.toLowerCase(),
      );
    case RecipeSortOption.shortestTime:
      return _compareTime(a.totalMinutes, b.totalMinutes, longest: false);
    case RecipeSortOption.longestTime:
      return _compareTime(a.totalMinutes, b.totalMinutes, longest: true);
  }
}

int _compareTime(int? a, int? b, {required bool longest}) {
  if (a == null) return b == null ? 0 : 1;
  if (b == null) return -1;
  return longest ? b.compareTo(a) : a.compareTo(b);
}

// Kept for callers of the phase-one pure helper. The library now uses
// [applyRecipeQuery] with complete recipe data.
List<Recipe> filterAndSortRecipes(List<Recipe> recipes, String query) {
  final normalized = query.trim().toLowerCase();
  final result = recipes
      .where(
        (recipe) =>
            normalized.isEmpty ||
            recipe.title.toLowerCase().contains(normalized) ||
            (recipe.description?.toLowerCase().contains(normalized) ?? false),
      )
      .toList();
  result.sort((a, b) {
    final pinned = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
    return pinned != 0 ? pinned : b.updatedAt.compareTo(a.updatedAt);
  });
  return result;
}
