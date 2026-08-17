import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('execution policy enforces bounded positive budgets', () {
    expect(
      () => ScrollExecutionPolicy(deadline: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => ScrollExecutionPolicy(maxCorrections: -1),
      throwsRangeError,
    );
    expect(
      () => ScrollExecutionPolicy(targetTolerance: double.infinity),
      throwsArgumentError,
    );
    expect(ScrollExecutionPolicy.jump().deadline, const Duration(seconds: 1));
  });

  test('command options merge only explicit overrides', () {
    const ScrollCommandOptions defaults = ScrollCommandOptions(
      conflictPolicy: ScrollConflictPolicy.enqueue,
      boundaryPolicy: ScrollBoundaryPolicy.reject,
    );
    const ScrollCommandOptions override = ScrollCommandOptions(
      resolutionPolicy: ScrollResolutionPolicy(requireExact: true),
    );
    final ScrollCommandOptions merged = defaults.merge(override);
    expect(merged.conflictPolicy, ScrollConflictPolicy.enqueue);
    expect(merged.boundaryPolicy, ScrollBoundaryPolicy.reject);
    expect(merged.resolutionPolicy.requireExact, isTrue);
  });

  test('command options can explicitly restore default resolution policy', () {
    const ScrollCommandOptions defaults = ScrollCommandOptions(
      resolutionPolicy: ScrollResolutionPolicy(requireExact: true),
    );

    final ScrollCommandOptions inherited = defaults.merge(
      const ScrollCommandOptions(),
    );
    final ScrollCommandOptions restored = defaults.merge(
      const ScrollCommandOptions(
        resolutionPolicy: ScrollResolutionPolicy(),
      ),
    );

    expect(inherited.resolutionPolicy.requireExact, isTrue);
    expect(restored.resolutionPolicy.requireExact, isFalse);
    expect(restored.resolutionPolicy.allowFallback, isTrue);
  });

  test('default resolution policy permits explicit degraded outcomes', () {
    const ScrollResolutionPolicy policy = ScrollResolutionPolicy();
    expect(policy.allowEstimated, isTrue);
    expect(policy.allowSearched, isTrue);
    expect(policy.allowFallback, isTrue);
    expect(policy.requireExact, isFalse);
  });

  test('scroll result exposes degraded and terminal semantics', () {
    final ScrollResult result = ScrollResult(
      commandId: 7,
      outcome: ScrollOutcome.completed,
      requestedTarget: ScrollTarget.index(9),
      capturedTarget: ScrollTarget.key('k9'),
      achievedTarget: ScrollTarget.key('k9'),
      startRevision: 2,
      endRevision: 3,
      resolutionMode: ScrollResolutionMode.searched,
      finalLogicalPixels: 420,
      finalError: 0.25,
      elapsed: Duration(milliseconds: 30),
      replanCount: 1,
      correctionCount: 1,
    );
    expect(result.isSuccess, isTrue);
    expect(result.isDegraded, isTrue);
    expect(result.isTerminal, isTrue);
  });

  test('cancellation token notifies exactly once', () {
    final ScrollCancellationSource source = ScrollCancellationSource();
    var notifications = 0;
    source.token.addListener(() => notifications += 1);
    source.cancel(ScrollStopReason.requested);
    source.cancel(ScrollStopReason.disposed);
    expect(source.token.isCancelled, isTrue);
    expect(source.token.reason, ScrollStopReason.requested);
    expect(notifications, 1);
    source.dispose();
  });
}
