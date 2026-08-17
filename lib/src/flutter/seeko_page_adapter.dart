import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/command_model.dart';
import '../core/motion.dart';
import '../core/scroll_placement.dart';
import '../core/scroll_target.dart';
import 'seeko_controller.dart';
import 'seeko_snapshot.dart';

/// A composite destination inside a PageView or viewport-fraction carousel.
@immutable
final class SeekoPageItemTarget {
  SeekoPageItemTarget({
    required this.page,
    this.item,
    this.itemPlacement = const ScrollPlacement.nearest(),
  }) {
    RangeError.checkNotNegative(page, 'page');
  }

  factory SeekoPageItemTarget.page(int page) => SeekoPageItemTarget(page: page);

  final int page;
  final ScrollTarget? item;
  final ScrollPlacement itemPlacement;

  @override
  bool operator ==(Object other) =>
      other is SeekoPageItemTarget &&
      other.page == page &&
      other.item == item &&
      other.itemPlacement == itemPlacement;

  @override
  int get hashCode => Object.hash(page, item, itemPlacement);
}

@immutable
final class SeekoPageItemResult {
  const SeekoPageItemResult({
    required this.commandId,
    required this.outcome,
    required this.requestedTarget,
    required this.achievedPage,
    required this.elapsed,
    this.itemResult,
    this.diagnostics,
  });

  final int commandId;
  final ScrollOutcome outcome;
  final SeekoPageItemTarget requestedTarget;
  final int? achievedPage;
  final Duration elapsed;
  final ScrollResult? itemResult;
  final Map<String, Object?>? diagnostics;

  bool get isSuccess =>
      outcome == ScrollOutcome.completed || outcome == ScrollOutcome.clamped;
}

@immutable
final class SeekoPageRestorationState {
  const SeekoPageRestorationState({
    required this.page,
    this.itemKey,
    this.itemIndex,
    this.pageFraction = 0,
  })  : assert(page >= 0),
        assert(
          pageFraction > double.negativeInfinity &&
              pageFraction < double.infinity,
        );

  final int page;
  final Object? itemKey;
  final int? itemIndex;
  final double pageFraction;
}

typedef SeekoPageItemControllerResolver = SeekoController? Function(int page);

/// Adds cancellable page + item navigation to an existing PageController.
///
/// The adapter owns no PageView and never disposes a caller-owned item
/// controller. The same implementation supports carousels through
/// PageController.viewportFraction.
final class SeekoPageControllerAdapter extends ChangeNotifier {
  SeekoPageControllerAdapter({
    required this.pageController,
    required this.itemControllerForPage,
    this.pageCount,
    this.ownsPageController = false,
  }) {
    if (pageCount != null && pageCount! < 0) {
      throw RangeError.value(pageCount!, 'pageCount');
    }
    pageController.addListener(_handlePageChanged);
  }

  final PageController pageController;
  final SeekoPageItemControllerResolver itemControllerForPage;
  final int? pageCount;
  final bool ownsPageController;
  final ValueNotifier<int?> _currentPage = ValueNotifier<int?>(null);
  int _sequence = 0;
  int? _activeCommand;
  bool _userInterrupted = false;
  bool _disposed = false;

  ValueListenable<int?> get currentPage => _currentPage;
  bool get isAttached => pageController.hasClients;

  Future<SeekoPageItemResult> jumpToTarget(
    SeekoPageItemTarget target, {
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    return _execute(
      target,
      motion: const ScrollMotion.instant(),
      options: options,
    );
  }

  Future<SeekoPageItemResult> animateToTarget(
    SeekoPageItemTarget target, {
    ScrollMotion motion = const ScrollMotion.adaptive(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    return _execute(target, motion: motion, options: options);
  }

  Future<SeekoPageItemResult> ensureTargetVisible(
    SeekoPageItemTarget target, {
    ScrollMotion? motion,
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    return motion == null
        ? jumpToTarget(target, options: options)
        : animateToTarget(target, motion: motion, options: options);
  }

  SeekoPageRestorationState captureRestorationState() {
    final int page = _page.round();
    final SeekoController? itemController = itemControllerForPage(page);
    final ScrollSnapshot snapshot =
        itemController?.state.value ?? const ScrollSnapshot.detached();
    return SeekoPageRestorationState(
      page: page,
      itemKey: snapshot.anchor?.key,
      itemIndex: snapshot.anchor?.index,
      pageFraction: _page - page,
    );
  }

  Future<SeekoPageItemResult> restore(
    SeekoPageRestorationState state, {
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) async {
    final ScrollTarget? item = state.itemKey != null
        ? ScrollTarget.key(state.itemKey!)
        : state.itemIndex != null
            ? ScrollTarget.index(state.itemIndex!)
            : null;
    final SeekoPageItemResult result = await jumpToTarget(
      SeekoPageItemTarget(page: state.page, item: item),
      options: options,
    );
    if (result.isSuccess &&
        state.pageFraction != 0 &&
        pageController.hasClients) {
      final ScrollPosition position = pageController.position;
      final double pageExtent =
          position.viewportDimension * pageController.viewportFraction;
      if (pageExtent.isFinite && pageExtent > 0) {
        final double target =
            (position.pixels + state.pageFraction * pageExtent)
                .clamp(position.minScrollExtent, position.maxScrollExtent)
                .toDouble();
        if ((target - position.pixels).abs() > precisionErrorTolerance) {
          pageController.jumpTo(target);
        }
      }
    }
    return result;
  }

  void stop({ScrollStopReason reason = ScrollStopReason.requested}) {
    _sequence += 1;
    final int page = _page.round();
    itemControllerForPage(page)?.stop(reason: reason);
    if (pageController.hasClients) {
      pageController.jumpTo(pageController.position.pixels);
    }
    _activeCommand = null;
  }

  Future<SeekoPageItemResult> _execute(
    SeekoPageItemTarget target, {
    required ScrollMotion motion,
    required ScrollCommandOptions options,
  }) async {
    final int commandId = ++_sequence;
    final Stopwatch elapsed = Stopwatch()..start();
    final int? activeCommand = _activeCommand;
    final ScrollConflictPolicy conflict =
        options.conflictPolicy ?? ScrollConflictPolicy.replace;
    if (activeCommand != null &&
        conflict == ScrollConflictPolicy.ignoreWhileActive) {
      return SeekoPageItemResult(
        commandId: commandId,
        outcome: ScrollOutcome.ignored,
        requestedTarget: target,
        achievedPage: _currentPage.value,
        elapsed: elapsed.elapsed,
      );
    }
    if (activeCommand != null) {
      itemControllerForPage(_page.round())?.stop(
        reason: ScrollStopReason.superseded,
      );
      if (pageController.hasClients) {
        pageController.jumpTo(pageController.position.pixels);
      }
    }
    _activeCommand = commandId;
    _userInterrupted = false;
    final ScrollCancellationToken? cancellation = options.cancellationToken;
    void handleCancellation() {
      if (identical(_activeCommand, commandId)) {
        stop(reason: cancellation?.reason ?? ScrollStopReason.requested);
      }
    }

    cancellation?.addListener(handleCancellation);
    try {
      if (!pageController.hasClients) {
        return _pageResult(
          commandId,
          ScrollOutcome.detached,
          target,
          elapsed,
        );
      }
      final _ResolvedPage resolved = _resolvePage(
        target.page,
        options.boundaryPolicy ?? ScrollBoundaryPolicy.clampNumeric,
      );
      if (resolved.outcome != null) {
        return _pageResult(
          commandId,
          resolved.outcome!,
          target,
          elapsed,
        );
      }
      if (!_isCurrent(commandId, cancellation)) {
        return _pageResult(
          commandId,
          _cancelledOutcome(cancellation),
          target,
          elapsed,
        );
      }
      final int page = resolved.page!;
      final bool clamped = page != target.page;
      final Duration deadline =
          options.executionPolicy?.deadline ?? const Duration(seconds: 3);
      final DateTime expiresAt = DateTime.now().add(deadline);
      if (motion.kind == ScrollMotionKind.instant) {
        pageController.jumpToPage(page);
      } else {
        final double pageDistance = (_page - page).abs();
        final double viewport = pageController.position.viewportDimension;
        final ScrollMotionPlan plan = const AdaptiveMotionPlanner().plan(
          distance: pageDistance * math.max(1, viewport),
          viewportExtent: math.max(1, viewport),
          frameInterval: _frameInterval,
          motion: motion,
        );
        await pageController.animateToPage(
          page,
          duration: plan.duration,
          curve: plan.curve,
        );
      }
      if (!_isCurrent(commandId, cancellation)) {
        return _pageResult(
          commandId,
          _cancelledOutcome(cancellation),
          target,
          elapsed,
        );
      }
      if (_userInterrupted) {
        return _pageResult(
          commandId,
          ScrollOutcome.interruptedByUser,
          target,
          elapsed,
        );
      }
      final ScrollTarget? itemTarget = target.item;
      if (itemTarget == null) {
        return _pageResult(
          commandId,
          clamped ? ScrollOutcome.clamped : ScrollOutcome.completed,
          target,
          elapsed,
          achievedPage: page,
        );
      }
      final SeekoController? itemController =
          await _waitForItemController(page, expiresAt, commandId);
      if (itemController == null) {
        return _pageResult(
          commandId,
          DateTime.now().isAfter(expiresAt)
              ? ScrollOutcome.timedOut
              : ScrollOutcome.detached,
          target,
          elapsed,
          achievedPage: page,
        );
      }
      final Duration remaining = expiresAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        return _pageResult(
          commandId,
          ScrollOutcome.timedOut,
          target,
          elapsed,
          achievedPage: page,
        );
      }
      final ScrollCommandOptions itemOptions = ScrollCommandOptions(
        conflictPolicy: options.conflictPolicy,
        boundaryPolicy: options.boundaryPolicy,
        resolutionPolicy: options.resolutionPolicy,
        executionPolicy: ScrollExecutionPolicy(
          deadline: remaining > const Duration(seconds: 10)
              ? const Duration(seconds: 10)
              : remaining,
        ),
        cancellationToken: cancellation,
        lockUserInteraction: options.lockUserInteraction,
      );
      final ScrollResult itemResult = motion.kind == ScrollMotionKind.instant
          ? await itemController.jumpToTarget(
              itemTarget,
              placement: target.itemPlacement,
              options: itemOptions,
            )
          : await itemController.animateToTarget(
              itemTarget,
              placement: target.itemPlacement,
              motion: motion,
              options: itemOptions,
            );
      final ScrollOutcome outcome = itemResult.isSuccess && clamped
          ? ScrollOutcome.clamped
          : itemResult.outcome;
      return _pageResult(
        commandId,
        outcome,
        target,
        elapsed,
        achievedPage: page,
        itemResult: itemResult,
      );
    } finally {
      cancellation?.removeListener(handleCancellation);
      if (identical(_activeCommand, commandId)) {
        _activeCommand = null;
      }
    }
  }

  _ResolvedPage _resolvePage(
    int requested,
    ScrollBoundaryPolicy boundaryPolicy,
  ) {
    final int? count = pageCount;
    if (count == null) {
      return _ResolvedPage(page: requested);
    }
    if (count == 0) {
      return const _ResolvedPage(outcome: ScrollOutcome.targetOutOfRange);
    }
    if (requested < count) {
      return _ResolvedPage(page: requested);
    }
    if (boundaryPolicy == ScrollBoundaryPolicy.reject) {
      return const _ResolvedPage(outcome: ScrollOutcome.targetOutOfRange);
    }
    if (boundaryPolicy == ScrollBoundaryPolicy.allowPhysicsOverscroll) {
      return const _ResolvedPage(outcome: ScrollOutcome.unsupported);
    }
    return _ResolvedPage(page: count - 1);
  }

  Future<SeekoController?> _waitForItemController(
    int page,
    DateTime expiresAt,
    int commandId,
  ) async {
    while (_activeCommand == commandId && DateTime.now().isBefore(expiresAt)) {
      final SeekoController? controller = itemControllerForPage(page);
      if (controller != null && controller.hasClients) {
        return controller;
      }
      await SchedulerBinding.instance.endOfFrame;
    }
    return null;
  }

  bool _isCurrent(
    int commandId,
    ScrollCancellationToken? cancellation,
  ) {
    return _activeCommand == commandId &&
        !(cancellation?.isCancelled ?? false) &&
        !_disposed;
  }

  ScrollOutcome _cancelledOutcome(ScrollCancellationToken? cancellation) {
    if (_userInterrupted ||
        cancellation?.reason == ScrollStopReason.userInteraction) {
      return ScrollOutcome.interruptedByUser;
    }
    if (_disposed) {
      return ScrollOutcome.detached;
    }
    return ScrollOutcome.superseded;
  }

  SeekoPageItemResult _pageResult(
    int commandId,
    ScrollOutcome outcome,
    SeekoPageItemTarget target,
    Stopwatch elapsed, {
    int? achievedPage,
    ScrollResult? itemResult,
    Map<String, Object?>? diagnostics,
  }) {
    return SeekoPageItemResult(
      commandId: commandId,
      outcome: outcome,
      requestedTarget: target,
      achievedPage:
          achievedPage ?? (pageController.hasClients ? _page.round() : null),
      elapsed: elapsed.elapsed,
      itemResult: itemResult,
      diagnostics: diagnostics,
    );
  }

  double get _page {
    if (!pageController.hasClients) {
      return pageController.initialPage.toDouble();
    }
    return pageController.page ?? pageController.initialPage.toDouble();
  }

  Duration get _frameInterval {
    final BuildContext? context = pageController.hasClients
        ? pageController.position.context.notificationContext
        : null;
    final double? rate =
        context == null ? null : View.maybeOf(context)?.display.refreshRate;
    final double hz = rate == null || !rate.isFinite || rate <= 0 ? 60 : rate;
    return Duration(
      microseconds: (Duration.microsecondsPerSecond / hz).round(),
    );
  }

  void _handlePageChanged() {
    if (_disposed || !pageController.hasClients) {
      return;
    }
    final int page = _page.round();
    if (_currentPage.value != page) {
      _currentPage.value = page;
      notifyListeners();
    }
    if (_activeCommand != null &&
        pageController.position.userScrollDirection != ScrollDirection.idle) {
      _userInterrupted = true;
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    stop(reason: ScrollStopReason.disposed);
    _disposed = true;
    pageController.removeListener(_handlePageChanged);
    if (ownsPageController) {
      pageController.dispose();
    }
    _currentPage.dispose();
    super.dispose();
  }
}

final class _ResolvedPage {
  const _ResolvedPage({this.page, this.outcome});

  final int? page;
  final ScrollOutcome? outcome;
}

enum SeekoPageSyncMode { page, progress }

enum SeekoPageSyncRole { bidirectional, leader, follower }

@immutable
final class SeekoPageSyncMember {
  const SeekoPageSyncMember({
    this.role = SeekoPageSyncRole.bidirectional,
    this.priority = 0,
  });

  final SeekoPageSyncRole role;
  final int priority;
}

/// Synchronizes any number of PageView/carousel adapters.
final class SeekoPageSyncGroup extends ChangeNotifier {
  SeekoPageSyncGroup({this.mode = SeekoPageSyncMode.progress});

  final SeekoPageSyncMode mode;
  final LinkedHashMap<SeekoPageControllerAdapter, SeekoPageSyncMember>
      _members =
      LinkedHashMap<SeekoPageControllerAdapter, SeekoPageSyncMember>.identity();
  final Map<SeekoPageControllerAdapter, VoidCallback> _listeners =
      <SeekoPageControllerAdapter, VoidCallback>{};
  SeekoPageControllerAdapter? _leader;
  bool _applying = false;
  bool _disposed = false;

  int get length => _members.length;
  SeekoPageControllerAdapter? get leader => _leader;
  Iterable<SeekoPageControllerAdapter> get adapters => _members.keys;

  void add(
    SeekoPageControllerAdapter adapter, {
    SeekoPageSyncMember member = const SeekoPageSyncMember(),
  }) {
    if (_disposed) {
      throw StateError('Cannot add to a disposed page sync group.');
    }
    if (_members.containsKey(adapter)) {
      throw StateError('The adapter is already in this page sync group.');
    }
    _members[adapter] = member;
    void listener() => _handleChanged(adapter);
    _listeners[adapter] = listener;
    adapter.pageController.addListener(listener);
    final SeekoPageControllerAdapter? source = _leader;
    if (source != null && !identical(source, adapter)) {
      _fanOut(source, only: adapter);
    } else if (member.role != SeekoPageSyncRole.follower) {
      _leader = adapter;
    }
    notifyListeners();
  }

  bool remove(SeekoPageControllerAdapter adapter) {
    final VoidCallback? listener = _listeners.remove(adapter);
    if (listener == null) {
      return false;
    }
    adapter.pageController.removeListener(listener);
    _members.remove(adapter);
    if (identical(_leader, adapter)) {
      _leader = _selectLeader();
    }
    notifyListeners();
    return true;
  }

  void _handleChanged(SeekoPageControllerAdapter source) {
    if (_applying || _disposed) {
      return;
    }
    final SeekoPageSyncMember? config = _members[source];
    if (config == null || config.role == SeekoPageSyncRole.follower) {
      return;
    }
    final SeekoPageControllerAdapter? current = _leader;
    if (current != null &&
        !identical(current, source) &&
        current.pageController.hasClients &&
        current.pageController.position.userScrollDirection !=
            ScrollDirection.idle) {
      final int currentPriority = _members[current]?.priority ?? 0;
      if (currentPriority > config.priority) {
        return;
      }
    }
    _leader = source;
    _fanOut(source);
    notifyListeners();
  }

  void _fanOut(
    SeekoPageControllerAdapter source, {
    SeekoPageControllerAdapter? only,
  }) {
    if (!source.pageController.hasClients) {
      return;
    }
    final double page = source.pageController.page ??
        source.pageController.initialPage.toDouble();
    final int sourceMax = math.max(0, (source.pageCount ?? 1) - 1);
    final double progress = sourceMax == 0 ? 0 : page / sourceMax;
    _applying = true;
    try {
      for (final MapEntry<SeekoPageControllerAdapter, SeekoPageSyncMember> entry
          in _members.entries) {
        final SeekoPageControllerAdapter follower = entry.key;
        if (identical(follower, source) ||
            only != null && !identical(follower, only) ||
            !follower.pageController.hasClients ||
            entry.value.role == SeekoPageSyncRole.leader) {
          continue;
        }
        final int maxPage = math.max(0, (follower.pageCount ?? 1) - 1);
        final double target =
            mode == SeekoPageSyncMode.page ? page : progress * maxPage;
        final double clamped = target.clamp(0, maxPage).toDouble();
        if (mode == SeekoPageSyncMode.page) {
          follower.pageController.jumpToPage(clamped.round());
        } else {
          final ScrollPosition position = follower.pageController.position;
          final double currentPage = follower.pageController.page ??
              follower.pageController.initialPage.toDouble();
          final double pixelsPerPage = position.viewportDimension *
              follower.pageController.viewportFraction;
          position.jumpTo(
            position.pixels + (clamped - currentPage) * pixelsPerPage,
          );
        }
      }
    } finally {
      _applying = false;
    }
  }

  SeekoPageControllerAdapter? _selectLeader() {
    SeekoPageControllerAdapter? selected;
    var priority = -0x7fffffff;
    for (final MapEntry<SeekoPageControllerAdapter, SeekoPageSyncMember> entry
        in _members.entries) {
      if (entry.value.role == SeekoPageSyncRole.follower) {
        continue;
      }
      if (selected == null || entry.value.priority > priority) {
        selected = entry.key;
        priority = entry.value.priority;
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
    for (final MapEntry<SeekoPageControllerAdapter, VoidCallback> entry
        in _listeners.entries) {
      entry.key.pageController.removeListener(entry.value);
    }
    _listeners.clear();
    _members.clear();
    _leader = null;
    super.dispose();
  }
}
