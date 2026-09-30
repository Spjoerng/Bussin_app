import 'package:flutter/material.dart';
import '../../../core/theme/page_content.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/database/app_database.dart';
import '../controllers/recipe_controller.dart';

class TagManagementScreen extends StatefulWidget {
  const TagManagementScreen({super.key});
  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  Map<String, int> _counts = const {};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    final counts = await context.read<RecipeController>().getTagCounts();
    if (!mounted) return;
    setState(() {
      _counts = counts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RecipeController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage tags'),
        actions: [
          IconButton(
            tooltip: 'Remove unused tags',
            onPressed: () async {
              final count = await controller.removeUnusedTags();
              if (!mounted) return;
              await _refreshCounts();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Removed $count unused tag${count == 1 ? '' : 's'}.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editTag(),
        icon: const Icon(Icons.add),
        label: const Text('New tag'),
      ),
      body: PageContent(
        maxWidth: 840,
        child: controller.availableTags.isEmpty
            ? const Center(child: Text('No tags yet.'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: controller.availableTags.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final tag = controller.availableTags[index];
                  final count = _counts[tag.id] ?? 0;
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.placeholder,
                        child: Icon(
                          Icons.sell_outlined,
                          color: AppColors.accent,
                        ),
                      ),
                      title: Text(tag.name),
                      subtitle: Text('$count recipe${count == 1 ? '' : 's'}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') {
                            _editTag(tag);
                          } else {
                            _deleteTag(tag, count);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Delete',
                              style: TextStyle(color: AppColors.destructive),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _editTag([Tag? tag]) async {
    final controller = context.read<RecipeController>();
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _TagNameDialog(initialName: tag?.name, isEditing: tag != null),
    );
    if (name == null) return;
    try {
      if (tag == null) {
        await controller.createTag(name);
      } else {
        await controller.renameTag(tag.id, name);
      }
      if (!mounted) return;
      await _refreshCounts();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _deleteTag(Tag tag, int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${tag.name}”?'),
        content: Text(
          'Recipes will remain, but this tag will be removed from $count recipe${count == 1 ? '' : 's'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<RecipeController>().deleteTag(tag.id);
      if (!mounted) return;
      await _refreshCounts();
    }
  }
}

class _TagNameDialog extends StatefulWidget {
  const _TagNameDialog({required this.initialName, required this.isEditing});

  final String? initialName;
  final bool isEditing;

  @override
  State<_TagNameDialog> createState() => _TagNameDialogState();
}

class _TagNameDialogState extends State<_TagNameDialog> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isEditing ? 'Rename tag' : 'Create tag'),
    content: TextField(
      controller: _field,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Tag name'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _field.text),
        child: const Text('Save'),
      ),
    ],
  );
}
