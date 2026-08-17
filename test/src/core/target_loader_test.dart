import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('load policy keeps retry attempts and delays bounded', () {
    final ScrollTargetLoadPolicy policy = ScrollTargetLoadPolicy(
      maxAttempts: 4,
      initialRetryDelay: Duration(milliseconds: 50),
      backoffFactor: 2,
      maxRetryDelay: Duration(milliseconds: 120),
    );

    expect(policy.retryDelayAfter(1), const Duration(milliseconds: 50));
    expect(policy.retryDelayAfter(2), const Duration(milliseconds: 100));
    expect(policy.retryDelayAfter(3), const Duration(milliseconds: 120));
    expect(
      policy.retryDelayAfter(
        1,
        suggested: const Duration(milliseconds: 500),
      ),
      const Duration(milliseconds: 120),
    );
  });

  test('load policy rejects unbounded or invalid retry configuration', () {
    expect(
      () => ScrollTargetLoadPolicy(maxAttempts: 0),
      throwsRangeError,
    );
    expect(
      () => ScrollTargetLoadPolicy(backoffFactor: 0.5),
      throwsArgumentError,
    );
    expect(
      () => ScrollTargetLoadPolicy(
        initialRetryDelay: const Duration(milliseconds: 2),
        maxRetryDelay: const Duration(milliseconds: 1),
      ),
      throwsArgumentError,
    );
  });

  test('not-found result accepts only identity terminal outcomes', () {
    expect(
      ScrollTargetLoadResult.notFound(
        outcome: ScrollOutcome.targetDeleted,
      ).status,
      ScrollTargetLoadStatus.notFound,
    );
    expect(
      ScrollTargetLoadResult.notFound(
        outcome: ScrollOutcome.targetOutOfRange,
      ).outcome,
      ScrollOutcome.targetOutOfRange,
    );
    expect(
      () => ScrollTargetLoadResult.notFound(
        outcome: ScrollOutcome.completed,
      ),
      throwsArgumentError,
    );
  });

  test('loader protocol rejects invalid revisions and retry delays', () {
    final ScrollCancellationToken cancellation = ScrollCancellationToken();

    expect(
      () => ScrollTargetLoadRequest(
        commandId: 1,
        target: ScrollTarget.index(10),
        attempt: 1,
        startRevision: -1,
        cancellationToken: cancellation,
      ),
      throwsRangeError,
    );
    expect(
      () => ScrollTargetLoadResult.loaded(revision: -1),
      throwsRangeError,
    );
    expect(
      () => ScrollTargetLoadResult.retry(
        retryAfter: const Duration(microseconds: -1),
      ),
      throwsArgumentError,
    );

    cancellation.dispose();
  });

  test('callback loader receives command identity and cancellation', () async {
    late ScrollTargetLoadRequest observed;
    final CallbackScrollTargetLoader loader = CallbackScrollTargetLoader(
      (ScrollTargetLoadRequest request) {
        observed = request;
        return ScrollTargetLoadResult.loaded(revision: 7);
      },
    );
    final ScrollCancellationToken cancellation = ScrollCancellationToken();
    final ScrollTargetLoadResult result = await loader.load(
      ScrollTargetLoadRequest(
        commandId: 12,
        target: ScrollTarget.key('remote'),
        attempt: 2,
        startRevision: 3,
        cancellationToken: cancellation,
      ),
    );

    expect(result.status, ScrollTargetLoadStatus.loaded);
    expect(result.revision, 7);
    expect(observed.commandId, 12);
    expect(observed.attempt, 2);
    expect(observed.startRevision, 3);
    expect(observed.cancellationToken, same(cancellation));
  });
}
