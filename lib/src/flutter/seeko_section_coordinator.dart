import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/command_model.dart';
import '../core/motion.dart';
import '../core/scroll_placement.dart';
import '../core/scroll_target.dart';
import 'seeko_controller.dart';
import 'seeko_snapshot.dart';

/// Stable identity for a section header or one item inside a section.
@immutable
final class SeekoSectionKey<K extends Object> {
  const SeekoSectionKey.header(this.section)
      : itemKey = null,
        isHeader = true;

  const SeekoSectionKey.item(this.section, this.itemKey) : isHeader = false;

  final K section;
  final Object? itemKey;
  final bool isHeader;

  @override
  bool operator ==(Object other) =>
      other is SeekoSectionKey<K> &&
      other.section == section &&
      other.itemKey == itemKey &&
      other.isHeader == isHeader;

  @override
  int get hashCode => Object.hash(section, itemKey, isHeader);

  @override
  String toString() => isHeader
      ? 'SeekoSectionKey.header($section)'
      : 'SeekoSectionKey.item($section, $itemKey)';
}

/// Coordinates a sectioned content scrollable with one navigation scrollable.
///
/// Content remains a native Flutter scrollable. Tag its visible rows with
/// stable keys, then use [select] for navigation taps. User scrolling updates
/// [selectedSection] from the target crossing [viewportAnchor].
final class SeekoSectionCoordinator<K extends Object> {
  SeekoSectionCoordinator({
    required SeekoController contentController,
    required K initialSection,
    required SeekoVisibleSectionResolver<K> sectionOfTarget,
    required SeekoSectionTargetBuilder<K> sectionTarget,
    SeekoController? navigationController,
    SeekoSectionTargetBuilder<K>? navigationTarget,
    double viewportAnchor = 0,
  })  : _contentController = contentController,
        _navigationController = navigationController,
        _sectionOfTarget = sectionOfTarget,
        _sectionTarget = sectionTarget,
        _navigationTarget = navigationTarget,
        _viewportAnchor = _validateAnchor(viewportAnchor),
        _selectedSection = ValueNotifier<K>(initialSection) {
    _contentController.state.addListener(_handleContentSnapshot);
  }

  factory SeekoSectionCoordinator.tagged({
    required SeekoController contentController,
    required K initialSection,
    SeekoController? navigationController,
    double viewportAnchor = 0,
  }) {
    return SeekoSectionCoordinator<K>(
      contentController: contentController,
      navigationController: navigationController,
      initialSection: initialSection,
      viewportAnchor: viewportAnchor,
      sectionOfTarget: (ScrollVisibleTarget target) {
        final Object? key = target.key;
        return key is SeekoSectionKey<K> ? key.section : null;
      },
      sectionTarget: (K section) =>
          ScrollTarget.key(SeekoSectionKey<K>.header(section)),
      navigationTarget: (K section) => ScrollTarget.key(section),
    );
  }

  final SeekoController _contentController;
  final SeekoController? _navigationController;
  final SeekoVisibleSectionResolver<K> _sectionOfTarget;
  final SeekoSectionTargetBuilder<K> _sectionTarget;
  final SeekoSectionTargetBuilder<K>? _navigationTarget;
  final double _viewportAnchor;
  final ValueNotifier<K> _selectedSection;
  K? _pendingProgrammaticSection;
  var _selectionGeneration = 0;
  var _disposed = false;

  ValueListenable<K> get selectedSection => _selectedSection;

  /// Navigates content to [section] and returns the underlying typed result.
  Future<ScrollResult> select(
    K section, {
    bool animated = true,
    ScrollPlacement placement = const ScrollPlacement.start(),
    ScrollMotion motion = const ScrollMotion.adaptive(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) async {
    _requireActive();
    final int generation = ++_selectionGeneration;
    _pendingProgrammaticSection = section;
    _setSelectedSection(section, revealNavigation: true);
    final ScrollTarget target = _sectionTarget(section);
    try {
      if (animated && motion.kind != ScrollMotionKind.instant) {
        return await _contentController.animateToTarget(
          target,
          placement: placement,
          motion: motion,
          options: options,
        );
      }
      return await _contentController.jumpToTarget(
        target,
        placement: placement,
        options: options,
      );
    } finally {
      if (!_disposed && generation == _selectionGeneration) {
        _pendingProgrammaticSection = null;
        _handleContentSnapshot();
      }
    }
  }

  void _handleContentSnapshot() {
    if (_disposed) {
      return;
    }
    final ScrollSnapshot snapshot = _contentController.state.value;
    if (_pendingProgrammaticSection != null) {
      final bool userOwned = snapshot.origin == ScrollEventOrigin.user ||
          snapshot.phase == ScrollPhase.drag ||
          snapshot.phase == ScrollPhase.held;
      if (!userOwned) {
        return;
      }
      _pendingProgrammaticSection = null;
    }
    final List<ScrollVisibleTarget> targets = snapshot.visibleTargets;
    if (targets.isEmpty) {
      return;
    }
    if (snapshot.atTrailingEdge) {
      for (final ScrollVisibleTarget target in targets.reversed) {
        final K? section = _sectionOfTarget(target);
        if (section != null) {
          _setSelectedSection(section, revealNavigation: true);
          return;
        }
      }
    }
    if (snapshot.atLeadingEdge) {
      for (final ScrollVisibleTarget target in targets) {
        final K? section = _sectionOfTarget(target);
        if (section != null) {
          _setSelectedSection(section, revealNavigation: true);
          return;
        }
      }
    }
    ScrollVisibleTarget? candidate;
    for (final ScrollVisibleTarget target in targets) {
      if (target.leadingViewportFraction <= _viewportAnchor &&
          target.trailingViewportFraction >= _viewportAnchor) {
        candidate = target;
        break;
      }
      candidate ??= target;
    }
    final K? section = candidate == null ? null : _sectionOfTarget(candidate);
    if (section != null) {
      _setSelectedSection(section, revealNavigation: true);
    }
  }

  void _setSelectedSection(K section, {required bool revealNavigation}) {
    final bool changed = _selectedSection.value != section;
    if (changed) {
      _selectedSection.value = section;
    }
    if (revealNavigation && changed) {
      _revealNavigation(section);
    }
  }

  void _revealNavigation(K section) {
    final SeekoController? navigation = _navigationController;
    if (navigation == null || !navigation.isAttached) {
      return;
    }
    final ScrollTarget target =
        _navigationTarget?.call(section) ?? ScrollTarget.key(section);
    unawaited(navigation.ensureTargetVisible(target));
  }

  void _requireActive() {
    if (_disposed) {
      throw StateError('The SeekoSectionCoordinator has been disposed.');
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _contentController.state.removeListener(_handleContentSnapshot);
    _selectedSection.dispose();
  }
}

double _validateAnchor(double value) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw RangeError.value(value, 'viewportAnchor', 'must be between 0 and 1');
  }
  return value;
}
