import 'dart:async';

import '../core/command_model.dart';
import '../core/motion.dart';
import '../core/open_data.dart';
import '../core/scroll_target.dart';
import 'seeko_controller.dart';

/// Connects an open bidirectional data domain to a normal SeekoController.
final class SeekoOpenScrollAdapter<K extends Object> {
  const SeekoOpenScrollAdapter({
    required this.controller,
    required this.data,
    this.maxPageLoads = 8,
  }) : assert(maxPageLoads > 0);

  final SeekoController controller;
  final SeekoOpenDataController<K> data;
  final int maxPageLoads;

  Future<ScrollResult> jumpToIndex(
    int logicalIndex, {
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    return _reveal(
      logicalIndex,
      motion: const ScrollMotion.instant(),
      options: options,
    );
  }

  Future<ScrollResult> animateToIndex(
    int logicalIndex, {
    ScrollMotion motion = const ScrollMotion.adaptive(),
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) {
    return _reveal(logicalIndex, motion: motion, options: options);
  }

  Future<ScrollResult> jumpToKey(
    K key, {
    ScrollCommandOptions options = const ScrollCommandOptions(),
  }) async {
    final SeekoOpenResolution<K> resolution = data.resolveKey(key);
    if (resolution.status != SeekoOpenResolutionStatus.resolved) {
      return _terminal(
        ScrollTarget.key(key),
        resolution.status == SeekoOpenResolutionStatus.absent
            ? ScrollOutcome.targetDeleted
            : ScrollOutcome.targetNotLoaded,
      );
    }
    return controller.jumpToTarget(
      ScrollTarget.offset(resolution.contentOffset!),
      options: options,
    );
  }

  Future<ScrollResult> _reveal(
    int logicalIndex, {
    required ScrollMotion motion,
    required ScrollCommandOptions options,
  }) async {
    if (options.cancellationToken?.isCancelled ?? false) {
      return _terminal(
        ScrollTarget.custom(logicalIndex),
        ScrollOutcome.cancelled,
      );
    }
    SeekoOpenResolution<K> resolution = data.resolveIndex(logicalIndex);
    var loads = 0;
    while (resolution.status == SeekoOpenResolutionStatus.notLoaded &&
        loads < maxPageLoads) {
      final int? first = data.firstLoadedIndex;
      final SeekoOpenDirection direction =
          first == null || logicalIndex >= first
              ? SeekoOpenDirection.after
              : SeekoOpenDirection.before;
      final SeekoOpenMutationResult<K> mutation = await data.load(direction);
      loads += 1;
      if (mutation.pixelCorrection != 0 && controller.hasClients) {
        await controller.jumpBy(mutation.pixelCorrection);
      }
      if (options.cancellationToken?.isCancelled ?? false) {
        return _terminal(
          ScrollTarget.custom(logicalIndex),
          ScrollOutcome.cancelled,
        );
      }
      resolution = data.resolveIndex(logicalIndex);
    }
    if (resolution.status != SeekoOpenResolutionStatus.resolved) {
      return _terminal(
        ScrollTarget.custom(logicalIndex),
        resolution.status == SeekoOpenResolutionStatus.absent
            ? ScrollOutcome.targetOutOfRange
            : ScrollOutcome.targetNotLoaded,
      );
    }
    final ScrollTarget target = ScrollTarget.offset(resolution.contentOffset!);
    return motion.kind == ScrollMotionKind.instant
        ? controller.jumpToTarget(target, options: options)
        : controller.animateToTarget(
            target,
            motion: motion,
            options: options,
          );
  }

  ScrollResult _terminal(ScrollTarget target, ScrollOutcome outcome) {
    return ScrollResult(
      commandId: -1,
      outcome: outcome,
      requestedTarget: target,
      capturedTarget: null,
      achievedTarget: null,
      startRevision: data.revision,
      endRevision: data.revision,
      resolutionMode: ScrollResolutionMode.fallback,
      finalLogicalPixels: controller.hasClients ? controller.offset : null,
      finalError: null,
      elapsed: Duration.zero,
      replanCount: 0,
      correctionCount: 0,
      diagnostics: <String, Object?>{
        'loadedCount': data.loadedCount,
        'firstLoadedIndex': data.firstLoadedIndex,
        'lastLoadedIndex': data.lastLoadedIndex,
      },
    );
  }
}
