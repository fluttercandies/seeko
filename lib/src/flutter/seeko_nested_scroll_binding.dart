part of 'seeko_controller.dart';

/// Selects the active inner position when a [NestedScrollView] keeps multiple
/// bodies attached, such as an offstage `TabBarView`.
///
/// Returning `null` or a position outside [positions] rejects semantic
/// commands until a valid position is selected.
typedef SeekoNestedInnerPositionSelector = ScrollPosition? Function(
  List<ScrollPosition> positions,
);

/// Adds one composite Seeko coordinate space to a native [NestedScrollView].
///
/// The [child] remains an ordinary Flutter widget. The binding only owns
/// lifecycle observation and user-interruption forwarding; it does not create
/// or replace either scrollable.
class SeekoNestedScrollBinding extends StatefulWidget {
  const SeekoNestedScrollBinding({
    required this.controller,
    required this.nestedScrollViewKey,
    required this.child,
    this.innerPositionSelector,
    super.key,
  });

  final SeekoController controller;
  final GlobalKey<NestedScrollViewState> nestedScrollViewKey;
  final Widget child;

  /// Required when more than one inner position remains attached.
  ///
  /// With no selector, exactly one attached inner position is accepted. This
  /// prevents commands from silently targeting an offstage tab.
  final SeekoNestedInnerPositionSelector? innerPositionSelector;

  @override
  State<SeekoNestedScrollBinding> createState() =>
      _SeekoNestedScrollBindingState();
}

final class _SeekoNestedScrollBindingState
    extends State<SeekoNestedScrollBinding> {
  ScrollController? _observedInnerController;
  var _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(SeekoNestedScrollBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._unbindNestedScroll(this);
      _stopObservingInnerController();
    } else if (!identical(
      oldWidget.nestedScrollViewKey,
      widget.nestedScrollViewKey,
    )) {
      widget.controller._bindNestedScroll(
        owner: this,
        innerPosition: null,
        ambiguous: false,
      );
      _stopObservingInnerController();
    }
    _scheduleSync();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (ScrollMetricsNotification notification) {
        _scheduleSync();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          _scheduleSync();
          widget.controller._handleNestedScrollNotification(notification);
          return false;
        },
        child: widget.child,
      ),
    );
  }

  void _scheduleSync() {
    if (!mounted || _syncScheduled) {
      return;
    }
    _syncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) {
        _syncNow();
      }
    });
  }

  void _syncNow() {
    final NestedScrollViewState? nested =
        widget.nestedScrollViewKey.currentState;
    if (nested == null || !widget.controller.hasClients) {
      widget.controller._bindNestedScroll(
        owner: this,
        innerPosition: null,
        ambiguous: false,
      );
      return;
    }
    final ScrollController innerController = nested.innerController;
    if (!identical(_observedInnerController, innerController)) {
      _stopObservingInnerController();
      _observedInnerController = innerController;
      innerController.addListener(_scheduleSync);
    }
    final List<ScrollPosition> positions =
        innerController.positions.toList(growable: false);
    final SeekoNestedInnerPositionSelector? selector =
        widget.innerPositionSelector;
    ScrollPosition? selected;
    var ambiguous = false;
    if (selector == null) {
      if (positions.length == 1) {
        selected = positions.single;
      } else if (positions.length > 1) {
        ambiguous = true;
      }
    } else {
      try {
        selected = selector(positions);
      } on Object catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'seeko',
            context: ErrorDescription(
              'while selecting a NestedScrollView inner position',
            ),
          ),
        );
        ambiguous = true;
      }
      if (selected != null &&
          !positions.any(
            (ScrollPosition position) => identical(position, selected),
          )) {
        selected = null;
        ambiguous = true;
      }
    }
    widget.controller._bindNestedScroll(
      owner: this,
      innerPosition: selected,
      ambiguous: ambiguous,
    );
  }

  void _stopObservingInnerController() {
    _observedInnerController?.removeListener(_scheduleSync);
    _observedInnerController = null;
  }

  @override
  void dispose() {
    widget.controller._unbindNestedScroll(this);
    _stopObservingInnerController();
    super.dispose();
  }
}
