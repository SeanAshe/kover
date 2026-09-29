import 'dart:typed_data';

import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:kover/pages/reader/epub_reader/epub_image_preview.dart';
import 'package:material_ui/material_ui.dart';

class CachedImageFactory extends WidgetFactory {
  final Map<int, MemoryImage> _cache;
  final double? maxHeight;
  final bool interactive;

  CachedImageFactory({this.maxHeight})
    : _cache = {},
      interactive = true;

  CachedImageFactory._({
    required Map<int, MemoryImage> cache,
    required this.maxHeight,
    required this.interactive,
  }) : _cache = cache;

  /// Shares the decoded-image cache without registering tap targets.
  ///
  /// Page measurement builds a second copy of the chapter. Those copies must
  /// not compete with the images on screen.
  CachedImageFactory withoutPreview() {
    return CachedImageFactory._(
      cache: _cache,
      maxHeight: maxHeight,
      interactive: false,
    );
  }

  @override
  Widget? buildImageWidget(
    BuildTree meta,
    ImageSource src,
  ) {
    final svgBytes = _svgBytes(src.url);
    final provider = svgBytes == null ? _rasterProvider(src) : null;
    final inline = provider == null
        ? super.buildImageWidget(meta, src)
        : _rasterImage(src, provider);
    if (inline == null || !interactive) return inline;
    if (provider == null && svgBytes == null) return inline;

    return EpubImageAnchor(
      image: provider,
      svgBytes: svgBytes,
      child: inline,
    );
  }

  Widget _rasterImage(ImageSource src, ImageProvider provider) {
    final hash = Object.hash(src.url, src.url.length);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight ?? double.infinity,
      ),
      child: Image(
        key: ValueKey(hash),
        image: provider,
        gaplessPlayback: true,
        fit: .contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return SizedBox(
            height: src.height ?? maxHeight,
            width: src.width,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
      ),
    );
  }

  ImageProvider? _rasterProvider(ImageSource src) {
    if (_isSvg(src.url)) return null;
    final bytes = bytesFromDataUri(src.url);
    if (bytes != null) {
      final hash = Object.hash(src.url, src.url.length);
      return _cache[hash] ??= MemoryImage(bytes);
    }
    if (src.url.startsWith('http://') || src.url.startsWith('https://')) {
      return NetworkImage(src.url);
    }
    return null;
  }

  Uint8List? _svgBytes(String url) {
    if (!_isSvg(url)) return null;
    return bytesFromDataUri(url);
  }

  bool _isSvg(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('data:image/svg') ||
        lower.split('?').first.endsWith('.svg');
  }
}
