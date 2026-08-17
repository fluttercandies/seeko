import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion_prototype_content.dart';
import 'motion_prototype_models.dart';
import 'motion_prototype_trajectory.dart';

final class MotionPrototypeViewport extends StatelessWidget {
  const MotionPrototypeViewport({
    required this.candidate,
    required this.testCase,
    required this.targetPixels,
    required this.frame,
    this.windowGeneration = 0,
    this.onChildBuilt,
    super.key,
  });

  final MotionPrototypeCandidate candidate;
  final MotionPrototypeCase testCase;
  final double targetPixels;
  final MotionPrototypeFrame frame;
  final int windowGeneration;
  final VoidCallback? onChildBuilt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewportExtent = constraints.maxHeight;
        if (!viewportExtent.isFinite || viewportExtent <= 0) {
          throw StateError(
            'Motion prototype viewport requires a finite positive height.',
          );
        }
        final MotionPrototypeContent content = MotionPrototypeContent(
          testCase.extentProfile,
        );
        final double baseOffset = content.offsetForIndex(500000);
        final double progress = targetPixels == 0
            ? 1
            : (frame.logicalPixels / targetPixels).abs().clamp(0, 1);
        return ClipRect(
          child: ColoredBox(
            color: const Color(0xFF07111F),
            child: switch (candidate) {
              MotionPrototypeCandidate.dualViewportCrossfade => _buildCrossfade(
                  content,
                  baseOffset,
                  progress,
                  viewportExtent,
                ),
              MotionPrototypeCandidate.tagSegmentedSearch => _buildSearch(
                  content,
                  baseOffset,
                  viewportExtent,
                ),
              MotionPrototypeCandidate.virtualWindowRebase => _buildRebase(
                  content,
                  baseOffset,
                  progress,
                  viewportExtent,
                ),
            },
          ),
        );
      },
    );
  }

  Widget _buildCrossfade(
    MotionPrototypeContent content,
    double baseOffset,
    double progress,
    double viewportExtent,
  ) {
    final double travel = viewportExtent * 0.18;
    if (frame.layerCount == 1) {
      final bool destination = progress >= 0.5;
      return _window(
        key: Key(
          destination
              ? 'prototype-window-destination'
              : 'prototype-window-source',
        ),
        content: content,
        anchorOffset: baseOffset + (destination ? targetPixels : 0),
        viewportExtent: viewportExtent,
        shift: destination ? (1 - progress) * travel : -progress * travel,
        overscan: viewportExtent * 0.3,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Opacity(
          opacity: 1 - progress,
          child: _window(
            key: const Key('prototype-window-source'),
            content: content,
            anchorOffset: baseOffset,
            viewportExtent: viewportExtent,
            shift: -progress * travel,
            overscan: viewportExtent * 0.3,
          ),
        ),
        Opacity(
          opacity: progress,
          child: _window(
            key: const Key('prototype-window-destination'),
            content: content,
            anchorOffset: baseOffset + targetPixels,
            viewportExtent: viewportExtent,
            shift: (1 - progress) * travel,
            overscan: viewportExtent * 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildSearch(
    MotionPrototypeContent content,
    double baseOffset,
    double viewportExtent,
  ) {
    final double windowLogical =
        (frame.logicalPixels / viewportExtent).floorToDouble() * viewportExtent;
    return _window(
      key: const Key('prototype-window-search'),
      content: content,
      anchorOffset: baseOffset + windowLogical,
      viewportExtent: viewportExtent,
      shift: -(frame.logicalPixels - windowLogical),
      overscan: viewportExtent * 0.3,
    );
  }

  Widget _buildRebase(
    MotionPrototypeContent content,
    double baseOffset,
    double progress,
    double viewportExtent,
  ) {
    if (testCase.distanceViewports <= 10) {
      final double windowLogical =
          (frame.logicalPixels / viewportExtent).floorToDouble() *
              viewportExtent;
      return _window(
        key: const Key('prototype-window-near'),
        content: content,
        anchorOffset: baseOffset + windowLogical,
        viewportExtent: viewportExtent,
        shift: -(frame.logicalPixels - windowLogical),
        overscan: viewportExtent * 0.3,
      );
    }
    final bool destination = frame.windowEpoch > 0;
    final double travel = viewportExtent * 1.15;
    final double shift = destination
        ? ((1 - progress) / 0.35).clamp(0, 1) * travel
        : -(progress / 0.35).clamp(0, 1) * travel;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (progress > 0.2 && progress < 0.8)
          CustomPaint(
            key: const Key('prototype-cruise-layer'),
            painter: _CruisePainter(
              phase: frame.logicalPixels / viewportExtent,
              direction: testCase.direction,
            ),
          ),
        _window(
          key: Key(
            destination
                ? 'prototype-window-destination'
                : 'prototype-window-source',
          ),
          content: content,
          anchorOffset: baseOffset + (destination ? targetPixels : 0),
          viewportExtent: viewportExtent,
          shift: shift,
          overscan: viewportExtent * 0.3,
        ),
      ],
    );
  }

  Widget _window({
    required Key key,
    required MotionPrototypeContent content,
    required double anchorOffset,
    required double viewportExtent,
    required double shift,
    required double overscan,
  }) {
    return KeyedSubtree(
      key: ValueKey<(Key, int)>((key, windowGeneration)),
      child: _MotionWindowLayer(
        key: key,
        content: content,
        anchorOffset: anchorOffset,
        viewportExtent: viewportExtent,
        shift: shift,
        overscan: overscan,
        onChildBuilt: onChildBuilt,
      ),
    );
  }
}

final class _MotionWindowLayer extends StatefulWidget {
  const _MotionWindowLayer({
    required this.content,
    required this.anchorOffset,
    required this.viewportExtent,
    required this.shift,
    required this.overscan,
    required this.onChildBuilt,
    super.key,
  });

  final MotionPrototypeContent content;
  final double anchorOffset;
  final double viewportExtent;
  final double shift;
  final double overscan;
  final VoidCallback? onChildBuilt;

  @override
  State<_MotionWindowLayer> createState() => _MotionWindowLayerState();
}

final class _MotionWindowLayerState extends State<_MotionWindowLayer> {
  late List<Widget> _children;

  @override
  void initState() {
    super.initState();
    _rebuildChildren();
  }

  @override
  void didUpdateWidget(_MotionWindowLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.profile != widget.content.profile ||
        oldWidget.anchorOffset != widget.anchorOffset ||
        oldWidget.viewportExtent != widget.viewportExtent ||
        oldWidget.overscan != widget.overscan) {
      _rebuildChildren();
    }
  }

  void _rebuildChildren() {
    final List<MotionPrototypeItemGeometry> items =
        widget.content.itemsCovering(
      widget.anchorOffset,
      viewportExtent: widget.viewportExtent,
      overscan: widget.overscan,
    );
    _children = items
        .map(
          (MotionPrototypeItemGeometry geometry) => Positioned(
            key: ValueKey<int>(geometry.index),
            left: 0,
            right: 0,
            top: geometry.leading,
            height: geometry.extent,
            child: MotionPrototypeItem(
              index: geometry.index,
              onBuilt: widget.onChildBuilt,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, widget.shift),
      child: Stack(
        clipBehavior: Clip.none,
        children: _children,
      ),
    );
  }
}

final class MotionPrototypeItem extends StatelessWidget {
  const MotionPrototypeItem({
    required this.index,
    this.onBuilt,
    super.key,
  });

  final int index;
  final VoidCallback? onBuilt;

  @override
  Widget build(BuildContext context) {
    onBuilt?.call();
    final bool alternate = index.isOdd;
    return RepaintBoundary(
      child: ColoredBox(
        color: alternate ? const Color(0xFF10263A) : const Color(0xFF0D2031),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 8,
              child: ColoredBox(
                color: Color(
                  0xFF16C79A + (index % 4) * 0x00050800,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Item ${index.toString().padLeft(6, '0')}',
              style: const TextStyle(
                color: Color(0xFFF8FAFC),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CruisePainter extends CustomPainter {
  const _CruisePainter({required this.phase, required this.direction});

  final double phase;
  final MotionDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A1A2A),
    );
    final Paint paint = Paint()..strokeWidth = 5;
    final double signedPhase =
        direction == MotionDirection.forward ? phase : -phase;
    final double offset = signedPhase.remainder(48);
    for (double y = -96 + offset; y < size.height + 96; y += 48) {
      final double intensity = 0.35 + 0.25 * math.sin((y + phase) * 0.02);
      paint.color = Color.lerp(
        const Color(0xFF16C79A),
        const Color(0xFF4C7DFF),
        intensity,
      )!;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y - 32),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CruisePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.direction != direction;
}
