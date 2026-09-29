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

  final _transform = TransformationController();
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _pixelSize;
  bool _failed = false;
  bool _acceptRebuild = false;

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
      _transform.value = Matrix4.identity();
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _stopImage();
    _transform.dispose();
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

  Widget _zoomable(Size source, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = Size(constraints.maxWidth, constraints.maxHeight);
        final fitted = widget.svgBytes != null
            ? view
            : applyBoxFit(.contain, source, view).destination;
        return InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          minScale: 1,
          maxScale: _maxScale,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: math.max(1, fitted.width),
            height: math.max(1, fitted.height),
            child: child,
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
