import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/page_content.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/repositories/recipe_repository.dart';
import '../controllers/recipe_controller.dart';
import '../models/recipe_models.dart';
import '../widgets/recipe_card.dart';
import 'recipe_editor_screen.dart';
import 'recipe_viewer_screen.dart';
import 'tag_management_screen.dart';
import '../../backup/screens/backup_transfer_screen.dart';

class RecipeLibraryScreen extends StatefulWidget {
  const RecipeLibraryScreen({super.key});
  @override
  State<RecipeLibraryScreen> createState() => _RecipeLibraryScreenState();
}

class _RecipeLibraryScreenState extends State<RecipeLibraryScreen> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RecipeController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bussin'"),
        actions: [
          if (kDebugMode && !controller.hasAnyRecipes)
            IconButton(
              tooltip: 'Add sample recipes',
              onPressed: controller.seedSamples,
              icon: const Icon(Icons.auto_awesome),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'tags') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TagManagementScreen(),
                  ),
                );
              } else if (value == 'images') {
                _cleanOrphanImages(controller);
              } else if (value == 'backup') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BackupTransferScreen(),
                  ),
                );
              } else if (value == 'export_selected') {
                _chooseRecipesToExport(controller);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'tags',
                child: ListTile(
                  leading: Icon(Icons.sell_outlined),
                  title: Text('Manage tags'),
                ),
              ),
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  leading: Icon(Icons.import_export),
                  title: Text('Backup and Transfer'),
                ),
              ),
              PopupMenuItem(
                value: 'export_selected',
                child: ListTile(
                  leading: Icon(Icons.checklist),
                  title: Text('Export selected recipes'),
                ),
              ),
              PopupMenuItem(
                value: 'images',
                child: ListTile(
                  leading: Icon(Icons.cleaning_services_outlined),
                  title: Text('Clean unused photos'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: PageContent(
        maxWidth: 1200,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.xSmall,
                AppSpacing.screen,
                AppSpacing.small,
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: controller.setSearchQuery,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search recipes',
                      suffixIcon: controller.searchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _search.clear();
                                controller.clearSearch();
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Badge(
                        isLabelVisible: controller.activeFilterCount > 0,
                        label: Text('${controller.activeFilterCount}'),
                        child: IconButton.filledTonal(
                          tooltip: 'Filter',
                          onPressed: () => _showFilters(context, controller),
                          icon: const Icon(Icons.tune),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xSmall),
                      PopupMenuButton<RecipeSortOption>(
                        tooltip: 'Sort',
                        initialValue: controller.sortOption,
                        onSelected: controller.setSortOption,
                        icon: const Icon(Icons.sort),
                        itemBuilder: (_) => RecipeSortOption.values
                            .map(
                              (value) => PopupMenuItem(
                                value: value,
                                child: Text(_sortLabel(value)),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(width: AppSpacing.xSmall),
                      IconButton.filledTonal(
                        tooltip: controller.isGrid
                            ? 'Use list layout'
                            : 'Use grid layout',
                        onPressed: controller.toggleLayout,
                        icon: Icon(
                          controller.isGrid
                              ? Icons.grid_on_outlined
                              : Icons.view_list_outlined,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (controller.filterState.isActive)
              _ActiveFilters(controller: controller),
            Expanded(
              child: _LibraryBody(
                controller: controller,
                clearSearch: () {
                  _search.clear();
                  controller.clearSearch();
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
    );
  }

  Future<void> _cleanOrphanImages(RecipeController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clean unused photos?'),
        content: const Text(
          'Only image files in the cookbook’s managed folders that are not referenced by a recipe will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clean'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final count = await controller.removeOrphanImages();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed $count unused image file${count == 1 ? '' : 's'}.',
          ),
        ),
      );
    }
  }

  Future<void> _chooseRecipesToExport(RecipeController controller) async {
    final selected = <String>{};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            selected.isEmpty
                ? 'Select recipes to export'
                : '${selected.length} selected',
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.small,
            AppSpacing.small,
            AppSpacing.small,
            0,
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 0,
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: SizedBox(
              width: 480,
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.small,
                ),
                itemCount: controller.recipes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final item = controller.recipes[index];
                  return CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.small,
                      vertical: AppSpacing.xSmall,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selected.contains(item.recipe.id),
                    title: Text(item.recipe.title),
                    onChanged: (value) => setDialogState(() {
                      if (value ?? false) {
                        selected.add(item.recipe.id);
                      } else {
                        selected.remove(item.recipe.id);
                      }
                    }),
                  );
                },
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            AppSpacing.large,
            AppSpacing.small,
            AppSpacing.large,
            AppSpacing.large,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, {...selected}),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BackupTransferScreen(selectedRecipeIds: result),
        ),
      );
    }
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.controller});
  final RecipeController controller;
  @override
  Widget build(BuildContext context) {
    final f = controller.filterState;
    return SizedBox(
      height: 40 + MediaQuery.textScalerOf(context).scale(20),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (f.favoritesOnly) const Chip(label: Text('Favorites')),
          if (f.pinnedOnly) const Chip(label: Text('Pinned')),
          if (f.status != RecipeStatusFilter.any)
            Chip(label: Text(f.status.name)),
          ...f.selectedTagIds.map(
            (id) => Chip(
              label: Text(
                controller.availableTags
                        .where((t) => t.id == id)
                        .firstOrNull
                        ?.name ??
                    'Tag',
              ),
            ),
          ),
          if (f.maximumTotalMinutes != null)
            Chip(label: Text('≤ ${f.maximumTotalMinutes} min')),
          if (f.untaggedOnly) const Chip(label: Text('Untagged')),
          TextButton(
            onPressed: controller.clearFilters,
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }
}

class _LibraryBody extends StatelessWidget {
  const _LibraryBody({required this.controller, required this.clearSearch});
  final RecipeController controller;
  final VoidCallback clearSearch;
  @override
  Widget build(BuildContext context) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && !controller.hasAnyRecipes) {
      return Center(
        child: Text(
          'Could not load recipes.\n${controller.error}',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (controller.recipes.isEmpty) {
      final hasSearch = controller.searchQuery.trim().isNotEmpty;
      final hasFilters = controller.filterState.isActive;
      final title = !controller.hasAnyRecipes
          ? 'Your cookbook is ready.'
          : hasFilters
          ? 'No recipes match these filters.'
          : 'No matching recipes.';
      return Align(
        alignment: const Alignment(0, -0.18),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_outlined, size: 72),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (!controller.hasAnyRecipes)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Add your first recipe and make it yours.',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (hasSearch)
                TextButton(
                  onPressed: clearSearch,
                  child: const Text('Clear search'),
                ),
            ],
          ),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: ListView(
        key: ValueKey('${controller.isGrid}-${controller.sortOption}'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          if (controller.pinnedRecipes.isNotEmpty) ...[
            const _SectionTitle('Pinned'),
            _RecipeCollection(
              recipes: controller.pinnedRecipes,
              isGrid: controller.isGrid,
            ),
            const SizedBox(height: 24),
          ],
          const _SectionTitle('All recipes'),
          _RecipeCollection(
            recipes: controller.unpinnedRecipes,
            isGrid: controller.isGrid,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

class _RecipeCollection extends StatelessWidget {
  const _RecipeCollection({required this.recipes, required this.isGrid});
  final List<CompleteRecipe> recipes;
  final bool isGrid;
  @override
  Widget build(BuildContext context) {
    if (recipes.isEmpty) return const SizedBox.shrink();
    Widget card(CompleteRecipe item) => RecipeCard(
      recipe: item,
      imageService: context.read<RecipeController>().imageService,
      compact: isGrid,
      onFavorite: () =>
          context.read<RecipeController>().toggleFavorite(item.recipe.id),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecipeViewerScreen(recipeId: item.recipe.id),
        ),
      ),
    );
    if (!isGrid) {
      return Column(
        children: [
          for (final item in recipes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.grid),
              child: card(item),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (_, constraints) {
        final columns =
            ((constraints.maxWidth + AppSpacing.grid) /
                    (180 *
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(1).clamp(1, 1.5) +
                        AppSpacing.grid))
                .floor()
                .clamp(1, 4);
        return MasonryGridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.grid,
          mainAxisSpacing: AppSpacing.grid,
          itemCount: recipes.length,
          itemBuilder: (_, i) => card(recipes[i]),
        );
      },
    );
  }
}

Future<void> _showFilters(
  BuildContext context,
  RecipeController controller,
) async {
  var draft = controller.filterState;
  final result = await showModalBottomSheet<RecipeFilterState>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Filter recipes',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Favorites only'),
                  value: draft.favoritesOnly,
                  onChanged: (v) => setModalState(
                    () => draft = draft.copyWith(favoritesOnly: v),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pinned only'),
                  value: draft.pinnedOnly,
                  onChanged: (v) => setModalState(
                    () => draft = draft.copyWith(pinnedOnly: v),
                  ),
                ),
                SegmentedButton<RecipeStatusFilter>(
                  segments: const [
                    ButtonSegment(
                      value: RecipeStatusFilter.any,
                      label: Text('Any'),
                    ),
                    ButtonSegment(
                      value: RecipeStatusFilter.draft,
                      label: Text('Draft'),
                    ),
                    ButtonSegment(
                      value: RecipeStatusFilter.complete,
                      label: Text('Complete'),
                    ),
                  ],
                  selected: {draft.status},
                  onSelectionChanged: (v) => setModalState(
                    () => draft = draft.copyWith(status: v.single),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Tags', style: Theme.of(context).textTheme.titleMedium),
                Wrap(
                  spacing: 6,
                  children: controller.availableTags
                      .map(
                        (tag) => FilterChip(
                          label: Text(tag.name),
                          selected: draft.selectedTagIds.contains(tag.id),
                          onSelected: (selected) => setModalState(() {
                            final ids = {...draft.selectedTagIds};
                            selected ? ids.add(tag.id) : ids.remove(tag.id);
                            draft = draft.copyWith(
                              selectedTagIds: ids,
                              untaggedOnly: false,
                            );
                          }),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: draft.maximumTotalMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Maximum total time',
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Any duration')),
                    DropdownMenuItem(
                      value: 15,
                      child: Text('15 minutes or less'),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text('30 minutes or less'),
                    ),
                    DropdownMenuItem(
                      value: 60,
                      child: Text('60 minutes or less'),
                    ),
                    DropdownMenuItem(
                      value: 120,
                      child: Text('120 minutes or less'),
                    ),
                  ],
                  onChanged: (v) => setModalState(
                    () => draft = v == null
                        ? draft.copyWith(clearMaximumTime: true)
                        : draft.copyWith(maximumTotalMinutes: v),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Recipes with no tags'),
                  value: draft.untaggedOnly,
                  onChanged: (v) => setModalState(
                    () => draft = draft.copyWith(
                      untaggedOnly: v,
                      selectedTagIds: v ? {} : draft.selectedTagIds,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setModalState(
                        () => draft = const RecipeFilterState(),
                      ),
                      child: const Text('Reset'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, draft),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (result != null) controller.setFilters(result);
}

String _sortLabel(RecipeSortOption value) => switch (value) {
  RecipeSortOption.recentlyUpdated => 'Recently updated',
  RecipeSortOption.recentlyCreated => 'Recently created',
  RecipeSortOption.alphabeticalAscending => 'Alphabetical A–Z',
  RecipeSortOption.alphabeticalDescending => 'Alphabetical Z–A',
  RecipeSortOption.shortestTime => 'Shortest total time',
  RecipeSortOption.longestTime => 'Longest total time',
};
