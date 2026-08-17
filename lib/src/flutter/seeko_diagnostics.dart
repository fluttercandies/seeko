import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/command_model.dart';
import 'seeko_controller.dart';
import 'seeko_snapshot.dart';

/// The source of one bounded diagnostics record.
enum ScrollDiagnosticEventKind {
  snapshot,
  rawPosition,
  commandResult,
  syncGroup,
}

/// Immutable diagnostics data that never retains widget tree objects.
@immutable
final class ScrollDiagnosticEvent {
  const ScrollDiagnosticEvent({
    required this.sequence,
    required this.timestamp,
    required this.kind,
    required this.source,
    required this.details,
    this.snapshot,
    this.rawEvent,
    this.commandResult,
  });

  final int sequence;
  final DateTime timestamp;
  final ScrollDiagnosticEventKind kind;
  final String source;
  final Map<String, Object?> details;
  final ScrollSnapshot? snapshot;
  final ScrollRawEvent? rawEvent;
  final ScrollResult? commandResult;

  Map<String, Object?> toMap() => <String, Object?>{
        'sequence': sequence,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'kind': kind.name,
        'source': source,
        'details': details,
      };
}

/// Opt-in bounded recorder for controller and synchronization evidence.
///
/// Merely importing Seeko does not allocate a recorder or add listeners.
/// Creating this object and attaching sources enables the work explicitly.
/// Attached controllers and groups remain caller-owned.
final class ScrollDiagnostics extends ChangeNotifier {
  ScrollDiagnostics({this.capacity = 256}) {
    if (capacity <= 0) {
      throw RangeError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final int capacity;
  final ListQueue<ScrollDiagnosticEvent> _events =
      ListQueue<ScrollDiagnosticEvent>();
  final Map<SeekoController, _ControllerDiagnosticsBinding> _controllers =
      <SeekoController, _ControllerDiagnosticsBinding>{};
  final Map<ScrollSyncGroup, _SyncDiagnosticsBinding> _groups =
      <ScrollSyncGroup, _SyncDiagnosticsBinding>{};
  var _sequence = 0;
  var _disposed = false;
  var _notificationScheduled = false;

  List<ScrollDiagnosticEvent> get events =>
      List<ScrollDiagnosticEvent>.unmodifiable(_events);

  ScrollDiagnosticEvent? get latest => _events.isEmpty ? null : _events.last;

  /// Attaches one controller and records its coalesced snapshots and results.
  ///
  /// Set [includeRawEvents] only for short diagnostic sessions because it
  /// records high-frequency position changes into the same bounded buffer.
  void attachController(
    SeekoController controller, {
    String? label,
    bool includeRawEvents = false,
  }) {
    _requireActive();
    if (_controllers.containsKey(controller)) {
      throw StateError('The controller is already attached to diagnostics.');
    }
    final String source = label ?? controller.debugLabel ?? 'controller';

    void snapshotListener() {
      final ScrollSnapshot snapshot = controller.state.value;
      _record(
        ScrollDiagnosticEventKind.snapshot,
        source,
        <String, Object?>{
          'pixels': snapshot.pixels,
          'progress': snapshot.progress,
          'velocity': snapshot.velocity,
          'phase': snapshot.phase.name,
          'origin': snapshot.origin.name,
          'visibleTargetCount': snapshot.visibleTargets.length,
          'anchorKey': snapshot.anchor?.key?.toString(),
          'anchorIndex': snapshot.anchor?.index,
          'activeCommandId': snapshot.activeCommandId,
          'syncTransactionId': snapshot.syncTransactionId,
          'atLeadingEdge': snapshot.atLeadingEdge,
          'atTrailingEdge': snapshot.atTrailingEdge,
          'viewportExtent': snapshot.viewportExtent,
          'dataRevision': snapshot.dataRevision,
          'effectiveViewportIntervals': <Map<String, double>>[
            for (final interval in snapshot.effectiveViewportIntervals)
              <String, double>{
                'start': interval.start,
                'end': interval.end,
              },
          ],
          if (snapshot.extent case final ScrollExtentSnapshot extent)
            'extent': <String, Object?>{
              'itemCount': extent.itemCount,
              'measuredItemCount': extent.measuredItemCount,
              'estimatedItemCount': extent.estimatedItemCount,
              'measuredExtent': extent.measuredExtent,
              'estimatedExtent': extent.estimatedExtent,
              'estimateConfidence': extent.estimateConfidence,
              'complete': extent.isComplete,
            },
        },
        snapshot: snapshot,
      );
    }

    controller.state.addListener(snapshotListener);
    // The binding owns and cancels this subscription in detachController.
    // ignore: cancel_subscriptions
    final StreamSubscription<ScrollResult> commandSubscription =
        controller.commandResults.listen((ScrollResult result) {
      _record(
        ScrollDiagnosticEventKind.commandResult,
        source,
        <String, Object?>{
          'commandId': result.commandId,
          'outcome': result.outcome.name,
          'requestedTarget': result.requestedTarget.toString(),
          'capturedTarget': result.capturedTarget?.toString(),
          'achievedTarget': result.achievedTarget?.toString(),
          'resolutionMode': result.resolutionMode.name,
          'degraded': result.isDegraded,
          'finalLogicalPixels': result.finalLogicalPixels,
          'finalError': result.finalError,
          'elapsedMicroseconds': result.elapsed.inMicroseconds,
          'replanCount': result.replanCount,
          'correctionCount': result.correctionCount,
          if (result.diagnostics != null) 'diagnostics': result.diagnostics,
        },
        commandResult: result,
      );
    });
    // The binding owns and cancels this subscription in detachController.
    // ignore: cancel_subscriptions
    final StreamSubscription<ScrollRawEvent>? rawSubscription = includeRawEvents
        ? controller.rawEvents.listen((ScrollRawEvent event) {
            _record(
              ScrollDiagnosticEventKind.rawPosition,
              source,
              <String, Object?>{
                'rawSequence': event.sequence,
                'pixels': event.pixels,
                'velocity': event.velocity,
                'phase': event.phase.name,
                'origin': event.origin.name,
                'commandId': event.commandId,
                'syncTransactionId': event.syncTransactionId,
              },
              rawEvent: event,
            );
          })
        : null;
    _controllers[controller] = _ControllerDiagnosticsBinding(
      snapshotListener: snapshotListener,
      commandSubscription: commandSubscription,
      rawSubscription: rawSubscription,
    );
    snapshotListener();
  }

  void detachController(SeekoController controller) {
    final _ControllerDiagnosticsBinding? binding =
        _controllers.remove(controller);
    if (binding == null) {
      return;
    }
    controller.state.removeListener(binding.snapshotListener);
    unawaited(binding.commandSubscription.cancel());
    unawaited(binding.rawSubscription?.cancel());
  }

  /// Attaches a synchronization group and records its public group state.
  void attachSyncGroup(ScrollSyncGroup group, {String label = 'sync-group'}) {
    _requireActive();
    if (_groups.containsKey(group)) {
      throw StateError('The sync group is already attached to diagnostics.');
    }

    void groupListener() {
      _record(
        ScrollDiagnosticEventKind.syncGroup,
        label,
        <String, Object?>{
          'memberCount': group.memberCount,
          'activeMemberCount': group.activeMemberCount,
          'activeLeaderId': group.activeLeaderId?.toString(),
          'activeTransactionId': group.activeTransactionId,
          'transactionCount': group.transactionCount,
          'followerApplyCount': group.followerApplyCount,
          'failed': group.isFailed,
          'failureReason': group.failureReason,
        },
      );
    }

    group.addListener(groupListener);
    _groups[group] = _SyncDiagnosticsBinding(listener: groupListener);
    groupListener();
  }

  void detachSyncGroup(ScrollSyncGroup group) {
    final _SyncDiagnosticsBinding? binding = _groups.remove(group);
    if (binding != null) {
      group.removeListener(binding.listener);
    }
  }

  /// Returns a serialization-safe copy of the current bounded event window.
  List<Map<String, Object?>> export() => <Map<String, Object?>>[
        for (final ScrollDiagnosticEvent event in _events) event.toMap(),
      ];

  void clear() {
    _requireActive();
    if (_events.isEmpty) {
      return;
    }
    _events.clear();
    _scheduleNotification();
  }

  void _record(
    ScrollDiagnosticEventKind kind,
    String source,
    Map<String, Object?> details, {
    ScrollSnapshot? snapshot,
    ScrollRawEvent? rawEvent,
    ScrollResult? commandResult,
  }) {
    if (_disposed) {
      return;
    }
    if (_events.length == capacity) {
      _events.removeFirst();
    }
    _events.addLast(
      ScrollDiagnosticEvent(
        sequence: ++_sequence,
        timestamp: DateTime.now(),
        kind: kind,
        source: source,
        details: Map<String, Object?>.unmodifiable(details),
        snapshot: snapshot,
        rawEvent: rawEvent,
        commandResult: commandResult,
      ),
    );
    _scheduleNotification();
  }

  void _scheduleNotification() {
    if (!hasListeners || _notificationScheduled || _disposed) {
      return;
    }
    _notificationScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  void _requireActive() {
    if (_disposed) {
      throw StateError('ScrollDiagnostics has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    for (final SeekoController controller
        in _controllers.keys.toList(growable: false)) {
      detachController(controller);
    }
    for (final ScrollSyncGroup group in _groups.keys.toList(growable: false)) {
      detachSyncGroup(group);
    }
    _disposed = true;
    _events.clear();
    super.dispose();
  }
}

/// Debug-only, non-interactive overlay for the latest diagnostics state.
class SeekoDiagnosticsOverlay extends StatelessWidget {
  const SeekoDiagnosticsOverlay({
    required this.diagnostics,
    required this.child,
    this.enabled = true,
    this.alignment = Alignment.topRight,
    super.key,
  });

  final ScrollDiagnostics diagnostics;
  final Widget child;
  final bool enabled;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return child;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        child,
        if (enabled)
          Align(
            alignment: alignment,
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: diagnostics,
                  builder: (BuildContext context, _) {
                    final ScrollDiagnosticEvent? event = diagnostics.latest;
                    final ScrollSnapshot? snapshot = event?.snapshot;
                    final ColorScheme colors = Theme.of(context).colorScheme;
                    return Semantics(
                      container: true,
                      liveRegion: true,
                      label: 'Seeko diagnostics overlay',
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh
                              .withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.outlineVariant,
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: DefaultTextStyle(
                              style: Theme.of(context).textTheme.bodySmall!,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Seeko diagnostics',
                                    style:
                                        Theme.of(context).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    event == null
                                        ? 'Waiting for scroll activity'
                                        : '${event.source} · ${event.kind.name} · #${event.sequence}',
                                  ),
                                  if (snapshot != null) ...<Widget>[
                                    Text(
                                      '${snapshot.pixels.toStringAsFixed(1)} px · ${snapshot.phase.name} · ${snapshot.origin.name}',
                                    ),
                                    Text(
                                      '${snapshot.visibleTargets.length} visible · command ${snapshot.activeCommandId ?? 'none'}',
                                    ),
                                    Text(
                                      'anchor ${snapshot.anchor?.key ?? snapshot.anchor?.index ?? 'none'}',
                                    ),
                                    const SizedBox(height: 8),
                                    _DiagnosticsViewportStrip(
                                      snapshot: snapshot,
                                      colors: colors,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'viewport ${snapshot.viewportExtent.toStringAsFixed(0)} px · '
                                      '${snapshot.effectiveViewportIntervals.length} visible interval${snapshot.effectiveViewportIntervals.length == 1 ? '' : 's'} · '
                                      'revision ${snapshot.dataRevision ?? 'n/a'}',
                                    ),
                                    if (snapshot.extent
                                        case final ScrollExtentSnapshot extent)
                                      Text(
                                        '${extent.measuredItemCount}/${extent.itemCount} measured · '
                                        '${(extent.estimateConfidence * 100).toStringAsFixed(1)}% confidence${extent.isComplete ? '' : ' · partial'}',
                                      ),
                                  ] else if (event != null)
                                    Text(
                                      event.details.entries
                                          .take(3)
                                          .map(
                                            (MapEntry<String, Object?> entry) =>
                                                '${entry.key}: ${entry.value}',
                                          )
                                          .join(' · '),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DiagnosticsViewportStrip extends StatelessWidget {
  const _DiagnosticsViewportStrip({
    required this.snapshot,
    required this.colors,
  });

  final ScrollSnapshot snapshot;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      width: double.infinity,
      child: CustomPaint(
        painter: _DiagnosticsViewportPainter(
          snapshot: snapshot,
          trackColor: colors.surfaceContainerHighest,
          visibleColor: colors.primary.withValues(alpha: 0.32),
          targetColor: colors.tertiary,
          outlineColor: colors.outlineVariant,
        ),
      ),
    );
  }
}

class _DiagnosticsViewportPainter extends CustomPainter {
  const _DiagnosticsViewportPainter({
    required this.snapshot,
    required this.trackColor,
    required this.visibleColor,
    required this.targetColor,
    required this.outlineColor,
  });

  final ScrollSnapshot snapshot;
  final Color trackColor;
  final Color visibleColor;
  final Color targetColor;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas.drawRRect(track, Paint()..color = trackColor);
    final double viewport = snapshot.viewportExtent;
    if (viewport > 0) {
      final Paint visiblePaint = Paint()..color = visibleColor;
      for (final interval in snapshot.effectiveViewportIntervals) {
        final double start =
            (interval.start / viewport * size.width).clamp(0, size.width);
        final double end =
            (interval.end / viewport * size.width).clamp(0, size.width);
        canvas.drawRect(
            Rect.fromLTRB(start, 0, end, size.height), visiblePaint);
      }
      final Paint targetPaint = Paint()..color = targetColor;
      for (final ScrollVisibleTarget target in snapshot.visibleTargets) {
        final double start =
            (target.leadingPixels / viewport * size.width).clamp(0, size.width);
        final double end = (target.trailingPixels / viewport * size.width)
            .clamp(0, size.width);
        canvas.drawRect(
          Rect.fromLTRB(start, size.height - 4, end, size.height),
          targetPaint,
        );
      }
    }
    canvas.drawRRect(
      track,
      Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_DiagnosticsViewportPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.visibleColor != visibleColor ||
      oldDelegate.targetColor != targetColor ||
      oldDelegate.outlineColor != outlineColor;
}

final class _ControllerDiagnosticsBinding {
  const _ControllerDiagnosticsBinding({
    required this.snapshotListener,
    required this.commandSubscription,
    required this.rawSubscription,
  });

  final VoidCallback snapshotListener;
  final StreamSubscription<ScrollResult> commandSubscription;
  final StreamSubscription<ScrollRawEvent>? rawSubscription;
}

final class _SyncDiagnosticsBinding {
  const _SyncDiagnosticsBinding({required this.listener});

  final VoidCallback listener;
}
