import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/command_model.dart';
import '../core/motion.dart';
import 'seeko_two_dimensional.dart';

enum SeekoTwoDimensionalSyncMode { pixels, progress }

enum SeekoTwoDimensionalSyncRole { bidirectional, leader, follower }

@immutable
final class SeekoTwoDimensionalSyncMember {
  const SeekoTwoDimensionalSyncMember({
    this.role = SeekoTwoDimensionalSyncRole.bidirectional,
    this.priority = 0,
    this.horizontal = true,
    this.vertical = true,
  });

  final SeekoTwoDimensionalSyncRole role;
  final int priority;
  final bool horizontal;
  final bool vertical;
}

@immutable
final class SeekoTwoDimensionalGroupResult {
  const SeekoTwoDimensionalGroupResult({
    required this.results,
    required this.outcome,
  });

  final Map<SeekoTwoDimensionalController, SeekoTwoDimensionalResult> results;
  final ScrollOutcome outcome;

  bool get isSuccess =>
      outcome == ScrollOutcome.completed || outcome == ScrollOutcome.clamped;
}

/// Synchronizes any number of two-dimensional controllers without feedback.
///
/// One member event is the single writer for each transaction. Fan-out is
/// exactly O(active members), and followers never re-enter the group.
final class SeekoTwoDimensionalSyncGroup extends ChangeNotifier {
  SeekoTwoDimensionalSyncGroup({
    this.mode = SeekoTwoDimensionalSyncMode.progress,
  });

  final SeekoTwoDimensionalSyncMode mode;
  final LinkedHashMap<SeekoTwoDimensionalController,
          SeekoTwoDimensionalSyncMember> _members =
      LinkedHashMap<SeekoTwoDimensionalController,
          SeekoTwoDimensionalSyncMember>.identity();
  final Map<SeekoTwoDimensionalController, VoidCallback> _listeners =
      <SeekoTwoDimensionalController, VoidCallback>{};
  SeekoTwoDimensionalController? _leader;
  bool _applying = false;
  bool _disposed = false;

  int get length => _members.length;
  Iterable<SeekoTwoDimensionalController> get controllers => _members.keys;
  SeekoTwoDimensionalController? get leader => _leader;

  void add(
    SeekoTwoDimensionalController controller, {
    SeekoTwoDimensionalSyncMember member =
        const SeekoTwoDimensionalSyncMember(),
  }) {
    if (_disposed) {
      throw StateError('Cannot add a member to a disposed sync group.');
    }
    if (_members.containsKey(controller)) {
      throw StateError('The controller is already in this sync group.');
    }
    if (!member.horizontal && !member.vertical) {
      throw ArgumentError('A sync member must enable at least one axis.');
    }
    _members[controller] = member;
    void listener() => _handleMemberChanged(controller);
    _listeners[controller] = listener;
    controller.addListener(listener);
    final SeekoTwoDimensionalController? source = _leader ??
        _members.keys.cast<SeekoTwoDimensionalController?>().firstWhere(
              (SeekoTwoDimensionalController? value) =>
                  value != null && !identical(value, controller),
              orElse: () => null,
            );
    if (source != null) {
      _fanOut(source, only: controller);
    } else if (member.role != SeekoTwoDimensionalSyncRole.follower) {
      _leader = controller;
    }
    notifyListeners();
  }

  bool remove(SeekoTwoDimensionalController controller) {
    final VoidCallback? listener = _listeners.remove(controller);
    if (listener == null) {
      return false;
    }
    controller.removeListener(listener);
    _members.remove(controller);
    if (identical(_leader, controller)) {
      _leader = _selectLeader();
    }
    notifyListeners();
    return true;
  }

  Future<SeekoTwoDimensionalGroupResult> jumpToCell(
    SeekoCellTarget target, {
    SeekoTwoDimensionalPlacement placement =
        const SeekoTwoDimensionalPlacement.nearest(),
  }) {
    return _runGroupCommand(
      (SeekoTwoDimensionalController controller) =>
          controller.jumpToCell(target, placement: placement),
    );
  }

  Future<SeekoTwoDimensionalGroupResult> animateToCell(
    SeekoCellTarget target, {
    SeekoTwoDimensionalPlacement placement =
        const SeekoTwoDimensionalPlacement.nearest(),
    ScrollMotion motion = const ScrollMotion.adaptive(),
  }) {
    return _runGroupCommand(
      (SeekoTwoDimensionalController controller) => controller.animateToCell(
        target,
        placement: placement,
        motion: motion,
      ),
    );
  }

  Future<SeekoTwoDimensionalGroupResult> _runGroupCommand(
    Future<SeekoTwoDimensionalResult> Function(
      SeekoTwoDimensionalController controller,
    ) command,
  ) async {
    _applying = true;
    try {
      final List<SeekoTwoDimensionalController> active = _members.keys
          .where(
            (SeekoTwoDimensionalController controller) =>
                controller.vertical.hasClients &&
                controller.horizontal.hasClients,
          )
          .toList(growable: false);
      final List<SeekoTwoDimensionalResult> values =
          await Future.wait<SeekoTwoDimensionalResult>(
        active.map(command),
      );
      final Map<SeekoTwoDimensionalController, SeekoTwoDimensionalResult>
          results = <SeekoTwoDimensionalController, SeekoTwoDimensionalResult>{
        for (var index = 0; index < active.length; index += 1)
          active[index]: values[index],
      };
      final ScrollOutcome outcome = values.isEmpty
          ? ScrollOutcome.detached
          : values.any(
              (SeekoTwoDimensionalResult value) => !value.isSuccess,
            )
              ? values
                  .firstWhere(
                    (SeekoTwoDimensionalResult value) => !value.isSuccess,
                  )
                  .outcome
              : values.any(
                  (SeekoTwoDimensionalResult value) =>
                      value.outcome == ScrollOutcome.clamped,
                )
                  ? ScrollOutcome.clamped
                  : ScrollOutcome.completed;
      return SeekoTwoDimensionalGroupResult(
        results: Map<SeekoTwoDimensionalController,
            SeekoTwoDimensionalResult>.unmodifiable(results),
        outcome: outcome,
      );
    } finally {
      _applying = false;
    }
  }

  void _handleMemberChanged(SeekoTwoDimensionalController source) {
    if (_applying || _disposed) {
      return;
    }
    final SeekoTwoDimensionalSyncMember? member = _members[source];
    if (member == null || member.role == SeekoTwoDimensionalSyncRole.follower) {
      return;
    }
    final SeekoTwoDimensionalController? currentLeader = _leader;
    if (currentLeader != null &&
        !identical(currentLeader, source) &&
        _isUserScrolling(currentLeader)) {
      final int currentPriority = _members[currentLeader]?.priority ?? 0;
      if (currentPriority > member.priority) {
        return;
      }
    }
    _leader = source;
    _fanOut(source);
    notifyListeners();
  }

  void _fanOut(
    SeekoTwoDimensionalController source, {
    SeekoTwoDimensionalController? only,
  }) {
    if (!source.vertical.hasClients || !source.horizontal.hasClients) {
      return;
    }
    final SeekoTwoDimensionalSnapshot snapshot = source.state.value;
    _applying = true;
    try {
      for (final MapEntry<SeekoTwoDimensionalController,
          SeekoTwoDimensionalSyncMember> entry in _members.entries) {
        final SeekoTwoDimensionalController follower = entry.key;
        if (identical(follower, source) ||
            only != null && !identical(follower, only) ||
            !follower.vertical.hasClients ||
            !follower.horizontal.hasClients) {
          continue;
        }
        final SeekoTwoDimensionalSyncMember config = entry.value;
        if (config.role == SeekoTwoDimensionalSyncRole.leader) {
          continue;
        }
        if (config.horizontal) {
          final double target = mode == SeekoTwoDimensionalSyncMode.pixels
              ? snapshot.horizontalPixels
              : snapshot.horizontalProgress *
                  follower.state.value.horizontalMax;
          _jumpAxis(follower.horizontal, target);
        }
        if (config.vertical) {
          final double target = mode == SeekoTwoDimensionalSyncMode.pixels
              ? snapshot.verticalPixels
              : snapshot.verticalProgress * follower.state.value.verticalMax;
          _jumpAxis(follower.vertical, target);
        }
      }
    } finally {
      _applying = false;
    }
  }

  void _jumpAxis(ScrollController controller, double pixels) {
    final ScrollPosition position = controller.position;
    final double target = pixels.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() > precisionErrorTolerance) {
      controller.jumpTo(target);
    }
  }

  bool _isUserScrolling(SeekoTwoDimensionalController controller) {
    return controller.vertical.hasClients &&
            controller.vertical.position.userScrollDirection !=
                ScrollDirection.idle ||
        controller.horizontal.hasClients &&
            controller.horizontal.position.userScrollDirection !=
                ScrollDirection.idle;
  }

  SeekoTwoDimensionalController? _selectLeader() {
    SeekoTwoDimensionalController? selected;
    var selectedPriority = -0x7fffffff;
    for (final MapEntry<SeekoTwoDimensionalController,
        SeekoTwoDimensionalSyncMember> entry in _members.entries) {
      if (entry.value.role == SeekoTwoDimensionalSyncRole.follower) {
        continue;
      }
      if (selected == null || entry.value.priority > selectedPriority) {
        selected = entry.key;
        selectedPriority = entry.value.priority;
      }
    }
    return selected;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final MapEntry<SeekoTwoDimensionalController, VoidCallback> entry
        in _listeners.entries) {
      entry.key.removeListener(entry.value);
    }
    _listeners.clear();
    _members.clear();
    _leader = null;
    super.dispose();
  }
}
