import 'package:flutter/widgets.dart';

import 'seeko_controller.dart';

/// Minimally registers an already-mounted child as a semantic scroll target.
class SeekoTag extends StatefulWidget {
  const SeekoTag({
    required this.controller,
    required this.child,
    this.targetKey,
    this.index,
    super.key,
  });

  final SeekoController controller;
  final Object? targetKey;
  final int? index;
  final Widget child;

  @override
  State<SeekoTag> createState() => _SeekoTagState();
}

class _SeekoTagState extends State<SeekoTag> {
  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(covariant SeekoTag oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.targetKey != widget.targetKey ||
        oldWidget.index != widget.index) {
      oldWidget.controller.unregisterMountedTarget(
        context,
        key: oldWidget.targetKey,
        index: oldWidget.index,
      );
      _register();
    }
  }

  void _register() {
    widget.controller.registerMountedTarget(
      context,
      key: widget.targetKey,
      index: widget.index,
    );
  }

  @override
  void dispose() {
    widget.controller.unregisterMountedTarget(
      context,
      key: widget.targetKey,
      index: widget.index,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
