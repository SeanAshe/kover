import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:material_ui/material_ui.dart';

/// Book-page image that opens [EpubImagePreview] when tapped.
///
/// The reader overlay sits above the page and would otherwise take the tap.
/// [tryOpen] lets that overlay hand the tap to the image underneath.
class EpubImageAnchor extends StatefulWidget {
  final Widget child;
  final ImageProvider? image;
  final Uint8List? svgBytes;

  const EpubImageAnchor({
    super.key,
    required this.child,
    this.image,
    this.svgBytes,
  });

  static final Set<EpubImageAnchorState> _anchors = {};
  static bool _opening = false;

  static bool tryOpen(Offset globalPosition) {
    EpubImageAnchorState? target;
    var targetArea = double.infinity;
    for (final anchor in _anchors) {
      final area = anchor.hitArea(globalPosition);
      if (area == null || area >= targetArea) continue;
      target = anchor;
      targetArea = area;
    }
    if (target == null) return false;
    target.open();
    return true;
  }

  @override
  State<EpubImageAnchor> createState() => EpubImageAnchorState();
}

class EpubImageAnchorState extends State<EpubImageAnchor> {
  @override
  void initState() {
    super.initState();
    EpubImageAnchor._anchors.add(this);
  }

  @override
  void activate() {
    super.activate();
    EpubImageAnchor._anchors.add(this);
  }

  @override
  void deactivate() {
    EpubImageAnchor._anchors.remove(this);
    super.deactivate();
  }

  @override
  void dispose() {
    EpubImageAnchor._anchors.remove(this);
    super.dispose();
  }

  /// Area of this image when [globalPosition] lands on it.
  ///
  /// Tiny images (icons, spacers) stay in the page so edge taps can still
  /// turn pages. Measurement copies live on another pipeline and are ignored.
  double? hitArea(Offset globalPosition) {
    if (!mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.owner != RendererBinding.instance.pipelineOwner) return null;
    if (box.size.width < 48 && box.size.height < 48) return null;
    final local = box.globalToLocal(globalPosition);
    if (!(Offset.zero & box.size).contains(local)) return null;
    return box.size.width * box.size.height;
  }

  void open() {
    if (!mounted || EpubImageAnchor._opening) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    if (box.owner != RendererBinding.instance.pipelineOwner) return;
    if (box.size.width < 48 && box.size.height < 48) return;
    final image = widget.image;
    final svgBytes = widget.svgBytes;
    if (image == null && svgBytes == null) return;

    EpubImageAnchor._opening = true;
    Navigator.of(context, rootNavigator: true)
        .push<void>(
          PageRouteBuilder<void>(
            opaque: true,
            transitionDuration: const Duration(milliseconds: 150),
            reverseTransitionDuration: const Duration(milliseconds: 120),
            pageBuilder: (context, animation, _) {
              return FadeTransition(
                opacity: animation,
                child: EpubImagePreview(
                  image: image,
                  svgBytes: svgBytes,
                ),
              );
            },
          ),
        )
        .whenComplete(() => EpubImageAnchor._opening = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: .opaque,
      onTap: open,
      child: widget.child,
    );
  }
}

class EpubImagePreview extends StatefulWidget {
  final ImageProvider? image;
  final Uint8List? svgBytes;

  const EpubImagePreview({
    super.key,
    this.image,
    this.svgBytes,
  });

  @override
  State<EpubImagePreview> createState() => _EpubImagePreviewState();
}

class _EpubImagePreviewState extends State<EpubImagePreview> {
  static const _maxScale = 6.0;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _pixelSize;
  bool _failed = false;
  bool _acceptRebuild = false;
  double _scale = 1;
  double _minScale = 1;
  Offset _topLeft = Offset.zero;
  double _gestureScale = 1;
  Offset _gestureFocal = Offset.zero;
  Offset _gestureTopLeft = Offset.zero;
  Size? _view;
  Size? _base;

  @override
  void initState() {
    super.initState();
    _resolveImage();
    _acceptRebuild = true;
  }

  @override
  void didUpdateWidget(EpubImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _stopImage();
      _pixelSize = null;
      _failed = false;
      _scale = 1;
      _minScale = 1;
      _topLeft = Offset.zero;
      _view = null;
      _base = null;
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _stopImage();
    super.dispose();
  }

  void _resolveImage() {
    final image = widget.image;
    if (image == null) return;
    final stream = image.resolve(const ImageConfiguration());
    _listener = ImageStreamListener(
      (info, _) {
        _pixelSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        if (!_acceptRebuild || !mounted) return;
        setState(() {});
      },
      onError: (_, _) {
        _failed = true;
        if (!_acceptRebuild || !mounted) return;
        setState(() {});
      },
    );
    _stream = stream;
    stream.addListener(_listener!);
  }

  void _stopImage() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _viewport()),
          Positioned(
            top: padding.top + 12,
            right: padding.right + 12,
            child: _closeButton(context),
          ),
        ],
      ),
    );
  }

  Widget _viewport() {
    if (widget.svgBytes != null) {
      return _zoomable(
        const Size.square(1),
        SvgPicture.memory(
          widget.svgBytes!,
          fit: .contain,
        ),
      );
    }
    if (_failed) {
      return const Center(
        child: Icon(KoverIcons.error, color: Colors.white70, size: 48),
      );
    }
    final pixels = _pixelSize;
    final image = widget.image;
    if (pixels == null || image == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return _zoomable(
      pixels,
      Image(
        image: image,
        fit: .fill,
        filterQuality: .medium,
        gaplessPlayback: true,
      ),
    );
  }

  /// Scale that fits [natural] inside [view]. This is the preview's 1x:
  /// smaller images are enlarged, larger ones are shrunk, and pinch zoom
  /// starts here instead of at the bitmap's original pixel size.
  double _fitScale(Size view, Size natural) {
    return math.min(
      view.width / natural.width,
      view.height / natural.height,
    );
  }

  Offset _clamp(Offset topLeft, double scale, Size view, Size base) {
    final width = base.width * scale;
    final height = base.height * scale;
    final dx = width <= view.width
        ? (view.width - width) / 2
        : topLeft.dx.clamp(view.width - width, 0.0).toDouble();
    final dy = height <= view.height
        ? (view.height - height) / 2
        : topLeft.dy.clamp(view.height - height, 0.0).toDouble();
    return Offset(dx, dy);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureScale = _scale;
    _gestureFocal = details.localFocalPoint;
    _gestureTopLeft = _topLeft;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final view = _view;
    final base = _base;
    if (view == null || base == null) return;
    final minScale = _minScale;
    final newScale = (_gestureScale * details.scale).clamp(
      minScale,
      minScale * _maxScale,
    );
    if (newScale <= minScale * 1.001) {
      setState(() {
        _scale = minScale;
        _topLeft = _clamp(Offset.zero, minScale, view, base);
      });
      return;
    }
    final local = (_gestureFocal - _gestureTopLeft) / _gestureScale;
    final topLeft = details.localFocalPoint - local * newScale;
    setState(() {
      _scale = newScale;
      _topLeft = _clamp(topLeft, newScale, view, base);
    });
  }

  Widget _zoomable(Size source, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = Size(constraints.maxWidth, constraints.maxHeight);
        final natural = widget.svgBytes != null
            ? view
            : Size(
                math.max(1, source.width),
                math.max(1, source.height),
              );
        final fit = _fitScale(view, natural);
        if (_view != view || _base != natural || _minScale != fit) {
          _view = view;
          _base = natural;
          _minScale = fit;
          _scale = fit;
          _topLeft = _clamp(Offset.zero, fit, view, natural);
        }
        final topLeft = _clamp(_topLeft, _scale, view, natural);

        return GestureDetector(
          behavior: .opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: topLeft.dx,
                  top: topLeft.dy,
                  width: natural.width * _scale,
                  height: natural.height * _scale,
                  child: child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _closeButton(BuildContext context) {
    return Material(
      color: const Color(0xE6121212),
      elevation: 8,
      shadowColor: Colors.black,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onPressed: () => Navigator.of(context).pop(),
        color: Colors.white,
        icon: const Icon(KoverIcons.close),
      ),
    );
  }
}
