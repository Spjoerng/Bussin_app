import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/images/recipe_image_service.dart';
import '../../../data/repositories/recipe_repository.dart';
import 'recipe_image.dart';
import 'favorite_button.dart';

class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onTap,
    required this.onFavorite,
    required this.imageService,
    this.compact = false,
  });
  final CompleteRecipe recipe;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final RecipeImageService imageService;
  final bool compact;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadii.card),
      onTap: onTap,
      child: compact ? _gridContent(context) : _listContent(context),
    ),
  );

  Widget _gridContent(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AspectRatio(
        aspectRatio: 3 / 2,
        child: _photo(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadii.card),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(AppSpacing.card),
        child: _details(context, descriptionLines: 2, tagLimit: 2),
      ),
    ],
  );

  Widget _listContent(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.medium),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: MediaQuery.sizeOf(context).width < 360 ? 76 : 104,
          child: AspectRatio(
            aspectRatio: 1,
            child: _photo(borderRadius: BorderRadius.circular(AppRadii.medium)),
          ),
        ),
        const SizedBox(width: AppSpacing.medium),
        Expanded(child: _details(context, descriptionLines: 3, tagLimit: 3)),
      ],
    ),
  );

  Widget _photo({required BorderRadius borderRadius}) {
    final data = recipe.recipe;
    final image = RecipeImage(
      imageService: imageService,
      relativePath: data.imageThumbnailPath,
      thumbnail: true,
      borderRadius: borderRadius,
    );
    return data.imageThumbnailPath == null
        ? image
        : Hero(tag: 'recipe-image-${data.id}', child: image);
  }

  Widget _details(
    BuildContext context, {
    required int descriptionLines,
    required int tagLimit,
  }) {
    final data = recipe.recipe;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                data.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            AnimatedSwitcher(
              duration: AppDurations.quick,
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: data.isPinned
                  ? const Padding(
                      key: ValueKey(true),
                      padding: EdgeInsets.only(top: 8),
                      child: Icon(
                        Icons.push_pin,
                        size: 17,
                        semanticLabel: 'Pinned recipe',
                      ),
                    )
                  : const SizedBox(key: ValueKey(false)),
            ),
            FavoriteButton(isFavorite: data.isFavorite, onPressed: onFavorite),
          ],
        ),
        if (data.description?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: AppSpacing.xSmall),
          Text(
            data.description!,
            maxLines: descriptionLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (recipe.tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.small),
          Wrap(
            spacing: AppSpacing.xSmall,
            runSpacing: AppSpacing.xSmall,
            children: [
              ...recipe.tags.take(tagLimit).map((tag) => _CompactTag(tag.name)),
              if (recipe.tags.length > tagLimit)
                _CompactTag('+${recipe.tags.length - tagLimit}'),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.small),
        Wrap(
          spacing: AppSpacing.medium,
          runSpacing: AppSpacing.xSmall,
          children: [
            if (recipe.totalMinutes != null)
              _Metadata(
                icon: Icons.schedule,
                label: '${recipe.totalMinutes} min',
              ),
            _Metadata(
              icon: data.isFinished
                  ? Icons.check_circle_outline
                  : Icons.edit_note,
              label: data.isFinished ? 'Complete' : 'Draft',
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactTag extends StatelessWidget {
  const _CompactTag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.placeholder,
      borderRadius: BorderRadius.circular(AppRadii.small),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: icon == Icons.check_circle_outline
              ? AppColors.success
              : AppColors.accent,
        ),
        const SizedBox(width: AppSpacing.xSmall),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.mutedText),
          ),
        ),
      ],
    ),
  );
}
