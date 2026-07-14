import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/recipe_repository.dart';
import '../controllers/recipe_controller.dart';
import '../widgets/recipe_image.dart';
import 'recipe_editor_screen.dart';

class RecipeViewerScreen extends StatefulWidget {
  const RecipeViewerScreen({super.key, required this.recipeId});
  final String recipeId;
  @override
  State<RecipeViewerScreen> createState() => _RecipeViewerScreenState();
}

class _RecipeViewerScreenState extends State<RecipeViewerScreen> {
  late Future<CompleteRecipe?> _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      _future = context.read<RecipeController>().loadRecipe(widget.recipeId);

  @override
  Widget build(BuildContext context) => FutureBuilder<CompleteRecipe?>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final value = snapshot.data;
      if (value == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Recipe not found.')),
        );
      }
      final recipe = value.recipe;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Recipe'),
          actions: [
            IconButton(
              tooltip: 'Favorite',
              onPressed: () async {
                await context.read<RecipeController>().toggleFavorite(
                  recipe.id,
                );
                if (mounted) setState(_reload);
              },
              icon: Icon(
                recipe.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: recipe.isFavorite ? AppColors.destructive : null,
              ),
            ),
            IconButton(
              tooltip: 'Pin',
              onPressed: () async {
                await context.read<RecipeController>().togglePinned(recipe.id);
                if (mounted) setState(_reload);
              },
              icon: Icon(
                recipe.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Edit',
              onPressed: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecipeEditorScreen(recipe: value),
                  ),
                );
                if ((changed ?? false) && mounted) setState(_reload);
              },
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (action) =>
                  action == 'duplicate' ? _duplicate() : _delete(value),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'duplicate',
                  child: ListTile(
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Duplicate'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: AppColors.destructive,
                    ),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: AppColors.destructive),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Material(
          color: Colors.transparent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: [
              if (recipe.imagePath != null) ...[
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Hero(
                    tag: 'recipe-image-${recipe.id}',
                    child: RecipeImage(
                      imageService: context
                          .read<RecipeController>()
                          .imageService,
                      relativePath: recipe.imagePath,
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Text(
                recipe.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (recipe.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  recipe.description!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    recipe.isFinished ? 'Complete' : 'Draft',
                    recipe.isFinished
                        ? Icons.check_circle_outline
                        : Icons.edit_note,
                  ),
                  if (recipe.servings != null)
                    _Chip('${recipe.servings} servings', Icons.people_outline),
                  if (recipe.preparationMinutes != null)
                    _Chip(
                      '${recipe.preparationMinutes} min prep',
                      Icons.timer_outlined,
                    ),
                  if (recipe.cookingMinutes != null)
                    _Chip(
                      '${recipe.cookingMinutes} min cook',
                      Icons.local_fire_department_outlined,
                    ),
                ],
              ),
              if (value.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: value.tags
                      .map((tag) => Chip(label: Text(tag.name)))
                      .toList(),
                ),
              ],
              if (value.ingredients.isNotEmpty) ...[
                const _Heading('Ingredients'),
                ...value.ingredients.map(
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(
                          child: Text(
                            [
                              i.quantity,
                              i.unit,
                              i.name,
                              i.notes,
                            ].where((v) => v?.isNotEmpty ?? false).join(' '),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (value.instructions.isNotEmpty) ...[
                const _Heading('Instructions'),
                ...value.instructions.indexed.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            '${entry.$1 + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(entry.$2.instructionText)),
                      ],
                    ),
                  ),
                ),
              ],
              if (recipe.notes != null) ...[
                const _Heading('Notes'),
                Text(recipe.notes!),
              ],
            ],
          ),
        ),
      );
    },
  );

  Future<void> _duplicate() async {
    await context.read<RecipeController>().duplicate(widget.recipeId);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Recipe duplicated.')));
    }
  }

  Future<void> _delete(CompleteRecipe value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recipe?'),
        content: Text(
          '“${value.recipe.title}” and all of its steps will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final controller = context.read<RecipeController>();
    final deleted = await controller.delete(value.recipe.id);
    if (!mounted) return;
    Navigator.pop(context);
    if (deleted != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Recipe deleted.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => controller.restore(deleted),
          ),
        ),
      );
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.icon);
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) =>
      Chip(avatar: Icon(icon, size: 18), label: Text(label));
}

class _Heading extends StatelessWidget {
  const _Heading(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(
      value,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}
