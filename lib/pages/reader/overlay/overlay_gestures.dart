import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kover/mapping/enums/read_direction.dart';
import 'package:kover/pages/reader/epub_reader/epub_image_preview.dart';
import 'package:kover/pages/reader/overlay/overlay_gestures_provider.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

class OverlayGestures extends ConsumerWidget {
  final int seriesId;
  final VoidCallback? onCenterTap;
  final VoidCallback? onLeftTap;
  final VoidCallback? onRightTap;
  final bool disableGestures;

  const OverlayGestures({
    super.key,
    required this.seriesId,
    this.onCenterTap,
    this.onLeftTap,
    this.onRightTap,
    this.disableGestures = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(overlayGesturesProvider(seriesId: seriesId));

    return IgnorePointer(
      ignoring: disableGestures,
      child: Async(
        asyncValue: model,
        data: (data) {
          return _ReaderEdgeTaps(
            enabled: data.navigationGestures,
            onPrevious: onLeftTap,
            onNext: onRightTap,
            onCenterTap: onCenterTap,
            textDirection: data.readDirection.toTextDirection(),
            child: Row(
              textDirection: data.readDirection.toTextDirection(),
              children: [
                if (data.navigationGestures)
                  const Flexible(flex: 1, child: SizedBox.expand()),
                const Flexible(flex: 2, child: SizedBox.expand()),
                if (data.navigationGestures)
                  const Flexible(flex: 1, child: SizedBox.expand()),
              ],
            ),
          );
        },
        loading: () => const SizedBox.shrink(),
      ),
    );
  }
}

class _ReaderEdgeTaps extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCenterTap;
  final TextDirection textDirection;
  final Widget child;

  const _ReaderEdgeTaps({
    required this.enabled,
    required this.onPrevious,
    required this.onNext,
    required this.onCenterTap,
    required this.textDirection,
    required this.child,
  });

  @override
  State<_ReaderEdgeTaps> createState() => _ReaderEdgeTapsState();
}

class _ReaderEdgeTapsState extends State<_ReaderEdgeTaps> {
  Offset? _down;
  int _pointers = 0;

  void _up(PointerUpEvent event) {
    final down = _down;
    _down = null;
    if (down == null) return;
    if ((event.localPosition - down).distance > kTouchSlop) return;
    if (EpubImageAnchor.tryOpen(event.position)) return;

    if (!widget.enabled) {
      widget.onCenterTap?.call();
      return;
    }

    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    final x = event.localPosition.dx;
    final atStart = widget.textDirection == TextDirection.ltr
        ? x <= width / 4
        : x >= width * 3 / 4;
    final atEnd = widget.textDirection == TextDirection.ltr
        ? x >= width * 3 / 4
        : x <= width / 4;
    if (atStart) {
      widget.onPrevious?.call();
    } else if (atEnd) {
      widget.onNext?.call();
    } else {
      widget.onCenterTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: .translucent,
      onPointerDown: (event) {
        _pointers++;
        _down = event.localPosition;
      },
      onPointerCancel: (_) {
        if (_pointers > 0) _pointers--;
        _down = null;
      },
      onPointerUp: (event) {
        if (_pointers > 0) _pointers--;
        if (_pointers > 0) {
          _down = null;
          return;
        }
        _up(event);
      },
      child: widget.child,
    );
  }
}
