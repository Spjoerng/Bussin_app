import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/database/app_database.dart';
import 'data/repositories/recipe_repository.dart';
import 'features/recipes/controllers/recipe_controller.dart';
import 'features/recipes/screens/recipe_library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  runApp(MyApp(database: database));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.database});
  final AppDatabase database;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => RecipeController(RecipeRepository(database)),
    child: MaterialApp(
      title: "Bussin'",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const RecipeLibraryScreen(),
    ),
  );
}
