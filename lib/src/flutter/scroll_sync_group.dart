part of 'seeko_controller.dart';

const double _scrollSyncPixelTolerance = 0.5;

/// Whether a synchronization member may lead, follow, or only observe.
enum ScrollSyncRole { bidirectional, leaderOnly, followerOnly, observer }

/// Runtime participation without removing a member from its group.
enum ScrollSyncParticipation { active, temporarilyMuted, offstage }

/// Whether followers mirror each update or converge with member-local motion.
enum ScrollSyncMode { strict, natural }

/// What happens after a natural follower reaches its canonical target.
enum NaturalSyncSnapBehavior {
  /// Stop exactly at the canonical target without starting member physics.
  none,

  /// Hand off to the member's zero-velocity ballistic physics.
  memberPhysics,
}

/// Declares the bounded motion contract of a natural synchronization member.
@immutable
final class NaturalSyncPhysicsProfile {
  const NaturalSyncPhysicsProfile({
    required this.settleDuration,
    required this.curve,
    required this.convergesToTarget,
    required this.boundedDuration,
    required this.supportsExternalInitialVelocity,
    required this.snapBehavior,
  });

  /// Maximum duration used to converge after the latest canonical update.
  final Duration settleDuration;

  /// Member-local convergence curve.
  final Curve curve;

  /// Whether the member guarantees convergence to an unclamped target.
  final bool convergesToTarget;

  /// Whether convergence has a finite upper duration bound.
  final bool boundedDuration;

  /// Whether the member can accept a canonical initial velocity hint.
  final bool supportsExternalInitialVelocity;

  /// Ballistic or snap behavior after reaching the canonical target.
  final NaturalSyncSnapBehavior snapBehavior;
}

/// Runtime convergence measurements for one natural synchronization member.
///
/// The coordinator stores primitive counters on the hot path and creates this
/// immutable snapshot only when [ScrollSyncMember.naturalDiagnostics] is read.
@immutable
final class NaturalSyncMemberDiagnostics {
  const NaturalSyncMemberDiagnostics({
    required this.transactionId,
    required this.targetLogicalPixels,
    required this.currentMappingError,
    required this.peakMappingError,
    required this.phaseLag,
    required this.settleLag,
    required this.isSettled,
  });

  /// Group transaction that produced these measurements.
  final int transactionId;

  /// Latest member-local target mapped from the canonical coordinate.
  final double targetLogicalPixels;

  /// Absolute member-local distance from the latest target.
  final double currentMappingError;

  /// Largest absolute mapping error observed during this transaction.
  final double peakMappingError;

  /// Delay from transaction propagation until the member first moved.
  final Duration? phaseLag;

  /// Delay from the latest canonical target update until exact settlement.
  final Duration? settleLag;

  /// Whether the member is within the library's 0.5 logical-pixel tolerance.
  final bool isSettled;
}

/// How a scalar synchronization transaction handles unequal member bounds.
enum ScrollSyncBoundaryPolicy {
  perMemberClamp,
  stopAtFirstBoundary,
  sharedReachableRange,
}

enum ScrollSyncMemberFailurePolicy { removeAndContinue, failGroup }

/// Current semantic alignment state of one synchronization member.
enum ScrollSyncMemberSynchronizationStatus {
  synchronized,
  holding,
  fallback,
  desynchronized,
}

/// Result of translating a member-local semantic anchor to or from a group's
/// canonical semantic domain.
@immutable
final class ScrollSyncSemanticMappingResult {
  const ScrollSyncSemanticMappingResult.mapped(this.anchor)
      : isFallback = false,
        diagnostic = null,
        missingAnchorPolicy = null;

  const ScrollSyncSemanticMappingResult.fallback(
    this.anchor, {
    this.diagnostic,
  })  : isFallback = true,
        missingAnchorPolicy = null;

  const ScrollSyncSemanticMappingResult.missing({
    this.diagnostic,
    this.missingAnchorPolicy,
  })  : anchor = null,
        isFallback = false;

  final ScrollSemanticAnchor? anchor;
  final bool isFallback;
  final String? diagnostic;
  final ScrollSyncMissingAnchorPolicy? missingAnchorPolicy;
}

typedef ScrollSyncMemberToCanonicalSemantic = ScrollSyncSemanticMappingResult
    Function(
  SeekoController controller,
  ScrollSnapshot snapshot,
  ScrollSemanticAnchor anchor,
);

typedef ScrollSyncCanonicalToMemberSemantic = ScrollSyncSemanticMappingResult
    Function(
  SeekoController controller,
  ScrollSemanticAnchor anchor,
);

/// Bidirectional adapter between one member's keys and a canonical semantic
/// domain shared by the synchronization group.
abstract interface class ScrollSyncSemanticMapping {
  Listenable? get changes;

  ScrollSyncSemanticMappingResult memberToCanonical(
    SeekoController controller,
    ScrollSnapshot snapshot,
    ScrollSemanticAnchor anchor,
  );

  ScrollSyncSemanticMappingResult canonicalToMember(
    SeekoController controller,
    ScrollSemanticAnchor anchor,
  );
}

/// Callback adapter for application-defined semantic domains.
final class CallbackScrollSyncSemanticMapping
    implements ScrollSyncSemanticMapping {
  const CallbackScrollSyncSemanticMapping({
    required ScrollSyncMemberToCanonicalSemantic memberToCanonical,
    required ScrollSyncCanonicalToMemberSemantic canonicalToMember,
    this.changes,
  })  : _memberToCanonical = memberToCanonical,
        _canonicalToMember = canonicalToMember;

  final ScrollSyncMemberToCanonicalSemantic _memberToCanonical;
  final ScrollSyncCanonicalToMemberSemantic _canonicalToMember;

  @override
  final Listenable? changes;

  @override
  ScrollSyncSemanticMappingResult memberToCanonical(
    SeekoController controller,
    ScrollSnapshot snapshot,
    ScrollSemanticAnchor anchor,
  ) =>
      _memberToCanonical(controller, snapshot, anchor);

  @override
  ScrollSyncSemanticMappingResult canonicalToMember(
    SeekoController controller,
    ScrollSemanticAnchor anchor,
  ) =>
      _canonicalToMember(controller, anchor);
}

enum GroupScrollOutcome {
  completed,
  superseded,
  interruptedByUser,
  disposed,
  noActiveMembers,
  memberFailed,
}

enum GroupScrollMemberOutcome {
  completed,
  clamped,
  unsupported,
  detached,
  removed,
  superseded,
  interruptedByUser,
  disposed,
  failed,
}

final class GroupScrollMemberResult {
  const GroupScrollMemberResult({
    required this.memberId,
    required this.outcome,
    required this.finalLogicalPixels,
  });

  final Object memberId;
  final GroupScrollMemberOutcome outcome;
  final double? finalLogicalPixels;
}

final class GroupScrollResult {
  const GroupScrollResult({
    required this.outcome,
    required this.requestedCoordinate,
    required this.finalCoordinate,
    required this.elapsed,
    required this.members,
  });

  final GroupScrollOutcome outcome;
  final double requestedCoordinate;
  final double? finalCoordinate;
  final Duration elapsed;
  final List<GroupScrollMemberResult> members;

  bool get isSuccess => outcome == GroupScrollOutcome.completed;
}

/// Coordinates any number of native scrollables through one canonical domain.
///
/// Each member keeps its own [SeekoController]. The group never owns or
/// disposes controllers, and a controller can belong to only one active group.
final class ScrollSyncGroup extends ChangeNotifier {
  ScrollSyncGroup({
    this.mapping = const ScrollSyncMapping.progress(),
    this.mode = ScrollSyncMode.strict,
    this.boundaryPolicy = ScrollSyncBoundaryPolicy.perMemberClamp,
    this.memberFailurePolicy = ScrollSyncMemberFailurePolicy.removeAndContinue,
  }) {
    if (mapping.kind == ScrollSyncMappingKind.semantic &&
        boundaryPolicy != ScrollSyncBoundaryPolicy.perMemberClamp) {
      throw ArgumentError(
        'Semantic synchronization uses missing-anchor policy rather than '
        'scalar shared boundary calculation.',
      );
    }
    if (boundaryPolicy != ScrollSyncBoundaryPolicy.perMemberClamp &&
        !mapping.isInvertible) {
      throw ArgumentError(
        'Shared boundary policies require an invertible mapping.',
      );
    }
  }

  factory ScrollSyncGroup.pixels({
    ScrollSyncMode mode = ScrollSyncMode.strict,
    ScrollSyncBoundaryPolicy boundaryPolicy =
        ScrollSyncBoundaryPolicy.perMemberClamp,
    ScrollSyncMemberFailurePolicy memberFailurePolicy =
        ScrollSyncMemberFailurePolicy.removeAndContinue,
  }) =>
      ScrollSyncGroup(
        mapping: const ScrollSyncMapping.pixels(),
        mode: mode,
        boundaryPolicy: boundaryPolicy,
        memberFailurePolicy: memberFailurePolicy,
      );

  factory ScrollSyncGroup.progress({
    ScrollSyncMode mode = ScrollSyncMode.strict,
    ScrollSyncBoundaryPolicy boundaryPolicy =
        ScrollSyncBoundaryPolicy.perMemberClamp,
    ScrollSyncMemberFailurePolicy memberFailurePolicy =
        ScrollSyncMemberFailurePolicy.removeAndContinue,
  }) =>
      ScrollSyncGroup(
        mapping: const ScrollSyncMapping.progress(),
        mode: mode,
        boundaryPolicy: boundaryPolicy,
        memberFailurePolicy: memberFailurePolicy,
      );

  factory ScrollSyncGroup.delta({
    ScrollSyncMode mode = ScrollSyncMode.strict,
    ScrollSyncBoundaryPolicy boundaryPolicy =
        ScrollSyncBoundaryPolicy.perMemberClamp,
    ScrollSyncMemberFailurePolicy memberFailurePolicy =
        ScrollSyncMemberFailurePolicy.removeAndContinue,
  }) =>
      ScrollSyncGroup(
        mapping: const ScrollSyncMapping.delta(),
        mode: mode,
        boundaryPolicy: boundaryPolicy,
        memberFailurePolicy: memberFailurePolicy,
      );

  factory ScrollSyncGroup.viewportFraction({
    ScrollSyncMode mode = ScrollSyncMode.strict,
    ScrollSyncBoundaryPolicy boundaryPolicy =
        ScrollSyncBoundaryPolicy.perMemberClamp,
    ScrollSyncMemberFailurePolicy memberFailurePolicy =
        ScrollSyncMemberFailurePolicy.removeAndContinue,
  }) =>
      ScrollSyncGroup(
        mapping: const ScrollSyncMapping.viewportFraction(),
        mode: mode,
        boundaryPolicy: boundaryPolicy,
        memberFailurePolicy: memberFailurePolicy,
      );

  factory ScrollSyncGroup.semantic({
    ScrollSyncMode mode = ScrollSyncMode.strict,
    ScrollSyncMissingAnchorPolicy missingAnchorPolicy =
        ScrollSyncMissingAnchorPolicy.hold,
    ScrollSyncMemberFailurePolicy memberFailurePolicy =
        ScrollSyncMemberFailurePolicy.removeAndContinue,
  }) =>
      ScrollSyncGroup(
        mapping: ScrollSyncMapping.semantic(
          missingAnchorPolicy: missingAnchorPolicy,
        ),
        mode: mode,
        memberFailurePolicy: memberFailurePolicy,
      );

  final ScrollSyncMapping mapping;
  final ScrollSyncMode mode;
  final ScrollSyncBoundaryPolicy boundaryPolicy;
  final ScrollSyncMemberFailurePolicy memberFailurePolicy;
  final ScrollSyncCoordinatorKernel _coordinator =
      ScrollSyncCoordinatorKernel();
  final List<_ScrollSyncMemberState> _members = <_ScrollSyncMemberState>[];
  _ScrollSyncMemberState? _leader;
  double? _canonicalCoordinate;
  ScrollSemanticAnchor? _canonicalSemanticAnchor;
  double? _semanticFallbackProgress;
  Duration? _leaderFrameTime;
  ScrollEventOrigin _leaderOrigin = ScrollEventOrigin.none;
  ScrollPhase _leaderPhase = ScrollPhase.idle;
  var _nextMemberId = 1;
  var _nextTransactionId = 1;
  var _transactionCount = 0;
  var _followerApplyCount = 0;
  var _metricsCorrectionScheduled = false;
  var _semanticCorrectionScheduled = false;
  var _notificationScheduled = false;
  var _disposed = false;
  String? _failureReason;
  Ticker? _programmaticTicker;
  Completer<GroupScrollResult>? _programmaticCompleter;
  List<_ScrollSyncMemberState>? _programmaticParticipants;
  Stopwatch? _programmaticStopwatch;
  double? _programmaticRequestedCoordinate;
  var _programmaticNaturalSettling = false;
  int? _programmaticTransactionId;

  int get memberCount => _members.length;

  int get activeMemberCount => _members.where(_isActiveFollowerOrLeader).length;

  Object? get activeLeaderId => _leader?.member.id;

  ScrollSemanticAnchor? get canonicalSemanticAnchor => _canonicalSemanticAnchor;

  int? get activeTransactionId =>
      _leader == null ? null : _nextTransactionId - 1;

  int get transactionCount => _transactionCount;

  int get followerApplyCount => _followerApplyCount;

  bool get isFailed => _failureReason != null;

  String? get failureReason => _failureReason;

  Iterable<ScrollSyncMember> get members sync* {
    for (final _ScrollSyncMemberState state in _members) {
      yield state.member;
    }
  }

  Future<GroupScrollResult> jumpToCoordinate(double coordinate) {
    _requireActive();
    _requireScalarMapping();
    _requireFiniteCoordinate(coordinate);
    _finishProgrammatic(GroupScrollOutcome.superseded);
    final List<_ScrollSyncMemberState> participants =
        _members.toList(growable: false);
    _beginProgrammaticTransaction(participants);
    final Stopwatch stopwatch = Stopwatch()..start();
    final bool applied = _applyProgrammaticCoordinate(
      coordinate,
      participants,
    );
    stopwatch.stop();
    return Future<GroupScrollResult>.value(
      _buildProgrammaticResult(
        outcome: applied
            ? GroupScrollOutcome.completed
            : GroupScrollOutcome.noActiveMembers,
        requestedCoordinate: coordinate,
        participants: participants,
        elapsed: stopwatch.elapsed,
      ),
    );
  }

  Future<GroupScrollResult> animateToCoordinate(
    double coordinate, {
    required TickerProvider vsync,
    required Duration duration,
    Curve curve = Curves.easeInOutCubic,
  }) {
    _requireActive();
    _requireScalarMapping();
    _requireFiniteCoordinate(coordinate);
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'must be positive');
    }
    _finishProgrammatic(GroupScrollOutcome.superseded);
    final List<_ScrollSyncMemberState> participants =
        _members.toList(growable: false);
    final double? start = _beginProgrammaticTransaction(participants);
    if (start == null) {
      return Future<GroupScrollResult>.value(
        _buildProgrammaticResult(
          outcome: GroupScrollOutcome.noActiveMembers,
          requestedCoordinate: coordinate,
          participants: participants,
          elapsed: Duration.zero,
        ),
      );
    }
    final Completer<GroupScrollResult> completer =
        Completer<GroupScrollResult>();
    _programmaticCompleter = completer;
    _programmaticParticipants = participants;
    _programmaticRequestedCoordinate = coordinate;
    _programmaticStopwatch = Stopwatch()..start();
    _programmaticTransactionId = _nextTransactionId - 1;
    final Duration naturalSettleBudget =
        _naturalSettleBudget(participants) + const Duration(milliseconds: 50);
    _programmaticTicker = vsync.createTicker((Duration elapsed) {
      if (mode == ScrollSyncMode.strict) {
        final double linear =
            (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0, 1);
        final double transformed = curve.transform(linear);
        final double current = start + (coordinate - start) * transformed;
        _applyProgrammaticCoordinate(current, participants);
        if (linear >= 1) {
          _applyProgrammaticCoordinate(coordinate, participants);
          _finishProgrammatic(GroupScrollOutcome.completed);
        }
        return;
      }
      if (!_programmaticNaturalSettling) {
        final double linear =
            (elapsed.inMicroseconds / duration.inMicroseconds).clamp(0, 1);
        final double transformed = curve.transform(linear);
        final double current = start + (coordinate - start) * transformed;
        _applyProgrammaticCoordinate(
          current,
          participants,
          natural: true,
        );
        if (linear >= 1) {
          _applyProgrammaticCoordinate(
            coordinate,
            participants,
            natural: true,
          );
          _programmaticNaturalSettling = true;
        }
      }
      if (_programmaticNaturalMembersSettled(participants)) {
        _finishProgrammatic(GroupScrollOutcome.completed);
      } else if (elapsed >= duration + naturalSettleBudget) {
        _finishProgrammatic(GroupScrollOutcome.memberFailed);
      }
    });
    unawaited(_programmaticTicker!.start());
    return completer.future;
  }

  void _requireFiniteCoordinate(double coordinate) {
    if (!coordinate.isFinite) {
      throw ArgumentError.value(coordinate, 'coordinate', 'must be finite');
    }
  }

  void _requireScalarMapping() {
    if (mapping.kind == ScrollSyncMappingKind.semantic) {
      throw StateError(
        'Semantic groups are driven by visible stable anchors, not scalar '
        'coordinates.',
      );
    }
  }

  double? _beginProgrammaticTransaction(
    List<_ScrollSyncMemberState> participants,
  ) {
    _leader = null;
    _nextTransactionId++;
    _transactionCount++;
    _ScrollSyncMemberState? first;
    for (final _ScrollSyncMemberState member in participants) {
      member
        .._lastApplyClamped = false
        .._lastApplied = false;
      if (member._readCurrentMetrics()) {
        member._transactionOrigin = member._pixels;
        if (first == null && _canFollow(member)) {
          first = member;
        }
      }
    }
    if (first == null) {
      return null;
    }
    if (mapping.kind == ScrollSyncMappingKind.delta) {
      _canonicalCoordinate = 0;
    } else {
      _canonicalCoordinate ??= mapping.memberValuesToGroup(
        pixels: first._pixels,
        minScrollExtent: 0,
        maxScrollExtent: first._maxScrollExtent,
        viewportExtent: first._viewportExtent,
        origin: first._transactionOrigin,
      );
    }
    return _canonicalCoordinate;
  }

  bool _applyProgrammaticCoordinate(
    double coordinate,
    List<_ScrollSyncMemberState> participants, {
    bool natural = false,
  }) {
    if (kReleaseMode) {
      return _applyProgrammaticCoordinateUntraced(
        coordinate,
        participants,
        natural: natural,
      );
    }
    return SeekoTimeline.sync(
      'Seeko.syncFanOut',
      () => _applyProgrammaticCoordinateUntraced(
        coordinate,
        participants,
        natural: natural,
      ),
      arguments: <String, Object?>{
        'mode': natural ? 'programmatic-natural' : 'programmatic-strict',
        'members': participants.length,
      },
    );
  }

  bool _applyProgrammaticCoordinateUntraced(
    double coordinate,
    List<_ScrollSyncMemberState> participants, {
    required bool natural,
  }) {
    final double bounded = _boundedCoordinate(coordinate);
    _canonicalCoordinate = bounded;
    var appliedAny = false;
    final int transactionId = _nextTransactionId - 1;
    for (final _ScrollSyncMemberState member in participants) {
      if (!_canFollow(member)) {
        continue;
      }
      final bool applied = natural
          ? _applyLiveCanonicalToMember(
              member,
              coordinate: bounded,
              transactionId: transactionId,
            )
          : _applyCanonicalToMember(
              member,
              coordinate: bounded,
              transactionId: transactionId,
            );
      if (applied) {
        appliedAny = true;
        _followerApplyCount++;
      } else if (member._lastApplied) {
        appliedAny = true;
      }
    }
    _scheduleNotification();
    return appliedAny;
  }

  Duration _naturalSettleBudget(
    List<_ScrollSyncMemberState> participants,
  ) {
    var budget = Duration.zero;
    for (final _ScrollSyncMemberState member in participants) {
      final Duration? settleDuration =
          member._naturalPhysicsProfile?.settleDuration;
      if (settleDuration != null && settleDuration > budget) {
        budget = settleDuration;
      }
    }
    return budget;
  }

  bool _programmaticNaturalMembersSettled(
    List<_ScrollSyncMemberState> participants,
  ) {
    final int? transactionId = _programmaticTransactionId;
    if (transactionId == null || !_programmaticNaturalSettling) {
      return false;
    }
    for (final _ScrollSyncMemberState member in participants) {
      if (!_canFollow(member)) {
        continue;
      }
      if (member._naturalTransactionId != transactionId ||
          !member._naturalSettled) {
        return false;
      }
    }
    return true;
  }

  void _finishProgrammatic(GroupScrollOutcome outcome) {
    final Completer<GroupScrollResult>? completer = _programmaticCompleter;
    if (completer == null) {
      return;
    }
    final Ticker? ticker = _programmaticTicker;
    _programmaticTicker = null;
    if (ticker != null) {
      ticker.stop(canceled: outcome != GroupScrollOutcome.completed);
      ticker.dispose();
    }
    final Stopwatch stopwatch = _programmaticStopwatch!..stop();
    final List<_ScrollSyncMemberState> participants =
        _programmaticParticipants!;
    final double requested = _programmaticRequestedCoordinate!;
    _programmaticCompleter = null;
    _programmaticParticipants = null;
    _programmaticStopwatch = null;
    _programmaticRequestedCoordinate = null;
    _programmaticNaturalSettling = false;
    _programmaticTransactionId = null;
    completer.complete(
      _buildProgrammaticResult(
        outcome: outcome,
        requestedCoordinate: requested,
        participants: participants,
        elapsed: stopwatch.elapsed,
      ),
    );
  }

  GroupScrollResult _buildProgrammaticResult({
    required GroupScrollOutcome outcome,
    required double requestedCoordinate,
    required List<_ScrollSyncMemberState> participants,
    required Duration elapsed,
  }) {
    final List<GroupScrollMemberResult> memberResults =
        <GroupScrollMemberResult>[];
    for (final _ScrollSyncMemberState member in participants) {
      final GroupScrollMemberOutcome memberOutcome;
      if (outcome == GroupScrollOutcome.superseded) {
        memberOutcome = GroupScrollMemberOutcome.superseded;
      } else if (outcome == GroupScrollOutcome.interruptedByUser) {
        memberOutcome = GroupScrollMemberOutcome.interruptedByUser;
      } else if (outcome == GroupScrollOutcome.disposed) {
        memberOutcome = GroupScrollMemberOutcome.disposed;
      } else if (outcome == GroupScrollOutcome.memberFailed) {
        memberOutcome = GroupScrollMemberOutcome.failed;
      } else if (member._removed) {
        memberOutcome = GroupScrollMemberOutcome.removed;
      } else if (!member._attached) {
        memberOutcome = GroupScrollMemberOutcome.detached;
      } else if (!_canFollow(member)) {
        memberOutcome = GroupScrollMemberOutcome.unsupported;
      } else if (member._lastApplyClamped) {
        memberOutcome = GroupScrollMemberOutcome.clamped;
      } else {
        memberOutcome = GroupScrollMemberOutcome.completed;
      }
      memberResults.add(
        GroupScrollMemberResult(
          memberId: member.member.id,
          outcome: memberOutcome,
          finalLogicalPixels: member._attached ? member._pixels : null,
        ),
      );
    }
    return GroupScrollResult(
      outcome: outcome,
      requestedCoordinate: requestedCoordinate,
      finalCoordinate: _canonicalCoordinate,
      elapsed: elapsed,
      members: List<GroupScrollMemberResult>.unmodifiable(memberResults),
    );
  }

  ScrollSyncMember add(
    SeekoController controller, {
    Object? id,
    ScrollSyncRole role = ScrollSyncRole.bidirectional,
    int priority = 0,
    NaturalSyncPhysicsProfile? naturalPhysicsProfile,
    ScrollSyncSemanticMapping? semanticMapping,
  }) {
    _requireActive();
    if (controller._disposed) {
      throw StateError('A disposed SeekoController cannot join a sync group.');
    }
    if (!controller.capabilities.supports(ScrollCapability.strictSync)) {
      throw StateError(
        'This controller does not provide strict synchronization capability. '
        'Use a direct SeekoController rather than an adapted controller.',
      );
    }
    if (mode == ScrollSyncMode.natural &&
        !controller.capabilities.supports(
          ScrollCapability.naturalSyncPhysics,
        )) {
      throw StateError(
        'This controller does not provide bounded natural synchronization '
        'physics.',
      );
    }
    if (controller._syncMember != null) {
      throw StateError(
        'A SeekoController can belong to only one active ScrollSyncGroup.',
      );
    }
    if (!mapping.isInvertible && role == ScrollSyncRole.bidirectional) {
      throw StateError(
        'A non-invertible ScrollSyncMapping requires an explicit '
        'leaderOnly or followerOnly member role.',
      );
    }
    if (mode == ScrollSyncMode.natural &&
        role != ScrollSyncRole.observer &&
        naturalPhysicsProfile == null) {
      throw ArgumentError.notNull('naturalPhysicsProfile');
    }
    if (mode == ScrollSyncMode.strict && naturalPhysicsProfile != null) {
      throw ArgumentError.value(
        naturalPhysicsProfile,
        'naturalPhysicsProfile',
        'is only valid for a natural synchronization group',
      );
    }
    if (mapping.kind != ScrollSyncMappingKind.semantic &&
        semanticMapping != null) {
      throw ArgumentError.value(
        semanticMapping,
        'semanticMapping',
        'is only valid for a semantic synchronization group',
      );
    }
    if (naturalPhysicsProfile != null) {
      _validateNaturalProfile(naturalPhysicsProfile);
      if (mode == ScrollSyncMode.natural) {
        for (final _ScrollSyncMemberState existing in _members) {
          final NaturalSyncPhysicsProfile? other =
              existing._naturalPhysicsProfile;
          if (other != null &&
              !_naturalProfilesAreCompatible(other, naturalPhysicsProfile)) {
            throw ArgumentError.value(
              naturalPhysicsProfile,
              'naturalPhysicsProfile',
              'must use compatible initial-velocity, snap, and bounded-settle '
                  'contracts across the group',
            );
          }
        }
      }
    }
    final Object effectiveId = id ?? _nextMemberId++;
    if (_members.any(
      (_ScrollSyncMemberState value) => value.member.id == effectiveId,
    )) {
      throw ArgumentError.value(id, 'id', 'must be unique inside the group');
    }
    final _ScrollSyncMemberState state = _ScrollSyncMemberState(
      group: this,
      controller: controller,
      id: effectiveId,
      role: role,
      priority: priority,
      naturalPhysicsProfile: naturalPhysicsProfile,
      semanticMapping: semanticMapping,
    );
    _members.add(state);
    _coordinator.add(state);
    controller._syncMember = state;
    if (controller.hasClients && controller.position.hasContentDimensions) {
      state._handleAttach();
    }
    _scheduleNotification();
    return state.member;
  }

  void _validateNaturalProfile(NaturalSyncPhysicsProfile profile) {
    if (profile.settleDuration <= Duration.zero) {
      throw ArgumentError.value(
        profile.settleDuration,
        'naturalPhysicsProfile.settleDuration',
        'must be positive',
      );
    }
    if (!profile.convergesToTarget) {
      throw ArgumentError.value(
        profile.convergesToTarget,
        'naturalPhysicsProfile.convergesToTarget',
        'must be true',
      );
    }
    if (!profile.boundedDuration) {
      throw ArgumentError.value(
        profile.boundedDuration,
        'naturalPhysicsProfile.boundedDuration',
        'must be true',
      );
    }
    var previous = 0.0;
    for (var sample = 0; sample <= 16; sample += 1) {
      final double t = sample / 16;
      final double value = profile.curve.transform(t);
      if (!value.isFinite || value < 0 || value > 1) {
        throw ArgumentError.value(
          profile.curve,
          'naturalPhysicsProfile.curve',
          'must remain finite inside [0, 1]',
        );
      }
      if (sample == 0 && value.abs() > precisionErrorTolerance) {
        throw ArgumentError.value(
          profile.curve,
          'naturalPhysicsProfile.curve',
          'must start at 0',
        );
      }
      if (sample > 0 && value + precisionErrorTolerance < previous) {
        throw ArgumentError.value(
          profile.curve,
          'naturalPhysicsProfile.curve',
          'must be monotonic',
        );
      }
      previous = value;
    }
    final double nearStart = profile.curve.transform(1e-6);
    final double nearEnd = profile.curve.transform(1 - 1e-6);
    if (nearStart > 1e-2 || (nearEnd - 1).abs() > 1e-2) {
      throw ArgumentError.value(
        profile.curve,
        'naturalPhysicsProfile.curve',
        'must continuously approach both endpoints '
            '(nearStart=$nearStart, nearEnd=$nearEnd)',
      );
    }
  }

  bool _naturalProfilesAreCompatible(
    NaturalSyncPhysicsProfile first,
    NaturalSyncPhysicsProfile second,
  ) {
    final int settleDifference =
        (first.settleDuration - second.settleDuration).abs().inMicroseconds;
    return first.supportsExternalInitialVelocity ==
            second.supportsExternalInitialVelocity &&
        first.snapBehavior == second.snapBehavior &&
        settleDifference <= const Duration(milliseconds: 100).inMicroseconds;
  }

  bool remove(SeekoController controller) {
    final _ScrollSyncMemberState? state = controller._syncMember;
    if (state == null || !identical(state.group, this)) {
      return false;
    }
    _removeState(state);
    return true;
  }

  void _removeState(_ScrollSyncMemberState state) {
    if (!_members.remove(state)) {
      return;
    }
    _coordinator.remove(state);
    state._disposeListeners();
    if (identical(state.controller._syncMember, state)) {
      state.controller._syncMember = null;
    }
    state._removed = true;
    if (identical(_leader, state)) {
      _leader = null;
    }
    _scheduleNotification();
  }

  void _handleActivity(
    _ScrollSyncMemberState source,
    ScrollPhase phase,
    ScrollEventOrigin origin,
  ) {
    if (!_canLead(source) || origin == ScrollEventOrigin.synchronized) {
      return;
    }
    if (origin == ScrollEventOrigin.none) {
      return;
    }
    if (_programmaticCompleter != null) {
      final bool userInterrupted = origin == ScrollEventOrigin.user ||
          origin == ScrollEventOrigin.accessibility;
      _finishProgrammatic(
        userInterrupted
            ? GroupScrollOutcome.interruptedByUser
            : GroupScrollOutcome.superseded,
      );
    }
    if (phase == ScrollPhase.drag ||
        phase == ScrollPhase.ballistic ||
        phase == ScrollPhase.programmatic ||
        origin == ScrollEventOrigin.programmatic ||
        origin == ScrollEventOrigin.user ||
        origin == ScrollEventOrigin.accessibility) {
      if (!identical(_leader, source) &&
          _shouldAcceptLeadership(source, phase, origin)) {
        _beginTransaction(source, phase: phase, origin: origin);
      }
    }
  }

  void _handlePosition(
    _ScrollSyncMemberState source, {
    required double logicalPixels,
    required double maxScrollExtent,
    required double viewportExtent,
    required ScrollPhase phase,
    required ScrollEventOrigin origin,
    required int? applyingTransactionId,
  }) {
    source
      .._attached = true
      .._pixels = logicalPixels
      .._maxScrollExtent = maxScrollExtent
      .._viewportExtent = viewportExtent;
    if (mode == ScrollSyncMode.natural &&
        origin == ScrollEventOrigin.synchronized &&
        applyingTransactionId != null) {
      source._recordNaturalPosition(
        transactionId: applyingTransactionId,
        timestamp: _currentFrameTime,
      );
      final List<_ScrollSyncMemberState>? participants =
          _programmaticParticipants;
      if (participants != null &&
          _programmaticNaturalMembersSettled(participants)) {
        _finishProgrammatic(GroupScrollOutcome.completed);
      }
    }
    if (_programmaticCompleter != null &&
        applyingTransactionId == null &&
        origin != ScrollEventOrigin.synchronized) {
      final bool userInterrupted = origin == ScrollEventOrigin.user ||
          origin == ScrollEventOrigin.accessibility;
      _finishProgrammatic(
        userInterrupted
            ? GroupScrollOutcome.interruptedByUser
            : GroupScrollOutcome.superseded,
      );
    }
    if (mapping.kind == ScrollSyncMappingKind.semantic) {
      return;
    }
    if (applyingTransactionId != null ||
        origin == ScrollEventOrigin.synchronized ||
        !_canLead(source)) {
      return;
    }
    if (!identical(_leader, source)) {
      if (!_shouldAcceptLeadership(source, phase, origin)) {
        _applyLiveCanonicalToMember(
          source,
          transactionId: _nextTransactionId - 1,
        );
        return;
      }
      _beginTransaction(source, phase: phase, origin: origin);
    }
    final int transactionId = _nextTransactionId - 1;
    final double requestedCoordinate = mapping.memberValuesToGroup(
      pixels: source._pixels,
      minScrollExtent: 0,
      maxScrollExtent: source._maxScrollExtent,
      viewportExtent: source._viewportExtent,
      origin: source._transactionOrigin,
    );
    final double coordinate = _boundedCoordinate(requestedCoordinate);
    final bool reachedSharedBoundary = coordinate != requestedCoordinate;
    _canonicalCoordinate = coordinate;
    if (reachedSharedBoundary) {
      _applyCanonicalToMember(
        source,
        coordinate: coordinate,
        transactionId: transactionId,
      );
    }
    final int applied = kReleaseMode
        ? _coordinator.propagate(
            source: source,
            coordinate: coordinate,
            transactionId: transactionId,
          )
        : SeekoTimeline.sync(
            'Seeko.syncFanOut',
            () => _coordinator.propagate(
              source: source,
              coordinate: coordinate,
              transactionId: transactionId,
            ),
            arguments: <String, Object?>{
              'mode': mode.name,
              'members': activeMemberCount,
              'mapping': mapping.kind.name,
            },
          );
    _followerApplyCount += applied;
    if (reachedSharedBoundary &&
        boundaryPolicy == ScrollSyncBoundaryPolicy.stopAtFirstBoundary) {
      _leader = null;
    }
    _scheduleNotification();
  }

  void _handleSemanticSnapshot(_ScrollSyncMemberState source) {
    if (mapping.kind != ScrollSyncMappingKind.semantic || !_canLead(source)) {
      return;
    }
    final ScrollSnapshot snapshot = source.controller.state.value;
    final ScrollSemanticAnchor? memberAnchor = snapshot.anchor;
    if (memberAnchor == null ||
        snapshot.origin == ScrollEventOrigin.none ||
        snapshot.origin == ScrollEventOrigin.synchronized ||
        snapshot.synchronized) {
      return;
    }
    final ScrollSyncSemanticMappingResult mappingResult =
        source._mapMemberToCanonical(snapshot, memberAnchor);
    final ScrollSemanticAnchor? anchor = mappingResult.anchor;
    if (anchor == null) {
      source
        .._synchronizationStatus =
            ScrollSyncMemberSynchronizationStatus.desynchronized
        .._semanticFailure = mappingResult.diagnostic ??
            'The member semantic anchor could not be mapped to the canonical '
                'domain.';
      _scheduleNotification();
      return;
    }
    if (!identical(_leader, source)) {
      if (!_shouldAcceptLeadership(
        source,
        snapshot.phase,
        snapshot.origin,
      )) {
        _applySemanticToMember(
          source,
          transactionId: _nextTransactionId - 1,
          natural: mode == ScrollSyncMode.natural,
        );
        return;
      }
      _beginTransaction(
        source,
        phase: snapshot.phase,
        origin: snapshot.origin,
      );
    }
    _canonicalSemanticAnchor = anchor;
    _semanticFallbackProgress = snapshot.progress;
    source
      .._synchronizationStatus = mappingResult.isFallback
          ? ScrollSyncMemberSynchronizationStatus.fallback
          : ScrollSyncMemberSynchronizationStatus.synchronized
      .._semanticFailure = null;
    final int transactionId = _nextTransactionId - 1;
    _followerApplyCount += _applySemanticFollowers(
      source,
      transactionId: transactionId,
    );
    _scheduleNotification();
  }

  int _applySemanticFollowers(
    _ScrollSyncMemberState? source, {
    required int transactionId,
  }) {
    if (kReleaseMode) {
      return _applySemanticFollowersUntraced(
        source,
        transactionId: transactionId,
      );
    }
    return SeekoTimeline.sync(
      'Seeko.syncFanOut',
      () => _applySemanticFollowersUntraced(
        source,
        transactionId: transactionId,
      ),
      arguments: <String, Object?>{
        'mode': '${mode.name}-semantic',
        'members': activeMemberCount,
      },
    );
  }

  int _applySemanticFollowersUntraced(
    _ScrollSyncMemberState? source, {
    required int transactionId,
  }) {
    var applied = 0;
    for (final _ScrollSyncMemberState follower in _members) {
      if (identical(follower, source) || !_canFollow(follower)) {
        continue;
      }
      if (_applySemanticToMember(
        follower,
        transactionId: transactionId,
        natural: mode == ScrollSyncMode.natural,
      )) {
        applied += 1;
      }
    }
    return applied;
  }

  bool _applySemanticToMember(
    _ScrollSyncMemberState member, {
    required int transactionId,
    required bool natural,
  }) {
    final ScrollSemanticAnchor? anchor = _canonicalSemanticAnchor;
    if (anchor == null ||
        !_canFollow(member) ||
        !member._readCurrentMetrics()) {
      return false;
    }
    if (!member.controller.capabilities.supports(
      ScrollCapability.semanticSync,
    )) {
      member
        .._synchronizationStatus =
            ScrollSyncMemberSynchronizationStatus.desynchronized
        .._semanticFailure = 'semanticSync capability is unavailable';
      return false;
    }
    final ScrollSyncSemanticMappingResult mappingResult =
        member._mapCanonicalToMember(anchor);
    final ScrollSemanticAnchor? memberAnchor = mappingResult.anchor;
    var usedFallback = mappingResult.isFallback;
    double? target = memberAnchor == null
        ? null
        : member.controller._semanticSyncPixels(memberAnchor);
    if (target == null) {
      final SemanticScrollSyncMapping semantic =
          mapping as SemanticScrollSyncMapping;
      final ScrollSyncMissingAnchorPolicy missingPolicy =
          mappingResult.missingAnchorPolicy ?? semantic.missingAnchorPolicy;
      switch (missingPolicy) {
        case ScrollSyncMissingAnchorPolicy.fallbackProgress
            when _semanticFallbackProgress != null:
          target = _semanticFallbackProgress! * member._maxScrollExtent;
          usedFallback = true;
        case ScrollSyncMissingAnchorPolicy.hold:
          member
            .._synchronizationStatus =
                ScrollSyncMemberSynchronizationStatus.holding
            .._semanticFailure = null;
          return false;
        case ScrollSyncMissingAnchorPolicy.fallbackProgress ||
              ScrollSyncMissingAnchorPolicy.desynchronized:
          member
            .._synchronizationStatus =
                ScrollSyncMemberSynchronizationStatus.desynchronized
            .._semanticFailure = mappingResult.diagnostic ??
                'Missing semantic anchor key=${anchor.key} '
                    'index=${anchor.index}';
          return false;
      }
    }
    final bool applied = natural
        ? _applyNaturalTargetToMember(
            member,
            target: target,
            transactionId: transactionId,
          )
        : member.controller._applySynchronizedLogicalPixels(
            logicalPixels: target,
            transactionId: transactionId,
          );
    if (!natural && applied) {
      member._pixels = target.clamp(0, member._maxScrollExtent);
    }
    member
      .._synchronizationStatus = usedFallback
          ? ScrollSyncMemberSynchronizationStatus.fallback
          : ScrollSyncMemberSynchronizationStatus.synchronized
      .._semanticFailure = null;
    return applied;
  }

  double _boundedCoordinate(double coordinate) {
    _requireScalarMapping();
    if (boundaryPolicy == ScrollSyncBoundaryPolicy.perMemberClamp) {
      return coordinate;
    }
    var lower = double.negativeInfinity;
    var upper = double.infinity;
    var found = false;
    for (final _ScrollSyncMemberState member in _members) {
      if (!_isActiveFollowerOrLeader(member) ||
          member.member.role == ScrollSyncRole.observer ||
          !member._readCurrentMetrics()) {
        continue;
      }
      final double first = mapping.memberValuesToGroup(
        pixels: 0,
        minScrollExtent: 0,
        maxScrollExtent: member._maxScrollExtent,
        viewportExtent: member._viewportExtent,
        origin: member._transactionOrigin,
      );
      final double last = mapping.memberValuesToGroup(
        pixels: member._maxScrollExtent,
        minScrollExtent: 0,
        maxScrollExtent: member._maxScrollExtent,
        viewportExtent: member._viewportExtent,
        origin: member._transactionOrigin,
      );
      final double memberLower = math.min(first, last);
      final double memberUpper = math.max(first, last);
      lower = math.max(lower, memberLower);
      upper = math.min(upper, memberUpper);
      found = true;
    }
    if (!found) {
      return coordinate;
    }
    if (lower > upper) {
      throw StateError(
        'ScrollSyncGroup members have no shared reachable coordinate.',
      );
    }
    return coordinate.clamp(lower, upper).toDouble();
  }

  bool _shouldAcceptLeadership(
    _ScrollSyncMemberState candidate,
    ScrollPhase phase,
    ScrollEventOrigin origin,
  ) {
    final _ScrollSyncMemberState? leader = _leader;
    if (leader == null || !identical(_leaderFrameTime, _currentFrameTime)) {
      return true;
    }
    final int phaseComparison = _phasePriority(phase).compareTo(
      _phasePriority(_leaderPhase),
    );
    if (phaseComparison != 0) {
      return phaseComparison > 0;
    }
    final int originComparison = _originPriority(origin).compareTo(
      _originPriority(_leaderOrigin),
    );
    if (originComparison != 0) {
      return originComparison > 0;
    }
    return candidate.member.priority > leader.member.priority;
  }

  Duration get _currentFrameTime =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp;

  int _phasePriority(ScrollPhase phase) => switch (phase) {
        ScrollPhase.drag => 5,
        ScrollPhase.ballistic => 4,
        ScrollPhase.programmatic => 3,
        ScrollPhase.correcting => 2,
        ScrollPhase.scrolling => 2,
        ScrollPhase.held => 1,
        ScrollPhase.idle => 0,
      };

  int _originPriority(ScrollEventOrigin origin) => switch (origin) {
        ScrollEventOrigin.user => 5,
        ScrollEventOrigin.accessibility => 4,
        ScrollEventOrigin.restoration => 3,
        ScrollEventOrigin.programmatic => 2,
        ScrollEventOrigin.external => 1,
        ScrollEventOrigin.synchronized || ScrollEventOrigin.none => 0,
      };

  void _beginTransaction(
    _ScrollSyncMemberState source, {
    required ScrollPhase phase,
    required ScrollEventOrigin origin,
  }) {
    _leader = source;
    _leaderFrameTime = _currentFrameTime;
    _leaderPhase = phase;
    _leaderOrigin = origin;
    _nextTransactionId++;
    _transactionCount++;
    for (final _ScrollSyncMemberState member in _members) {
      if (member._readCurrentMetrics()) {
        member._transactionOrigin = member._pixels;
      }
    }
    _scheduleNotification();
  }

  bool _applyCanonicalToMember(
    _ScrollSyncMemberState member, {
    double? coordinate,
    required int transactionId,
  }) {
    final double? effectiveCoordinate = coordinate ?? _canonicalCoordinate;
    if (effectiveCoordinate == null || !member._readCurrentMetrics()) {
      return false;
    }
    final double requested = mapping.groupToMemberValues(
      coordinate: effectiveCoordinate,
      pixels: member._pixels,
      minScrollExtent: 0,
      maxScrollExtent: member._maxScrollExtent,
      viewportExtent: member._viewportExtent,
      origin: member._transactionOrigin,
    );
    final double target = requested.clamp(0, member._maxScrollExtent);
    member
      .._lastApplyClamped = target != requested
      .._lastApplied = true;
    if (mode == ScrollSyncMode.strict &&
        (target - member._pixels).abs() <= _scrollSyncPixelTolerance) {
      return false;
    }
    final bool applied = member.controller._applySynchronizedLogicalPixels(
      logicalPixels: target,
      transactionId: transactionId,
    );
    if (applied) {
      member._pixels = target;
    }
    return applied;
  }

  bool _applyLiveCanonicalToMember(
    _ScrollSyncMemberState member, {
    double? coordinate,
    required int transactionId,
  }) {
    if (mode == ScrollSyncMode.strict) {
      return _applyCanonicalToMember(
        member,
        coordinate: coordinate,
        transactionId: transactionId,
      );
    }
    final double? effectiveCoordinate = coordinate ?? _canonicalCoordinate;
    if (effectiveCoordinate == null || !member._readCurrentMetrics()) {
      return false;
    }
    final double requested = mapping.groupToMemberValues(
      coordinate: effectiveCoordinate,
      pixels: member._pixels,
      minScrollExtent: 0,
      maxScrollExtent: member._maxScrollExtent,
      viewportExtent: member._viewportExtent,
      origin: member._transactionOrigin,
    );
    final double target = requested.clamp(0, member._maxScrollExtent);
    member
      .._lastApplyClamped = target != requested
      .._lastApplied = true;
    if ((target - member._pixels).abs() <= _scrollSyncPixelTolerance) {
      return false;
    }
    return _applyNaturalTargetToMember(
      member,
      target: target,
      transactionId: transactionId,
    );
  }

  bool _applyNaturalTargetToMember(
    _ScrollSyncMemberState member, {
    required double target,
    required int transactionId,
  }) {
    final double boundedTarget = target.clamp(0, member._maxScrollExtent);
    member
      .._lastApplyClamped = boundedTarget != target
      .._beginNaturalTarget(
        transactionId: transactionId,
        target: boundedTarget,
        timestamp: _currentFrameTime,
      );
    if ((boundedTarget - member._pixels).abs() <= _scrollSyncPixelTolerance) {
      return false;
    }
    final NaturalSyncPhysicsProfile profile = member._naturalPhysicsProfile!;
    return member.controller._applyNaturalSynchronizedLogicalPixels(
      logicalPixels: boundedTarget,
      transactionId: transactionId,
      duration: profile.settleDuration,
      curve: profile.curve,
      snapBehavior: profile.snapBehavior,
    );
  }

  void _catchUp(_ScrollSyncMemberState follower) {
    if (mapping.kind == ScrollSyncMappingKind.semantic) {
      if (_applySemanticToMember(
        follower,
        transactionId: _nextTransactionId - 1,
        natural: mode == ScrollSyncMode.natural,
      )) {
        _followerApplyCount++;
        _scheduleNotification();
      }
      return;
    }
    if (!_canFollow(follower) || _canonicalCoordinate == null) {
      return;
    }
    if (_applyLiveCanonicalToMember(
      follower,
      transactionId: _nextTransactionId - 1,
    )) {
      _followerApplyCount++;
      _scheduleNotification();
    }
  }

  void _handleMetricsChanged(_ScrollSyncMemberState member) {
    if (_disposed || member._removed) {
      return;
    }
    final bool wasAttached = member._attached;
    final double previousMaxScrollExtent = member._maxScrollExtent;
    final double previousViewportExtent = member._viewportExtent;
    if (!member._readCurrentMetrics()) {
      return;
    }
    if (mapping.kind == ScrollSyncMappingKind.semantic) {
      return;
    }
    final bool metricsChanged = !wasAttached ||
        (previousMaxScrollExtent - member._maxScrollExtent).abs() >
            _scrollSyncPixelTolerance ||
        (previousViewportExtent - member._viewportExtent).abs() >
            _scrollSyncPixelTolerance;
    if (!metricsChanged || _leader == null || _metricsCorrectionScheduled) {
      return;
    }
    final bool followerMetrics = !identical(member, _leader);
    // A follower may emit several layout samples while lazy extents converge.
    // Stop only after the correction target reverses at a stable canonical
    // coordinate; monotonic extent convergence must remain correctable.
    if (followerMetrics && member._metricsCorrectionOscillating) {
      return;
    }
    _metricsCorrectionScheduled = true;
    SchedulerBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _metricsCorrectionScheduled = false;
      if (_disposed) {
        return;
      }
      final _ScrollSyncMemberState? source = _leader;
      if (source != null && source._readCurrentMetrics()) {
        _canonicalCoordinate = mapping.memberValuesToGroup(
          pixels: source._pixels,
          minScrollExtent: 0,
          maxScrollExtent: source._maxScrollExtent,
          viewportExtent: source._viewportExtent,
          origin: source._transactionOrigin,
        );
      }
      if (_canonicalCoordinate == null) {
        return;
      }
      final int correctionTransactionId = _nextTransactionId - 1;
      for (final _ScrollSyncMemberState follower in _members) {
        if (identical(follower, _leader) || !_canFollow(follower)) {
          continue;
        }
        if (_shouldSuppressMetricsCorrection(
          follower,
          transactionId: correctionTransactionId,
          coordinate: _canonicalCoordinate!,
        )) {
          continue;
        }
        if (_applyLiveCanonicalToMember(
          follower,
          transactionId: correctionTransactionId,
        )) {
          _followerApplyCount++;
        }
      }
      _scheduleNotification();
    });
  }

  bool _shouldSuppressMetricsCorrection(
    _ScrollSyncMemberState member, {
    required int transactionId,
    required double coordinate,
  }) {
    final double requested = mapping.groupToMemberValues(
      coordinate: coordinate,
      pixels: member._pixels,
      minScrollExtent: 0,
      maxScrollExtent: member._maxScrollExtent,
      viewportExtent: member._viewportExtent,
      origin: member._transactionOrigin,
    );
    final double target = requested.clamp(0, member._maxScrollExtent);
    final bool newTransaction =
        member._metricsCorrectionTransactionId != transactionId;
    final double? trackedCoordinate = member._metricsCorrectionCoordinate;
    final double? trackedTarget = trackedCoordinate == null
        ? null
        : mapping
            .groupToMemberValues(
              coordinate: trackedCoordinate,
              pixels: member._pixels,
              minScrollExtent: 0,
              maxScrollExtent: member._maxScrollExtent,
              viewportExtent: member._viewportExtent,
              origin: member._transactionOrigin,
            )
            .clamp(0, member._maxScrollExtent);
    final bool newCoordinate = trackedTarget == null ||
        (trackedTarget - target).abs() > _scrollSyncPixelTolerance;
    if (newTransaction || newCoordinate) {
      member
        .._metricsCorrectionTransactionId = transactionId
        .._metricsCorrectionCoordinate = coordinate
        .._metricsCorrectionCount = 0
        .._metricsCorrectionPreviousTarget = null
        .._metricsCorrectionLastTarget = null
        .._metricsCorrectionOscillating = false;
    }
    if (member._metricsCorrectionOscillating ||
        member._metricsCorrectionCount >= 8) {
      member._metricsCorrectionOscillating = true;
      return true;
    }
    final double? previousTarget = member._metricsCorrectionPreviousTarget;
    final double? lastTarget = member._metricsCorrectionLastTarget;
    if (previousTarget != null &&
        lastTarget != null &&
        (target - previousTarget).abs() <= _scrollSyncPixelTolerance &&
        (target - lastTarget).abs() > _scrollSyncPixelTolerance) {
      member._metricsCorrectionOscillating = true;
      return true;
    }
    member
      .._metricsCorrectionPreviousTarget = lastTarget
      .._metricsCorrectionLastTarget = target
      .._metricsCorrectionCount += 1;
    return false;
  }

  void _handleSemanticMappingChanged() {
    if (_disposed ||
        mapping.kind != ScrollSyncMappingKind.semantic ||
        _semanticCorrectionScheduled) {
      return;
    }
    _semanticCorrectionScheduled = true;
    SchedulerBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _semanticCorrectionScheduled = false;
      if (_disposed) {
        return;
      }
      final _ScrollSyncMemberState? source = _leader;
      if (source != null && _canLead(source)) {
        final ScrollSnapshot snapshot = source.controller.state.value;
        final ScrollSemanticAnchor? memberAnchor = snapshot.anchor;
        if (memberAnchor != null) {
          final ScrollSyncSemanticMappingResult result =
              source._mapMemberToCanonical(snapshot, memberAnchor);
          if (result.anchor != null) {
            _canonicalSemanticAnchor = result.anchor;
            _semanticFallbackProgress = snapshot.progress;
            source
              .._synchronizationStatus = result.isFallback
                  ? ScrollSyncMemberSynchronizationStatus.fallback
                  : ScrollSyncMemberSynchronizationStatus.synchronized
              .._semanticFailure = null;
          } else {
            source
              .._synchronizationStatus =
                  ScrollSyncMemberSynchronizationStatus.desynchronized
              .._semanticFailure = result.diagnostic;
          }
        }
      }
      if (_canonicalSemanticAnchor == null) {
        _scheduleNotification();
        return;
      }
      final int transactionId = _nextTransactionId - 1;
      _followerApplyCount += _applySemanticFollowers(
        source,
        transactionId: transactionId,
      );
      _scheduleNotification();
    });
  }

  bool _canLead(_ScrollSyncMemberState member) {
    if (isFailed || !_isActive(member) || !member._attached) {
      return false;
    }
    return member.member.role == ScrollSyncRole.bidirectional ||
        member.member.role == ScrollSyncRole.leaderOnly;
  }

  bool _canFollow(_ScrollSyncMemberState member) {
    if (isFailed || !_isActive(member) || !member._attached) {
      return false;
    }
    return member.member.role == ScrollSyncRole.bidirectional ||
        member.member.role == ScrollSyncRole.followerOnly;
  }

  bool _isActive(_ScrollSyncMemberState member) =>
      !member._removed &&
      member.member.participation == ScrollSyncParticipation.active;

  bool _isActiveFollowerOrLeader(_ScrollSyncMemberState member) =>
      _isActive(member) && member._attached;

  void _scheduleNotification() {
    if (!hasListeners || _notificationScheduled || _disposed) {
      return;
    }
    _notificationScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  void _requireActive() {
    if (_disposed) {
      throw StateError('The ScrollSyncGroup has been disposed.');
    }
    if (isFailed) {
      throw StateError('The ScrollSyncGroup failed: $_failureReason');
    }
  }

  void _handleMemberDetach(_ScrollSyncMemberState member) {
    if (identical(_leader, member)) {
      _leader = null;
    }
    if (!_disposed &&
        !member._removed &&
        memberFailurePolicy == ScrollSyncMemberFailurePolicy.failGroup) {
      _fail('Sync member ${member.member.id} detached.');
    }
    _scheduleNotification();
  }

  void _fail(String reason) {
    if (_disposed || isFailed) {
      return;
    }
    _failureReason = reason;
    _leader = null;
    _finishProgrammatic(GroupScrollOutcome.memberFailed);
    _scheduleNotification();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _finishProgrammatic(GroupScrollOutcome.disposed);
    _disposed = true;
    for (final _ScrollSyncMemberState member
        in _members.toList(growable: false)) {
      if (identical(member.controller._syncMember, member)) {
        member.controller._syncMember = null;
      }
      member._disposeListeners();
      member._removed = true;
    }
    _members.clear();
    _coordinator.clear();
    _leader = null;
    _canonicalCoordinate = null;
    _canonicalSemanticAnchor = null;
    _semanticFallbackProgress = null;
    super.dispose();
  }
}

/// A caller-owned membership handle. Removing it never disposes the controller.
final class ScrollSyncMember {
  ScrollSyncMember._(this._state);

  final _ScrollSyncMemberState _state;

  Object get id => _state._id;
  SeekoController get controller => _state.controller;
  ScrollSyncRole get role => _state._role;
  int get priority => _state._priority;
  NaturalSyncPhysicsProfile? get naturalPhysicsProfile =>
      _state._naturalPhysicsProfile;
  ScrollSyncSemanticMapping? get semanticMapping => _state._semanticMapping;
  NaturalSyncMemberDiagnostics? get naturalDiagnostics =>
      _state._naturalDiagnostics;
  bool get isAttached => _state._attached;
  ScrollSyncMemberSynchronizationStatus get synchronizationStatus =>
      _state._synchronizationStatus;
  bool get isSynchronized =>
      synchronizationStatus ==
          ScrollSyncMemberSynchronizationStatus.synchronized ||
      synchronizationStatus == ScrollSyncMemberSynchronizationStatus.fallback;
  String? get synchronizationFailure => _state._semanticFailure;

  ScrollSyncParticipation get participation => _state._participation;

  set participation(ScrollSyncParticipation value) {
    if (_state._removed || _state.group._disposed) {
      throw StateError('The ScrollSyncMember is no longer active.');
    }
    if (_state._participation == value) {
      return;
    }
    _state._participation = value;
    if (value != ScrollSyncParticipation.active &&
        identical(_state.group._leader, _state)) {
      _state.group._leader = null;
    } else if (value == ScrollSyncParticipation.active) {
      _state.group._catchUp(_state);
    }
    _state.group._scheduleNotification();
  }

  void remove() => _state.group._removeState(_state);
}

final class _ScrollSyncMemberState implements ScrollSyncCoordinatorParticipant {
  _ScrollSyncMemberState({
    required this.group,
    required this.controller,
    required Object id,
    required ScrollSyncRole role,
    required int priority,
    required NaturalSyncPhysicsProfile? naturalPhysicsProfile,
    required ScrollSyncSemanticMapping? semanticMapping,
  })  : _id = id,
        _role = role,
        _priority = priority,
        _naturalPhysicsProfile = naturalPhysicsProfile,
        _semanticMapping = semanticMapping {
    member = ScrollSyncMember._(this);
    if (group.mapping.kind == ScrollSyncMappingKind.semantic) {
      controller.state.addListener(_handleSemanticSnapshot);
      _listensToSemanticSnapshot = true;
    }
    _semanticMapping?.changes?.addListener(_handleSemanticMappingChanged);
  }

  final ScrollSyncGroup group;
  final SeekoController controller;
  final Object _id;
  final ScrollSyncRole _role;
  final int _priority;
  final NaturalSyncPhysicsProfile? _naturalPhysicsProfile;
  final ScrollSyncSemanticMapping? _semanticMapping;
  late final ScrollSyncMember member;
  ScrollSyncParticipation _participation = ScrollSyncParticipation.active;
  var _attached = false;
  var _removed = false;
  var _pixels = 0.0;
  var _maxScrollExtent = 0.0;
  var _viewportExtent = 1.0;
  var _transactionOrigin = 0.0;
  var _lastApplyClamped = false;
  var _lastApplied = false;
  int? _metricsCorrectionTransactionId;
  double? _metricsCorrectionCoordinate;
  double? _metricsCorrectionPreviousTarget;
  double? _metricsCorrectionLastTarget;
  var _metricsCorrectionCount = 0;
  var _metricsCorrectionOscillating = false;
  var _synchronizationStatus =
      ScrollSyncMemberSynchronizationStatus.synchronized;
  String? _semanticFailure;
  var _listensToSemanticSnapshot = false;
  int? _naturalTransactionId;
  double? _naturalTargetLogicalPixels;
  double? _naturalStartPixels;
  var _naturalCurrentMappingError = 0.0;
  var _naturalPeakMappingError = 0.0;
  Duration? _naturalTransactionStartedAt;
  Duration? _naturalLatestTargetAt;
  Duration? _naturalPhaseLag;
  Duration? _naturalSettleLag;
  var _naturalSettled = false;

  @override
  bool get participatesInFollowerPropagation => group._canFollow(this);

  @override
  bool applyCanonicalCoordinate({
    required double coordinate,
    required int transactionId,
  }) =>
      group._applyLiveCanonicalToMember(
        this,
        coordinate: coordinate,
        transactionId: transactionId,
      );

  NaturalSyncMemberDiagnostics? get _naturalDiagnostics {
    final int? transactionId = _naturalTransactionId;
    final double? target = _naturalTargetLogicalPixels;
    if (transactionId == null || target == null) {
      return null;
    }
    return NaturalSyncMemberDiagnostics(
      transactionId: transactionId,
      targetLogicalPixels: target,
      currentMappingError: _naturalCurrentMappingError,
      peakMappingError: _naturalPeakMappingError,
      phaseLag: _naturalPhaseLag,
      settleLag: _naturalSettleLag,
      isSettled: _naturalSettled,
    );
  }

  void _beginNaturalTarget({
    required int transactionId,
    required double target,
    required Duration timestamp,
  }) {
    final double error = (target - _pixels).abs();
    if (_naturalTransactionId != transactionId) {
      _naturalTransactionId = transactionId;
      _naturalTransactionStartedAt = timestamp;
      _naturalStartPixels = _pixels;
      _naturalPhaseLag = null;
      _naturalPeakMappingError = error;
    } else if (error > _naturalPeakMappingError) {
      _naturalPeakMappingError = error;
    }
    _naturalTargetLogicalPixels = target;
    _naturalLatestTargetAt = timestamp;
    _naturalCurrentMappingError = error;
    _naturalSettled = error <= _scrollSyncPixelTolerance;
    _naturalSettleLag = _naturalSettled ? Duration.zero : null;
  }

  void _recordNaturalPosition({
    required int transactionId,
    required Duration timestamp,
  }) {
    if (_naturalTransactionId != transactionId) {
      return;
    }
    final double? target = _naturalTargetLogicalPixels;
    if (target == null) {
      return;
    }
    final double? startPixels = _naturalStartPixels;
    final Duration? startedAt = _naturalTransactionStartedAt;
    if (_naturalPhaseLag == null &&
        startPixels != null &&
        startedAt != null &&
        (_pixels - startPixels).abs() > precisionErrorTolerance) {
      _naturalPhaseLag = timestamp - startedAt;
    }
    final double error = (target - _pixels).abs();
    _naturalCurrentMappingError = error;
    if (error > _naturalPeakMappingError) {
      _naturalPeakMappingError = error;
    }
    if (error <= _scrollSyncPixelTolerance) {
      if (!_naturalSettled) {
        final Duration? latestTargetAt = _naturalLatestTargetAt;
        _naturalSettleLag =
            latestTargetAt == null ? null : timestamp - latestTargetAt;
      }
      _naturalSettled = true;
    } else {
      _naturalSettled = false;
      _naturalSettleLag = null;
    }
  }

  bool _readCurrentMetrics() {
    if (_removed || !controller.hasClients) {
      _attached = false;
      return false;
    }
    final ScrollPosition position = controller.position;
    if (!position.hasContentDimensions || position.viewportDimension <= 0) {
      return false;
    }
    _attached = true;
    _pixels = controller._logicalPixelsFor(position);
    _maxScrollExtent = controller._logicalExtentFor(position);
    _viewportExtent = controller._viewportExtentFor(position);
    return true;
  }

  void _handleAttach() {
    _attached = true;
    group._scheduleNotification();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_removed && _readCurrentMetrics()) {
        group._catchUp(this);
      }
    });
  }

  void _handleDetach() {
    _attached = false;
    group._handleMemberDetach(this);
  }

  void _handleActivity(ScrollPhase phase, ScrollEventOrigin origin) {
    group._handleActivity(this, phase, origin);
  }

  void _handleMetricsChanged() => group._handleMetricsChanged(this);

  void _handleSemanticSnapshot() => group._handleSemanticSnapshot(this);

  void _handleSemanticMappingChanged() => group._handleSemanticMappingChanged();

  ScrollSyncSemanticMappingResult _mapMemberToCanonical(
    ScrollSnapshot snapshot,
    ScrollSemanticAnchor anchor,
  ) {
    final ScrollSyncSemanticMapping? mapping = _semanticMapping;
    if (mapping == null) {
      return ScrollSyncSemanticMappingResult.mapped(anchor);
    }
    try {
      return mapping.memberToCanonical(controller, snapshot, anchor);
    } on Object catch (error, stackTrace) {
      return ScrollSyncSemanticMappingResult.missing(
        diagnostic: 'memberToCanonical failed: $error\n$stackTrace',
      );
    }
  }

  ScrollSyncSemanticMappingResult _mapCanonicalToMember(
    ScrollSemanticAnchor anchor,
  ) {
    final ScrollSyncSemanticMapping? mapping = _semanticMapping;
    if (mapping == null) {
      return ScrollSyncSemanticMappingResult.mapped(anchor);
    }
    try {
      return mapping.canonicalToMember(controller, anchor);
    } on Object catch (error, stackTrace) {
      return ScrollSyncSemanticMappingResult.missing(
        diagnostic: 'canonicalToMember failed: $error\n$stackTrace',
      );
    }
  }

  void _disposeListeners() {
    _semanticMapping?.changes?.removeListener(_handleSemanticMappingChanged);
    if (!_listensToSemanticSnapshot) {
      return;
    }
    _listensToSemanticSnapshot = false;
    controller.state.removeListener(_handleSemanticSnapshot);
  }

  void _handlePosition({
    required double logicalPixels,
    required double maxScrollExtent,
    required double viewportExtent,
    required ScrollPhase phase,
    required ScrollEventOrigin origin,
    required int? applyingTransactionId,
  }) {
    group._handlePosition(
      this,
      logicalPixels: logicalPixels,
      maxScrollExtent: maxScrollExtent,
      viewportExtent: viewportExtent,
      phase: phase,
      origin: origin,
      applyingTransactionId: applyingTransactionId,
    );
  }

  void _handleControllerDispose() => group._removeState(this);
}
