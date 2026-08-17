import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../core/logical_geometry.dart';

enum ScrollEventOrigin {
  none,
  user,
  programmatic,
  synchronized,
  restoration,
  accessibility,
  external,
}

enum ScrollPhase {
  idle,
  scrolling,
  drag,
  ballistic,
  programmatic,
  correcting,
  held,
}

@immutable
final class ScrollVisibleTarget {
  const ScrollVisibleTarget({
    required this.key,
    required this.index,
    required this.leadingPixels,
    required this.trailingPixels,
    required this.leadingViewportFraction,
    required this.trailingViewportFraction,
    required this.visibleFraction,
  });

  final Object? key;
  final int? index;
  final double leadingPixels;
  final double trailingPixels;
  final double leadingViewportFraction;
  final double trailingViewportFraction;
  final double visibleFraction;

  bool get isFullyVisible => visibleFraction >= 1;

  @override
  bool operator ==(Object other) =>
      other is ScrollVisibleTarget &&
      other.key == key &&
      other.index == index &&
      other.leadingPixels == leadingPixels &&
      other.trailingPixels == trailingPixels &&
      other.leadingViewportFraction == leadingViewportFraction &&
      other.trailingViewportFraction == trailingViewportFraction &&
      other.visibleFraction == visibleFraction;

  @override
  int get hashCode => Object.hash(
        key,
        index,
        leadingPixels,
        trailingPixels,
        leadingViewportFraction,
        trailingViewportFraction,
        visibleFraction,
      );
}

@immutable
final class ScrollSemanticAnchor {
  const ScrollSemanticAnchor({
    required this.key,
    required this.index,
    required this.itemAnchor,
    required this.viewportAnchor,
    required this.logicalOffset,
  });

  final Object? key;
  final int? index;
  final double itemAnchor;
  final double viewportAnchor;
  final double logicalOffset;

  @override
  bool operator ==(Object other) =>
      other is ScrollSemanticAnchor &&
      other.key == key &&
      other.index == index &&
      other.itemAnchor == itemAnchor &&
      other.viewportAnchor == viewportAnchor &&
      other.logicalOffset == logicalOffset;

  @override
  int get hashCode => Object.hash(
        key,
        index,
        itemAnchor,
        viewportAnchor,
        logicalOffset,
      );
}

@immutable
final class ScrollRawEvent {
  const ScrollRawEvent({
    required this.sequence,
    required this.pixels,
    required this.velocity,
    required this.phase,
    required this.origin,
    required this.commandId,
    required this.syncTransactionId,
  });

  final int sequence;
  final double pixels;
  final double velocity;
  final ScrollPhase phase;
  final ScrollEventOrigin origin;
  final int? commandId;
  final int? syncTransactionId;
}

/// Bounded layout-knowledge summary for layout-aware indexed slivers.
///
/// [estimateConfidence] is a conservative measured-item coverage ratio. It is
/// useful for diagnostics and motion planning evidence, but is not a promise
/// that heterogeneous unmeasured items match the current estimate exactly.
@immutable
final class ScrollExtentSnapshot {
  const ScrollExtentSnapshot({
    required this.itemCount,
    required this.measuredItemCount,
    required this.measuredExtent,
    required this.estimatedExtent,
    required this.sourceCount,
    required this.reportedSourceCount,
  });

  final int itemCount;
  final int measuredItemCount;
  final double measuredExtent;
  final double estimatedExtent;
  final int sourceCount;
  final int reportedSourceCount;

  int get estimatedItemCount => itemCount - measuredItemCount;
  double get totalExtent => measuredExtent + estimatedExtent;
  double get estimateConfidence =>
      itemCount == 0 ? 1 : measuredItemCount / itemCount;
  bool get isComplete => sourceCount == reportedSourceCount;

  @override
  bool operator ==(Object other) =>
      other is ScrollExtentSnapshot &&
      other.itemCount == itemCount &&
      other.measuredItemCount == measuredItemCount &&
      other.measuredExtent == measuredExtent &&
      other.estimatedExtent == estimatedExtent &&
      other.sourceCount == sourceCount &&
      other.reportedSourceCount == reportedSourceCount;

  @override
  int get hashCode => Object.hash(
        itemCount,
        measuredItemCount,
        measuredExtent,
        estimatedExtent,
        sourceCount,
        reportedSourceCount,
      );
}

final class ScrollSnapshot {
  const ScrollSnapshot({
    required this.pixels,
    required this.minScrollExtent,
    required this.maxScrollExtent,
    required this.viewportExtent,
    required this.progress,
    required this.axis,
    required this.axisDirection,
    required this.userScrollDirection,
    required this.velocity,
    required this.phase,
    required this.origin,
    required this.atLeadingEdge,
    required this.atTrailingEdge,
    this.visibleTargets = const <ScrollVisibleTarget>[],
    this.anchor,
    this.activeCommandId,
    this.synchronized = false,
    this.syncTransactionId,
    this.pendingMetricsCorrection = false,
    this.dataRevision,
    this.effectiveViewportIntervals = const <LogicalInterval>[],
    this.extent,
  });

  const ScrollSnapshot.detached()
      : pixels = 0,
        minScrollExtent = 0,
        maxScrollExtent = 0,
        viewportExtent = 0,
        progress = null,
        axis = Axis.vertical,
        axisDirection = AxisDirection.down,
        userScrollDirection = ScrollDirection.idle,
        velocity = 0,
        phase = ScrollPhase.idle,
        origin = ScrollEventOrigin.none,
        atLeadingEdge = true,
        atTrailingEdge = true,
        visibleTargets = const <ScrollVisibleTarget>[],
        anchor = null,
        activeCommandId = null,
        synchronized = false,
        syncTransactionId = null,
        pendingMetricsCorrection = false,
        dataRevision = null,
        effectiveViewportIntervals = const <LogicalInterval>[],
        extent = null;

  final double pixels;
  final double minScrollExtent;
  final double maxScrollExtent;
  final double viewportExtent;
  final double? progress;
  final Axis axis;
  final AxisDirection axisDirection;
  final ScrollDirection userScrollDirection;
  final double velocity;
  final ScrollPhase phase;
  final ScrollEventOrigin origin;
  final bool atLeadingEdge;
  final bool atTrailingEdge;
  final List<ScrollVisibleTarget> visibleTargets;
  final ScrollSemanticAnchor? anchor;
  final int? activeCommandId;
  final bool synchronized;
  final int? syncTransactionId;
  final bool pendingMetricsCorrection;
  final int? dataRevision;
  final List<LogicalInterval> effectiveViewportIntervals;
  final ScrollExtentSnapshot? extent;

  ScrollVisibleTarget? get firstVisibleTarget =>
      visibleTargets.isEmpty ? null : visibleTargets.first;

  ScrollVisibleTarget? get lastVisibleTarget =>
      visibleTargets.isEmpty ? null : visibleTargets.last;

  @override
  bool operator ==(Object other) =>
      other is ScrollSnapshot &&
      other.pixels == pixels &&
      other.minScrollExtent == minScrollExtent &&
      other.maxScrollExtent == maxScrollExtent &&
      other.viewportExtent == viewportExtent &&
      other.progress == progress &&
      other.axis == axis &&
      other.axisDirection == axisDirection &&
      other.userScrollDirection == userScrollDirection &&
      other.velocity == velocity &&
      other.phase == phase &&
      other.origin == origin &&
      other.atLeadingEdge == atLeadingEdge &&
      other.atTrailingEdge == atTrailingEdge &&
      listEquals(other.visibleTargets, visibleTargets) &&
      other.anchor == anchor &&
      other.activeCommandId == activeCommandId &&
      other.synchronized == synchronized &&
      other.syncTransactionId == syncTransactionId &&
      other.pendingMetricsCorrection == pendingMetricsCorrection &&
      other.dataRevision == dataRevision &&
      listEquals(
        other.effectiveViewportIntervals,
        effectiveViewportIntervals,
      ) &&
      other.extent == extent;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        pixels,
        minScrollExtent,
        maxScrollExtent,
        viewportExtent,
        progress,
        axis,
        axisDirection,
        userScrollDirection,
        velocity,
        phase,
        origin,
        atLeadingEdge,
        atTrailingEdge,
        Object.hashAll(visibleTargets),
        anchor,
        activeCommandId,
        synchronized,
        syncTransactionId,
        pendingMetricsCorrection,
        dataRevision,
        Object.hashAll(effectiveViewportIntervals),
        extent,
      ]);
}

final class ScrollSnapshotNotifier extends ValueNotifier<ScrollSnapshot> {
  ScrollSnapshotNotifier() : super(const ScrollSnapshot.detached());
}
