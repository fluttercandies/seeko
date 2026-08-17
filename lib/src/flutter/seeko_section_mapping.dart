part of 'seeko_controller.dart';

typedef SeekoVisibleSectionResolver<K extends Object> = K? Function(
  ScrollVisibleTarget target,
);

typedef SeekoSectionTargetBuilder<K extends Object> = ScrollTarget Function(
  K section,
);

enum SeekoMissingSectionPolicy {
  hold,
  previousThenNext,
  nextThenPrevious,
  nearest,
  fallbackProgress,
  desynchronized,
}

/// Canonical position inside a stable business section.
@immutable
final class SeekoSectionCoordinate<K extends Object> {
  factory SeekoSectionCoordinate({
    required K section,
    required double progress,
    required int domainRevision,
    required int domainIndex,
  }) {
    if (!progress.isFinite || progress < 0 || progress > 1) {
      throw RangeError.value(
        progress,
        'progress',
        'must be finite and between 0 and 1',
      );
    }
    if (domainRevision < 0) {
      throw RangeError.value(
        domainRevision,
        'domainRevision',
        'must be non-negative',
      );
    }
    if (domainIndex < 0) {
      throw RangeError.value(
        domainIndex,
        'domainIndex',
        'must be non-negative',
      );
    }
    return SeekoSectionCoordinate<K>._(
      section: section,
      progress: progress,
      domainRevision: domainRevision,
      domainIndex: domainIndex,
    );
  }

  const SeekoSectionCoordinate._({
    required this.section,
    required this.progress,
    required this.domainRevision,
    required this.domainIndex,
  });

  final K section;
  final double progress;
  final int domainRevision;
  final int domainIndex;

  @override
  bool operator ==(Object other) =>
      other is SeekoSectionCoordinate<K> &&
      other.section == section &&
      other.progress == progress &&
      other.domainRevision == domainRevision &&
      other.domainIndex == domainIndex;

  @override
  int get hashCode =>
      Object.hash(section, progress, domainRevision, domainIndex);

  @override
  String toString() => 'SeekoSectionCoordinate($section, progress: $progress, '
      'revision: $domainRevision, index: $domainIndex)';
}

/// Cached canonical order shared by heterogeneous section members.
///
/// Use [fixed] for immutable section sets or [listenable] when insertion,
/// deletion, and reorder operations replace a [ValueListenable] list.
final class SeekoSectionDomain<K extends Object> extends ChangeNotifier {
  factory SeekoSectionDomain.fixed(Iterable<K> sections) {
    return SeekoSectionDomain<K>._(
      source: null,
      initialSections: sections,
    );
  }

  factory SeekoSectionDomain.listenable(
    ValueListenable<List<K>> sections,
  ) {
    return SeekoSectionDomain<K>._(
      source: sections,
      initialSections: sections.value,
    );
  }

  SeekoSectionDomain._({
    required ValueListenable<List<K>>? source,
    required Iterable<K> initialSections,
  }) : _source = source {
    _replace(initialSections);
    _source?.addListener(_handleSourceChanged);
  }

  final ValueListenable<List<K>>? _source;
  List<K> _sections = const <Never>[];
  Map<K, int> _indexes = const <Never, int>{};
  var _revision = 0;
  var _disposed = false;

  List<K> get sections => _sections;
  int get revision => _revision;
  int? indexOf(K section) => _indexes[section];
  bool contains(K section) => _indexes.containsKey(section);

  void _handleSourceChanged() {
    if (_disposed) {
      return;
    }
    _replace(_source!.value);
    _revision += 1;
    notifyListeners();
  }

  void _replace(Iterable<K> sections) {
    final List<K> snapshot = List<K>.unmodifiable(sections);
    final Map<K, int> indexes = <K, int>{};
    for (var index = 0; index < snapshot.length; index += 1) {
      final K section = snapshot[index];
      if (indexes.containsKey(section)) {
        throw ArgumentError.value(
          section,
          'sections',
          'must contain unique stable section identifiers',
        );
      }
      indexes[section] = index;
    }
    _sections = snapshot;
    _indexes = Map<K, int>.unmodifiable(indexes);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _source?.removeListener(_handleSourceChanged);
    super.dispose();
  }
}

/// Maps member-local targets into a shared section id and normalized progress.
final class SeekoSectionSemanticMapping<K extends Object>
    implements ScrollSyncSemanticMapping {
  const SeekoSectionSemanticMapping({
    required this.domain,
    required this.sectionOfTarget,
    required this.sectionTarget,
    this.missingSectionPolicy = SeekoMissingSectionPolicy.hold,
  });

  final SeekoSectionDomain<K> domain;
  final SeekoVisibleSectionResolver<K> sectionOfTarget;
  final SeekoSectionTargetBuilder<K> sectionTarget;
  final SeekoMissingSectionPolicy missingSectionPolicy;

  @override
  Listenable get changes => domain;

  @override
  ScrollSyncSemanticMappingResult memberToCanonical(
    SeekoController controller,
    ScrollSnapshot snapshot,
    ScrollSemanticAnchor anchor,
  ) {
    final ScrollVisibleTarget? visible = _visibleTargetForSnapshot(
      snapshot,
      anchor,
    );
    final K? section = visible == null ? null : sectionOfTarget(visible);
    final int? sectionIndex = section == null ? null : domain.indexOf(section);
    if (section == null || sectionIndex == null) {
      return const ScrollSyncSemanticMappingResult.missing(
        diagnostic: 'The visible target is not part of the section domain.',
      );
    }
    final ScrollVisibleTarget resolvedVisible = visible!;
    final double? start = _sectionStart(controller, section);
    if (start == null) {
      return ScrollSyncSemanticMappingResult.missing(
        diagnostic: 'Section $section is not resolvable in the source member.',
      );
    }
    final double end = _nextResolvableSectionStart(
          controller,
          sectionIndex + 1,
        ) ??
        _logicalContentEnd(controller);
    final double viewportAnchor = snapshot.atTrailingEdge
        ? 1
        : snapshot.atLeadingEdge
            ? 0
            : anchor.viewportAnchor;
    final double visibleExtent =
        resolvedVisible.trailingPixels - resolvedVisible.leadingPixels;
    final double contentPoint = snapshot.atTrailingEdge
        ? snapshot.pixels + snapshot.viewportExtent
        : snapshot.atLeadingEdge
            ? snapshot.pixels
            : snapshot.pixels +
                resolvedVisible.leadingPixels +
                visibleExtent * anchor.itemAnchor;
    final double progress = end <= start
        ? 0
        : ((contentPoint - start) / (end - start)).clamp(0, 1).toDouble();
    return ScrollSyncSemanticMappingResult.mapped(
      ScrollSemanticAnchor(
        key: SeekoSectionCoordinate<K>(
          section: section,
          progress: progress,
          domainRevision: domain.revision,
          domainIndex: sectionIndex,
        ),
        index: null,
        itemAnchor: 0,
        viewportAnchor: viewportAnchor,
        logicalOffset: 0,
      ),
    );
  }

  @override
  ScrollSyncSemanticMappingResult canonicalToMember(
    SeekoController controller,
    ScrollSemanticAnchor anchor,
  ) {
    final Object? key = anchor.key;
    if (key is! SeekoSectionCoordinate<K>) {
      return const ScrollSyncSemanticMappingResult.missing(
        diagnostic: 'The canonical anchor is not a section coordinate.',
      );
    }
    final int? sectionIndex = domain.indexOf(key.section);
    if (sectionIndex == null) {
      final _SectionFallbackTarget? fallback =
          _deletedSectionFallbackTarget(controller, key.domainIndex);
      if (fallback == null) {
        return ScrollSyncSemanticMappingResult.missing(
          diagnostic: 'Section ${key.section} is absent from the domain.',
          missingAnchorPolicy: _missingAnchorPolicy,
        );
      }
      return ScrollSyncSemanticMappingResult.fallback(
        _anchorForTarget(
          fallback.target,
          viewportAnchor: anchor.viewportAnchor,
          logicalOffset: 0,
        ),
        diagnostic: 'Deleted section ${key.section} fell back from canonical '
            'index ${key.domainIndex}.',
      );
    }
    ScrollTarget target = sectionTarget(key.section);
    double? start = _targetStart(controller, target);
    var usedFallback = false;
    var targetSectionIndex = sectionIndex;
    if (start == null) {
      final _SectionFallbackTarget? fallback =
          _fallbackTarget(controller, sectionIndex);
      if (fallback == null) {
        return ScrollSyncSemanticMappingResult.missing(
          diagnostic: 'Section ${key.section} is missing from this member.',
          missingAnchorPolicy: _missingAnchorPolicy,
        );
      }
      target = fallback.target;
      start = fallback.start;
      targetSectionIndex = fallback.index;
      usedFallback = true;
    }
    final double end = _nextResolvableSectionStart(
          controller,
          targetSectionIndex + 1,
        ) ??
        _logicalContentEnd(controller);
    final ScrollSemanticAnchor memberAnchor = _anchorForTarget(
      target,
      viewportAnchor: anchor.viewportAnchor,
      logicalOffset: usedFallback ? 0 : key.progress * math.max(0, end - start),
    );
    return usedFallback
        ? ScrollSyncSemanticMappingResult.fallback(
            memberAnchor,
            diagnostic: 'Section ${key.section} fell back by canonical order.',
          )
        : ScrollSyncSemanticMappingResult.mapped(
            memberAnchor,
          );
  }

  ScrollSyncMissingAnchorPolicy get _missingAnchorPolicy =>
      switch (missingSectionPolicy) {
        SeekoMissingSectionPolicy.fallbackProgress =>
          ScrollSyncMissingAnchorPolicy.fallbackProgress,
        SeekoMissingSectionPolicy.desynchronized =>
          ScrollSyncMissingAnchorPolicy.desynchronized,
        SeekoMissingSectionPolicy.hold ||
        SeekoMissingSectionPolicy.previousThenNext ||
        SeekoMissingSectionPolicy.nextThenPrevious ||
        SeekoMissingSectionPolicy.nearest =>
          ScrollSyncMissingAnchorPolicy.hold,
      };

  _SectionFallbackTarget? _fallbackTarget(
    SeekoController controller,
    int missingIndex,
  ) {
    final Iterable<int> candidates = switch (missingSectionPolicy) {
      SeekoMissingSectionPolicy.previousThenNext =>
        _previousThenNextIndexes(missingIndex),
      SeekoMissingSectionPolicy.nextThenPrevious =>
        _nextThenPreviousIndexes(missingIndex),
      SeekoMissingSectionPolicy.nearest => _nearestIndexes(missingIndex),
      SeekoMissingSectionPolicy.hold ||
      SeekoMissingSectionPolicy.fallbackProgress ||
      SeekoMissingSectionPolicy.desynchronized =>
        const <int>[],
    };
    for (final int index in candidates) {
      final K section = domain.sections[index];
      final ScrollTarget target = sectionTarget(section);
      final double? start = _targetStart(controller, target);
      if (start != null) {
        return _SectionFallbackTarget(
          index: index,
          target: target,
          start: start,
        );
      }
    }
    return null;
  }

  _SectionFallbackTarget? _deletedSectionFallbackTarget(
    SeekoController controller,
    int priorIndex,
  ) {
    final int length = domain.sections.length;
    if (length == 0) {
      return null;
    }
    final int insertionIndex = priorIndex.clamp(0, length);
    final Iterable<int> candidates = switch (missingSectionPolicy) {
      SeekoMissingSectionPolicy.previousThenNext =>
        _deletedPreviousThenNextIndexes(insertionIndex),
      SeekoMissingSectionPolicy.nextThenPrevious =>
        _deletedNextThenPreviousIndexes(insertionIndex),
      SeekoMissingSectionPolicy.nearest =>
        _deletedNearestIndexes(insertionIndex),
      SeekoMissingSectionPolicy.hold ||
      SeekoMissingSectionPolicy.fallbackProgress ||
      SeekoMissingSectionPolicy.desynchronized =>
        const <int>[],
    };
    for (final int index in candidates) {
      final ScrollTarget target = sectionTarget(domain.sections[index]);
      final double? start = _targetStart(controller, target);
      if (start != null) {
        return _SectionFallbackTarget(
          index: index,
          target: target,
          start: start,
        );
      }
    }
    return null;
  }

  Iterable<int> _deletedPreviousThenNextIndexes(int insertionIndex) sync* {
    for (var candidate = insertionIndex - 1; candidate >= 0; candidate -= 1) {
      yield candidate;
    }
    for (var candidate = insertionIndex;
        candidate < domain.sections.length;
        candidate += 1) {
      yield candidate;
    }
  }

  Iterable<int> _deletedNextThenPreviousIndexes(int insertionIndex) sync* {
    for (var candidate = insertionIndex;
        candidate < domain.sections.length;
        candidate += 1) {
      yield candidate;
    }
    for (var candidate = insertionIndex - 1; candidate >= 0; candidate -= 1) {
      yield candidate;
    }
  }

  Iterable<int> _deletedNearestIndexes(int insertionIndex) sync* {
    for (var distance = 1; distance <= domain.sections.length; distance += 1) {
      final int previous = insertionIndex - distance;
      if (previous >= 0) {
        yield previous;
      }
      final int next = insertionIndex + distance - 1;
      if (next < domain.sections.length) {
        yield next;
      }
    }
  }

  Iterable<int> _previousThenNextIndexes(int index) sync* {
    for (var candidate = index - 1; candidate >= 0; candidate -= 1) {
      yield candidate;
    }
    for (var candidate = index + 1;
        candidate < domain.sections.length;
        candidate += 1) {
      yield candidate;
    }
  }

  Iterable<int> _nextThenPreviousIndexes(int index) sync* {
    for (var candidate = index + 1;
        candidate < domain.sections.length;
        candidate += 1) {
      yield candidate;
    }
    for (var candidate = index - 1; candidate >= 0; candidate -= 1) {
      yield candidate;
    }
  }

  Iterable<int> _nearestIndexes(int index) sync* {
    for (var distance = 1; distance < domain.sections.length; distance += 1) {
      final int previous = index - distance;
      if (previous >= 0) {
        yield previous;
      }
      final int next = index + distance;
      if (next < domain.sections.length) {
        yield next;
      }
    }
  }

  ScrollVisibleTarget? _visibleTargetForSnapshot(
    ScrollSnapshot snapshot,
    ScrollSemanticAnchor anchor,
  ) {
    final List<ScrollVisibleTarget> targets = snapshot.visibleTargets;
    if (snapshot.atTrailingEdge) {
      for (final ScrollVisibleTarget target in targets.reversed) {
        final K? section = sectionOfTarget(target);
        if (section != null && domain.contains(section)) {
          return target;
        }
      }
    }
    if (snapshot.atLeadingEdge) {
      for (final ScrollVisibleTarget target in targets) {
        final K? section = sectionOfTarget(target);
        if (section != null && domain.contains(section)) {
          return target;
        }
      }
    }
    for (final ScrollVisibleTarget target in targets) {
      if ((anchor.key != null && target.key == anchor.key) ||
          (anchor.key == null &&
              anchor.index != null &&
              target.index == anchor.index)) {
        return target;
      }
    }
    return targets.isEmpty ? null : targets.first;
  }

  double? _sectionStart(SeekoController controller, K section) =>
      _targetStart(controller, sectionTarget(section));

  double? _nextResolvableSectionStart(
    SeekoController controller,
    int startIndex,
  ) {
    final List<K> sections = domain.sections;
    for (var index = startIndex; index < sections.length; index += 1) {
      final double? start = _sectionStart(controller, sections[index]);
      if (start != null) {
        return start;
      }
    }
    return null;
  }

  double? _targetStart(SeekoController controller, ScrollTarget target) =>
      controller._semanticTargetInterval(target)?.start;

  double _logicalContentEnd(SeekoController controller) {
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return 0;
    }
    return controller._logicalExtentFor(controller.position) +
        controller._viewportExtentFor(controller.position);
  }

  ScrollSemanticAnchor _anchorForTarget(
    ScrollTarget target, {
    required double viewportAnchor,
    required double logicalOffset,
  }) {
    return switch (target) {
      KeyScrollTarget(:final Object key) => ScrollSemanticAnchor(
          key: key,
          index: null,
          itemAnchor: 0,
          viewportAnchor: viewportAnchor,
          logicalOffset: logicalOffset,
        ),
      IndexScrollTarget(:final int index) => ScrollSemanticAnchor(
          key: null,
          index: index,
          itemAnchor: 0,
          viewportAnchor: viewportAnchor,
          logicalOffset: logicalOffset,
        ),
      _ => throw ArgumentError.value(
          target,
          'sectionTarget',
          'must resolve to a stable key or index target',
        ),
    };
  }
}

final class _SectionFallbackTarget {
  const _SectionFallbackTarget({
    required this.index,
    required this.target,
    required this.start,
  });

  final int index;
  final ScrollTarget target;
  final double start;
}
