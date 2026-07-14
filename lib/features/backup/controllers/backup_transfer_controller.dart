import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/backup/backup_models.dart';
import '../../../data/backup/cookbook_backup_service.dart';
import '../../../data/images/recipe_image_service.dart';
import '../../../data/repositories/recipe_repository.dart';
import '../../recipes/controllers/recipe_controller.dart';
import '../../recipes/models/recipe_models.dart';

class BackupTransferController extends ChangeNotifier {
  BackupTransferController({
    required this.service,
    required this.repository,
    required this.imageService,
  });
  final CookbookBackupService service;
  final RecipeRepository repository;
  final RecipeImageService imageService;
  bool isBusy = false;
  bool canCancel = false;
  bool _cancelRequested = false;
  String? progressLabel;
  Object? error;
  ImportPreview? preview;
  List<LocalBackupInfo> localBackups = [];

  Future<BackupExportResult> export({
    Set<String>? recipeIds,
    bool local = false,
  }) => _run(() async {
    progressLabel = 'Creating archive…';
    notifyListeners();
    final result = await service.exportCookbook(
      recipeIds: recipeIds,
      localBackup: local,
    );
    if (local) await refreshLocalBackups();
    return result;
  });

  Future<void> shareExport(BackupExportResult result) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.filePath)],
          text: "Bussin' cookbook backup",
        ),
      );

  Future<String?> saveExport(BackupExportResult result) async {
    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return null;
    final destination = p.join(directory, p.basename(result.filePath));
    await File(result.filePath).copy(destination);
    return destination;
  }

  Future<String?> pickImportFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cookbook', 'recipe', 'zip'],
      withData: false,
    );
    return result?.files.single.path;
  }

  Future<ImportPreview> buildPreview(String path) => _run(() async {
    progressLabel = 'Validating backup…';
    notifyListeners();
    final parsed = await service.readAndValidate(path);
    final local = await repository.getAllCompleteRecipes();
    final ids = local.map((r) => r.recipe.id).toSet();
    final titles = local
        .map((r) => r.recipe.title.trim().toLowerCase())
        .toSet();
    var newRecipes = 0, existing = 0, duplicateTitles = 0, invalidImages = 0;
    for (final row in parsed.recipes) {
      final id = row['id'] as String;
      if (ids.contains(id)) {
        existing++;
      } else {
        newRecipes++;
        if (titles.contains((row['title'] as String).trim().toLowerCase())) {
          duplicateTitles++;
        }
      }
      final image = row['imageOriginal'] as String?;
      if (image != null && !parsed.images.containsKey(image)) invalidImages++;
    }
    return preview = ImportPreview(
      archive: parsed,
      newRecipes: newRecipes,
      existingRecipes: existing,
      possibleDuplicates: duplicateTitles,
      invalidImages: invalidImages,
    );
  });

  Future<ImportResult> importPreview({
    required ImportMode mode,
    required ConflictPolicy conflictPolicy,
    bool importPreferences = false,
  }) => _run(() async {
    final selected = preview;
    if (selected == null) {
      throw const BackupValidationException(
        'Choose and validate a backup first.',
      );
    }
    if (mode == ImportMode.replaceCookbook &&
        selected.archive.manifest.type != BackupType.full) {
      throw const BackupValidationException(
        'Replace cookbook is only available for full backups.',
      );
    }
    progressLabel = 'Staging recipe photos…';
    canCancel = true;
    notifyListeners();
    BackupExportResult? safetyBackup;
    if (mode == ImportMode.replaceCookbook) {
      if ((await repository.getAllCompleteRecipes()).isNotEmpty) {
        safetyBackup = await service.exportCookbook();
      }
    }
    final staged = <String, ({String imagePath, String thumbnailPath})>{};
    final createdFiles = <RecipeImageFiles>[];
    final referencedBefore = await repository.getReferencedImagePaths();
    final temp = await getTemporaryDirectory();
    final warnings = <String>[];
    try {
      for (final row in selected.archive.recipes) {
        if (_cancelRequested) {
          throw const BackupValidationException(
            'Import canceled. No cookbook data was changed.',
          );
        }
        final archivePath = row['imageOriginal'] as String?;
        if (archivePath == null) continue;
        final bytes = selected.archive.images[archivePath];
        if (bytes == null) {
          warnings.add('Photo missing for “${row['title']}”.');
          continue;
        }
        final stagingFile = File(
          p.join(
            temp.path,
            'cookbook_import_${row['id']}${p.extension(archivePath)}',
          ),
        );
        try {
          await stagingFile.writeAsBytes(bytes, flush: true);
          final files = await imageService.importImage(stagingFile.path);
          createdFiles.add(files);
          staged[row['id'] as String] = (
            imagePath: files.imagePath,
            thumbnailPath: files.thumbnailPath,
          );
        } catch (_) {
          warnings.add('Photo skipped for “${row['title']}”.');
        } finally {
          if (await stagingFile.exists()) await stagingFile.delete();
        }
      }
      progressLabel = 'Updating cookbook…';
      canCancel = false;
      notifyListeners();
      final result = await repository.applyBackupImport(
        selected.archive,
        mode: mode,
        conflictPolicy: conflictPolicy,
        images: staged,
      );
      final referencedAfter = await repository.getReferencedImagePaths();
      for (final oldPath in referencedBefore.difference(referencedAfter)) {
        await imageService.deleteRelative(oldPath);
      }
      if (importPreferences) {
        await _importPreferences(selected.archive.manifest.preferences);
      }
      if (mode == ImportMode.replaceCookbook) {
        await imageService.removeOrphans(
          await repository.getReferencedImagePaths(),
        );
      }
      if (safetyBackup != null) {
        final file = File(safetyBackup.filePath);
        if (await file.exists()) await file.delete();
      }
      return ImportResult(
        added: result.added,
        updated: result.updated,
        skipped: result.skipped,
        copied: result.copied,
        imagesImported: result.imagesImported,
        tagsCreated: result.tagsCreated,
        tagsReused: result.tagsReused,
        preferencesImported: importPreferences,
        warnings: [...result.warnings, ...warnings],
      );
    } catch (_) {
      for (final files in createdFiles) {
        await imageService.deletePair(files.imagePath, files.thumbnailPath);
      }
      rethrow;
    }
  });

  Future<void> _importPreferences(Map<String, Object?>? values) async {
    if (values == null) return;
    final prefs = await SharedPreferences.getInstance();
    final grid = values['isGrid'];
    final sort = values['sort'];
    if (grid is bool) {
      await prefs.setBool(RecipeController.gridPreferenceKey, grid);
    }
    if (sort is String && RecipeSortOption.values.any((v) => v.name == sort)) {
      await prefs.setString(RecipeController.sortPreferenceKey, sort);
    }
  }

  Future<void> refreshLocalBackups() async {
    localBackups = await service.listLocalBackups();
    notifyListeners();
  }

  Future<void> deleteLocalBackup(String path) async {
    await service.deleteLocalBackup(path);
    await refreshLocalBackups();
  }

  Future<void> shareLocalBackup(String path) => SharePlus.instance.share(
    ShareParams(files: [XFile(path)], text: "Bussin' cookbook backup"),
  );

  void requestCancel() {
    if (canCancel) _cancelRequested = true;
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    isBusy = true;
    canCancel = false;
    _cancelRequested = false;
    error = null;
    notifyListeners();
    try {
      return await action();
    } catch (value) {
      error = value;
      if (kDebugMode) debugPrint('Backup operation failed: $value');
      rethrow;
    } finally {
      isBusy = false;
      canCancel = false;
      progressLabel = null;
      notifyListeners();
    }
  }
}
