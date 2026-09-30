import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          surface: AppColors.card,
        ).copyWith(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          error: AppColors.destructive,
          onSurface: AppColors.text,
          onPrimary: AppColors.text,
          onSecondary: AppColors.text,
          primaryContainer: AppColors.placeholder,
          onPrimaryContainer: AppColors.text,
          secondaryContainer: AppColors.placeholder,
          onSecondaryContainer: AppColors.text,
          onSurfaceVariant: AppColors.mutedText,
          surfaceContainer: AppColors.card,
          surfaceContainerHigh: AppColors.card,
          surfaceTint: Colors.transparent,
          outline: AppColors.border,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
    );
    return base.copyWith(
      iconTheme: const IconThemeData(color: AppColors.mutedText),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 24),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.accent,
        textColor: AppColors.text,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.medium)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      textTheme: base.textTheme
          .apply(bodyColor: AppColors.text, displayColor: AppColors.text)
          .copyWith(
            headlineSmall: base.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.35),
            bodySmall: base.textTheme.bodySmall?.copyWith(
              color: AppColors.mutedText,
              height: 1.3,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shadowColor: AppColors.border,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: AppColors.mutedText),
        hintStyle: TextStyle(color: AppColors.mutedText),
        floatingLabelStyle: TextStyle(color: AppColors.text),
        filled: true,
        fillColor: AppColors.card,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.large,
          vertical: AppSpacing.medium,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.medium)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.medium)),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.medium)),
          borderSide: BorderSide(color: AppColors.secondary, width: 1.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.placeholder,
        selectedColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        labelStyle: const TextStyle(color: AppColors.text),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.text,
        elevation: 3,
        shape: StadiumBorder(),
      ),
      dialogTheme: const DialogThemeData(
        constraints: BoxConstraints(maxWidth: 560),
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.large)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        modalBackgroundColor: AppColors.card,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.large),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.text,
        contentTextStyle: TextStyle(color: AppColors.card),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.medium)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.large,
            vertical: AppSpacing.medium,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}
