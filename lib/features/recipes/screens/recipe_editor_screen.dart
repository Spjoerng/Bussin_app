import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/database/app_database.dart';
import '../../../data/images/recipe_image_service.dart';
import '../../../data/repositories/recipe_repository.dart';
import '../controllers/recipe_controller.dart';
import '../models/recipe_models.dart';
import '../widgets/recipe_image.dart';

class RecipeEditorScreen extends StatefulWidget {
  const RecipeEditorScreen({
    super.key,
    this.recipe,
    this.recoverLostImage = true,
  });
  final CompleteRecipe? recipe;
  final bool recoverLostImage;
  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _servings;
  late final TextEditingController _prep;
  late final TextEditingController _cook;
  late final TextEditingController _notes;
  final List<_IngredientFields> _ingredients = [];
  final List<_InstructionFields> _instructions = [];
  final Set<String> _tagNames = {};
  final ImagePicker _imagePicker = ImagePicker();
  RecipeImageFiles? _pendingImage;
  bool _removeImage = false;
  bool _finished = false;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final value = widget.recipe;
    _title = TextEditingController(text: value?.recipe.title);
    _description = TextEditingController(text: value?.recipe.description);
    _servings = TextEditingController(text: value?.recipe.servings?.toString());
    _prep = TextEditingController(
      text: value?.recipe.preparationMinutes?.toString(),
    );
    _cook = TextEditingController(
      text: value?.recipe.cookingMinutes?.toString(),
    );
    _notes = TextEditingController(text: value?.recipe.notes);
    _finished = value?.recipe.isFinished ?? false;
    _tagNames.addAll(value?.tags.map((tag) => tag.name) ?? const []);
    _ingredients.addAll(
      value?.ingredients.map(
            (i) => _IngredientFields(
              id: i.id,
              name: i.name,
              quantity: i.quantity,
              unit: i.unit,
              notes: i.notes,
            ),
          ) ??
          [],
    );
    _instructions.addAll(
      value?.instructions.map(
            (i) => _InstructionFields(id: i.id, text: i.instructionText),
          ) ??
          [],
    );
    for (final controller in [
      _title,
      _description,
      _servings,
      _prep,
      _cook,
      _notes,
    ]) {
      controller.addListener(_markDirty);
    }
    if (widget.recoverLostImage) _recoverLostImage();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<bool> _canLeave() async {
    if (!_dirty || _saving) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('Your unsaved changes will be lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final old = widget.recipe?.recipe;
    final input = RecipeInput(
      id: old?.id,
      title: _title.text,
      description: _description.text,
      servings: int.tryParse(_servings.text),
      preparationMinutes: int.tryParse(_prep.text),
      cookingMinutes: int.tryParse(_cook.text),
      notes: _notes.text,
      isFavorite: old?.isFavorite ?? false,
      isPinned: old?.isPinned ?? false,
      isFinished: _finished,
      ingredients: _ingredients
          .where((f) => f.name.text.trim().isNotEmpty)
          .map(
            (f) => IngredientInput(
              id: f.id,
              name: f.name.text,
              quantity: f.quantity.text,
              unit: f.unit.text,
              notes: f.notes.text,
            ),
          )
          .toList(),
      instructions: _instructions
          .where((f) => f.text.text.trim().isNotEmpty)
          .map((f) => InstructionInput(id: f.id, text: f.text.text))
          .toList(),
      tagNames: _tagNames.toList(),
      imagePath:
          _pendingImage?.imagePath ?? (_removeImage ? null : old?.imagePath),
      imageThumbnailPath:
          _pendingImage?.thumbnailPath ??
          (_removeImage ? null : old?.imageThumbnailPath),
      imageUpdatedAt: _pendingImage != null
          ? DateTime.now()
          : (_removeImage ? null : old?.imageUpdatedAt),
    );
    try {
      await context.read<RecipeController>().saveWithImage(
        input,
        previous: widget.recipe,
        pendingImage: _pendingImage,
      );
      _pendingImage = null;
      _dirty = false;
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _pendingImage = null;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty || _saving,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop && await _canLeave() && context.mounted) {
        await _discardPendingAndPop();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.recipe == null ? 'New recipe' : 'Edit recipe'),
        leading: IconButton(
          onPressed: () async {
            if (await _canLeave() && context.mounted) {
              await _discardPendingAndPop();
            }
          },
          icon: const Icon(Icons.close),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            Text('Photo', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.small),
            _imageSection(),
            const SizedBox(height: AppSpacing.xLarge),
            Text(
              'Basic information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.medium),
            TextFormField(
              controller: _title,
              autofocus: widget.recipe == null,
              decoration: const InputDecoration(labelText: 'Title *'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'A title is required.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 480;
                final width = wide
                    ? (constraints.maxWidth - AppSpacing.medium * 2) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: AppSpacing.medium,
                  runSpacing: AppSpacing.medium,
                  children: [
                    SizedBox(
                      width: width,
                      child: _numberField(_servings, 'Servings'),
                    ),
                    SizedBox(
                      width: width,
                      child: _numberField(_prep, 'Prep minutes'),
                    ),
                    SizedBox(
                      width: width,
                      child: _numberField(_cook, 'Cook minutes'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Recipe is complete'),
              subtitle: Text(_finished ? 'Complete' : 'Draft'),
              value: _finished,
              onChanged: (v) => setState(() {
                _finished = v;
                _dirty = true;
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tags',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Select or create tag',
                    onPressed: _selectTags,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
            if (_tagNames.isEmpty)
              const Text('No tags assigned.')
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _tagNames
                    .map(
                      (name) => InputChip(
                        label: Text(name),
                        onDeleted: () => setState(() {
                          _tagNames.remove(name);
                          _dirty = true;
                        }),
                      ),
                    )
                    .toList(),
              ),
            _heading(
              'Ingredients',
              _ingredients.length,
              () => setState(() {
                _ingredients.add(_IngredientFields());
                _dirty = true;
              }),
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ingredients.length,
              onReorderItem: (oldIndex, newIndex) => setState(() {
                _ingredients.insert(newIndex, _ingredients.removeAt(oldIndex));
                _dirty = true;
              }),
              itemBuilder: (_, index) => _ingredientRow(index),
            ),
            _heading(
              'Instructions',
              _instructions.length,
              () => setState(() {
                _instructions.add(_InstructionFields());
                _dirty = true;
              }),
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _instructions.length,
              onReorderItem: (oldIndex, newIndex) => setState(() {
                _instructions.insert(
                  newIndex,
                  _instructions.removeAt(oldIndex),
                );
                _dirty = true;
              }),
              itemBuilder: (_, index) => _instructionRow(index),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _numberField(TextEditingController c, String label) => TextFormField(
    controller: c,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (v) =>
        v!.isNotEmpty && (int.tryParse(v) == null || int.parse(v) < 0)
        ? 'Use 0 or more'
        : null,
  );

  Widget _imageSection() {
    final old = widget.recipe?.recipe;
    final path =
        _pendingImage?.imagePath ?? (_removeImage ? null : old?.imagePath);
    final hasImage = path != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: SizedBox(
            key: ValueKey(path),
            height: 210,
            child: RecipeImage(
              imageService: context.read<RecipeController>().imageService,
              relativePath: path,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _chooseImageSource,
              icon: Icon(
                hasImage
                    ? Icons.cameraswitch_outlined
                    : Icons.add_a_photo_outlined,
              ),
              label: Text(hasImage ? 'Replace photo' : 'Add photo'),
            ),
            if (hasImage)
              TextButton.icon(
                onPressed: _removeSelectedImage,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove photo'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _chooseImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final picked = await _imagePicker.pickImage(source: source);
      if (picked == null || !mounted) return;
      await _setPendingImage(picked.path);
    } catch (error) {
      _showImageError(
        source == ImageSource.camera
            ? 'The camera is unavailable or permission was denied.'
            : 'The photo library is unavailable or permission was denied.',
      );
    }
  }

  Future<void> _recoverLostImage() async {
    try {
      final response = await _imagePicker.retrieveLostData();
      final recovered = response.files?.firstOrNull;
      if (recovered != null && mounted && !_dirty) {
        await _setPendingImage(recovered.path);
      }
    } catch (_) {
      // Recovery is best-effort and never overwrites active edits.
    }
  }

  Future<void> _setPendingImage(String sourcePath) async {
    try {
      final controller = context.read<RecipeController>();
      final prepared = await controller.prepareImage(sourcePath);
      await controller.discardPendingImage(_pendingImage);
      if (!mounted) {
        await controller.discardPendingImage(prepared);
        return;
      }
      setState(() {
        _pendingImage = prepared;
        _removeImage = false;
        _dirty = true;
      });
    } on RecipeImageException catch (error) {
      _showImageError(error.message);
    } catch (_) {
      _showImageError('The selected photo could not be processed.');
    }
  }

  Future<void> _removeSelectedImage() async {
    await context.read<RecipeController>().discardPendingImage(_pendingImage);
    if (mounted) {
      setState(() {
        _pendingImage = null;
        _removeImage = true;
        _dirty = true;
      });
    }
  }

  void _showImageError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _discardPendingAndPop() async {
    await context.read<RecipeController>().discardPendingImage(_pendingImage);
    _pendingImage = null;
    _dirty = false;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _selectTags() async {
    final controller = context.read<RecipeController>();
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TagSelectionSheet(
        initialNames: _tagNames,
        availableTags: controller.availableTags,
      ),
    );
    if (selected != null) {
      setState(() {
        _tagNames
          ..clear()
          ..addAll(selected);
        _dirty = true;
      });
    }
  }

  Widget _heading(String title, int count, VoidCallback add) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xLarge, bottom: 8),
    child: Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: AppSpacing.small),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.placeholder,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text('$count', style: Theme.of(context).textTheme.labelMedium),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: add,
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add'),
        ),
      ],
    ),
  );

  InputDecoration _compactDecoration(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  Widget _ingredientRow(int index) {
    final f = _ingredients[index];
    return Card(
      key: ObjectKey(f),
      margin: const EdgeInsets.only(bottom: AppSpacing.small),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.drag_handle, color: AppColors.mutedText),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: f.name,
                    onChanged: (_) => _markDirty(),
                    decoration: _compactDecoration('Ingredient'),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove ingredient',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _ingredients.removeAt(index).dispose();
                    _dirty = true;
                  }),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.small),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: f.quantity,
                    onChanged: (_) => _markDirty(),
                    decoration: _compactDecoration('Quantity'),
                  ),
                ),
                const SizedBox(width: AppSpacing.small),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: f.unit,
                    onChanged: (_) => _markDirty(),
                    decoration: _compactDecoration('Unit'),
                  ),
                ),
                const SizedBox(width: AppSpacing.small),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: f.notes,
                    onChanged: (_) => _markDirty(),
                    decoration: _compactDecoration('Notes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _instructionRow(int index) {
    final f = _instructions[index];
    return Card(
      key: ObjectKey(f),
      margin: const EdgeInsets.only(bottom: AppSpacing.small),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Icon(Icons.drag_handle, color: AppColors.mutedText),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 13, left: 4, right: 8),
              child: Text(
                '${index + 1}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Expanded(
              child: TextField(
                controller: f.text,
                maxLines: null,
                onChanged: (_) => _markDirty(),
                decoration: _compactDecoration('Step'),
              ),
            ),
            IconButton(
              tooltip: 'Remove step',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _instructions.removeAt(index).dispose();
                _dirty = true;
              }),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _servings, _prep, _cook, _notes]) {
      c.dispose();
    }
    for (final f in _ingredients) {
      f.dispose();
    }
    for (final f in _instructions) {
      f.dispose();
    }
    super.dispose();
  }
}

class _TagSelectionSheet extends StatefulWidget {
  const _TagSelectionSheet({
    required this.initialNames,
    required this.availableTags,
  });

  final Set<String> initialNames;
  final List<Tag> availableTags;

  @override
  State<_TagSelectionSheet> createState() => _TagSelectionSheetState();
}

class _TagSelectionSheetState extends State<_TagSelectionSheet> {
  late final Set<String> _draft;
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _draft = {...widget.initialNames};
    _field = TextEditingController();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _addTag() {
    final name = _field.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final duplicate = _draft.any(
      (value) => normalizeTagName(value) == normalizeTagName(name),
    );
    if (name.isEmpty || duplicate) return;
    setState(() {
      _draft.add(name);
      _field.clear();
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recipe tags',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: widget.availableTags.map((tag) {
                final selected = _draft.any(
                  (name) => normalizeTagName(name) == tag.normalizedName,
                );
                return FilterChip(
                  label: Text(tag.name),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    _draft.removeWhere(
                      (name) => normalizeTagName(name) == tag.normalizedName,
                    );
                    if (value) _draft.add(tag.name);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _field,
                    decoration: const InputDecoration(
                      labelText: 'Create a new tag',
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                IconButton(onPressed: _addTag, icon: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _draft),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _IngredientFields {
  _IngredientFields({
    this.id,
    String? name,
    String? quantity,
    String? unit,
    String? notes,
  }) : name = TextEditingController(text: name),
       quantity = TextEditingController(text: quantity),
       unit = TextEditingController(text: unit),
       notes = TextEditingController(text: notes);
  final String? id;
  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController notes;
  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
    notes.dispose();
  }
}

class _InstructionFields {
  _InstructionFields({this.id, String? text})
    : text = TextEditingController(text: text);
  final String? id;
  final TextEditingController text;
  void dispose() => text.dispose();
}
