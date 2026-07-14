class IngredientInput {
  const IngredientInput({
    this.id,
    required this.name,
    this.quantity,
    this.unit,
    this.notes,
  });

  final String? id;
  final String name;
  final String? quantity;
  final String? unit;
  final String? notes;
}

class InstructionInput {
  const InstructionInput({this.id, required this.text});

  final String? id;
  final String text;
}

class RecipeInput {
  const RecipeInput({
    this.id,
    required this.title,
    this.description,
    this.servings,
    this.preparationMinutes,
    this.cookingMinutes,
    this.notes,
    this.isFavorite = false,
    this.isPinned = false,
    this.isFinished = false,
    this.ingredients = const [],
    this.instructions = const [],
    this.tagNames = const [],
    this.imagePath,
    this.imageThumbnailPath,
    this.imageUpdatedAt,
  });

  final String? id;
  final String title;
  final String? description;
  final int? servings;
  final int? preparationMinutes;
  final int? cookingMinutes;
  final String? notes;
  final bool isFavorite;
  final bool isPinned;
  final bool isFinished;
  final List<IngredientInput> ingredients;
  final List<InstructionInput> instructions;
  final List<String> tagNames;
  final String? imagePath;
  final String? imageThumbnailPath;
  final DateTime? imageUpdatedAt;

  String? validateTitle() =>
      title.trim().isEmpty ? 'A title is required.' : null;
}

enum RecipeStatusFilter { any, draft, complete }

enum RecipeSortOption {
  recentlyUpdated,
  recentlyCreated,
  alphabeticalAscending,
  alphabeticalDescending,
  shortestTime,
  longestTime,
}

class RecipeFilterState {
  const RecipeFilterState({
    this.favoritesOnly = false,
    this.pinnedOnly = false,
    this.status = RecipeStatusFilter.any,
    this.selectedTagIds = const {},
    this.maximumTotalMinutes,
    this.untaggedOnly = false,
  });

  final bool favoritesOnly;
  final bool pinnedOnly;
  final RecipeStatusFilter status;
  final Set<String> selectedTagIds;
  final int? maximumTotalMinutes;
  final bool untaggedOnly;

  bool get isActive => activeCount > 0;
  int get activeCount =>
      (favoritesOnly ? 1 : 0) +
      (pinnedOnly ? 1 : 0) +
      (status == RecipeStatusFilter.any ? 0 : 1) +
      (selectedTagIds.isEmpty ? 0 : 1) +
      (maximumTotalMinutes == null ? 0 : 1) +
      (untaggedOnly ? 1 : 0);

  RecipeFilterState copyWith({
    bool? favoritesOnly,
    bool? pinnedOnly,
    RecipeStatusFilter? status,
    Set<String>? selectedTagIds,
    int? maximumTotalMinutes,
    bool clearMaximumTime = false,
    bool? untaggedOnly,
  }) => RecipeFilterState(
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    pinnedOnly: pinnedOnly ?? this.pinnedOnly,
    status: status ?? this.status,
    selectedTagIds: Set.unmodifiable(selectedTagIds ?? this.selectedTagIds),
    maximumTotalMinutes: clearMaximumTime
        ? null
        : maximumTotalMinutes ?? this.maximumTotalMinutes,
    untaggedOnly: untaggedOnly ?? this.untaggedOnly,
  );

  RecipeFilterState clear() => const RecipeFilterState();

  @override
  bool operator ==(Object other) =>
      other is RecipeFilterState &&
      favoritesOnly == other.favoritesOnly &&
      pinnedOnly == other.pinnedOnly &&
      status == other.status &&
      maximumTotalMinutes == other.maximumTotalMinutes &&
      untaggedOnly == other.untaggedOnly &&
      setEquals(selectedTagIds, other.selectedTagIds);

  @override
  int get hashCode => Object.hash(
    favoritesOnly,
    pinnedOnly,
    status,
    Object.hashAllUnordered(selectedTagIds),
    maximumTotalMinutes,
    untaggedOnly,
  );
}

bool setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
