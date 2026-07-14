import 'dart:io';

import 'package:cookbook_app/data/database/app_database.dart';
import 'package:cookbook_app/data/images/recipe_image_service.dart';
import 'package:cookbook_app/data/repositories/recipe_repository.dart';
import 'package:cookbook_app/features/recipes/controllers/recipe_controller.dart';
import 'package:cookbook_app/features/recipes/models/recipe_models.dart';
import 'package:cookbook_app/features/recipes/widgets/recipe_image.dart';
import 'package:cookbook_app/features/recipes/widgets/recipe_card.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory directory;
  late RecipeImageService images;
  late AppDatabase database;
  late RecipeRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cookbook_images_');
    images = RecipeImageService(documentsDirectory: () async => directory);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = RecipeRepository(database);
  });
  tearDown(() async {
    await database.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<File> sourceImage() async {
    final source = File('${directory.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(
      img.encodePng(img.Image(width: 1800, height: 900)),
    );
    return source;
  }

  test('imports resized images and returns relative managed paths', () async {
    final result = await images.importImage((await sourceImage()).path);
    expect(result.imagePath, startsWith('recipe_images/originals/'));
    expect(result.thumbnailPath, startsWith('recipe_images/thumbnails/'));
    expect(result.imagePath, isNot(startsWith(directory.path)));
    final main = img.decodeImage(
      await (await images.resolveFile(result.imagePath)).readAsBytes(),
    )!;
    final thumbnail = img.decodeImage(
      await (await images.resolveFile(result.thumbnailPath)).readAsBytes(),
    )!;
    expect(main.width, 1600);
    expect(thumbnail.width, 500);
  });

  test(
    'creates, keeps, replaces, and removes recipe image metadata safely',
    () async {
      final first = await images.importImage((await sourceImage()).path);
      final id = await repository.createRecipe(
        RecipeInput(
          title: 'Photo recipe',
          imagePath: first.imagePath,
          imageThumbnailPath: first.thumbnailPath,
          imageUpdatedAt: DateTime(2026),
        ),
      );
      expect(
        (await repository.getRecipe(id))!.recipe.imagePath,
        first.imagePath,
      );

      final current = await repository.getRecipe(id);
      await repository.updateRecipe(
        RecipeInput(
          id: id,
          title: 'Kept',
          imagePath: current!.recipe.imagePath,
          imageThumbnailPath: current.recipe.imageThumbnailPath,
          imageUpdatedAt: current.recipe.imageUpdatedAt,
        ),
      );
      expect(
        (await repository.getRecipe(id))!.recipe.imagePath,
        first.imagePath,
      );

      SharedPreferences.setMockInitialValues({});
      final controller = RecipeController(
        repository,
        preferences: await SharedPreferences.getInstance(),
        imageService: images,
      );
      final replacement = await images.importImage((await sourceImage()).path);
      await controller.saveWithImage(
        RecipeInput(
          id: id,
          title: 'Replaced',
          imagePath: replacement.imagePath,
          imageThumbnailPath: replacement.thumbnailPath,
          imageUpdatedAt: DateTime.now(),
        ),
        previous: current,
        pendingImage: replacement,
      );
      expect(await images.exists(first.imagePath), isFalse);
      final replaced = await repository.getRecipe(id);
      await controller.saveWithImage(
        RecipeInput(id: id, title: 'Removed'),
        previous: replaced,
      );
      expect((await repository.getRecipe(id))!.recipe.imagePath, isNull);
      expect(await images.exists(replacement.imagePath), isFalse);
      controller.dispose();
    },
  );

  test(
    'failed save and canceled pending image clean generated files',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = RecipeController(
        repository,
        preferences: await SharedPreferences.getInstance(),
        imageService: images,
      );
      final pending = await images.importImage((await sourceImage()).path);
      await expectLater(
        controller.saveWithImage(
          RecipeInput(
            title: ' ',
            imagePath: pending.imagePath,
            imageThumbnailPath: pending.thumbnailPath,
          ),
          pendingImage: pending,
        ),
        throwsArgumentError,
      );
      expect(await images.exists(pending.imagePath), isFalse);
      final canceled = await images.importImage((await sourceImage()).path);
      await controller.discardPendingImage(canceled);
      expect(await images.exists(canceled.imagePath), isFalse);
      controller.dispose();
    },
  );

  test(
    'delete finalization removes images while undo preserves them',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = RecipeController(
        repository,
        preferences: await SharedPreferences.getInstance(),
        imageService: images,
      );
      final files = await images.importImage((await sourceImage()).path);
      final id = await repository.createRecipe(
        RecipeInput(
          title: 'Delete me',
          imagePath: files.imagePath,
          imageThumbnailPath: files.thumbnailPath,
        ),
      );
      final deleted = await controller.delete(id);
      expect(await images.exists(files.imagePath), isTrue);
      await controller.restore(deleted!);
      expect(await images.exists(files.imagePath), isTrue);
      await controller.delete(id);
      await controller.finalizeDeletion(id);
      expect(await images.exists(files.imagePath), isFalse);
      controller.dispose();
    },
  );

  test('duplicates physical image files with new names', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecipeController(
      repository,
      preferences: await SharedPreferences.getInstance(),
      imageService: images,
    );
    final files = await images.importImage((await sourceImage()).path);
    final id = await repository.createRecipe(
      RecipeInput(
        title: 'Original',
        imagePath: files.imagePath,
        imageThumbnailPath: files.thumbnailPath,
      ),
    );
    final copyId = await controller.duplicate(id);
    final copy = (await repository.getRecipe(copyId))!.recipe;
    expect(copy.imagePath, isNot(files.imagePath));
    expect(await images.exists(copy.imagePath), isTrue);
    controller.dispose();
  });

  test('orphan cleanup only removes unreferenced managed files', () async {
    final referenced = await images.importImage((await sourceImage()).path);
    final orphan = await images.importImage((await sourceImage()).path);
    final removed = await images.removeOrphans({
      referenced.imagePath,
      referenced.thumbnailPath,
    });
    expect(removed, 2);
    expect(await images.exists(referenced.imagePath), isTrue);
    expect(await images.exists(orphan.imagePath), isFalse);
  });

  testWidgets('missing image uses fallback placeholder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 120,
          child: RecipeImage(imageService: images),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
  });

  testWidgets('recipe card includes its thumbnail widget', (tester) async {
    final recipe = CompleteRecipe(
      Recipe(
        id: 'card',
        title: 'Photo card',
        imageThumbnailPath: 'recipe_images/thumbnails/card.jpg',
        isFavorite: false,
        isPinned: false,
        isFinished: false,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      const [],
      const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 360,
            child: RecipeCard(
              recipe: recipe,
              imageService: images,
              compact: true,
              onTap: () {},
              onFavorite: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(RecipeImage), findsOneWidget);
  });
}
