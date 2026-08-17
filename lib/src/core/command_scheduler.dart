import 'dart:async';
import 'dart:collection';

import 'command_model.dart';
import 'scroll_target.dart';

typedef ScrollCommandExecutor = Future<ScrollResult> Function(
  ScrollCommandContext context,
);

final class ScrollCommandStateMachine {
  ScrollCommandPhase _phase = ScrollCommandPhase.queued;

  ScrollCommandPhase get phase => _phase;

  void transitionTo(ScrollCommandPhase next) {
    final bool allowed = switch (_phase) {
      ScrollCommandPhase.queued => next == ScrollCommandPhase.resolving ||
          next == ScrollCommandPhase.terminal,
      ScrollCommandPhase.resolving => next == ScrollCommandPhase.moving ||
          next == ScrollCommandPhase.terminal,
      ScrollCommandPhase.moving => next == ScrollCommandPhase.correcting ||
          next == ScrollCommandPhase.settled ||
          next == ScrollCommandPhase.terminal,
      ScrollCommandPhase.correcting => next == ScrollCommandPhase.moving ||
          next == ScrollCommandPhase.settled ||
          next == ScrollCommandPhase.terminal,
      ScrollCommandPhase.settled => next == ScrollCommandPhase.terminal,
      ScrollCommandPhase.terminal => false,
    };
    if (!allowed) {
      throw StateError('Invalid scroll command transition: $_phase -> $next');
    }
    _phase = next;
  }
}

final class ScrollCommandContext {
  ScrollCommandContext._({
    required this.commandId,
    required this.target,
    required this.executionPolicy,
    required this.cancellationToken,
    required this.state,
    required Stopwatch stopwatch,
    required bool Function() canCommit,
  })  : _stopwatch = stopwatch,
        _canCommit = canCommit;

  final int commandId;
  final ScrollTarget target;
  final ScrollExecutionPolicy executionPolicy;
  final ScrollCancellationToken cancellationToken;
  final ScrollCommandStateMachine state;
  final Stopwatch _stopwatch;
  final bool Function() _canCommit;

  /// Whether this command still owns the scheduler's synchronous write slot.
  bool get canCommit => _canCommit();

  /// Runs [callback] only while this command is active and not terminated.
  ///
  /// Executors must use this guard for every synchronous position or driver
  /// write. It cannot prevent side effects performed by callbacks that ignore
  /// the context after an asynchronous boundary.
  bool commit(void Function() callback) {
    if (!canCommit) {
      return false;
    }
    callback();
    return true;
  }

  /// Advances the command lifecycle while this context still owns execution.
  bool transitionTo(ScrollCommandPhase phase) {
    if (!canCommit) {
      return false;
    }
    state.transitionTo(phase);
    return true;
  }

  ScrollResult completed({
    required double finalPixels,
    double finalError = 0,
    ScrollTarget? capturedTarget,
    ScrollTarget? achievedTarget,
    int? startRevision,
    int? endRevision,
    ScrollResolutionMode resolutionMode = ScrollResolutionMode.exact,
    int replanCount = 0,
    int correctionCount = 0,
  }) {
    return ScrollResult(
      commandId: commandId,
      outcome: ScrollOutcome.completed,
      requestedTarget: target,
      capturedTarget: capturedTarget ?? target,
      achievedTarget: achievedTarget ?? capturedTarget ?? target,
      startRevision: startRevision,
      endRevision: endRevision,
      resolutionMode: resolutionMode,
      finalLogicalPixels: finalPixels,
      finalError: finalError,
      elapsed: _stopwatch.elapsed,
      replanCount: replanCount,
      correctionCount: correctionCount,
    );
  }
}

final class ScrollCommandScheduler {
  final Queue<_ScheduledCommand> _queue = Queue<_ScheduledCommand>();
  _ScheduledCommand? _active;
  var _nextId = 1;
  var _disposed = false;

  bool get hasActiveCommand => _active != null;
  int get pendingCount => _queue.length;

  Future<ScrollResult> schedule({
    required ScrollTarget target,
    required ScrollConflictPolicy policy,
    ScrollExecutionPolicy? executionPolicy,
    ScrollCancellationToken? cancellationToken,
    required ScrollCommandExecutor execute,
  }) {
    if (_disposed) {
      throw StateError('ScrollCommandScheduler is disposed.');
    }
    final _ScheduledCommand command = _ScheduledCommand(
      id: _nextId++,
      target: target,
      policy: policy,
      executionPolicy: executionPolicy ?? ScrollExecutionPolicy(),
      externalCancellationToken: cancellationToken,
      execute: execute,
    );
    command.stopwatch.start();
    command.deadlineTimer = Timer(
      command.executionPolicy.deadline,
      () => _handleDeadline(command),
    );
    _attachExternalCancellation(command);
    if (command.completer.isCompleted) {
      return command.completer.future;
    }
    final _ScheduledCommand? active = _active;
    if (active == null) {
      _start(command);
      return command.completer.future;
    }
    switch (policy) {
      case ScrollConflictPolicy.replace:
        _terminate(
            active, ScrollOutcome.superseded, ScrollStopReason.superseded);
        _active = null;
        _start(command);
      case ScrollConflictPolicy.enqueue:
        _queue.addLast(command);
      case ScrollConflictPolicy.ignoreWhileActive:
        _completeTerminal(command, ScrollOutcome.ignored);
      case ScrollConflictPolicy.coalesce:
        for (final _ScheduledCommand queued in _queue.toList()) {
          if (queued.policy == ScrollConflictPolicy.coalesce) {
            _queue.remove(queued);
            _terminate(
              queued,
              ScrollOutcome.superseded,
              ScrollStopReason.superseded,
            );
          }
        }
        _queue.addLast(command);
    }
    return command.completer.future;
  }

  void cancelActive([ScrollStopReason reason = ScrollStopReason.requested]) {
    final _ScheduledCommand? active = _active;
    if (active == null) {
      return;
    }
    _terminate(
      active,
      _outcomeForStopReason(reason),
      reason,
    );
    _active = null;
    _pump();
  }

  /// Atomically terminates the active command and every queued command.
  ///
  /// Use this when the underlying write target is no longer valid or an
  /// external Flutter write takes ownership. Unlike [cancelActive], this never
  /// starts another queued executor during cancellation.
  void cancelAll([ScrollStopReason reason = ScrollStopReason.requested]) {
    final ScrollOutcome outcome = _outcomeForStopReason(reason);
    final _ScheduledCommand? active = _active;
    _active = null;
    if (active != null) {
      _terminate(active, outcome, reason);
    }
    while (_queue.isNotEmpty) {
      _terminate(_queue.removeFirst(), outcome, reason);
    }
  }

  void _start(_ScheduledCommand command) {
    _active = command;
    command.state.transitionTo(ScrollCommandPhase.resolving);
    final ScrollCommandContext context = ScrollCommandContext._(
      commandId: command.id,
      target: command.target,
      executionPolicy: command.executionPolicy,
      cancellationToken: command.cancellationSource.token,
      state: command.state,
      stopwatch: command.stopwatch,
      canCommit: () =>
          identical(_active, command) &&
          !command.completer.isCompleted &&
          !command.cancellationSource.token.isCancelled,
    );
    unawaited(_run(command, context));
  }

  void _handleDeadline(_ScheduledCommand command) {
    if (command.completer.isCompleted) {
      return;
    }
    final bool wasActive = identical(_active, command);
    if (!wasActive) {
      _queue.remove(command);
    }
    _terminate(
      command,
      ScrollOutcome.timedOut,
      ScrollStopReason.timedOut,
    );
    if (wasActive) {
      _active = null;
      _pump();
    }
  }

  Future<void> _run(
    _ScheduledCommand command,
    ScrollCommandContext context,
  ) async {
    try {
      final ScrollResult result = await command.execute(context);
      if (!command.completer.isCompleted) {
        command.stopwatch.stop();
        _moveToTerminal(command.state);
        command.completer.complete(
          _enforceExecutionPolicy(
            result,
            command.id,
            command.target,
            command.executionPolicy,
            command.stopwatch.elapsed,
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      if (!command.completer.isCompleted) {
        command.stopwatch.stop();
        _moveToTerminal(command.state);
        command.completer.completeError(error, stackTrace);
      }
    } finally {
      _releaseResources(command);
      if (identical(_active, command)) {
        _active = null;
        _pump();
      }
    }
  }

  void _pump() {
    if (_disposed || _active != null || _queue.isEmpty) {
      return;
    }
    _start(_queue.removeFirst());
  }

  void _terminate(
    _ScheduledCommand command,
    ScrollOutcome outcome,
    ScrollStopReason reason,
  ) {
    command.cancellationSource.cancel(reason);
    _completeTerminal(command, outcome);
  }

  void _attachExternalCancellation(_ScheduledCommand command) {
    final ScrollCancellationToken? token = command.externalCancellationToken;
    if (token == null) {
      return;
    }
    void listener() => _cancelFromExternal(command);
    command.externalCancellationListener = listener;
    token.addListener(listener);
    if (token.isCancelled) {
      listener();
    }
  }

  void _cancelFromExternal(_ScheduledCommand command) {
    if (command.completer.isCompleted) {
      return;
    }
    final ScrollStopReason reason =
        command.externalCancellationToken?.reason ?? ScrollStopReason.requested;
    final ScrollOutcome outcome = _outcomeForStopReason(reason);
    if (identical(_active, command)) {
      _terminate(command, outcome, reason);
      _active = null;
      _pump();
      return;
    }
    _queue.remove(command);
    _terminate(command, outcome, reason);
  }

  void _completeTerminal(_ScheduledCommand command, ScrollOutcome outcome) {
    if (command.completer.isCompleted) {
      return;
    }
    final ScrollCommandPhase terminalPhase = command.state.phase;
    command.deadlineTimer?.cancel();
    command.stopwatch.stop();
    _moveToTerminal(command.state);
    command.completer.complete(
      ScrollResult(
        commandId: command.id,
        outcome: outcome,
        requestedTarget: command.target,
        capturedTarget: null,
        achievedTarget: null,
        startRevision: null,
        endRevision: null,
        resolutionMode: ScrollResolutionMode.exact,
        finalLogicalPixels: null,
        finalError: null,
        elapsed: command.stopwatch.elapsed,
        replanCount: 0,
        correctionCount: 0,
        diagnostics: <String, Object?>{
          'terminalPhase': terminalPhase.name,
          if (outcome == ScrollOutcome.timedOut)
            'deadlineMs': command.executionPolicy.deadline.inMilliseconds,
        },
      ),
    );
    _releaseResources(command);
  }

  void _releaseResources(_ScheduledCommand command) {
    if (command.resourcesReleased) {
      return;
    }
    command.resourcesReleased = true;
    command.deadlineTimer?.cancel();
    final void Function()? listener = command.externalCancellationListener;
    if (listener != null) {
      command.externalCancellationToken?.removeListener(listener);
    }
    command.cancellationSource.dispose();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final _ScheduledCommand? active = _active;
    if (active != null) {
      _terminate(active, ScrollOutcome.cancelled, ScrollStopReason.disposed);
      _active = null;
    }
    while (_queue.isNotEmpty) {
      final _ScheduledCommand queued = _queue.removeFirst();
      _terminate(queued, ScrollOutcome.cancelled, ScrollStopReason.disposed);
    }
  }
}

ScrollOutcome _outcomeForStopReason(ScrollStopReason reason) {
  return switch (reason) {
    ScrollStopReason.userInteraction => ScrollOutcome.interruptedByUser,
    ScrollStopReason.superseded => ScrollOutcome.superseded,
    ScrollStopReason.timedOut => ScrollOutcome.timedOut,
    ScrollStopReason.detached => ScrollOutcome.detached,
    _ => ScrollOutcome.cancelled,
  };
}

final class _ScheduledCommand {
  _ScheduledCommand({
    required this.id,
    required this.target,
    required this.policy,
    required this.executionPolicy,
    required this.externalCancellationToken,
    required this.execute,
  });

  final int id;
  final ScrollTarget target;
  final ScrollConflictPolicy policy;
  final ScrollExecutionPolicy executionPolicy;
  final ScrollCancellationToken? externalCancellationToken;
  final ScrollCommandExecutor execute;
  final Completer<ScrollResult> completer = Completer<ScrollResult>();
  final ScrollCancellationSource cancellationSource =
      ScrollCancellationSource();
  final ScrollCommandStateMachine state = ScrollCommandStateMachine();
  final Stopwatch stopwatch = Stopwatch();
  Timer? deadlineTimer;
  void Function()? externalCancellationListener;
  var resourcesReleased = false;
}

void _moveToTerminal(ScrollCommandStateMachine state) {
  if (state.phase == ScrollCommandPhase.terminal) {
    return;
  }
  if (state.phase == ScrollCommandPhase.settled) {
    state.transitionTo(ScrollCommandPhase.terminal);
    return;
  }
  state.transitionTo(ScrollCommandPhase.terminal);
}

ScrollResult _enforceExecutionPolicy(
  ScrollResult result,
  int commandId,
  ScrollTarget requestedTarget,
  ScrollExecutionPolicy policy,
  Duration elapsed,
) {
  final bool successful = result.outcome == ScrollOutcome.completed ||
      result.outcome == ScrollOutcome.clamped;
  final String? violation = successful && result.replanCount > policy.maxReplans
      ? 'maxReplans'
      : successful && result.correctionCount > policy.maxCorrections
          ? 'maxCorrections'
          : successful &&
                  (result.finalError == null || !result.finalError!.isFinite)
              ? 'invalidFinalError'
              : result.outcome == ScrollOutcome.completed &&
                      result.finalError != null &&
                      result.finalError!.abs() > policy.targetTolerance
                  ? 'targetTolerance'
                  : null;
  return ScrollResult(
    commandId: commandId,
    outcome: violation == null ? result.outcome : ScrollOutcome.layoutUnstable,
    requestedTarget: requestedTarget,
    capturedTarget: result.capturedTarget,
    achievedTarget: result.achievedTarget,
    startRevision: result.startRevision,
    endRevision: result.endRevision,
    resolutionMode: result.resolutionMode,
    finalLogicalPixels: result.finalLogicalPixels,
    finalError: result.finalError,
    elapsed: elapsed,
    replanCount: result.replanCount,
    correctionCount: result.correctionCount,
    clampReason: result.clampReason,
    diagnostics: violation == null
        ? result.diagnostics
        : <String, Object?>{
            ...?result.diagnostics,
            'schedulerPolicyViolation': violation,
          },
  );
}
