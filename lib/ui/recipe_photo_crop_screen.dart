import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Future<ui.Image> decodeRecipePhoto(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 30 * 1024 * 1024) {
    throw const FormatException('Photo exceeds the input size limit');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final ratio = math.min(
      1.0,
      1536 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * ratio).round()),
      targetHeight: math.max(1, (descriptor.height * ratio).round()),
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// Normalized center and zoom keep the crop stable across viewport sizes.
Rect recipePhotoCrop(Size imageSize, Offset center, double zoom) {
  final side = imageSize.shortestSide / zoom.clamp(1.0, 4.0);
  final x = (center.dx * imageSize.width).clamp(
    side / 2,
    imageSize.width - side / 2,
  );
  final y = (center.dy * imageSize.height).clamp(
    side / 2,
    imageSize.height - side / 2,
  );
  return Rect.fromCenter(center: Offset(x, y), width: side, height: side);
}

Future<Uint8List> renderRoundRecipePhoto(ui.Image image, Rect crop) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const target = Rect.fromLTWH(0, 0, 512, 512);
  canvas.clipPath(Path()..addOval(target), doAntiAlias: true);
  canvas.drawImageRect(
    image,
    crop,
    target,
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  ui.Image? thumbnail;
  try {
    thumbnail = await picture.toImage(512, 512);
    final png = await thumbnail.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const FormatException('Photo encoding failed');
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  } finally {
    thumbnail?.dispose();
    picture.dispose();
  }
}

class RecipePhotoCropScreen extends StatefulWidget {
  const RecipePhotoCropScreen({required this.image, super.key});

  /// Ownership transfers to this route, including its exit animation.
  final ui.Image image;
  @override
  State<RecipePhotoCropScreen> createState() => _RecipePhotoCropScreenState();
}

class _RecipePhotoCropScreenState extends State<RecipePhotoCropScreen> {
  Offset _center = const Offset(.5, .5),
      _startCenter = const Offset(.5, .5),
      _startFocal = Offset.zero;
  double _zoom = 1, _startZoom = 1;
  bool _saving = false;
  String? _error;
  Size get _imageSize =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());
  Rect get _crop => recipePhotoCrop(_imageSize, _center, _zoom);

  @override
  void dispose() {
    widget.image.dispose();
    super.dispose();
  }

  void _normalizeCenter() {
    final rect = _crop;
    _center = Offset(
      rect.center.dx / _imageSize.width,
      rect.center.dy / _imageSize.height,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final png = await renderRoundRecipePhoto(widget.image, _crop);
      if (mounted) Navigator.pop(context, png);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '写真を切り抜けませんでした。もう一度お試しください。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('写真を丸く切り抜く')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('写真を動かして、料理を丸の中に合わせてください'),
                    const SizedBox(height: 24),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final side = math.min(320.0, constraints.maxWidth);
                        return Center(
                          child: GestureDetector(
                            key: const Key('recipe_photo_crop_area'),
                            onScaleStart: _saving
                                ? null
                                : (details) {
                                    _startCenter = _center;
                                    _startZoom = _zoom;
                                    _startFocal = details.localFocalPoint;
                                  },
                            onScaleUpdate: _saving
                                ? null
                                : (details) => setState(() {
                                    _zoom = (_startZoom * details.scale).clamp(
                                      1.0,
                                      4.0,
                                    );
                                    final delta =
                                        details.localFocalPoint - _startFocal;
                                    final sourceSide =
                                        _imageSize.shortestSide / _zoom;
                                    _center =
                                        _startCenter -
                                        Offset(
                                          delta.dx /
                                              side *
                                              sourceSide /
                                              _imageSize.width,
                                          delta.dy /
                                              side *
                                              sourceSide /
                                              _imageSize.height,
                                        );
                                    _normalizeCenter();
                                  }),
                            child: ClipOval(
                              child: ColoredBox(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: CustomPaint(
                                  size: Size.square(side),
                                  painter: _CropPainter(widget.image, _crop),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    const Text('拡大率'),
                    Slider(
                      key: const Key('recipe_photo_zoom'),
                      value: _zoom,
                      min: 1,
                      max: 4,
                      semanticFormatterCallback: (value) =>
                          '${value.toStringAsFixed(1)}倍',
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _zoom = value;
                              _normalizeCenter();
                            }),
                    ),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _center = const Offset(.5, .5);
                              _zoom = 1;
                            }),
                      child: const Text('中央に戻す'),
                    ),
                    const Text('元の写真は変更しません。丸く切り抜いた写真を端末内に保存します。'),
                    if (_error != null)
                      Semantics(liveRegion: true, child: Text(_error!)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('save_recipe_photo_crop'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '切り抜いています' : 'この範囲で保存'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop);
  final ui.Image image;
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    crop,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.high,
  );
  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      image != oldDelegate.image || crop != oldDelegate.crop;
}
