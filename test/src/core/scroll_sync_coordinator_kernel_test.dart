import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/src/core/scroll_sync_coordinator_kernel.dart';

void main() {
  test('propagation visits every active follower exactly once', () {
    for (final int memberCount in <int>[1, 2, 8, 32, 128, 512, 1024]) {
      final ScrollSyncCoordinatorKernel kernel = ScrollSyncCoordinatorKernel();
      final List<_Participant> members = List<_Participant>.generate(
        memberCount,
        (int index) => _Participant(),
      );
      for (final _Participant member in members) {
        kernel.add(member);
      }

      final int applied = kernel.propagate(
        source: members.first,
        coordinate: 0.75,
        transactionId: 42,
      );

      expect(applied, memberCount - 1, reason: 'memberCount=$memberCount');
      expect(members.first.applyCount, 0);
      for (final _Participant follower in members.skip(1)) {
        expect(follower.applyCount, 1);
        expect(follower.lastCoordinate, 0.75);
        expect(follower.lastTransactionId, 42);
      }
    }
  });

  test('inactive and removed participants never receive propagation', () {
    final ScrollSyncCoordinatorKernel kernel = ScrollSyncCoordinatorKernel();
    final _Participant source = _Participant();
    final _Participant active = _Participant();
    final _Participant inactive = _Participant()..active = false;
    final _Participant removed = _Participant();
    kernel
      ..add(source)
      ..add(active)
      ..add(inactive)
      ..add(removed);
    expect(kernel.remove(removed), isTrue);

    expect(
      kernel.propagate(
        source: source,
        coordinate: 120,
        transactionId: 7,
      ),
      1,
    );
    expect(active.applyCount, 1);
    expect(inactive.applyCount, 0);
    expect(removed.applyCount, 0);
    expect(kernel.memberCount, 3);
  });

  test('duplicate identity is rejected and clear releases all members', () {
    final ScrollSyncCoordinatorKernel kernel = ScrollSyncCoordinatorKernel();
    final _Participant member = _Participant();
    kernel.add(member);

    expect(() => kernel.add(member), throwsStateError);
    kernel.clear();

    expect(kernel.memberCount, 0);
    expect(kernel.remove(member), isFalse);
  });
}

final class _Participant implements ScrollSyncCoordinatorParticipant {
  var active = true;
  var applyCount = 0;
  double? lastCoordinate;
  int? lastTransactionId;

  @override
  bool get participatesInFollowerPropagation => active;

  @override
  bool applyCanonicalCoordinate({
    required double coordinate,
    required int transactionId,
  }) {
    applyCount += 1;
    lastCoordinate = coordinate;
    lastTransactionId = transactionId;
    return true;
  }
}
