import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:html/parser.dart';
import 'package:kover/riverpod/providers/settings/epub_reader_settings.dart';
import 'package:kover/utils/image_size.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps comic pages from painting into the status bar / notch.
class ComicNotchClip extends StatelessWidget {
  final Widget child;

  const ComicNotchClip({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    if (top <= 0) return child;
    return ClipRect(
      clipper: _BelowInsetClipper(top),
      child: child,
    );
  }
}

class _BelowInsetClipper extends CustomClipper<Rect> {
  final double top;

  const _BelowInsetClipper(this.top);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, top, size.width, math.max(0, size.height - top));
  }

  @override
  bool shouldReclip(covariant _BelowInsetClipper oldClipper) {
    return oldClipper.top != top;
  }
}

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
          _ComicPage(
            source: source,
            scale: scale,
          ),
      ],
    );
  }
}

class _ComicPage extends StatefulWidget {
  final String source;
  final EpubImageScale scale;

  const _ComicPage({
    required this.source,
    required this.scale,
  });

  @override
  State<_ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends State<_ComicPage> {
  static const double _maxScale = 6;

  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _listenedSource;
  int? _pixelWidth;
  int? _pixelHeight;
  Size? _laidOutSize;
  double? _laidOutNotch;
  _ComicFrame? _frame;

  int _loadGeneration = 0;
  double _scale = 1;
  Offset _pan = Offset.zero;
  double _gestureScale = 1;
  Offset _gestureFocal = Offset.zero;
  Offset _gestureTopLeft = Offset.zero;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  @override
  void didUpdateWidget(covariant _ComicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _pixelWidth = null;
      _pixelHeight = null;
      _frame = null;
      _provider = null;
      _scale = 1;
      _pan = Offset.zero;
      _loadImage();
      return;
    }
    if (oldWidget.scale != widget.scale) {
      _scale = 1;
      _pan = Offset.zero;
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final generation = ++_loadGeneration;
    final source = widget.source;
    final decoded = await compute(_decodeComicImage, source);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _pixelWidth = decoded == null || decoded.width == 0 ? null : decoded.width;
      _pixelHeight = decoded == null || decoded.height == 0
          ? null
          : decoded.height;
      _provider = decoded == null ? NetworkImage(source) : MemoryImage(decoded.bytes);
      _listenedSource = null;
    });
    _listen();
  }

  void _listen() {
    final provider = _provider;
    if (provider == null || _listenedSource == widget.source) return;
    _stopListening();
    _listenedSource = widget.source;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener(
      (info, _) {
        final width = info.image.width;
        final height = info.image.height;
        if (!mounted || (width == _pixelWidth && height == _pixelHeight)) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _pixelWidth = width;
            _pixelHeight = height;
            _scale = 1;
            _pan = Offset.zero;
          });
        });
      },
      onError: (Object _, StackTrace? _) {},
    );
    stream.addListener(_listener!);
  }

  void _stopListening() {
    final listener = _listener;
    if (_stream != null && listener != null) {
      _stream!.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  void _setTransform(double scale, Offset pan) {
    if (_scale == scale && _pan == pan) return;
    setState(() {
      _scale = scale;
      _pan = pan;
    });
  }

  bool _allowPan(Offset total) {
    final frame = _frame;
    if (frame == null) return false;
    final horizontal = total.dx.abs() >= total.dy.abs();
    // Horizontal drags at the initial scale belong to the page view. Claiming
    // them makes the page swipe wait out the gesture arena and feel stuck.
    if (horizontal) {
      return widget.scale != .original && _scale > 1.001;
    }
    if (widget.scale != .original && _scale > 1.001) return true;
    final height = frame.base.height;
    if (widget.scale == .original) {
      return (height - frame.viewHeight).abs() > 0.5;
    }
    return height > frame.viewHeight + 0.5;
  }

  void _onScaleStart(ScaleStartDetails details) {
    final frame = _frame;
    if (frame == null) return;
    _gestureScale = _scale;
    _gestureFocal = details.localFocalPoint;
    _gestureTopLeft = frame.clampTopLeft(
      frame.topLeft(_scale, _pan),
      _scale,
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final frame = _frame;
    if (frame == null) return;
    final zoomable = widget.scale != .original;
    final newScale = zoomable
        ? (_gestureScale * details.scale).clamp(1.0, _maxScale)
        : 1.0;

    // Min scale is the fitted layout. Panning at that scale is only possible
    // when the fitted image is already larger than the safe area.
    if (zoomable &&
        newScale <= 1.001 &&
        (_gestureScale > 1.001 || !frame.overflows)) {
      _setTransform(1, Offset.zero);
      return;
    }

    final local = (_gestureFocal - _gestureTopLeft) / _gestureScale;
    final topLeft = details.localFocalPoint - local * newScale;
    final clamped = frame.clampTopLeft(topLeft, newScale);
    _setTransform(newScale, frame.panFor(clamped, newScale));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : screen.width;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : screen.height;
        final notch = math.min(
          MediaQuery.viewPaddingOf(context).top,
          math.max(0.0, height),
        );
        final safeHeight = math.max(0.0, height - notch);
        final laidOut = Size(width, height);
        if (_laidOutSize != laidOut || _laidOutNotch != notch) {
          _laidOutSize = laidOut;
          _laidOutNotch = notch;
          _scale = 1;
          _pan = Offset.zero;
        }

        return SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: EdgeInsets.only(top: notch),
            child: _buildSafeArea(width, safeHeight),
          ),
        );
      },
    );
  }

  Widget _buildSafeArea(double width, double height) {
    final pixelWidth = _pixelWidth;
    final pixelHeight = _pixelHeight;
    final provider = _provider;
    if (pixelWidth == null ||
        pixelHeight == null ||
        provider == null ||
        width <= 0 ||
        height <= 0) {
      _frame = null;
      return const Center(child: CircularProgressIndicator());
    }

    final frame = _ComicFrame.layout(
      mode: widget.scale,
      viewWidth: width,
      viewHeight: height,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    _frame = frame;
    final topLeft = frame.clampTopLeft(frame.topLeft(_scale, _pan), _scale);
    final drawnWidth = frame.base.width * _scale;
    final drawnHeight = frame.base.height * _scale;

    return RawGestureDetector(
      behavior: .opaque,
      gestures: {
        _ComicScaleRecognizer:
            GestureRecognizerFactoryWithHandlers<_ComicScaleRecognizer>(
              _ComicScaleRecognizer.new,
              (recognizer) {
                recognizer.allowPan = _allowPan;
                recognizer.onStart = _onScaleStart;
                recognizer.onUpdate = _onScaleUpdate;
              },
            ),
      },
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          fit: StackFit.expand,
          children: [
            Positioned(
              left: topLeft.dx,
              top: topLeft.dy,
              width: drawnWidth,
              height: drawnHeight,
              child: Image(
                image: provider,
                fit: .fill,
                gaplessPlayback: true,
                filterQuality: _scale > 1
                    ? FilterQuality.medium
                    : FilterQuality.low,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComicFrame {
  final double viewWidth;
  final double viewHeight;
  final Size base;
  final Offset origin;

  const _ComicFrame({
    required this.viewWidth,
    required this.viewHeight,
    required this.base,
    required this.origin,
  });

  bool get overflows =>
      base.width > viewWidth + 0.5 || base.height > viewHeight + 0.5;

  static _ComicFrame layout({
    required EpubImageScale mode,
    required double viewWidth,
    required double viewHeight,
    required int pixelWidth,
    required int pixelHeight,
    required double devicePixelRatio,
  }) {
    final sourceWidth = math.max(1, pixelWidth).toDouble();
    final sourceHeight = math.max(1, pixelHeight).toDouble();
    final base = switch (mode) {
      .fit => applyBoxFit(
        .contain,
        Size(sourceWidth, sourceHeight),
        Size(viewWidth, viewHeight),
      ).destination,
      .fitWidth => Size(
        viewWidth,
        viewWidth * sourceHeight / sourceWidth,
      ),
      // One source pixel per physical pixel. Logical size is pixels / dpr.
      .original => Size(
        sourceWidth / devicePixelRatio,
        sourceHeight / devicePixelRatio,
      ),
    };
    final origin = switch (mode) {
      .fit => Offset(
        (viewWidth - base.width) / 2,
        (viewHeight - base.height) / 2,
      ),
      .fitWidth => Offset(0, (viewHeight - base.height) / 2),
      .original => Offset.zero,
    };
    return _ComicFrame(
      viewWidth: viewWidth,
      viewHeight: viewHeight,
      base: base,
      origin: origin,
    );
  }

  Offset topLeft(double scale, Offset pan) {
    final width = base.width * scale;
    final height = base.height * scale;
    final center = origin + Offset(base.width / 2, base.height / 2);
    return Offset(center.dx - width / 2, center.dy - height / 2) + pan;
  }

  Offset panFor(Offset topLeft, double scale) {
    return topLeft - this.topLeft(scale, Offset.zero);
  }

  /// Keeps the image inside the safe viewport. The viewport's top is the
  /// bottom of the notch, so the image never draws into the cutout.
  Offset clampTopLeft(Offset topLeft, double scale) {
    final width = base.width * scale;
    final height = base.height * scale;
    return Offset(
      _clampStart(
        start: topLeft.dx,
        content: width,
        viewStart: 0,
        viewEnd: viewWidth,
      ),
      _clampStart(
        start: topLeft.dy,
        content: height,
        viewStart: 0,
        viewEnd: viewHeight,
      ),
    );
  }
}

double _clampStart({
  required double start,
  required double content,
  required double viewStart,
  required double viewEnd,
}) {
  final view = viewEnd - viewStart;
  if (view <= 0) return viewStart;
  if (content <= view) {
    final max = viewEnd - content;
    if (max < viewStart) return viewStart;
    return start.clamp(viewStart, max);
  }
  return start.clamp(viewEnd - content, viewStart);
}

class _ComicScaleRecognizer extends ScaleGestureRecognizer {
  _ComicScaleRecognizer();

  bool Function(Offset delta)? allowPan;
  final Set<int> _pointers = {};
  Offset _moved = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (_pointers.isEmpty) _moved = Offset.zero;
    _pointers.add(event.pointer);
    if (_pointers.length >= 2) {
      resolve(.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
    if (event is PointerMoveEvent && _pointers.length < 2) {
      _moved += event.delta;
      if (_moved.distance <= kTouchSlop) return;
      final allowed = allowPan?.call(_moved) ?? false;
      if (!allowed) {
        resolve(.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }
      resolve(.accepted);
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers.clear();
    _moved = Offset.zero;
    super.didStopTrackingLastPointer(pointer);
  }
}

({Uint8List bytes, int width, int height})? _decodeComicImage(String source) {
  final bytes = _decodeDataUri(source);
  if (bytes == null) return null;
  final size = imagePixelSize(bytes);
  return (
    bytes: bytes,
    width: size?.width ?? 0,
    height: size?.height ?? 0,
  );
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
      return base64Decode(data.replaceAll(RegExp(r'\s+'), ''));
    } catch (_) {
      return null;
    }
  }
  return Uint8List.fromList(Uri.decodeFull(data).codeUnits);
}
