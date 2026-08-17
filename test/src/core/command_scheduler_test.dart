import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/src/core/command_model.dart';
import 'package:seeko/src/core/command_scheduler.dart';
import 'package:seeko/src/core/scroll_target.dart';

void main() {
  test('state machine accepts only declared lifecycle transitions', () {
    final ScrollCommandStateMachine machine = ScrollCommandStateMachine();
    machine.transitionTo(ScrollCommandPhase.resolving);
    machine.transitionTo(ScrollCommandPhase.moving);
    machine.transitionTo(ScrollCommandPhase.correcting);
    machine.transitionTo(ScrollCommandPhase.settled);
    machine.transitionTo(ScrollCommandPhase.terminal);
    expect(machine.phase, ScrollCommandPhase.terminal);
    expect(
      () => machine.transitionTo(ScrollCommandPhase.moving),
      throwsStateError,
    );
  });

  test('deadline cancels the active context and completes as timed out',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource caller = ScrollCancellationSource();
    final Completer<ScrollResult> never = Completer<ScrollResult>();
    late ScrollCommandContext context;

    final ScrollResult result = await scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      executionPolicy: ScrollExecutionPolicy(
        deadline: const Duration(milliseconds: 20),
      ),
      cancellationToken: caller.token,
      execute: (ScrollCommandContext value) {
        context = value;
        return never.future;
      },
    );

    expect(result.outcome, ScrollOutcome.timedOut);
    expect(context.cancellationToken.isCancelled, isTrue);
    expect(context.cancellationToken.reason, ScrollStopReason.timedOut);
    expect(result.elapsed, greaterThan(Duration.zero));
    expect(
      result.diagnostics,
      containsPair('terminalPhase', ScrollCommandPhase.resolving.name),
    );
    expect(caller.token.isCancelled, isFalse);
    expect(caller.token.debugHasListeners, isFalse);
    caller.dispose();
    scheduler.dispose();
  });

  test('deadline expires while queued without starting the executor', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final Completer<ScrollResult> gate = Completer<ScrollResult>();
    var queuedStarted = false;

    final Future<ScrollResult> active = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) => gate.future,
    );
    final ScrollResult queued = await scheduler
        .schedule(
          target: ScrollTarget.index(2),
          policy: ScrollConflictPolicy.enqueue,
          executionPolicy: ScrollExecutionPolicy(
            deadline: const Duration(milliseconds: 20),
          ),
          execute: (_) async {
            queuedStarted = true;
            return _completed(2);
          },
        )
        .timeout(const Duration(milliseconds: 100));

    expect(queued.outcome, ScrollOutcome.timedOut);
    expect(queuedStarted, isFalse);
    expect(scheduler.pendingCount, 0);
    expect(queued.elapsed, greaterThan(Duration.zero));

    gate.complete(_completed(1));
    await active;
    scheduler.dispose();
  });

  test('external cancellation removes only the queued command', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final Completer<ScrollResult> gate = Completer<ScrollResult>();
    var cancelledCommandStarted = false;

    final Future<ScrollResult> first = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) => gate.future,
    );
    final Future<ScrollResult> cancelled = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.enqueue,
      cancellationToken: cancellation.token,
      execute: (_) async {
        cancelledCommandStarted = true;
        return _completed(2);
      },
    );
    final Future<ScrollResult> last = scheduler.schedule(
      target: ScrollTarget.index(3),
      policy: ScrollConflictPolicy.enqueue,
      execute: (ScrollCommandContext context) async =>
          context.completed(finalPixels: 30),
    );

    cancellation.cancel();
    expect((await cancelled).outcome, ScrollOutcome.cancelled);
    expect(cancelledCommandStarted, isFalse);
    expect(scheduler.pendingCount, 1);

    gate.complete(_completed(1));
    await first;
    expect((await last).outcome, ScrollOutcome.completed);
    cancellation.dispose();
    scheduler.dispose();
  });

  test('pre-cancelled token prevents scheduling synchronously', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    cancellation.cancel();
    var started = false;

    final Future<ScrollResult> future = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      executionPolicy: ScrollExecutionPolicy(
        deadline: const Duration(milliseconds: 20),
      ),
      cancellationToken: cancellation.token,
      execute: (_) async {
        started = true;
        return _completed(1);
      },
    );

    expect(started, isFalse);
    expect(scheduler.hasActiveCommand, isFalse);
    expect(scheduler.pendingCount, 0);
    expect((await future).outcome, ScrollOutcome.cancelled);
    expect(cancellation.token.debugHasListeners, isFalse);
    cancellation.dispose();
    scheduler.dispose();
  });

  test('external cancellation stops only the active command', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final Completer<ScrollResult> never = Completer<ScrollResult>();
    late ScrollCommandContext activeContext;

    final Future<ScrollResult> active = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      cancellationToken: cancellation.token,
      execute: (ScrollCommandContext context) {
        activeContext = context;
        return never.future;
      },
    );
    final Future<ScrollResult> queued = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.enqueue,
      execute: (ScrollCommandContext context) async =>
          context.completed(finalPixels: 20),
    );

    cancellation.cancel();

    expect((await active).outcome, ScrollOutcome.cancelled);
    expect(activeContext.cancellationToken.isCancelled, isTrue);
    expect((await queued).outcome, ScrollOutcome.completed);
    cancellation.dispose();
    scheduler.dispose();
  });

  test('user interaction cancellation maps to interrupted by user', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final Completer<ScrollResult> never = Completer<ScrollResult>();
    late ScrollCommandContext context;

    final Future<ScrollResult> result = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      cancellationToken: cancellation.token,
      execute: (ScrollCommandContext value) {
        context = value;
        return never.future;
      },
    );

    cancellation.cancel(ScrollStopReason.userInteraction);

    expect((await result).outcome, ScrollOutcome.interruptedByUser);
    expect(context.cancellationToken.reason, ScrollStopReason.userInteraction);
    cancellation.dispose();
    scheduler.dispose();
  });

  test('detached cancellation maps to the detached outcome', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final Completer<ScrollResult> never = Completer<ScrollResult>();

    final Future<ScrollResult> result = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) => never.future,
    );

    scheduler.cancelActive(ScrollStopReason.detached);

    expect((await result).outcome, ScrollOutcome.detached);
    scheduler.dispose();
  });

  test('cancelAll atomically terminates active and queued commands', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final Completer<ScrollResult> never = Completer<ScrollResult>();
    var queuedStarted = false;

    final Future<ScrollResult> active = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) => never.future,
    );
    final Future<ScrollResult> queued = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) async {
        queuedStarted = true;
        return _completed(2);
      },
    );

    scheduler.cancelAll(ScrollStopReason.detached);

    expect((await active).outcome, ScrollOutcome.detached);
    expect((await queued).outcome, ScrollOutcome.detached);
    expect(queuedStarted, isFalse);
    expect(scheduler.hasActiveCommand, isFalse);
    expect(scheduler.pendingCount, 0);
    scheduler.dispose();
  });

  for (final (ScrollStopReason, ScrollOutcome) mapping
      in <(ScrollStopReason, ScrollOutcome)>[
    (ScrollStopReason.superseded, ScrollOutcome.superseded),
    (ScrollStopReason.timedOut, ScrollOutcome.timedOut),
    (ScrollStopReason.detached, ScrollOutcome.detached),
  ]) {
    test('cancelActive maps ${mapping.$1} to ${mapping.$2}', () async {
      final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
      final Completer<ScrollResult> never = Completer<ScrollResult>();
      final Future<ScrollResult> result = scheduler.schedule(
        target: ScrollTarget.index(1),
        policy: ScrollConflictPolicy.enqueue,
        execute: (_) => never.future,
      );

      scheduler.cancelActive(mapping.$1);

      expect((await result).outcome, mapping.$2);
      scheduler.dispose();
    });

    test('external token maps ${mapping.$1} to ${mapping.$2}', () async {
      final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
      final ScrollCancellationSource cancellation = ScrollCancellationSource();
      final Completer<ScrollResult> never = Completer<ScrollResult>();
      final Future<ScrollResult> result = scheduler.schedule(
        target: ScrollTarget.index(1),
        policy: ScrollConflictPolicy.enqueue,
        cancellationToken: cancellation.token,
        execute: (_) => never.future,
      );

      cancellation.cancel(mapping.$1);

      expect((await result).outcome, mapping.$2);
      cancellation.dispose();
      scheduler.dispose();
    });
  }

  test('scheduler records real elapsed time for executor results', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();

    final ScrollResult result = await scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _completed(1);
      },
    );

    expect(
        result.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 10)));
    scheduler.dispose();
  });

  test('scheduler normalizes executor result identity', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollTarget scheduledTarget = ScrollTarget.index(7);

    final ScrollResult result = await scheduler.schedule(
      target: scheduledTarget,
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) async => ScrollResult(
        commandId: 999,
        outcome: ScrollOutcome.completed,
        requestedTarget: ScrollTarget.index(999),
        capturedTarget: ScrollTarget.key('captured'),
        achievedTarget: ScrollTarget.offset(10),
        startRevision: 2,
        endRevision: 3,
        resolutionMode: ScrollResolutionMode.estimated,
        finalLogicalPixels: 10,
        finalError: 0,
        elapsed: Duration.zero,
        replanCount: 1,
        correctionCount: 1,
      ),
    );

    expect(result.commandId, 1);
    expect(result.requestedTarget, scheduledTarget);
    expect(result.capturedTarget, ScrollTarget.key('captured'));
    expect(result.startRevision, 2);
    expect(result.resolutionMode, ScrollResolutionMode.estimated);
    scheduler.dispose();
  });

  test('executor receives the complete execution policy', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollExecutionPolicy policy = ScrollExecutionPolicy(
      deadline: const Duration(seconds: 1),
      maxReplans: 3,
      maxCorrections: 2,
      settleSamples: 4,
      targetTolerance: 0.25,
    );

    final ScrollResult result = await scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      executionPolicy: policy,
      execute: (ScrollCommandContext context) async {
        expect(context.executionPolicy, same(policy));
        expect(context.executionPolicy.settleSamples, 4);
        return context.completed(finalPixels: 10);
      },
    );

    expect(result.outcome, ScrollOutcome.completed);
    scheduler.dispose();
  });

  test('executor advances the real command lifecycle through context',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final List<ScrollCommandPhase> phases = <ScrollCommandPhase>[];

    final ScrollResult result = await scheduler.schedule(
      target: ScrollTarget.offset(10),
      policy: ScrollConflictPolicy.replace,
      execute: (ScrollCommandContext context) async {
        phases.add(context.state.phase);
        expect(context.transitionTo(ScrollCommandPhase.moving), isTrue);
        phases.add(context.state.phase);
        expect(context.transitionTo(ScrollCommandPhase.correcting), isTrue);
        phases.add(context.state.phase);
        expect(context.transitionTo(ScrollCommandPhase.settled), isTrue);
        phases.add(context.state.phase);
        return context.completed(finalPixels: 10);
      },
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(phases, <ScrollCommandPhase>[
      ScrollCommandPhase.resolving,
      ScrollCommandPhase.moving,
      ScrollCommandPhase.correcting,
      ScrollCommandPhase.settled,
    ]);
    scheduler.dispose();
  });

  test('scheduler rejects results beyond the replan budget', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();

    final ScrollResult result = await scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      executionPolicy: ScrollExecutionPolicy(maxReplans: 1),
      execute: (ScrollCommandContext context) async => ScrollResult(
        commandId: context.commandId,
        outcome: ScrollOutcome.completed,
        requestedTarget: context.target,
        capturedTarget: context.target,
        achievedTarget: context.target,
        startRevision: 2,
        endRevision: 3,
        resolutionMode: ScrollResolutionMode.estimated,
        finalLogicalPixels: 10,
        finalError: 0.25,
        elapsed: Duration.zero,
        replanCount: 2,
        correctionCount: 0,
        diagnostics: const <String, Object?>{'executor': 'preserved'},
      ),
    );

    expect(result.outcome, ScrollOutcome.layoutUnstable);
    expect(result.replanCount, 2);
    expect(result.startRevision, 2);
    expect(result.resolutionMode, ScrollResolutionMode.estimated);
    expect(result.diagnostics, containsPair('executor', 'preserved'));
    expect(
      result.diagnostics,
      containsPair('schedulerPolicyViolation', 'maxReplans'),
    );
    scheduler.dispose();
  });

  test('scheduler rejects results beyond the correction budget', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();

    final ScrollResult result = await scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      executionPolicy: ScrollExecutionPolicy(maxCorrections: 1),
      execute: (ScrollCommandContext context) async => context.completed(
        finalPixels: 10,
        correctionCount: 2,
      ),
    );

    expect(result.outcome, ScrollOutcome.layoutUnstable);
    expect(result.correctionCount, 2);
    expect(
      result.diagnostics,
      containsPair('schedulerPolicyViolation', 'maxCorrections'),
    );
    scheduler.dispose();
  });

  test('scheduler rejects successful results outside target tolerance',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();

    final ScrollResult result = await scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      executionPolicy: ScrollExecutionPolicy(targetTolerance: 0.25),
      execute: (ScrollCommandContext context) async => context.completed(
        finalPixels: 10,
        finalError: 0.5,
      ),
    );

    expect(result.outcome, ScrollOutcome.layoutUnstable);
    expect(result.finalError, 0.5);
    expect(
      result.diagnostics,
      containsPair('schedulerPolicyViolation', 'targetTolerance'),
    );
    scheduler.dispose();
  });

  for (final double? finalError in <double?>[
    null,
    double.nan,
    double.infinity,
  ]) {
    test('scheduler rejects successful final error $finalError', () async {
      final ScrollCommandScheduler scheduler = ScrollCommandScheduler();

      final ScrollResult result = await scheduler.schedule(
        target: ScrollTarget.index(1),
        policy: ScrollConflictPolicy.enqueue,
        execute: (ScrollCommandContext context) async => ScrollResult(
          commandId: context.commandId,
          outcome: ScrollOutcome.completed,
          requestedTarget: context.target,
          capturedTarget: context.target,
          achievedTarget: context.target,
          startRevision: null,
          endRevision: null,
          resolutionMode: ScrollResolutionMode.exact,
          finalLogicalPixels: 10,
          finalError: finalError,
          elapsed: Duration.zero,
          replanCount: 0,
          correctionCount: 0,
        ),
      );

      expect(result.outcome, ScrollOutcome.layoutUnstable);
      expect(
        result.diagnostics,
        containsPair('schedulerPolicyViolation', 'invalidFinalError'),
      );
      scheduler.dispose();
    });
  }

  test('target tolerance does not reclassify executor failure outcomes',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();

    final ScrollResult result = await scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      executionPolicy: ScrollExecutionPolicy(targetTolerance: 0.25),
      execute: (ScrollCommandContext context) async => ScrollResult(
        commandId: context.commandId,
        outcome: ScrollOutcome.targetDeleted,
        requestedTarget: context.target,
        capturedTarget: context.target,
        achievedTarget: null,
        startRevision: 2,
        endRevision: 3,
        resolutionMode: ScrollResolutionMode.exact,
        finalLogicalPixels: 10,
        finalError: 5,
        elapsed: Duration.zero,
        replanCount: 99,
        correctionCount: 99,
      ),
    );

    expect(result.outcome, ScrollOutcome.targetDeleted);
    expect(result.replanCount, 99);
    expect(result.correctionCount, 99);
    expect(result.diagnostics, isNull);
    scheduler.dispose();
  });

  test('target tolerance does not reclassify an intentional clamped result',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollResult result = await scheduler.schedule(
      target: ScrollTarget.offset(-80),
      policy: ScrollConflictPolicy.replace,
      executionPolicy: ScrollExecutionPolicy(targetTolerance: 0.25),
      execute: (ScrollCommandContext context) async => ScrollResult(
        commandId: context.commandId,
        outcome: ScrollOutcome.clamped,
        requestedTarget: context.target,
        capturedTarget: context.target,
        achievedTarget: ScrollTarget.offset(0),
        startRevision: null,
        endRevision: null,
        resolutionMode: ScrollResolutionMode.exact,
        finalLogicalPixels: 0,
        finalError: 80,
        elapsed: Duration.zero,
        replanCount: 0,
        correctionCount: 0,
        clampReason: 'Finite content boundary.',
      ),
    );

    expect(result.outcome, ScrollOutcome.clamped);
    expect(result.finalError, 80);
    scheduler.dispose();
  });

  test('normal completion releases the external cancellation listener',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource cancellation = ScrollCancellationSource();

    expect(cancellation.token.debugHasListeners, isFalse);
    final Future<ScrollResult> result = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      cancellationToken: cancellation.token,
      execute: (ScrollCommandContext context) async =>
          context.completed(finalPixels: 10),
    );
    expect(cancellation.token.debugHasListeners, isTrue);

    await result;

    expect(cancellation.token.debugHasListeners, isFalse);
    cancellation.dispose();
    scheduler.dispose();
  });

  test('normal completion cancels its deadline timer', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    Timer? deadlineTimer;
    final Zone zone = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (
          Zone self,
          ZoneDelegate parent,
          Zone zone,
          Duration duration,
          void Function() callback,
        ) {
          final Timer timer = parent.createTimer(zone, duration, callback);
          if (duration == const Duration(seconds: 5)) {
            deadlineTimer = timer;
          }
          return timer;
        },
      ),
    );

    final ScrollResult result = await zone.run(
      () => scheduler.schedule(
        target: ScrollTarget.index(1),
        policy: ScrollConflictPolicy.enqueue,
        executionPolicy: ScrollExecutionPolicy(
          deadline: const Duration(seconds: 5),
        ),
        execute: (ScrollCommandContext context) async =>
            context.completed(finalPixels: 10),
      ),
    );

    expect(result.outcome, ScrollOutcome.completed);
    expect(deadlineTimer, isNotNull);
    expect(deadlineTimer!.isActive, isFalse);
    scheduler.dispose();
  });

  test('ignore releases caller cancellation resources immediately', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource caller = ScrollCancellationSource();
    final Completer<ScrollResult> gate = Completer<ScrollResult>();

    final Future<ScrollResult> active = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) => gate.future,
    );
    final ScrollResult ignored = await scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.ignoreWhileActive,
      cancellationToken: caller.token,
      execute: (_) async => _completed(2),
    );

    expect(ignored.outcome, ScrollOutcome.ignored);
    expect(caller.token.debugHasListeners, isFalse);
    expect(caller.token.isCancelled, isFalse);
    gate.complete(_completed(1));
    await active;
    caller.dispose();
    scheduler.dispose();
  });

  test('coalesce releases superseded queued cancellation resources', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource oldCaller = ScrollCancellationSource();
    final ScrollCancellationSource newCaller = ScrollCancellationSource();
    final Completer<ScrollResult> gate = Completer<ScrollResult>();

    final Future<ScrollResult> active = scheduler.schedule(
      target: ScrollTarget.index(0),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) => gate.future,
    );
    final Future<ScrollResult> old = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.coalesce,
      cancellationToken: oldCaller.token,
      execute: (_) async => _completed(1),
    );
    final Future<ScrollResult> newest = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.coalesce,
      cancellationToken: newCaller.token,
      execute: (_) async => _completed(2),
    );

    expect((await old).outcome, ScrollOutcome.superseded);
    expect(oldCaller.token.debugHasListeners, isFalse);
    expect(oldCaller.token.isCancelled, isFalse);
    expect(newCaller.token.debugHasListeners, isTrue);
    gate.complete(_completed(0));
    await active;
    expect((await newest).outcome, ScrollOutcome.completed);
    expect(newCaller.token.debugHasListeners, isFalse);
    oldCaller.dispose();
    newCaller.dispose();
    scheduler.dispose();
  });

  test('supersede never cancels or retains the caller token', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource caller = ScrollCancellationSource();
    final Completer<ScrollResult> never = Completer<ScrollResult>();
    late ScrollCommandContext firstContext;

    final Future<ScrollResult> first = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      cancellationToken: caller.token,
      execute: (ScrollCommandContext context) {
        firstContext = context;
        return never.future;
      },
    );
    final Future<ScrollResult> replacement = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.replace,
      execute: (ScrollCommandContext context) async =>
          context.completed(finalPixels: 20),
    );

    expect((await first).outcome, ScrollOutcome.superseded);
    expect(firstContext.cancellationToken.reason, ScrollStopReason.superseded);
    expect(caller.token.isCancelled, isFalse);
    expect(caller.token.debugHasListeners, isFalse);
    expect((await replacement).outcome, ScrollOutcome.completed);
    caller.cancel();
    expect(caller.token.isCancelled, isTrue);
    caller.dispose();
    scheduler.dispose();
  });

  test('dispose cancels internal work without owning caller tokens', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource caller = ScrollCancellationSource();
    final Completer<ScrollResult> never = Completer<ScrollResult>();
    late ScrollCommandContext context;

    final Future<ScrollResult> result = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      cancellationToken: caller.token,
      execute: (ScrollCommandContext value) {
        context = value;
        return never.future;
      },
    );

    scheduler.dispose();

    expect((await result).outcome, ScrollOutcome.cancelled);
    expect(context.cancellationToken.reason, ScrollStopReason.disposed);
    expect(caller.token.isCancelled, isFalse);
    expect(caller.token.debugHasListeners, isFalse);
    caller.cancel();
    expect(caller.token.reason, ScrollStopReason.requested);
    caller.dispose();
  });

  test('dispose releases queued resources and remains idempotent', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource queuedCaller = ScrollCancellationSource();
    final Completer<ScrollResult> never = Completer<ScrollResult>();
    var queuedStarted = false;

    final Future<ScrollResult> active = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) => never.future,
    );
    final Future<ScrollResult> queued = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.enqueue,
      cancellationToken: queuedCaller.token,
      execute: (_) async {
        queuedStarted = true;
        return _completed(2);
      },
    );

    scheduler.dispose();
    scheduler.dispose();

    expect((await active).outcome, ScrollOutcome.cancelled);
    expect((await queued).outcome, ScrollOutcome.cancelled);
    expect(queuedStarted, isFalse);
    expect(queuedCaller.token.debugHasListeners, isFalse);
    expect(queuedCaller.token.isCancelled, isFalse);
    queuedCaller.cancel();
    expect(queuedCaller.token.reason, ScrollStopReason.requested);
    queuedCaller.dispose();
  });

  test('commit guard rejects an executor after replacement', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final Completer<ScrollResult> oldExecutor = Completer<ScrollResult>();
    late ScrollCommandContext oldContext;
    var sideEffects = 0;

    final Future<ScrollResult> oldResult = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      execute: (ScrollCommandContext context) {
        oldContext = context;
        expect(context.canCommit, isTrue);
        expect(context.commit(() => sideEffects += 1), isTrue);
        return oldExecutor.future;
      },
    );
    final Future<ScrollResult> replacement = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.replace,
      execute: (ScrollCommandContext context) async {
        expect(context.commit(() => sideEffects += 1), isTrue);
        return context.completed(finalPixels: 20);
      },
    );

    expect((await oldResult).outcome, ScrollOutcome.superseded);
    expect(oldContext.canCommit, isFalse);
    expect(oldContext.commit(() => sideEffects += 100), isFalse);
    expect((await replacement).outcome, ScrollOutcome.completed);
    expect(sideEffects, 2);
    oldExecutor.complete(_completed(1));
    scheduler.dispose();
  });

  test('commit guard rejects an executor after timeout', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final Completer<ScrollResult> executor = Completer<ScrollResult>();
    late ScrollCommandContext context;
    var sideEffects = 0;

    final Future<ScrollResult> result = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      executionPolicy: ScrollExecutionPolicy(
        deadline: const Duration(milliseconds: 20),
      ),
      execute: (ScrollCommandContext value) {
        context = value;
        return executor.future;
      },
    );

    expect((await result).outcome, ScrollOutcome.timedOut);
    expect(context.canCommit, isFalse);
    expect(context.commit(() => sideEffects += 1), isFalse);
    expect(sideEffects, 0);
    executor.complete(_completed(1));
    scheduler.dispose();
  });

  test('commit guard rejects an executor after external cancellation',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final Completer<ScrollResult> executor = Completer<ScrollResult>();
    late ScrollCommandContext context;
    var sideEffects = 0;

    final Future<ScrollResult> result = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      cancellationToken: cancellation.token,
      execute: (ScrollCommandContext value) {
        context = value;
        return executor.future;
      },
    );

    cancellation.cancel();
    expect((await result).outcome, ScrollOutcome.cancelled);
    expect(context.canCommit, isFalse);
    expect(context.commit(() => sideEffects += 1), isFalse);
    expect(sideEffects, 0);
    executor.complete(_completed(1));
    cancellation.dispose();
    scheduler.dispose();
  });

  test('late executor completion cannot complete a timed out command twice',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final Completer<ScrollResult> executor = Completer<ScrollResult>();
    final List<Object> uncaught = <Object>[];

    await runZonedGuarded(() async {
      final Future<ScrollResult> result = scheduler.schedule(
        target: ScrollTarget.index(1),
        policy: ScrollConflictPolicy.enqueue,
        executionPolicy: ScrollExecutionPolicy(
          deadline: const Duration(milliseconds: 20),
        ),
        execute: (_) => executor.future,
      );

      expect((await result).outcome, ScrollOutcome.timedOut);
      executor.complete(_completed(1));
      await Future<void>.delayed(Duration.zero);
    }, (Object error, StackTrace stackTrace) {
      uncaught.add(error);
    });

    expect(uncaught, isEmpty);
    scheduler.dispose();
  });

  test('late executor error cannot complete a cancelled command twice',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final ScrollCancellationSource cancellation = ScrollCancellationSource();
    final Completer<void> executor = Completer<void>();
    final List<Object> uncaught = <Object>[];

    await runZonedGuarded(() async {
      final Future<ScrollResult> result = scheduler.schedule(
        target: ScrollTarget.index(1),
        policy: ScrollConflictPolicy.enqueue,
        cancellationToken: cancellation.token,
        execute: (_) async {
          await executor.future;
          throw StateError('late failure');
        },
      );

      cancellation.cancel();
      expect((await result).outcome, ScrollOutcome.cancelled);
      executor.complete();
      await Future<void>.delayed(Duration.zero);
    }, (Object error, StackTrace stackTrace) {
      uncaught.add(error);
    });

    expect(uncaught, isEmpty);
    cancellation.dispose();
    scheduler.dispose();
  });

  test('replace supersedes the active command before starting the next',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final Completer<ScrollResult> firstRun = Completer<ScrollResult>();
    final Future<ScrollResult> first = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.replace,
      execute: (_) => firstRun.future,
    );
    await Future<void>.delayed(Duration.zero);
    final Future<ScrollResult> second = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.replace,
      execute: (ScrollCommandContext context) async =>
          context.completed(finalPixels: 20),
    );
    expect((await first).outcome, ScrollOutcome.superseded);
    expect((await second).outcome, ScrollOutcome.completed);
    firstRun.complete(_completed(1));
    scheduler.dispose();
  });

  test('enqueue preserves request order and ignore returns immediately',
      () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final Completer<ScrollResult> gate = Completer<ScrollResult>();
    final List<int> started = <int>[];
    final Future<ScrollResult> first = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.enqueue,
      execute: (ScrollCommandContext context) {
        started.add(1);
        return gate.future;
      },
    );
    final Future<ScrollResult> ignored = scheduler.schedule(
      target: ScrollTarget.index(9),
      policy: ScrollConflictPolicy.ignoreWhileActive,
      execute: (_) async => _completed(9),
    );
    final Future<ScrollResult> queued = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.enqueue,
      execute: (ScrollCommandContext context) async {
        started.add(2);
        return context.completed(finalPixels: 20);
      },
    );
    expect((await ignored).outcome, ScrollOutcome.ignored);
    expect(started, <int>[1]);
    gate.complete(_completed(1));
    await first;
    expect((await queued).outcome, ScrollOutcome.completed);
    expect(started, <int>[1, 2]);
    scheduler.dispose();
  });

  test('coalesce replaces only the newest queued request', () async {
    final ScrollCommandScheduler scheduler = ScrollCommandScheduler();
    final Completer<ScrollResult> gate = Completer<ScrollResult>();
    final Future<ScrollResult> first = scheduler.schedule(
      target: ScrollTarget.index(0),
      policy: ScrollConflictPolicy.enqueue,
      execute: (_) => gate.future,
    );
    final Future<ScrollResult> old = scheduler.schedule(
      target: ScrollTarget.index(1),
      policy: ScrollConflictPolicy.coalesce,
      execute: (_) async => _completed(1),
    );
    final Future<ScrollResult> newest = scheduler.schedule(
      target: ScrollTarget.index(2),
      policy: ScrollConflictPolicy.coalesce,
      execute: (_) async => _completed(2),
    );
    expect((await old).outcome, ScrollOutcome.superseded);
    gate.complete(_completed(0));
    await first;
    expect((await newest).achievedTarget, ScrollTarget.index(2));
    scheduler.dispose();
  });
}

ScrollResult _completed(int index) {
  return ScrollResult(
    commandId: index,
    outcome: ScrollOutcome.completed,
    requestedTarget: ScrollTarget.index(index),
    capturedTarget: ScrollTarget.index(index),
    achievedTarget: ScrollTarget.index(index),
    startRevision: 0,
    endRevision: 0,
    resolutionMode: ScrollResolutionMode.exact,
    finalLogicalPixels: index * 10,
    finalError: 0,
    elapsed: Duration.zero,
    replanCount: 0,
    correctionCount: 0,
  );
}
