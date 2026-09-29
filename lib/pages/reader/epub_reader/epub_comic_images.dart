import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart';
import 'package:kover/riverpod/providers/settings/epub_reader_settings.dart';
import 'package:kover/utils/image_size.dart';
import 'package:material_ui/material_ui.dart';

/// Renders only the images in a comic EPUB page.
class EpubComicImages extends StatelessWidget {
  final String html;
  final EpubImageScale scale;

  const EpubComicImages({
    super.key,
    required this.html,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final sources = _imageSources(html);
    if (sources.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: .min,
      children: [
        for (final source in sources)
          _ComicImage(
            source: source,
            scale: scale,
          ),
      ],
    );
  }
}

class _ComicImage extends StatelessWidget {
  final String source;
  final EpubImageScale scale;

  const _ComicImage({
    required this.source,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri(source);
    final pixels = bytes == null ? null : imagePixelSize(bytes);
    final provider = bytes == null ? null : MemoryImage(bytes);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final pageHeight = MediaQuery.sizeOf(context).height;
        final pixelWidth = (pixels?.width ?? width.round())
            .clamp(1, 1000000)
            .toInt();
        final pixelHeight = (pixels?.height ?? pageHeight.round())
            .clamp(1, 1000000)
            .toInt();
        final image = provider == null
            ? Image.network(source, fit: .fill)
            : Image(image: provider, fit: .fill, gaplessPlayback: true);

        return switch (scale) {
          .fit => SizedBox(
            width: width,
            height: pageHeight,
            child: FittedBox(
              fit: .contain,
              child: SizedBox(
                width: pixelWidth.toDouble(),
                height: pixelHeight.toDouble(),
                child: image,
              ),
            ),
          ),
          .fitWidth => SizedBox(
            width: width,
            height: width * pixelHeight / pixelWidth,
            child: image,
          ),
          .original => _OriginalImage(
            availableWidth: width,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            image: image,
          ),
        };
      },
    );
  }
}

class _OriginalImage extends StatelessWidget {
  final double availableWidth;
  final int pixelWidth;
  final int pixelHeight;
  final Widget image;

  const _OriginalImage({
    required this.availableWidth,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.image,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = pixelWidth / dpr;
    final height = pixelHeight / dpr;
    final picture = SizedBox(width: width, height: height, child: image);

    if (width <= availableWidth) {
      return SizedBox(
        width: availableWidth,
        height: height,
        child: Center(child: picture),
      );
    }

    return SingleChildScrollView(
      scrollDirection: .horizontal,
      primary: false,
      child: picture,
    );
  }
}

List<String> _imageSources(String html) {
  final fragment = parseFragment(html);
  return fragment
      .querySelectorAll('img')
      .map((image) => image.attributes['src'])
      .whereType<String>()
      .where((src) => src.isNotEmpty)
      .toList();
}

Uint8List? _decodeDataUri(String source) {
  if (!source.startsWith('data:')) return null;
  final comma = source.indexOf(',');
  if (comma < 0) return null;
  final meta = source.substring(5, comma);
  final data = source.substring(comma + 1);
  if (meta.contains(';base64')) {
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }
  return Uint8List.fromList(Uri.decodeFull(data).codeUnits);
}
