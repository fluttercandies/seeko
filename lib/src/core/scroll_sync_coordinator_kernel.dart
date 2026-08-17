/// A member managed by the allocation-stable synchronization fan-out kernel.
///
/// Implementations own mapping and application. The kernel only enforces
/// membership, active participation, source suppression, and exactly-once
/// follower visitation.
abstract interface class ScrollSyncCoordinatorParticipant {
  bool get participatesInFollowerPropagation;

  bool applyCanonicalCoordinate({
    required double coordinate,
    required int transactionId,
  });
}

/// Pure Dart synchronization fan-out shared by production and benchmarks.
///
/// Membership mutations may resize the internal list. [propagate] itself
/// performs one indexed pass without creating a temporary collection.
final class ScrollSyncCoordinatorKernel {
  final List<ScrollSyncCoordinatorParticipant> _members =
      <ScrollSyncCoordinatorParticipant>[];

  int get memberCount => _members.length;

  void add(ScrollSyncCoordinatorParticipant participant) {
    for (final ScrollSyncCoordinatorParticipant current in _members) {
      if (identical(current, participant)) {
        throw StateError(
          'A synchronization participant cannot be added more than once.',
        );
      }
    }
    _members.add(participant);
  }

  bool remove(ScrollSyncCoordinatorParticipant participant) {
    for (var index = 0; index < _members.length; index += 1) {
      if (identical(_members[index], participant)) {
        _members.removeAt(index);
        return true;
      }
    }
    return false;
  }

  int propagate({
    required ScrollSyncCoordinatorParticipant source,
    required double coordinate,
    required int transactionId,
  }) {
    var applied = 0;
    for (var index = 0; index < _members.length; index += 1) {
      final ScrollSyncCoordinatorParticipant member = _members[index];
      if (identical(member, source) ||
          !member.participatesInFollowerPropagation) {
        continue;
      }
      if (member.applyCanonicalCoordinate(
        coordinate: coordinate,
        transactionId: transactionId,
      )) {
        applied += 1;
      }
    }
    return applied;
  }

  void clear() => _members.clear();
}
