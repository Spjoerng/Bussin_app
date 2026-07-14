import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/images/recipe_image_service.dart';

class RecipeImage extends StatefulWidget {
  const RecipeImage({
    super.key,
    required this.imageService,
    this.relativePath,
    this.file,
    this.thumbnail = false,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.showPlaceholder = true,
  });

  final RecipeImageService imageService;
  final String? relativePath;
  final File? file;
  final bool thumbnail;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final bool showPlaceholder;

  @override
  State<RecipeImage> createState() => _RecipeImageState();
}

class _RecipeImageState extends State<RecipeImage> {
  Future<File?>? _fileFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(RecipeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath ||
        oldWidget.file?.path != widget.file?.path) {
      _refresh();
    }
  }

  void _refresh() {
    _fileFuture = widget.file != null
        ? Future.value(widget.file)
        : widget.relativePath == null
        ? null
        : _existingFile(widget.relativePath!);
  }

  Future<File?> _existingFile(String path) async {
    final resolved = await widget.imageService.resolveFile(path);
    return await resolved.exists() ? resolved : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_fileFuture == null) return _placeholder(context);
    return FutureBuilder<File?>(
      future: _fileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final file = snapshot.data;
        return file == null ? _placeholder(context) : _image(context, file);
      },
    );
  }

  Widget _image(BuildContext context, File value) => Semantics(
    image: true,
    label: widget.thumbnail ? 'Recipe photo thumbnail' : 'Recipe photo',
    child: ClipRRect(
      borderRadius: widget.borderRadius,
      child: Image.file(
        value,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(context),
      ),
    ),
  );

  Widget _placeholder(BuildContext context) {
    if (!widget.showPlaceholder) return const SizedBox.shrink();
    return Semantics(
      label: 'No recipe photo available',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: .45),
          borderRadius: widget.borderRadius,
        ),
        child: Center(
          child: Icon(
            Icons.restaurant_menu,
            size: widget.thumbnail ? 30 : 52,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ),
    );
  }
}
