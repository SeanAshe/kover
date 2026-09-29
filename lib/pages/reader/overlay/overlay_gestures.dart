import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kover/mapping/enums/read_direction.dart';
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
            textDirection: data.readDirection.toTextDirection(),
            child: Row(
              textDirection: data.readDirection.toTextDirection(),
              children: [
                if (data.navigationGestures)
                  const Flexible(flex: 1, child: SizedBox.expand()),
                Flexible(
                  flex: 2,
                  child: GestureDetector(
                    behavior: .translucent,
                    onTap: onCenterTap,
                  ),
                ),
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
  final TextDirection textDirection;
  final Widget child;

  const _ReaderEdgeTaps({
    required this.enabled,
    required this.onPrevious,
    required this.onNext,
    required this.textDirection,
    required this.child,
  });

  @override
  State<_ReaderEdgeTaps> createState() => _ReaderEdgeTapsState();
}

class _ReaderEdgeTapsState extends State<_ReaderEdgeTaps> {
  Offset? _down;

  void _up(PointerUpEvent event) {
    final down = _down;
    _down = null;
    if (!widget.enabled || down == null) return;
    if ((event.localPosition - down).distance > kTouchSlop) return;

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: .translucent,
      onPointerDown: (event) => _down = event.localPosition,
      onPointerCancel: (_) => _down = null,
      onPointerUp: _up,
      child: widget.child,
    );
  }
}
