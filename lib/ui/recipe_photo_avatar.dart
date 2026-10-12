import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../application/recipe_library_controller.dart';
import '../platform/recipe_photo_picker.dart';
import 'recipe_photo_crop_screen.dart';

class RecipePhotoAvatar extends StatefulWidget {
  const RecipePhotoAvatar({
    required this.library,
    required this.recipeId,
    required this.recipeTitle,
    this.picker = pickRecipePhoto,
    super.key,
  });
  final RecipeLibraryController library;
  final String recipeId, recipeTitle;
  final RecipePhotoPicker picker;
  @override
  State<RecipePhotoAvatar> createState() => _RecipePhotoAvatarState();
}

class _RecipePhotoAvatarState extends State<RecipePhotoAvatar> {
  bool _working = false;
  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _edit() async {
    if (_working || widget.library.isSavingPhoto(widget.recipeId)) return;
    setState(() => _working = true);
    try {
      final hasPhoto =
          widget.library.photoFor(widget.recipeId) != null ||
          widget.library.photoErrorFor(widget.recipeId) != null;
      if (hasPhoto) {
        final action = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('写真を変更'),
                  leading: const Icon(Icons.photo_library_outlined),
                  onTap: () => Navigator.pop(context, 'change'),
                ),
                ListTile(
                  title: const Text('写真を外してお皿に戻す'),
                  leading: const Icon(Icons.hide_image_outlined),
                  onTap: () => Navigator.pop(context, 'remove'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || action == null) return;
        if (action == 'remove') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('写真を外しますか？'),
              content: const Text('レシピと端末の元写真は残ります。お皿アイコンに戻します。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('写真を外す'),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
          final error = await widget.library.setRecipePhoto(
            widget.recipeId,
            null,
          );
          _message(error ?? 'お皿アイコンに戻しました');
          return;
        }
      }
      final source = await widget.picker();
      if (source == null || !mounted) return;
      final image = await decodeRecipePhoto(source);
      if (!mounted) {
        image.dispose();
        return;
      }
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => RecipePhotoCropScreen(image: image)),
      );
      if (cropped == null || !mounted) return;
      final error = await widget.library.setRecipePhoto(
        widget.recipeId,
        cropped,
      );
      _message(error ?? '写真を保存しました');
    } catch (_) {
      _message('写真を読み込めませんでした。30MB以下のJPEG・PNG・WebPを選んでください。');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.library,
    builder: (context, _) {
      final bytes = widget.library.photoFor(widget.recipeId);
      final error = widget.library.photoErrorFor(widget.recipeId);
      final label =
          error ?? '${widget.recipeTitle}の写真を${bytes == null ? '追加' : '変更'}';
      return SizedBox.square(
        dimension: 64,
        child: Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('recipe_photo_${widget.recipeId}'),
                customBorder: const CircleBorder(),
                onTap: _working || widget.library.isSavingPhoto(widget.recipeId)
                    ? null
                    : _edit,
                child: widget.library.isSavingPhoto(widget.recipeId)
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : bytes == null
                    ? _placeholder(context)
                    : Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => _placeholder(context),
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _placeholder(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Icon(
        Icons.restaurant,
        size: 30,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
      Positioned(
        right: 4,
        bottom: 4,
        child: Icon(
          Icons.add_a_photo_outlined,
          size: 16,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    ],
  );
}
