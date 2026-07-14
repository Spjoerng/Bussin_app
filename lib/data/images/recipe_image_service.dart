import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class RecipeImageFiles {
  const RecipeImageFiles({
    required this.imagePath,
    required this.thumbnailPath,
  });
  final String imagePath;
  final String thumbnailPath;
}

class RecipeImageException implements Exception {
  const RecipeImageException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

typedef DocumentsDirectoryProvider = Future<Directory> Function();

class RecipeImageService {
  RecipeImageService({
    DocumentsDirectoryProvider? documentsDirectory,
    Uuid? uuid,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _uuid = uuid ?? const Uuid();

  static const originalsDirectory = 'recipe_images/originals';
  static const thumbnailsDirectory = 'recipe_images/thumbnails';
  static const mainMaximumDimension = 1600;
  static const thumbnailMaximumDimension = 500;
  static const mainJpegQuality = 85;
  static const thumbnailJpegQuality = 78;
  static const maximumDecodedDimension = 12000;

  final DocumentsDirectoryProvider _documentsDirectory;
  final Uuid _uuid;

  Future<RecipeImageFiles> importImage(String sourcePath) async {
    final id = _uuid.v4();
    RecipeImageFiles? files;
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const RecipeImageException('This file is not a supported image.');
      }
      if (decoded.width > maximumDecodedDimension ||
          decoded.height > maximumDecodedDimension) {
        throw const RecipeImageException(
          'This image is too large to import safely.',
        );
      }
      final oriented = img.bakeOrientation(decoded);
      final preserveTransparency = oriented.any((pixel) => pixel.a < 255);
      final extension = preserveTransparency ? 'png' : 'jpg';
      files = RecipeImageFiles(
        imagePath: '$originalsDirectory/$id.$extension',
        thumbnailPath: '$thumbnailsDirectory/$id.$extension',
      );
      final main = _resize(oriented, mainMaximumDimension);
      final thumbnail = _resize(oriented, thumbnailMaximumDimension);
      final mainFile = await resolveFile(files.imagePath);
      final thumbnailFile = await resolveFile(files.thumbnailPath);
      await mainFile.parent.create(recursive: true);
      await thumbnailFile.parent.create(recursive: true);
      await mainFile.writeAsBytes(
        preserveTransparency
            ? img.encodePng(main)
            : img.encodeJpg(main, quality: mainJpegQuality),
        flush: true,
      );
      await thumbnailFile.writeAsBytes(
        preserveTransparency
            ? img.encodePng(thumbnail)
            : img.encodeJpg(thumbnail, quality: thumbnailJpegQuality),
        flush: true,
      );
      return files;
    } on RecipeImageException {
      rethrow;
    } catch (error) {
      if (files != null) {
        await deletePair(files.imagePath, files.thumbnailPath);
      }
      if (kDebugMode) debugPrint('Recipe image import failed: $error');
      throw RecipeImageException(
        'The photo could not be processed or saved.',
        error,
      );
    }
  }

  img.Image _resize(img.Image source, int maximum) {
    if (source.width <= maximum && source.height <= maximum) {
      return source.clone();
    }
    if (source.width >= source.height) {
      return img.copyResize(source, width: maximum);
    }
    return img.copyResize(source, height: maximum);
  }

  Future<RecipeImageFiles?> copyPair(
    String? imagePath,
    String? thumbnailPath,
  ) async {
    if (imagePath == null || thumbnailPath == null) return null;
    final sourceMain = await resolveFile(imagePath);
    final sourceThumbnail = await resolveFile(thumbnailPath);
    if (!await sourceMain.exists() || !await sourceThumbnail.exists()) {
      throw const RecipeImageException('The original recipe photo is missing.');
    }
    final id = _uuid.v4();
    final mainExtension = p.extension(imagePath).toLowerCase();
    final thumbnailExtension = p.extension(thumbnailPath).toLowerCase();
    final copy = RecipeImageFiles(
      imagePath: '$originalsDirectory/$id$mainExtension',
      thumbnailPath: '$thumbnailsDirectory/$id$thumbnailExtension',
    );
    try {
      final main = await resolveFile(copy.imagePath);
      final thumbnail = await resolveFile(copy.thumbnailPath);
      await main.parent.create(recursive: true);
      await thumbnail.parent.create(recursive: true);
      await sourceMain.copy(main.path);
      await sourceThumbnail.copy(thumbnail.path);
      return copy;
    } catch (error) {
      await deletePair(copy.imagePath, copy.thumbnailPath);
      throw RecipeImageException(
        'The recipe photo could not be copied.',
        error,
      );
    }
  }

  Future<File> resolveFile(String relativePath) async {
    if (!_isManaged(relativePath)) {
      throw const RecipeImageException('The stored image path is invalid.');
    }
    final root = await _documentsDirectory();
    return File(p.joinAll([root.path, ...p.posix.split(relativePath)]));
  }

  Future<bool> exists(String? relativePath) async =>
      relativePath != null && await (await resolveFile(relativePath)).exists();

  Future<void> deleteRelative(String? relativePath) async {
    if (relativePath == null || !_isManaged(relativePath)) return;
    try {
      final file = await resolveFile(relativePath);
      if (await file.exists()) await file.delete();
    } catch (error) {
      if (kDebugMode) debugPrint('Recipe image cleanup failed: $error');
    }
  }

  Future<void> deletePair(String? imagePath, String? thumbnailPath) async {
    await Future.wait([
      deleteRelative(imagePath),
      deleteRelative(thumbnailPath),
    ]);
  }

  Future<int> removeOrphans(Set<String> referencedRelativePaths) async {
    var removed = 0;
    final root = await _documentsDirectory();
    for (final relativeDirectory in [originalsDirectory, thumbnailsDirectory]) {
      final directory = Directory(
        p.joinAll([root.path, ...p.posix.split(relativeDirectory)]),
      );
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final relative = p.posix.join(
          relativeDirectory,
          p.basename(entity.path),
        );
        if (!referencedRelativePaths.contains(relative)) {
          await entity.delete();
          removed++;
        }
      }
    }
    return removed;
  }

  bool _isManaged(String relativePath) {
    final normalized = p.posix.normalize(relativePath.replaceAll('\\', '/'));
    return !p.posix.isAbsolute(normalized) &&
        !normalized.startsWith('../') &&
        (normalized.startsWith('$originalsDirectory/') ||
            normalized.startsWith('$thumbnailsDirectory/'));
  }
}
