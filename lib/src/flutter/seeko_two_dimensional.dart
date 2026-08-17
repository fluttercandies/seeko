import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/capability.dart';
import '../core/command_model.dart';
import '../core/motion.dart';

/// A stable row/column coordinate in a two-dimensional data set.
@immutable
final class SeekoCellCoordinate {
  factory SeekoCellCoordinate(int row, int column) {
    RangeError.checkNotNegative(row, 'row');
    RangeError.checkNotNegative(column, 'column');
    return SeekoCellCoordinate._(row, column);
  }

  const SeekoCellCoordinate._(this.row, this.column);

  static const SeekoCellCoordinate zero = SeekoCellCoordinate._(0, 0);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is SeekoCellCoordinate &&
      other.row == row &&
      other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'SeekoCellCoordinate($row, $column)';
}

/// A semantic target for a two-dimensional scroll operation.
sealed class SeekoCellTarget {
  const SeekoCellTarget._();

  factory SeekoCellTarget.cell(int row, int column) {
    RangeError.checkNotNegative(row, 'row');
    RangeError.checkNotNegative(column, 'column');
    return SeekoCoordinateCellTarget._(SeekoCellCoordinate(row, column));
  }

  factory SeekoCellTarget.key(Object key) = SeekoKeyCellTarget._;

  SeekoCellCoordinate? get coordinate => null;
  Object? get key => null;
}

final class SeekoCoordinateCellTarget extends SeekoCellTarget {
  const SeekoCoordinateCellTarget._(this._coordinate) : super._();

  final SeekoCellCoordinate _coordinate;

  @override
  SeekoCellCoordinate get coordinate => _coordinate;

  @override
  bool operator ==(Object other) =>
      other is SeekoCoordinateCellTarget && other.coordinate == coordinate;

  @override
  int get hashCode => Object.hash(SeekoCoordinateCellTarget, coordinate);

  @override
  String toString() =>
      'SeekoCellTarget.cell(${coordinate.row}, ${coordinate.column})';
}

final class SeekoKeyCellTarget extends SeekoCellTarget {
  const SeekoKeyCellTarget._(this._key) : super._();

  final Object _key;

  @override
  Object get key => _key;

  @override
  bool operator ==(Object other) =>
      other is SeekoKeyCellTarget && other.key == key;

  @override
  int get hashCode => Object.hash(SeekoKeyCellTarget, key);

  @override
  String toString() => 'SeekoCellTarget.key($key)';
}

/// Alignment used independently on the vertical and horizontal axes.
enum SeekoAxisPlacement { start, center, end, nearest }

/// Placement policy for a cell target.
@immutable
final class SeekoTwoDimensionalPlacement {
  const SeekoTwoDimensionalPlacement({
    this.vertical = SeekoAxisPlacement.nearest,
    this.horizontal = SeekoAxisPlacement.nearest,
    this.verticalOffset = 0,
    this.horizontalOffset = 0,
  })  : assert(
          verticalOffset >= -double.maxFinite &&
              verticalOffset <= double.maxFinite,
        ),
        assert(
          horizontalOffset >= -double.maxFinite &&
              horizontalOffset <= double.maxFinite,
        );

  const SeekoTwoDimensionalPlacement.nearest() : this();

  const SeekoTwoDimensionalPlacement.start()
      : this(
          vertical: SeekoAxisPlacement.start,
          horizontal: SeekoAxisPlacement.start,
        );

  const SeekoTwoDimensionalPlacement.center()
      : this(
          vertical: SeekoAxisPlacement.center,
          horizontal: SeekoAxisPlacement.center,
        );

  const SeekoTwoDimensionalPlacement.end()
      : this(
          vertical: SeekoAxisPlacement.end,
          horizontal: SeekoAxisPlacement.end,
        );

  final SeekoAxisPlacement vertical;
  final SeekoAxisPlacement horizontal;
  final double verticalOffset;
  final double horizontalOffset;
}

/// A cell rectangle in logical content coordinates.
@immutable
final class SeekoCellGeometry {
  const SeekoCellGeometry({
    required this.coordinate,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.key,
  });

  final SeekoCellCoordinate coordinate;
  final double left;
  final double top;
  final double width;
  final double height;
  final Object? key;

  double get right => left + width;
  double get bottom => top + height;
  Rect get rect => Rect.fromLTWH(left, top, width, height);
}

/// Describes row/column extents and optional stable key lookup.
abstract class SeekoTwoDimensionalLayout {
  int? get rowCount;
  int? get columnCount;

  double rowExtent(int row);
  double columnExtent(int column);

  Object? keyAt(int row, int column) => null;
  SeekoCellCoordinate? coordinateOfKey(Object key) => null;

  double rowOffset(int row);
  double columnOffset(int column);
  int rowAtOffset(double offset);
  int columnAtOffset(double offset);
  double get totalHeight;
  double get totalWidth;

  SeekoCellGeometry geometryFor(SeekoCellCoordinate coordinate) {
    return SeekoCellGeometry(
      coordinate: coordinate,
      left: columnOffset(coordinate.column),
      top: rowOffset(coordinate.row),
      width: columnExtent(coordinate.column),
      height: rowExtent(coordinate.row),
      key: keyAt(coordinate.row, coordinate.column),
    );
  }
}

/// A compact extent table with O(1) fixed extents and O(log n) variable lookup.
final class SeekoExtentTable {
  SeekoExtentTable.fixed({required this.count, required this.extent})
      : _extents = null,
        _prefix = null {
    _validateCount(count);
    _validateExtent(extent!);
  }

  SeekoExtentTable.variable(List<double> extents)
      : count = extents.length,
        extent = null,
        _extents = List<double>.unmodifiable(extents),
        _prefix = _buildPrefix(extents) {
    for (final double value in extents) {
      _validateExtent(value);
    }
  }

  final int count;
  final double? extent;
  final List<double>? _extents;
  final List<double>? _prefix;

  double extentAt(int index) {
    _checkIndex(index);
    return extent ?? _extents![index];
  }

  double offsetOf(int index) {
    if (index < 0 || index > count) {
      throw RangeError.range(index, 0, count, 'index');
    }
    return extent == null ? _prefix![index] : index * extent!;
  }

  int indexAt(double offset) {
    if (!offset.isFinite || offset < 0) {
      throw ArgumentError.value(
          offset, 'offset', 'must be finite and non-negative');
    }
    if (count == 0) {
      return 0;
    }
    if (extent != null) {
      return math.min(count - 1, offset ~/ extent!);
    }
    final List<double> prefix = _prefix!;
    var low = 0;
    var high = count;
    while (low < high) {
      final int middle = (low + high) >> 1;
      if (prefix[middle + 1] <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return math.min(count - 1, low);
  }

  double get totalExtent => offsetOf(count);

  void _checkIndex(int index) {
    if (index < 0 || index >= count) {
      throw RangeError.range(index, 0, count - 1, 'index');
    }
  }

  static List<double> _buildPrefix(List<double> values) {
    final List<double> prefix = List<double>.filled(values.length + 1, 0);
    for (var index = 0; index < values.length; index += 1) {
      prefix[index + 1] = prefix[index] + values[index];
    }
    return List<double>.unmodifiable(prefix);
  }

  static void _validateCount(int value) {
    if (value < 0) {
      throw RangeError.value(value, 'count');
    }
  }

  static void _validateExtent(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, 'extent', 'must be finite and positive');
    }
  }
}

/// A finite layout backed by row and column extent tables.
final class SeekoFiniteTwoDimensionalLayout extends SeekoTwoDimensionalLayout {
  SeekoFiniteTwoDimensionalLayout({
    required SeekoExtentTable rows,
    required SeekoExtentTable columns,
    Object? Function(int row, int column)? keyAt,
    SeekoCellCoordinate? Function(Object key)? coordinateOfKey,
  })  : _rows = rows,
        _columns = columns,
        _keyAt = keyAt,
        _coordinateOfKey = coordinateOfKey;

  factory SeekoFiniteTwoDimensionalLayout.fixed({
    required int rowCount,
    required int columnCount,
    double rowExtent = 48,
    double columnExtent = 120,
    Object? Function(int row, int column)? keyAt,
    SeekoCellCoordinate? Function(Object key)? coordinateOfKey,
  }) {
    return SeekoFiniteTwoDimensionalLayout(
      rows: SeekoExtentTable.fixed(count: rowCount, extent: rowExtent),
      columns: SeekoExtentTable.fixed(count: columnCount, extent: columnExtent),
      keyAt: keyAt,
      coordinateOfKey: coordinateOfKey,
    );
  }

  factory SeekoFiniteTwoDimensionalLayout.variable({
    required List<double> rowExtents,
    required List<double> columnExtents,
    Object? Function(int row, int column)? keyAt,
    SeekoCellCoordinate? Function(Object key)? coordinateOfKey,
  }) {
    return SeekoFiniteTwoDimensionalLayout(
      rows: SeekoExtentTable.variable(rowExtents),
      columns: SeekoExtentTable.variable(columnExtents),
      keyAt: keyAt,
      coordinateOfKey: coordinateOfKey,
    );
  }

  final SeekoExtentTable _rows;
  final SeekoExtentTable _columns;
  final Object? Function(int row, int column)? _keyAt;
  final SeekoCellCoordinate? Function(Object key)? _coordinateOfKey;

  @override
  int get rowCount => _rows.count;
  @override
  int get columnCount => _columns.count;
  @override
  double rowExtent(int row) => _rows.extentAt(row);
  @override
  double columnExtent(int column) => _columns.extentAt(column);
  @override
  double rowOffset(int row) => _rows.offsetOf(row);
  @override
  double columnOffset(int column) => _columns.offsetOf(column);
  @override
  int rowAtOffset(double offset) => _rows.indexAt(offset);
  @override
  int columnAtOffset(double offset) => _columns.indexAt(offset);
  @override
  double get totalHeight => _rows.totalExtent;
  @override
  double get totalWidth => _columns.totalExtent;
  @override
  Object? keyAt(int row, int column) => _keyAt?.call(row, column);
  @override
  SeekoCellCoordinate? coordinateOfKey(Object key) =>
      _coordinateOfKey?.call(key);
}

/// A cell intersecting the effective two-dimensional viewport.
@immutable
final class SeekoVisibleCell {
  const SeekoVisibleCell({
    required this.coordinate,
    required this.rect,
    required this.visibleFraction,
    this.key,
  });

  final SeekoCellCoordinate coordinate;
  final Rect rect;
  final double visibleFraction;
  final Object? key;

  @override
  bool operator ==(Object other) {
    return other is SeekoVisibleCell &&
        other.coordinate == coordinate &&
        other.rect == rect &&
        other.visibleFraction == visibleFraction &&
        other.key == key;
  }

  @override
  int get hashCode => Object.hash(coordinate, rect, visibleFraction, key);
}

/// Coalesced state for a two-dimensional scroll surface.
@immutable
final class SeekoTwoDimensionalSnapshot {
  const SeekoTwoDimensionalSnapshot({
    required this.horizontalPixels,
    required this.verticalPixels,
    required this.horizontalMax,
    required this.verticalMax,
    required this.viewportSize,
    required this.visibleCells,
    required this.phase,
    this.activeCommandId,
    this.userScrollDirection = ScrollDirection.idle,
  });

  const SeekoTwoDimensionalSnapshot.detached()
      : horizontalPixels = 0,
        verticalPixels = 0,
        horizontalMax = 0,
        verticalMax = 0,
        viewportSize = Size.zero,
        visibleCells = const <SeekoVisibleCell>[],
        phase = ScrollCommandPhase.terminal,
        activeCommandId = null,
        userScrollDirection = ScrollDirection.idle;

  final double horizontalPixels;
  final double verticalPixels;
  final double horizontalMax;
  final double verticalMax;
  final Size viewportSize;
  final List<SeekoVisibleCell> visibleCells;
  final ScrollCommandPhase phase;
  final int? activeCommandId;
  final ScrollDirection userScrollDirection;

  double get horizontalProgress =>
      horizontalMax == 0 ? 0 : (horizontalPixels / horizontalMax).clamp(0, 1);
  double get verticalProgress =>
      verticalMax == 0 ? 0 : (verticalPixels / verticalMax).clamp(0, 1);

  @override
  bool operator ==(Object other) {
    if (other is! SeekoTwoDimensionalSnapshot ||
        other.horizontalPixels != horizontalPixels ||
        other.verticalPixels != verticalPixels ||
        other.horizontalMax != horizontalMax ||
        other.verticalMax != verticalMax ||
        other.viewportSize != viewportSize ||
        other.phase != phase ||
        other.activeCommandId != activeCommandId ||
        other.userScrollDirection != userScrollDirection ||
        other.visibleCells.length != visibleCells.length) {
      return false;
    }
    for (var index = 0; index < visibleCells.length; index += 1) {
      if (other.visibleCells[index] != visibleCells[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        horizontalPixels,
        verticalPixels,
        horizontalMax,
        verticalMax,
        viewportSize,
        phase,
        activeCommandId,
        userScrollDirection,
        Object.hashAll(visibleCells),
      );
}

enum SeekoCellResolutionStatus {
  resolved,
  targetNotLoaded,
  targetDeleted,
  targetOutOfRange,
  detached,
  unsupported,
}

/// Typed result returned by two-dimensional target commands.
@immutable
final class SeekoTwoDimensionalResult {
  const SeekoTwoDimensionalResult({
    required this.commandId,
    required this.outcome,
    required this.requestedTarget,
    this.coordinate,
    this.finalHorizontalPixels,
    this.finalVerticalPixels,
    this.finalError = 0,
    this.elapsed = Duration.zero,
    this.diagnostics,
  });

  final int commandId;
  final ScrollOutcome outcome;
  final SeekoCellTarget requestedTarget;
  final SeekoCellCoordinate? coordinate;
  final double? finalHorizontalPixels;
  final double? finalVerticalPixels;
  final double finalError;
  final Duration elapsed;
  final Map<String, Object?>? diagnostics;

  bool get isSuccess =>
      outcome == ScrollOutcome.completed || outcome == ScrollOutcome.clamped;
}

/// An optional four-sided obstruction around a two-dimensional viewport.
@immutable
final class SeekoTwoDimensionalObstruction {
  const SeekoTwoDimensionalObstruction({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  })  : assert(left >= 0),
        assert(top >= 0),
        assert(right >= 0),
        assert(bottom >= 0);

  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// A high-performance binding for Flutter's native two-axis scrollables.
///
/// It owns no viewport or child delegate. Pass [vertical] and [horizontal] to
/// Flutter's `ScrollableDetails` (or use them with a native two-dimensional
/// viewport), then provide layout measurements through [layout].
final class SeekoTwoDimensionalController extends ChangeNotifier {
  SeekoTwoDimensionalController({
    ScrollController? vertical,
    ScrollController? horizontal,
    SeekoTwoDimensionalLayout? layout,
    Size viewportSize = Size.zero,
    SeekoTwoDimensionalObstruction obstruction =
        const SeekoTwoDimensionalObstruction(),
  })  : vertical = vertical ?? ScrollController(),
        horizontal = horizontal ?? ScrollController(),
        _ownsVertical = vertical == null,
        _ownsHorizontal = horizontal == null,
        _layout = layout,
        _viewportSize = viewportSize,
        _obstruction = obstruction {
    this.vertical.addListener(_handleOffsetChanged);
    this.horizontal.addListener(_handleOffsetChanged);
    _publishSnapshot();
  }

  final ScrollController vertical;
  final ScrollController horizontal;
  final bool _ownsVertical;
  final bool _ownsHorizontal;
  SeekoTwoDimensionalLayout? _layout;
  Size _viewportSize;
  SeekoTwoDimensionalObstruction _obstruction;
  final ValueNotifier<SeekoTwoDimensionalSnapshot> _state =
      ValueNotifier<SeekoTwoDimensionalSnapshot>(
    const SeekoTwoDimensionalSnapshot.detached(),
  );
  final AdaptiveMotionPlanner _planner = const AdaptiveMotionPlanner();
  _TwoDimensionalCommand? _active;
  int _commandSequence = 0;
  bool _disposed = false;
  bool _publishing = false;
  bool _snapshotFrameScheduled = false;
  int _snapshotGeneration = 0;

  ValueListenable<SeekoTwoDimensionalSnapshot> get state => _state;
  SeekoTwoDimensionalLayout? get layout => _layout;
  Size get viewportSize => _viewportSize;
  SeekoTwoDimensionalObstruction get obstruction => _obstruction;

  ScrollController get verticalController => vertical;
  ScrollController get horizontalController => horizontal;

  ScrollCapabilities get capabilities => const ScrollCapabilities(
        ScrollCapability.pixelBit |
            ScrollCapability.observationBit |
            ScrollCapability.unmountedIndexBit |
            ScrollCapability.stableKeyBit |
            ScrollCapability.visibleItemsBit |
            ScrollCapability.anchorPreservationBit |
            ScrollCapability.semanticSyncBit |
            ScrollCapability.dynamicExtentCorrectionBit |
            ScrollCapability.twoDimensionalBit,
      );

  void setLayout(SeekoTwoDimensionalLayout? value) {
    if (identical(_layout, value)) {
      return;
    }
    _layout = value;
    _publishSnapshot();
  }

  void setViewportSize(Size value) {
    if (!value.width.isFinite ||
        !value.height.isFinite ||
        value.width < 0 ||
        value.height < 0) {
      throw ArgumentError.value(
          value, 'value', 'must contain finite non-negative dimensions');
    }
    if (_viewportSize == value) {
      return;
    }
    _viewportSize = value;
    _publishSnapshot();
  }

  void setObstruction(SeekoTwoDimensionalObstruction value) {
    if (_obstruction == value) {
      return;
    }
    _obstruction = value;
    _publishSnapshot();
  }

  Future<SeekoTwoDimensionalResult> jumpToCell(
    SeekoCellTarget target, {
    SeekoTwoDimensionalPlacement placement =
        const SeekoTwoDimensionalPlacement.nearest(),
  }) {
    return _execute(target,
        placement: placement, motion: const ScrollMotion.instant());
  }

  Future<SeekoTwoDimensionalResult> animateToCell(
    SeekoCellTarget target, {
    SeekoTwoDimensionalPlacement placement =
        const SeekoTwoDimensionalPlacement.nearest(),
    ScrollMotion motion = const ScrollMotion.adaptive(),
  }) {
    return _execute(target, placement: placement, motion: motion);
  }

  Future<SeekoTwoDimensionalResult> ensureCellVisible(
    SeekoCellTarget target, {
    ScrollMotion? motion,
  }) {
    return motion == null
        ? jumpToCell(target)
        : animateToCell(target, motion: motion);
  }

  Future<SeekoTwoDimensionalResult> jumpTo({
    double? horizontalPixels,
    double? verticalPixels,
  }) async {
    final int commandId = ++_commandSequence;
    _cancelActive(ScrollOutcome.superseded);
    if (!_attached) {
      return _result(
        commandId,
        ScrollOutcome.detached,
        SeekoCellTarget.cell(0, 0),
      );
    }
    final double horizontalTarget =
        _clampHorizontal(horizontalPixels ?? horizontal.position.pixels);
    final double verticalTarget =
        _clampVertical(verticalPixels ?? vertical.position.pixels);
    if (horizontalPixels != null) {
      horizontal.jumpTo(horizontalTarget);
    }
    if (verticalPixels != null) {
      vertical.jumpTo(verticalTarget);
    }
    _publishSnapshot();
    return SeekoTwoDimensionalResult(
      commandId: commandId,
      outcome: horizontalTarget != (horizontalPixels ?? horizontalTarget) ||
              verticalTarget != (verticalPixels ?? verticalTarget)
          ? ScrollOutcome.clamped
          : ScrollOutcome.completed,
      requestedTarget: SeekoCellTarget.cell(0, 0),
      finalHorizontalPixels: horizontal.position.pixels,
      finalVerticalPixels: vertical.position.pixels,
    );
  }

  Future<SeekoTwoDimensionalResult> animateTo({
    required double horizontalPixels,
    required double verticalPixels,
    ScrollMotion motion = const ScrollMotion.adaptive(),
  }) {
    return _executePixels(
      horizontalPixels: horizontalPixels,
      verticalPixels: verticalPixels,
      motion: motion,
    );
  }

  void stop({ScrollStopReason reason = ScrollStopReason.requested}) {
    _cancelActive(reason == ScrollStopReason.userInteraction
        ? ScrollOutcome.interruptedByUser
        : ScrollOutcome.cancelled);
    if (horizontal.hasClients) {
      horizontal.jumpTo(horizontal.position.pixels);
    }
    if (vertical.hasClients) {
      vertical.jumpTo(vertical.position.pixels);
    }
    _publishSnapshot();
  }

  bool get _attached => vertical.hasClients && horizontal.hasClients;

  Future<SeekoTwoDimensionalResult> _execute(
    SeekoCellTarget target, {
    required SeekoTwoDimensionalPlacement placement,
    required ScrollMotion motion,
  }) {
    final int commandId = ++_commandSequence;
    _cancelActive(ScrollOutcome.superseded);
    final SeekoCellCoordinate? coordinate = _resolveCoordinate(target);
    if (!_attached) {
      return Future<SeekoTwoDimensionalResult>.value(
        _result(
          commandId,
          ScrollOutcome.detached,
          target,
          coordinate: coordinate,
        ),
      );
    }
    if (coordinate == null) {
      return Future<SeekoTwoDimensionalResult>.value(
        _result(
          commandId,
          _failureOutcome(target),
          target,
        ),
      );
    }
    final SeekoCellGeometry geometry = _layout!.geometryFor(coordinate);
    final double horizontalTarget = _desiredOffset(
      current: horizontal.position.pixels,
      start: geometry.left,
      end: geometry.right,
      viewport: _viewportSize.width,
      max: _horizontalMax,
      placement: placement.horizontal,
      leadingObstruction: _obstruction.left,
      trailingObstruction: _obstruction.right,
      extraOffset: placement.horizontalOffset,
    );
    final double verticalTarget = _desiredOffset(
      current: vertical.position.pixels,
      start: geometry.top,
      end: geometry.bottom,
      viewport: _viewportSize.height,
      max: _verticalMax,
      placement: placement.vertical,
      leadingObstruction: _obstruction.top,
      trailingObstruction: _obstruction.bottom,
      extraOffset: placement.verticalOffset,
    );
    return _executePixels(
      horizontalPixels: horizontalTarget,
      verticalPixels: verticalTarget,
      motion: motion,
      target: target,
      coordinate: coordinate,
      commandId: commandId,
    );
  }

  Future<SeekoTwoDimensionalResult> _executePixels({
    required double horizontalPixels,
    required double verticalPixels,
    required ScrollMotion motion,
    SeekoCellTarget? target,
    SeekoCellCoordinate? coordinate,
    int? commandId,
  }) async {
    if (!horizontalPixels.isFinite || !verticalPixels.isFinite) {
      throw ArgumentError(
        'horizontalPixels and verticalPixels must be finite.',
      );
    }
    final int id = commandId ?? ++_commandSequence;
    _cancelActive(ScrollOutcome.superseded);
    final SeekoCellTarget requested = target ?? SeekoCellTarget.cell(0, 0);
    if (!_attached) {
      return _result(
        id,
        ScrollOutcome.detached,
        requested,
        coordinate: coordinate,
      );
    }
    final double horizontalTarget = _clampHorizontal(horizontalPixels);
    final double verticalTarget = _clampVertical(verticalPixels);
    final bool clamped = horizontalTarget != horizontalPixels ||
        verticalTarget != verticalPixels;
    final Duration started = _clockNow;
    final _TwoDimensionalCommand active = _TwoDimensionalCommand(
      id: id,
      target: requested,
      coordinate: coordinate,
      started: started,
    );
    _active = active;
    _publishSnapshot(
      phase: ScrollCommandPhase.moving,
      commandId: id,
    );
    if (motion.kind == ScrollMotionKind.instant ||
        ((horizontalTarget - horizontal.position.pixels).abs() <= 0.01 &&
            (verticalTarget - vertical.position.pixels).abs() <= 0.01)) {
      horizontal.jumpTo(horizontalTarget);
      vertical.jumpTo(verticalTarget);
      return _finish(
        active,
        clamped ? ScrollOutcome.clamped : ScrollOutcome.completed,
      );
    }

    final Duration frameInterval = _frameInterval;
    final ScrollMotionPlan horizontalPlan = _planner.plan(
      distance: horizontalTarget - horizontal.position.pixels,
      viewportExtent: math.max(1, _effectiveWidth),
      frameInterval: frameInterval,
      motion: motion,
    );
    final ScrollMotionPlan verticalPlan = _planner.plan(
      distance: verticalTarget - vertical.position.pixels,
      viewportExtent: math.max(1, _effectiveHeight),
      frameInterval: frameInterval,
      motion: motion,
    );
    final Duration duration = horizontalPlan.duration >= verticalPlan.duration
        ? horizontalPlan.duration
        : verticalPlan.duration;
    final Curve curve = motion.kind == ScrollMotionKind.duration
        ? motion.curve!
        : horizontalPlan.curve;
    try {
      await Future.wait<void>(<Future<void>>[
        if ((horizontalTarget - horizontal.position.pixels).abs() > 0.01)
          horizontal.animateTo(
            horizontalTarget,
            duration: duration,
            curve: curve,
          ),
        if ((verticalTarget - vertical.position.pixels).abs() > 0.01)
          vertical.animateTo(
            verticalTarget,
            duration: duration,
            curve: curve,
          ),
      ]);
    } on Object catch (error, stackTrace) {
      return _finish(
        active,
        ScrollOutcome.detached,
        diagnostics: <String, Object?>{
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
    if (active.completed) {
      return active.result!;
    }
    final ScrollOutcome outcome = active.userInterrupted
        ? ScrollOutcome.interruptedByUser
        : clamped
            ? ScrollOutcome.clamped
            : ScrollOutcome.completed;
    return _finish(active, outcome);
  }

  SeekoCellCoordinate? _resolveCoordinate(SeekoCellTarget target) {
    final SeekoTwoDimensionalLayout? currentLayout = _layout;
    if (currentLayout == null) {
      return null;
    }
    final SeekoCellCoordinate? coordinate = target.coordinate ??
        (target.key == null
            ? null
            : currentLayout.coordinateOfKey(target.key!));
    if (coordinate == null) {
      return null;
    }
    final int? rows = currentLayout.rowCount;
    final int? columns = currentLayout.columnCount;
    if ((rows != null && coordinate.row >= rows) ||
        (columns != null && coordinate.column >= columns)) {
      return null;
    }
    return coordinate;
  }

  ScrollOutcome _failureOutcome(SeekoCellTarget target) {
    if (_layout == null) {
      return ScrollOutcome.unsupported;
    }
    if (target.coordinate != null) {
      final SeekoCellCoordinate coordinate = target.coordinate!;
      final int? rows = _layout!.rowCount;
      final int? columns = _layout!.columnCount;
      if ((rows != null && coordinate.row >= rows) ||
          (columns != null && coordinate.column >= columns)) {
        return ScrollOutcome.targetOutOfRange;
      }
      return ScrollOutcome.targetNotLoaded;
    }
    return ScrollOutcome.targetDeleted;
  }

  double _desiredOffset({
    required double current,
    required double start,
    required double end,
    required double viewport,
    required double max,
    required SeekoAxisPlacement placement,
    required double leadingObstruction,
    required double trailingObstruction,
    required double extraOffset,
  }) {
    final double visibleStart = current + leadingObstruction;
    final double visibleEnd = current + viewport - trailingObstruction;
    late final double desired;
    switch (placement) {
      case SeekoAxisPlacement.start:
        desired = start - leadingObstruction + extraOffset;
      case SeekoAxisPlacement.center:
        desired = (start + end) / 2 - viewport / 2 + extraOffset;
      case SeekoAxisPlacement.end:
        desired = end - viewport + trailingObstruction + extraOffset;
      case SeekoAxisPlacement.nearest:
        if (start >= visibleStart && end <= visibleEnd) {
          desired = current + extraOffset;
        } else if (start < visibleStart) {
          desired = start - leadingObstruction + extraOffset;
        } else {
          desired = end - viewport + trailingObstruction + extraOffset;
        }
    }
    return desired.clamp(0, max);
  }

  double get _effectiveWidth =>
      math.max(0, _viewportSize.width - _obstruction.left - _obstruction.right);
  double get _effectiveHeight => math.max(
      0, _viewportSize.height - _obstruction.top - _obstruction.bottom);

  double get _horizontalMax {
    final double content = _layout?.totalWidth ?? 0;
    final double fallback = math.max(0, content - _viewportSize.width);
    return horizontal.hasClients
        ? horizontal.position.maxScrollExtent
        : fallback;
  }

  double get _verticalMax {
    final double content = _layout?.totalHeight ?? 0;
    final double fallback = math.max(0, content - _viewportSize.height);
    return vertical.hasClients ? vertical.position.maxScrollExtent : fallback;
  }

  double _clampHorizontal(double value) => value.clamp(0, _horizontalMax);
  double _clampVertical(double value) => value.clamp(0, _verticalMax);

  Duration get _clockNow =>
      Duration(microseconds: DateTime.now().microsecondsSinceEpoch);

  Duration get _frameInterval {
    final BuildContext? context = vertical.hasClients
        ? vertical.position.context.notificationContext
        : null;
    final double? rate =
        context == null ? null : View.maybeOf(context)?.display.refreshRate;
    final double hz = rate == null || !rate.isFinite || rate <= 0 ? 60 : rate;
    return Duration(
      microseconds: (Duration.microsecondsPerSecond / hz).round(),
    );
  }

  void _cancelActive(ScrollOutcome outcome) {
    final _TwoDimensionalCommand? active = _active;
    if (active == null || active.completed) {
      return;
    }
    active.cancelled = true;
    _stopAxes();
    _finish(active, outcome);
  }

  void _stopAxes() {
    if (horizontal.hasClients) {
      horizontal.jumpTo(horizontal.position.pixels);
    }
    if (vertical.hasClients) {
      vertical.jumpTo(vertical.position.pixels);
    }
  }

  SeekoTwoDimensionalResult _finish(
    _TwoDimensionalCommand active,
    ScrollOutcome outcome, {
    Map<String, Object?>? diagnostics,
  }) {
    if (active.completed) {
      return active.result!;
    }
    active.completed = true;
    final SeekoTwoDimensionalResult result = SeekoTwoDimensionalResult(
      commandId: active.id,
      outcome: outcome,
      requestedTarget: active.target,
      coordinate: active.coordinate,
      finalHorizontalPixels:
          horizontal.hasClients ? horizontal.position.pixels : null,
      finalVerticalPixels:
          vertical.hasClients ? vertical.position.pixels : null,
      finalError: 0,
      elapsed: _clockNow - active.started,
      diagnostics: diagnostics,
    );
    active.result = result;
    if (identical(_active, active)) {
      _active = null;
    }
    _publishSnapshot(phase: ScrollCommandPhase.terminal);
    return result;
  }

  SeekoTwoDimensionalResult _result(
    int commandId,
    ScrollOutcome outcome,
    SeekoCellTarget target, {
    SeekoCellCoordinate? coordinate,
  }) {
    return SeekoTwoDimensionalResult(
      commandId: commandId,
      outcome: outcome,
      requestedTarget: target,
      coordinate: coordinate,
      finalHorizontalPixels:
          horizontal.hasClients ? horizontal.position.pixels : null,
      finalVerticalPixels:
          vertical.hasClients ? vertical.position.pixels : null,
    );
  }

  void _handleOffsetChanged() {
    final _TwoDimensionalCommand? active = _active;
    if (active != null &&
        ((vertical.hasClients &&
                vertical.position.userScrollDirection !=
                    ScrollDirection.idle) ||
            (horizontal.hasClients &&
                horizontal.position.userScrollDirection !=
                    ScrollDirection.idle))) {
      active.userInterrupted = true;
    }
    _scheduleSnapshot();
  }

  void _scheduleSnapshot() {
    if (_snapshotFrameScheduled || _disposed) {
      return;
    }
    _snapshotFrameScheduled = true;
    final int generation = ++_snapshotGeneration;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _snapshotFrameScheduled = false;
      if (_disposed || generation != _snapshotGeneration) {
        return;
      }
      _publishSnapshot();
    });
  }

  void _publishSnapshot({
    ScrollCommandPhase? phase,
    int? commandId,
  }) {
    if (_publishing || _disposed) {
      return;
    }
    _snapshotGeneration += 1;
    _publishing = true;
    try {
      final double horizontalPixels =
          horizontal.hasClients ? horizontal.position.pixels : 0;
      final double verticalPixels =
          vertical.hasClients ? vertical.position.pixels : 0;
      final SeekoTwoDimensionalSnapshot next = SeekoTwoDimensionalSnapshot(
        horizontalPixels: horizontalPixels,
        verticalPixels: verticalPixels,
        horizontalMax: _horizontalMax,
        verticalMax: _verticalMax,
        viewportSize: _viewportSize,
        visibleCells: _visibleCells(horizontalPixels, verticalPixels),
        phase: phase ??
            (_active == null
                ? ScrollCommandPhase.settled
                : ScrollCommandPhase.moving),
        activeCommandId: commandId ?? _active?.id,
        userScrollDirection: vertical.hasClients
            ? vertical.position.userScrollDirection
            : ScrollDirection.idle,
      );
      if (_state.value != next) {
        _state.value = next;
        notifyListeners();
      }
    } finally {
      _publishing = false;
    }
  }

  List<SeekoVisibleCell> _visibleCells(
    double horizontalPixels,
    double verticalPixels,
  ) {
    final SeekoTwoDimensionalLayout? currentLayout = _layout;
    if (currentLayout == null ||
        currentLayout.rowCount == 0 ||
        currentLayout.columnCount == 0 ||
        _effectiveWidth <= 0 ||
        _effectiveHeight <= 0) {
      return const <SeekoVisibleCell>[];
    }
    final int firstRow = currentLayout.rowAtOffset(verticalPixels);
    final int firstColumn = currentLayout.columnAtOffset(horizontalPixels);
    final int lastRow = currentLayout.rowAtOffset(
      verticalPixels + _effectiveHeight,
    );
    final int lastColumn = currentLayout.columnAtOffset(
      horizontalPixels + _effectiveWidth,
    );
    final Rect viewport = Rect.fromLTWH(
      horizontalPixels + _obstruction.left,
      verticalPixels + _obstruction.top,
      _effectiveWidth,
      _effectiveHeight,
    );
    final List<SeekoVisibleCell> cells = <SeekoVisibleCell>[];
    for (var row = firstRow; row <= lastRow; row += 1) {
      for (var column = firstColumn; column <= lastColumn; column += 1) {
        final SeekoCellGeometry geometry = currentLayout.geometryFor(
          SeekoCellCoordinate(row, column),
        );
        final double visible = _intersectionArea(geometry.rect, viewport);
        if (visible > 0) {
          cells.add(
            SeekoVisibleCell(
              coordinate: geometry.coordinate,
              rect: geometry.rect,
              visibleFraction:
                  (visible / (geometry.width * geometry.height)).clamp(0, 1),
              key: geometry.key,
            ),
          );
        }
      }
    }
    return List<SeekoVisibleCell>.unmodifiable(cells);
  }

  double _intersectionArea(Rect a, Rect b) {
    final double width = math.max(
      0,
      math.min(a.right, b.right) - math.max(a.left, b.left),
    );
    final double height = math.max(
      0,
      math.min(a.bottom, b.bottom) - math.max(a.top, b.top),
    );
    return width * height;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _cancelActive(ScrollOutcome.detached);
    _disposed = true;
    vertical.removeListener(_handleOffsetChanged);
    horizontal.removeListener(_handleOffsetChanged);
    if (_ownsVertical) {
      vertical.dispose();
    }
    if (_ownsHorizontal) {
      horizontal.dispose();
    }
    _state.dispose();
    super.dispose();
  }
}

final class _TwoDimensionalCommand {
  _TwoDimensionalCommand({
    required this.id,
    required this.target,
    required this.coordinate,
    required this.started,
  });

  final int id;
  final SeekoCellTarget target;
  final SeekoCellCoordinate? coordinate;
  final Duration started;
  bool userInterrupted = false;
  bool cancelled = false;
  bool completed = false;
  SeekoTwoDimensionalResult? result;
}

/// Frozen row/column configuration shared by table renderers and bindings.
@immutable
final class SeekoFrozenPaneConfiguration {
  const SeekoFrozenPaneConfiguration({
    this.rows = 0,
    this.columns = 0,
  })  : assert(rows >= 0),
        assert(columns >= 0);

  final int rows;
  final int columns;
  bool get isEmpty => rows == 0 && columns == 0;
}

/// Keeps frozen header and leading-column scroll positions aligned with a body.
///
/// The body is always the single writer. Followers are updated once per body
/// event with feedback suppression, so the cost is O(1) per frozen axis.
final class SeekoFrozenPaneBinding {
  SeekoFrozenPaneBinding({
    required this.bodyVertical,
    required this.bodyHorizontal,
    this.frozenRowsHorizontal,
    this.frozenColumnsVertical,
    this.configuration = const SeekoFrozenPaneConfiguration(),
  }) {
    bodyVertical.addListener(_syncVertical);
    bodyHorizontal.addListener(_syncHorizontal);
    syncNow();
  }

  final ScrollController bodyVertical;
  final ScrollController bodyHorizontal;
  final ScrollController? frozenRowsHorizontal;
  final ScrollController? frozenColumnsVertical;
  final SeekoFrozenPaneConfiguration configuration;
  bool _applying = false;
  bool _disposed = false;

  void syncNow() {
    _syncVertical();
    _syncHorizontal();
  }

  void _syncVertical() {
    final ScrollController? follower = frozenColumnsVertical;
    if (_applying ||
        _disposed ||
        follower == null ||
        !bodyVertical.hasClients ||
        !follower.hasClients) {
      return;
    }
    _apply(
      follower,
      bodyVertical.position.pixels,
    );
  }

  void _syncHorizontal() {
    final ScrollController? follower = frozenRowsHorizontal;
    if (_applying ||
        _disposed ||
        follower == null ||
        !bodyHorizontal.hasClients ||
        !follower.hasClients) {
      return;
    }
    _apply(
      follower,
      bodyHorizontal.position.pixels,
    );
  }

  void _apply(ScrollController follower, double pixels) {
    _applying = true;
    try {
      final ScrollPosition position = follower.position;
      final double target = pixels.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((position.pixels - target).abs() > precisionErrorTolerance) {
        follower.jumpTo(target);
      }
    } finally {
      _applying = false;
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    bodyVertical.removeListener(_syncVertical);
    bodyHorizontal.removeListener(_syncHorizontal);
  }
}

/// Reports the effective viewport size to a two-dimensional controller.
///
/// This is a layout observer only; it does not create a scrollable or impose a
/// child delegate. It can wrap Flutter's native two-dimensional viewport.
final class SeekoTwoDimensionalViewportObserver extends StatefulWidget {
  const SeekoTwoDimensionalViewportObserver({
    required this.controller,
    required this.child,
    super.key,
  });

  final SeekoTwoDimensionalController controller;
  final Widget child;

  @override
  State<SeekoTwoDimensionalViewportObserver> createState() =>
      _SeekoTwoDimensionalViewportObserverState();
}

final class _SeekoTwoDimensionalViewportObserverState
    extends State<SeekoTwoDimensionalViewportObserver> {
  Size? _lastSize;
  bool _frameScheduled = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        if (_lastSize != size && !_frameScheduled) {
          _frameScheduled = true;
          SchedulerBinding.instance.addPostFrameCallback((Duration _) {
            _frameScheduled = false;
            if (!mounted) {
              return;
            }
            _lastSize = size;
            widget.controller.setViewportSize(size);
          });
        }
        return widget.child;
      },
    );
  }
}
