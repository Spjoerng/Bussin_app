import 'package:cookbook_app/data/database/app_database.dart';
import 'package:cookbook_app/features/recipes/controllers/recipe_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Recipe recipe(
  String id,
  String title, {
  String? description,
  bool pinned = false,
  int minute = 0,
}) => Recipe(
  id: id,
  title: title,
  description: description,
  isFavorite: false,
  isPinned: pinned,
  isFinished: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026, 1, 1, 0, minute),
);

void main() {
  test('search filters titles and descriptions only', () {
    final values = [
      recipe('1', 'Apple Pie'),
      recipe('2', 'Soup', description: 'With apple'),
      recipe('3', 'Toast'),
    ];
    expect(filterAndSortRecipes(values, 'apple').map((e) => e.id).toSet(), {
      '1',
      '2',
    });
  });

  test('pinned recipes precede more recently updated recipes', () {
    final values = [
      recipe('new', 'New', minute: 20),
      recipe('pinned', 'Pinned', pinned: true, minute: 1),
    ];
    expect(filterAndSortRecipes(values, '').map((e) => e.id), [
      'pinned',
      'new',
    ]);
  });
}
