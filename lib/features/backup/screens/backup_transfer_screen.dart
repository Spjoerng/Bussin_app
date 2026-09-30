import 'package:flutter/material.dart';
import '../../../core/theme/page_content.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../data/backup/backup_models.dart';
import '../../../data/backup/cookbook_backup_service.dart';
import '../../recipes/controllers/recipe_controller.dart';
import '../controllers/backup_transfer_controller.dart';

class BackupTransferScreen extends StatelessWidget {
  const BackupTransferScreen({super.key, this.selectedRecipeIds});
  final Set<String>? selectedRecipeIds;

  @override
  Widget build(BuildContext context) {
    final recipes = context.read<RecipeController>();
    return ChangeNotifierProvider(
      create: (_) => BackupTransferController(
        service: CookbookBackupService(
          repository: recipes.repository,
          imageService: recipes.imageService,
        ),
        repository: recipes.repository,
        imageService: recipes.imageService,
      )..refreshLocalBackups(),
      child: _BackupTransferView(selectedRecipeIds: selectedRecipeIds),
    );
  }
}

class _BackupTransferView extends StatelessWidget {
  const _BackupTransferView({this.selectedRecipeIds});
  final Set<String>? selectedRecipeIds;
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BackupTransferController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and Transfer')),
      body: PageContent(
        maxWidth: 840,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.small,
                AppSpacing.screen,
                40,
              ),
              children: [
                const _Heading('Backup'),
                _ActionTile(
                  icon: Icons.archive_outlined,
                  title: 'Export cookbook',
                  subtitle:
                      'Create a portable backup with recipes, tags, and photos.',
                  onTap: () => _export(context, controller),
                ),
                if (selectedRecipeIds?.isNotEmpty ?? false)
                  _ActionTile(
                    icon: Icons.checklist,
                    title: 'Export selected recipes',
                    subtitle: '${selectedRecipeIds!.length} selected',
                    onTap: () =>
                        _export(context, controller, selectedRecipeIds),
                  ),
                _ActionTile(
                  icon: Icons.save_outlined,
                  title: 'Create local backup',
                  subtitle: 'Keep a manual backup inside the app.',
                  onTap: () => _localBackup(context, controller),
                ),
                const _Heading('Restore'),
                _ActionTile(
                  icon: Icons.unarchive_outlined,
                  title: 'Import cookbook or recipe',
                  subtitle: 'Preview and validate before changing any data.',
                  onTap: () => _pickImport(context, controller),
                ),
                const _Heading('Local backups'),
                if (controller.localBackups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.small,
                      AppSpacing.small,
                      AppSpacing.small,
                      AppSpacing.xLarge,
                    ),
                    child: Text('No local backups yet.'),
                  ),
                ...controller.localBackups.map(
                  (backup) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.small,
                      vertical: AppSpacing.small,
                    ),
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(backup.filename),
                    subtitle: Text(
                      '${backup.recipeCount} recipes • ${_size(backup.size)} • ${backup.createdAt.toLocal().toString().substring(0, 16)}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'restore') {
                          _previewPath(context, controller, backup.path);
                        }
                        if (value == 'share') {
                          controller.shareLocalBackup(backup.path);
                        }
                        if (value == 'delete') {
                          controller.deleteLocalBackup(backup.path);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'restore', child: Text('Restore')),
                        PopupMenuItem(value: 'share', child: Text('Share')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (controller.isBusy)
              ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(controller.progressLabel ?? 'Working…'),
                          if (controller.canCancel) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: controller.requestCancel,
                              child: const Text('Cancel'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    BackupTransferController controller, [
    Set<String>? ids,
  ]) async {
    try {
      final result = await controller.export(recipeIds: ids);
      if (!context.mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export ready'),
          content: Text(
            '${result.recipeCount} recipe${result.recipeCount == 1 ? '' : 's'} and ${result.imageCount} image${result.imageCount == 1 ? '' : 's'} exported.${result.warnings.isEmpty ? '' : '\n\n${result.warnings.join('\n')}'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save as…'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'share'),
              child: const Text('Share'),
            ),
          ],
        ),
      );
      if (action == 'share') await controller.shareExport(result);
      if (action == 'save') await controller.saveExport(result);
    } catch (_) {
      if (context.mounted) {
        _error(
          context,
          'The backup could not be created. No cookbook data was changed.',
        );
      }
    }
  }

  Future<void> _localBackup(
    BuildContext context,
    BackupTransferController controller,
  ) async {
    try {
      final result = await controller.export(local: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Local backup created with ${result.recipeCount} recipes.',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        _error(context, 'The local backup could not be created.');
      }
    }
  }

  Future<void> _pickImport(
    BuildContext context,
    BackupTransferController controller,
  ) async {
    final path = await controller.pickImportFile();
    if (path != null && context.mounted) {
      await _previewPath(context, controller, path);
    }
  }

  Future<void> _previewPath(
    BuildContext context,
    BackupTransferController controller,
    String path,
  ) async {
    try {
      final preview = await controller.buildPreview(path);
      if (context.mounted) {
        await _showImportPreview(context, controller, preview);
      }
    } on BackupValidationException catch (error) {
      if (context.mounted) {
        _error(context, '${error.message}\n\nNo cookbook data was changed.');
      }
    } catch (_) {
      if (context.mounted) {
        _error(
          context,
          'The backup is invalid or corrupted. No cookbook data was changed.',
        );
      }
    }
  }

  Future<void> _showImportPreview(
    BuildContext context,
    BackupTransferController controller,
    ImportPreview preview,
  ) async {
    var mode = ImportMode.merge;
    var policy = ConflictPolicy.keepNewer;
    var preferences = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Import preview'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${preview.archive.manifest.recipeCount} recipes • ${preview.archive.manifest.tagCount} tags • ${preview.archive.manifest.imageCount} images',
                ),
                const SizedBox(height: AppSpacing.xSmall),
                Text(
                  'Exported ${preview.archive.manifest.exportedAt.toLocal()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.medium),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.medium),
                Text('${preview.newRecipes} new'),
                const SizedBox(height: AppSpacing.xSmall),
                Text('${preview.existingRecipes} matching UUIDs'),
                const SizedBox(height: AppSpacing.xSmall),
                Text('${preview.possibleDuplicates} possible title duplicates'),
                if (preview.invalidImages > 0) ...[
                  const SizedBox(height: AppSpacing.xSmall),
                  Text('${preview.invalidImages} missing images'),
                ],
                const SizedBox(height: AppSpacing.large),
                DropdownButtonFormField<ImportMode>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Import mode'),
                  items: ImportMode.values
                      .where(
                        (v) =>
                            v != ImportMode.replaceCookbook ||
                            preview.archive.manifest.type == BackupType.full,
                      )
                      .map(
                        (v) =>
                            DropdownMenuItem(value: v, child: Text(_mode(v))),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => mode = v!),
                ),
                if (mode == ImportMode.merge) ...[
                  const SizedBox(height: AppSpacing.medium),
                  DropdownButtonFormField<ConflictPolicy>(
                    initialValue: policy,
                    decoration: const InputDecoration(
                      labelText: 'Matching recipes',
                    ),
                    items: ConflictPolicy.values
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(_policy(v)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => policy = v!),
                  ),
                ],
                const SizedBox(height: AppSpacing.small),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Import display preferences'),
                  value: preferences,
                  onChanged: (v) => setState(() => preferences = v ?? false),
                ),
                if (mode == ImportMode.replaceCookbook)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.small),
                    child: Text(
                      'Warning: all current recipes will be replaced after a safety backup is created.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
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
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final result = await controller.importPreview(
        mode: mode,
        conflictPolicy: policy,
        importPreferences: preferences,
      );
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import complete'),
            content: Text(
              '${result.added} added\n${result.updated} updated\n${result.copied} imported as copies\n${result.skipped} skipped\n${result.imagesImported} images imported${result.warnings.isEmpty ? '' : '\n\n${result.warnings.join('\n')}'}',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        _error(context, 'Import failed. No cookbook data was changed.');
      }
    }
  }

  void _error(BuildContext context, String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Backup error'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  static String _mode(ImportMode value) => switch (value) {
    ImportMode.merge => 'Merge',
    ImportMode.copies => 'Import as copies',
    ImportMode.skipExisting => 'Skip existing',
    ImportMode.replaceCookbook => 'Replace cookbook',
  };
  static String _policy(ConflictPolicy value) => switch (value) {
    ConflictPolicy.keepLocal => 'Keep local',
    ConflictPolicy.useImported => 'Use imported',
    ConflictPolicy.keepNewer => 'Keep newer',
  };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xSmall,
      AppSpacing.xLarge,
      AppSpacing.xSmall,
      AppSpacing.small,
    ),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: AppSpacing.small),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.large,
        vertical: AppSpacing.small,
      ),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
