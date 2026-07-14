import 'dart:io';

import 'package:cookbook_app/data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'version 1 migration preserves existing recipes and adds tags',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cookbook_migration_',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}test.sqlite',
      );
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('''
      CREATE TABLE recipes (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NULL,
        servings INTEGER NULL,
        preparation_minutes INTEGER NULL,
        cooking_minutes INTEGER NULL,
        notes TEXT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
        is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),
        is_finished INTEGER NOT NULL DEFAULT 0 CHECK (is_finished IN (0, 1)),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE ingredients (id TEXT NOT NULL PRIMARY KEY, recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE, name TEXT NOT NULL, quantity TEXT NULL, unit TEXT NULL, notes TEXT NULL, position INTEGER NOT NULL);
      CREATE TABLE instructions (id TEXT NOT NULL PRIMARY KEY, recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE, text TEXT NOT NULL, position INTEGER NOT NULL);
      INSERT INTO recipes (id, title, created_at, updated_at) VALUES ('kept', 'Existing Recipe', 1704067200, 1704067200);
      PRAGMA user_version = 1;
    ''');
      raw.close();

      final database = AppDatabase.forTesting(NativeDatabase(file));
      expect(
        (await database.select(database.recipes).get()).single.title,
        'Existing Recipe',
      );
      expect(await database.select(database.tags).get(), isEmpty);
      expect(await database.select(database.recipeTags).get(), isEmpty);
      await database.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'version 2 migration preserves recipes and tags and adds images',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cookbook_v2_migration_',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}test.sqlite',
      );
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('''
      CREATE TABLE recipes (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT NULL, servings INTEGER NULL, preparation_minutes INTEGER NULL, cooking_minutes INTEGER NULL, notes TEXT NULL, is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)), is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)), is_finished INTEGER NOT NULL DEFAULT 0 CHECK (is_finished IN (0, 1)), created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE ingredients (id TEXT NOT NULL PRIMARY KEY, recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE, name TEXT NOT NULL, quantity TEXT NULL, unit TEXT NULL, notes TEXT NULL, position INTEGER NOT NULL);
      CREATE TABLE instructions (id TEXT NOT NULL PRIMARY KEY, recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE, text TEXT NOT NULL, position INTEGER NOT NULL);
      CREATE TABLE tags (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, normalized_name TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL);
      CREATE TABLE recipe_tags (recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE, tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE, PRIMARY KEY (recipe_id, tag_id));
      CREATE INDEX recipe_tags_tag_id ON recipe_tags (tag_id);
      INSERT INTO recipes (id, title, created_at, updated_at) VALUES ('kept-v2', 'Existing V2 Recipe', 1704067200, 1704067200);
      INSERT INTO tags (id, name, normalized_name, created_at) VALUES ('tag', 'Dinner', 'dinner', 1704067200);
      INSERT INTO recipe_tags (recipe_id, tag_id) VALUES ('kept-v2', 'tag');
      PRAGMA user_version = 2;
    ''');
      raw.close();

      final database = AppDatabase.forTesting(NativeDatabase(file));
      final recipe = (await database.select(database.recipes).get()).single;
      expect(recipe.title, 'Existing V2 Recipe');
      expect(recipe.imagePath, isNull);
      expect(
        (await database.select(database.tags).get()).single.name,
        'Dinner',
      );
      expect(await database.select(database.recipeTags).get(), hasLength(1));
      await database.close();
      await directory.delete(recursive: true);
    },
  );
}
