enum BackupType { full, recipe }

enum ImportMode { merge, copies, skipExisting, replaceCookbook }

enum ConflictPolicy { keepLocal, useImported, keepNewer }

class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.exportedAt,
    required this.type,
    required this.recipeCount,
    required this.tagCount,
    required this.imageCount,
    required this.checksums,
    this.preferences,
  });
  static const formatIdentifier = 'offline_cookbook_backup';
  static const currentVersion = 1;
  final int formatVersion;
  final DateTime exportedAt;
  final BackupType type;
  final int recipeCount;
  final int tagCount;
  final int imageCount;
  final Map<String, String> checksums;
  final Map<String, Object?>? preferences;

  Map<String, Object?> toJson() => {
    'format': formatIdentifier,
    'formatVersion': formatVersion,
    'appName': "Bussin'",
    'appVersion': '1.0.0',
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'backupType': type.name,
    'recipeCount': recipeCount,
    'tagCount': tagCount,
    'imageCount': imageCount,
    'checksums': checksums,
    if (preferences != null) 'preferences': preferences,
  };

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    if (json['format'] != formatIdentifier) {
      throw const BackupValidationException("This is not a Bussin' backup.");
    }
    final version = json['formatVersion'];
    if (version != currentVersion) {
      throw const BackupValidationException(
        'This backup version is not supported.',
      );
    }
    final date = DateTime.tryParse(json['exportedAt'] as String? ?? '');
    if (date == null) {
      throw const BackupValidationException(
        'The backup export date is invalid.',
      );
    }
    final type = BackupType.values
        .where((v) => v.name == json['backupType'])
        .firstOrNull;
    if (type == null) {
      throw const BackupValidationException('The backup type is invalid.');
    }
    return BackupManifest(
      formatVersion: version as int,
      exportedAt: date.toUtc(),
      type: type,
      recipeCount: json['recipeCount'] as int? ?? -1,
      tagCount: json['tagCount'] as int? ?? -1,
      imageCount: json['imageCount'] as int? ?? -1,
      checksums: (json['checksums'] as Map? ?? {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      preferences: (json['preferences'] as Map?)?.cast<String, Object?>(),
    );
  }
}

class BackupValidationException implements Exception {
  const BackupValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupExportResult {
  const BackupExportResult({
    required this.filePath,
    required this.recipeCount,
    required this.imageCount,
    this.warnings = const [],
  });
  final String filePath;
  final int recipeCount;
  final int imageCount;
  final List<String> warnings;
}

class ImportPreview {
  const ImportPreview({
    required this.archive,
    required this.newRecipes,
    required this.existingRecipes,
    required this.possibleDuplicates,
    required this.invalidImages,
    this.warnings = const [],
  });
  final ParsedBackup archive;
  final int newRecipes;
  final int existingRecipes;
  final int possibleDuplicates;
  final int invalidImages;
  final List<String> warnings;
}

class ParsedBackup {
  const ParsedBackup({
    required this.manifest,
    required this.recipes,
    required this.tags,
    required this.recipeTags,
    required this.ingredients,
    required this.instructions,
    required this.images,
  });
  final BackupManifest manifest;
  final List<Map<String, Object?>> recipes;
  final List<Map<String, Object?>> tags;
  final List<Map<String, Object?>> recipeTags;
  final List<Map<String, Object?>> ingredients;
  final List<Map<String, Object?>> instructions;
  final Map<String, List<int>> images;
}

class ImportResult {
  const ImportResult({
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.copied = 0,
    this.tagsCreated = 0,
    this.tagsReused = 0,
    this.imagesImported = 0,
    this.imagesSkipped = 0,
    this.preferencesImported = false,
    this.warnings = const [],
  });
  final int added;
  final int updated;
  final int skipped;
  final int copied;
  final int tagsCreated;
  final int tagsReused;
  final int imagesImported;
  final int imagesSkipped;
  final bool preferencesImported;
  final List<String> warnings;
}

class LocalBackupInfo {
  const LocalBackupInfo({
    required this.path,
    required this.filename,
    required this.createdAt,
    required this.recipeCount,
    required this.size,
  });
  final String path;
  final String filename;
  final DateTime createdAt;
  final int recipeCount;
  final int size;
}
