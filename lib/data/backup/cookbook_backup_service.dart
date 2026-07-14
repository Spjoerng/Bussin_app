import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/recipes/controllers/recipe_controller.dart';
import '../images/recipe_image_service.dart';
import '../repositories/recipe_repository.dart';
import 'backup_models.dart';

class CookbookBackupService {
  CookbookBackupService({
    required this.repository,
    required this.imageService,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  static const maximumArchiveBytes = 500 * 1024 * 1024;
  static const maximumExtractedBytes = 1024 * 1024 * 1024;
  static const maximumEntries = 10000;
  static const maximumRecipes = 5000;
  static const maximumImages = 10000;
  static const maximumImageBytes = 25 * 1024 * 1024;
  static const maximumJsonBytes = 25 * 1024 * 1024;

  final RecipeRepository repository;
  final RecipeImageService imageService;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;

  Future<BackupExportResult> exportCookbook({
    Set<String>? recipeIds,
    bool localBackup = false,
  }) async {
    final all = await repository.getAllCompleteRecipes();
    final recipes = recipeIds == null
        ? all
        : all.where((r) => recipeIds.contains(r.recipe.id)).toList();
    if (recipes.isEmpty) {
      throw const BackupValidationException('There are no recipes to export.');
    }
    final single = recipes.length == 1 && recipeIds != null;
    final archive = Archive();
    final warnings = <String>[];
    final recipeRows = <Map<String, Object?>>[];
    final ingredientRows = <Map<String, Object?>>[];
    final instructionRows = <Map<String, Object?>>[];
    final recipeTagRows = <Map<String, Object?>>[];
    final usedTags = <String, Map<String, Object?>>{};
    final payloads = <String, List<int>>{};
    var imageCount = 0;

    for (final complete in recipes) {
      final recipe = complete.recipe;
      String? originalEntry;
      String? thumbnailEntry;
      for (final pair in [
        (recipe.imagePath, false),
        (recipe.imageThumbnailPath, true),
      ]) {
        final relative = pair.$1;
        if (relative == null) continue;
        try {
          final file = await imageService.resolveFile(relative);
          if (!await file.exists()) {
            warnings.add('Photo missing for “${recipe.title}”.');
            continue;
          }
          final bytes = await file.readAsBytes();
          final folder = pair.$2 ? 'thumbnails' : 'originals';
          final entry = 'images/$folder/${recipe.id}${p.extension(relative)}';
          payloads[entry] = bytes;
          if (pair.$2) {
            thumbnailEntry = entry;
          } else {
            originalEntry = entry;
          }
          imageCount++;
        } catch (_) {
          warnings.add('A photo for “${recipe.title}” was skipped.');
        }
      }
      recipeRows.add({
        'id': recipe.id,
        'title': recipe.title,
        'description': recipe.description,
        'servings': recipe.servings,
        'preparationMinutes': recipe.preparationMinutes,
        'cookingMinutes': recipe.cookingMinutes,
        'notes': recipe.notes,
        'isFavorite': recipe.isFavorite,
        'isPinned': recipe.isPinned,
        'isFinished': recipe.isFinished,
        'createdAt': recipe.createdAt.toUtc().toIso8601String(),
        'updatedAt': recipe.updatedAt.toUtc().toIso8601String(),
        'imageOriginal': originalEntry,
        'imageThumbnail': thumbnailEntry,
        'imageUpdatedAt': recipe.imageUpdatedAt?.toUtc().toIso8601String(),
      });
      ingredientRows.addAll(
        complete.ingredients.map(
          (i) => {
            'id': i.id,
            'recipeId': recipe.id,
            'name': i.name,
            'quantity': i.quantity,
            'unit': i.unit,
            'notes': i.notes,
            'position': i.position,
          },
        ),
      );
      instructionRows.addAll(
        complete.instructions.map(
          (i) => {
            'id': i.id,
            'recipeId': recipe.id,
            'text': i.instructionText,
            'position': i.position,
          },
        ),
      );
      for (final tag in complete.tags) {
        usedTags[tag.id] = {
          'id': tag.id,
          'name': tag.name,
          'normalizedName': tag.normalizedName,
          'createdAt': tag.createdAt.toUtc().toIso8601String(),
        };
        recipeTagRows.add({'recipeId': recipe.id, 'tagId': tag.id});
      }
    }

    void addJson(String name, Object data) =>
        payloads[name] = utf8.encode(jsonEncode(data));
    if (single) {
      addJson('data/recipe.json', recipeRows.single);
    } else {
      addJson('data/recipes.json', recipeRows);
    }
    addJson('data/tags.json', usedTags.values.toList());
    addJson('data/recipe_tags.json', recipeTagRows);
    addJson('data/ingredients.json', ingredientRows);
    addJson('data/instructions.json', instructionRows);
    final preferences = await SharedPreferences.getInstance();
    final checksums = {
      for (final entry in payloads.entries)
        entry.key: sha256.convert(entry.value).toString(),
    };
    final manifest = BackupManifest(
      formatVersion: BackupManifest.currentVersion,
      exportedAt: DateTime.now().toUtc(),
      type: single ? BackupType.recipe : BackupType.full,
      recipeCount: recipes.length,
      tagCount: usedTags.length,
      imageCount: imageCount,
      checksums: checksums,
      preferences: {
        'isGrid': preferences.getBool(RecipeController.gridPreferenceKey),
        'sort': preferences.getString(RecipeController.sortPreferenceKey),
      },
    );
    payloads['manifest.json'] = utf8.encode(jsonEncode(manifest.toJson()));
    for (final entry in payloads.entries) {
      archive.add(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    final date = DateTime.now().toIso8601String().substring(0, 10);
    final filename = single
        ? '${_safeFilename(recipes.single.recipe.title)}.recipe'
        : 'my_cookbook_$date.cookbook';
    final directory = localBackup
        ? Directory(p.join((await _documentsDirectory()).path, 'backups'))
        : await _temporaryDirectory();
    await directory.create(recursive: true);
    final output = File(p.join(directory.path, filename));
    await output.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    return BackupExportResult(
      filePath: output.path,
      recipeCount: recipes.length,
      imageCount: imageCount,
      warnings: warnings,
    );
  }

  Future<ParsedBackup> readAndValidate(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const BackupValidationException(
        'The selected backup file could not be read.',
      );
    }
    if (await file.length() > maximumArchiveBytes) {
      throw const BackupValidationException('This backup is too large.');
    }
    late Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(
        await file.readAsBytes(),
        verify: true,
      );
    } catch (_) {
      throw const BackupValidationException(
        'The selected file is not a valid cookbook archive.',
      );
    }
    if (archive.length > maximumEntries) {
      throw const BackupValidationException(
        'This backup contains too many entries.',
      );
    }
    final entries = <String, ArchiveFile>{};
    var extractedSize = 0;
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (!_safeArchivePath(name)) {
        throw const BackupValidationException(
          'The backup contains an unsafe file path.',
        );
      }
      if (entries.containsKey(name)) {
        throw const BackupValidationException(
          'The backup contains duplicate entries.',
        );
      }
      if (!entry.isFile) continue;
      extractedSize += entry.size;
      if (extractedSize > maximumExtractedBytes) {
        throw const BackupValidationException(
          'The expanded backup is too large.',
        );
      }
      if (name.startsWith('data/') && entry.size > maximumJsonBytes) {
        throw const BackupValidationException(
          'A backup data file is too large.',
        );
      }
      if (name.startsWith('images/') && entry.size > maximumImageBytes) {
        throw const BackupValidationException('A backup image is too large.');
      }
      if (name.startsWith('images/') &&
          !const {
            '.jpg',
            '.jpeg',
            '.png',
          }.contains(p.extension(name).toLowerCase())) {
        throw const BackupValidationException(
          'The backup contains an unsupported image type.',
        );
      }
      if (name != 'manifest.json' &&
          !name.startsWith('data/') &&
          !name.startsWith('images/')) {
        throw const BackupValidationException(
          'The backup contains an unexpected file.',
        );
      }
      entries[name] = entry;
    }
    final manifestEntry = entries['manifest.json'];
    if (manifestEntry == null) {
      throw const BackupValidationException('The backup manifest is missing.');
    }
    final manifest = BackupManifest.fromJson(_jsonMap(manifestEntry.content));
    final payloadNames = entries.keys
        .where((name) => name != 'manifest.json')
        .toSet();
    if (manifest.checksums.keys.toSet().length != payloadNames.length ||
        !manifest.checksums.keys.toSet().containsAll(payloadNames)) {
      throw const BackupValidationException(
        'The backup checksum list is incomplete.',
      );
    }
    final recipeFile = manifest.type == BackupType.recipe
        ? 'data/recipe.json'
        : 'data/recipes.json';
    for (final required in [
      recipeFile,
      'data/tags.json',
      'data/recipe_tags.json',
      'data/ingredients.json',
      'data/instructions.json',
    ]) {
      if (!entries.containsKey(required)) {
        throw BackupValidationException(
          'Required backup data is missing: $required',
        );
      }
    }
    for (final checksum in manifest.checksums.entries) {
      final entry = entries[checksum.key];
      if (entry == null ||
          sha256.convert(entry.content).toString() != checksum.value) {
        throw const BackupValidationException(
          'Backup checksum verification failed.',
        );
      }
    }
    final recipes = manifest.type == BackupType.recipe
        ? [_jsonMap(entries[recipeFile]!.content)]
        : _jsonList(entries[recipeFile]!.content);
    final tags = _jsonList(entries['data/tags.json']!.content);
    final recipeTags = _jsonList(entries['data/recipe_tags.json']!.content);
    final ingredients = _jsonList(entries['data/ingredients.json']!.content);
    final instructions = _jsonList(entries['data/instructions.json']!.content);
    _validateRecords(
      recipes,
      tags,
      recipeTags,
      ingredients,
      instructions,
      manifest,
    );
    final images = <String, List<int>>{
      for (final entry in entries.entries.where(
        (e) => e.key.startsWith('images/'),
      ))
        entry.key: entry.value.content,
    };
    if (images.length != manifest.imageCount) {
      throw const BackupValidationException('The image count is invalid.');
    }
    return ParsedBackup(
      manifest: manifest,
      recipes: recipes,
      tags: tags,
      recipeTags: recipeTags,
      ingredients: ingredients,
      instructions: instructions,
      images: images,
    );
  }

  Future<List<LocalBackupInfo>> listLocalBackups() async {
    final directory = Directory(
      p.join((await _documentsDirectory()).path, 'backups'),
    );
    if (!await directory.exists()) return [];
    final result = <LocalBackupInfo>[];
    await for (final entity in directory.list()) {
      if (entity is! File || p.extension(entity.path) != '.cookbook') continue;
      try {
        final parsed = await readAndValidate(entity.path);
        final stat = await entity.stat();
        result.add(
          LocalBackupInfo(
            path: entity.path,
            filename: p.basename(entity.path),
            createdAt: stat.modified,
            recipeCount: parsed.manifest.recipeCount,
            size: stat.size,
          ),
        );
      } catch (_) {}
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<void> deleteLocalBackup(String path) async {
    final root = p.normalize(
      p.join((await _documentsDirectory()).path, 'backups'),
    );
    final target = p.normalize(path);
    if (!p.isWithin(root, target)) {
      throw const BackupValidationException('The backup path is invalid.');
    }
    final file = File(target);
    if (await file.exists()) await file.delete();
  }

  Map<String, Object?> _jsonMap(List<int> bytes) {
    try {
      return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
    } catch (_) {
      throw const BackupValidationException('A backup JSON file is invalid.');
    }
  }

  List<Map<String, Object?>> _jsonList(List<int> bytes) {
    try {
      return (jsonDecode(utf8.decode(bytes)) as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
    } catch (_) {
      throw const BackupValidationException('A backup JSON file is invalid.');
    }
  }

  bool _safeArchivePath(String name) {
    final normalized = p.posix.normalize(name);
    return name.isNotEmpty &&
        !p.posix.isAbsolute(name) &&
        !RegExp(r'^[A-Za-z]:').hasMatch(name) &&
        !name.startsWith('../') &&
        normalized == name;
  }

  String _safeFilename(String title) {
    final value = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return value.isEmpty ? 'recipe' : value;
  }

  void _validateRecords(
    List<Map<String, Object?>> recipes,
    List<Map<String, Object?>> tags,
    List<Map<String, Object?>> recipeTags,
    List<Map<String, Object?>> ingredients,
    List<Map<String, Object?>> instructions,
    BackupManifest manifest,
  ) {
    if (recipes.length != manifest.recipeCount ||
        recipes.length > maximumRecipes) {
      throw const BackupValidationException('The recipe count is invalid.');
    }
    if (tags.length != manifest.tagCount) {
      throw const BackupValidationException('The tag count is invalid.');
    }
    final recipeIds = <String>{};
    for (final row in recipes) {
      final id = row['id'];
      if (id is! String ||
          !_validUuid(id) ||
          !recipeIds.add(id) ||
          row['title'] is! String ||
          DateTime.tryParse(row['createdAt'] as String? ?? '') == null ||
          DateTime.tryParse(row['updatedAt'] as String? ?? '') == null) {
        throw const BackupValidationException('A recipe record is invalid.');
      }
      for (final key in ['imageOriginal', 'imageThumbnail']) {
        final path = row[key];
        if (path != null &&
            (path is! String ||
                !_safeArchivePath(path) ||
                !path.startsWith('images/'))) {
          throw const BackupValidationException(
            'A recipe image reference is invalid.',
          );
        }
      }
    }
    final tagIds = <String>{};
    final normalized = <String>{};
    for (final row in tags) {
      final id = row['id'];
      final name = row['normalizedName'];
      if (id is! String ||
          !_validUuid(id) ||
          name is! String ||
          DateTime.tryParse(row['createdAt'] as String? ?? '') == null ||
          !tagIds.add(id) ||
          !normalized.add(name)) {
        throw const BackupValidationException('A tag record is invalid.');
      }
    }
    for (final row in recipeTags) {
      if (!recipeIds.contains(row['recipeId']) ||
          !tagIds.contains(row['tagId'])) {
        throw const BackupValidationException(
          'A recipe-tag relationship is invalid.',
        );
      }
    }
    for (final row in ingredients) {
      if (!_validUuid(row['id'] as String? ?? '') ||
          !recipeIds.contains(row['recipeId']) ||
          row['name'] is! String ||
          row['position'] is! int ||
          (row['position'] as int) < 0) {
        throw const BackupValidationException(
          'A recipe child record is invalid.',
        );
      }
    }
    for (final row in instructions) {
      if (!_validUuid(row['id'] as String? ?? '') ||
          !recipeIds.contains(row['recipeId']) ||
          row['text'] is! String ||
          row['position'] is! int ||
          (row['position'] as int) < 0) {
        throw const BackupValidationException(
          'A recipe child record is invalid.',
        );
      }
    }
    if (manifest.imageCount > maximumImages) {
      throw const BackupValidationException('The image count is invalid.');
    }
  }

  bool _validUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
