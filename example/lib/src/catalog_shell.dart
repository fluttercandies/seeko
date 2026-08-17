import 'package:flutter/material.dart';

class CatalogShell extends StatelessWidget {
  const CatalogShell({
    required this.activeRoute,
    required this.child,
    super.key,
  });

  final String activeRoute;
  final Widget child;

  static const List<_CatalogDestination> _destinations = <_CatalogDestination>[
    _CatalogDestination(
      route: '/target-navigation',
      label: 'Target Navigation',
      subtitle: 'Pixels and mounted targets',
      icon: Icons.my_location_outlined,
      selectedIcon: Icons.my_location,
    ),
    _CatalogDestination(
      route: '/synchronized-views/progress',
      label: 'Progress Sync',
      subtitle: 'Different extents, one progress',
      icon: Icons.sync_alt_outlined,
      selectedIcon: Icons.sync_alt,
    ),
    _CatalogDestination(
      route: '/synchronized-views/vertical-categories',
      label: 'Vertical Categories',
      subtitle: 'Category rail and grouped content',
      icon: Icons.view_sidebar_outlined,
      selectedIcon: Icons.view_sidebar,
    ),
    _CatalogDestination(
      route: '/synchronized-views/horizontal-sections',
      label: 'Horizontal Sections',
      subtitle: 'Scrollable tabs and grouped content',
      icon: Icons.view_week_outlined,
      selectedIcon: Icons.view_week,
    ),
    _CatalogDestination(
      route: '/synchronized-views/multi-view',
      label: '2 / 4 / 8 Views',
      subtitle: 'Scale one group across active views',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view,
    ),
    _CatalogDestination(
      route: '/natural-motion',
      label: 'Natural Motion',
      subtitle: 'Adaptive and explicit motion policies',
      icon: Icons.motion_photos_on_outlined,
      selectedIcon: Icons.motion_photos_on,
    ),
    _CatalogDestination(
      route: '/complex-slivers',
      label: 'Complex Slivers',
      subtitle: 'Targets across a native sliver tree',
      icon: Icons.layers_outlined,
      selectedIcon: Icons.layers,
    ),
    _CatalogDestination(
      route: '/obstructions-and-forms',
      label: 'Obstructions & Forms',
      subtitle: 'Pinned controls and keyboard-safe reveal',
      icon: Icons.keyboard_alt_outlined,
      selectedIcon: Icons.keyboard_alt,
    ),
    _CatalogDestination(
      route: '/two-dimensional',
      label: 'Two-dimensional',
      subtitle: 'Independent row and column targets',
      icon: Icons.open_with_outlined,
      selectedIcon: Icons.open_with,
    ),
    _CatalogDestination(
      route: '/two-dimensional/sync',
      label: 'Two-dimensional Sync',
      subtitle: 'Dual-axis leader and late join',
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view,
    ),
    _CatalogDestination(
      route: '/chat-and-paging/open-timeline',
      label: 'Open Timeline',
      subtitle: 'Stable bidirectional paging',
      icon: Icons.timeline_outlined,
      selectedIcon: Icons.timeline,
    ),
    _CatalogDestination(
      route: '/page-view/carousel',
      label: 'Page + Item',
      subtitle: 'Composite carousel navigation',
      icon: Icons.view_carousel_outlined,
      selectedIcon: Icons.view_carousel,
    ),
    _CatalogDestination(
      route: '/page-view/sync',
      label: 'Page Sync',
      subtitle: 'Leader, progress, late join',
      icon: Icons.compare_arrows_outlined,
      selectedIcon: Icons.compare_arrows,
    ),
    _CatalogDestination(
      route: '/two-dimensional/tree-table',
      label: 'Tree Table',
      subtitle: 'Expansion and keyboard navigation',
      icon: Icons.account_tree_outlined,
      selectedIcon: Icons.account_tree,
    ),
    _CatalogDestination(
      route: '/grid',
      label: 'Grid',
      subtitle: 'Virtualized cell targeting',
      icon: Icons.grid_3x3_outlined,
      selectedIcon: Icons.grid_3x3,
    ),
    _CatalogDestination(
      route: '/advanced-drivers',
      label: 'Advanced Drivers',
      subtitle: 'Nested, snap, focus, load, restore',
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
    ),
    _CatalogDestination(
      route: '/diagnostics-performance',
      label: 'Diagnostics Lab',
      subtitle: 'Bounded evidence and frame samples',
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart,
    ),
  ];

  int get _selectedIndex {
    final int index = _destinations.indexWhere(
      (_CatalogDestination destination) => destination.route == activeRoute,
    );
    return index < 0 ? 0 : index;
  }

  void _navigate(BuildContext context, int index, {required bool closeDrawer}) {
    if (closeDrawer) Navigator.of(context).pop();
    final String route = _destinations[index].route;
    if (route != activeRoute) Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 960) {
          return Scaffold(
            appBar: AppBar(
              key: const Key('catalog-top-bar'),
              title: const _BrandLockup(),
              surfaceTintColor: Colors.transparent,
            ),
            drawer: Drawer(
              child: SafeArea(
                child: _CatalogDrawer(
                  activeRoute: activeRoute,
                  destinations: _destinations,
                ),
              ),
            ),
            body: child,
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: <Widget>[
                SizedBox(
                  key: const Key('catalog-sidebar'),
                  width: 252,
                  child: _CatalogSidebar(
                    selectedIndex: _selectedIndex,
                    destinations: _destinations,
                    onSelected: (int index) =>
                        _navigate(context, index, closeDrawer: false),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CatalogSidebar extends StatelessWidget {
  const _CatalogSidebar({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_CatalogDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Semantics(
        label: 'Seeko capability catalog navigation',
        child: ListView(
          key: const Key('catalog-navigation'),
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 2, 8, 20),
              child: _BrandLockup(expanded: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                'Scroll scenarios',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            for (var index = 0; index < destinations.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _CatalogNavigationTile(
                  destination: destinations[index],
                  selected: index == selectedIndex,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogNavigationTile extends StatelessWidget {
  const _CatalogNavigationTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _CatalogDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 20,
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: selected
                            ? colors.onPrimaryContainer.withValues(alpha: 0.78)
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogDrawer extends StatelessWidget {
  const _CatalogDrawer({required this.activeRoute, required this.destinations});

  final String activeRoute;
  final List<_CatalogDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('catalog-navigation'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 24),
          child: _BrandLockup(expanded: true),
        ),
        for (final _CatalogDestination destination in destinations)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _CatalogNavigationTile(
              selected: destination.route == activeRoute,
              destination: destination,
              onTap: () {
                Navigator.of(context).pop();
                if (destination.route != activeRoute) {
                  Navigator.of(context).pushReplacementNamed(destination.route);
                }
              },
            ),
          ),
      ],
    );
  }
}

class _CatalogDestination {
  const _CatalogDestination({
    required this.route,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selectedIcon,
  });

  final String route;
  final String label;
  final String subtitle;
  final IconData icon;
  final IconData selectedIcon;
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({this.expanded = false});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final Widget name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Seeko',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        if (expanded)
          Text(
            'Native scroll orchestration',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
    if (expanded) {
      return Row(
        children: <Widget>[
          const _BrandMark(),
          const SizedBox(width: 10),
          Expanded(child: name),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[const _BrandMark(), const SizedBox(width: 10), name],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const Key('seeko-brand-mark'),
      label: 'Seeko',
      image: true,
      child: SizedBox(
        width: 36,
        height: 36,
        child: CustomPaint(
          painter: _SeekoMarkPainter(
            background: const Color(0xFF07111F),
            rail: const Color(0xFFF8FAFC),
            motion: colors.secondary,
            target: colors.primary,
          ),
        ),
      ),
    );
  }
}

class _SeekoMarkPainter extends CustomPainter {
  const _SeekoMarkPainter({
    required this.background,
    required this.rail,
    required this.motion,
    required this.target,
  });

  final Color background;
  final Color rail;
  final Color motion;
  final Color target;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 128, size.height / 128);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 128, 128),
        const Radius.circular(24),
      ),
      Paint()..color = background,
    );

    final Path railPath = Path()
      ..moveTo(20, 30)
      ..lineTo(82, 30)
      ..cubicTo(100, 30, 108, 37, 108, 48)
      ..cubicTo(108, 59, 99, 65, 82, 65)
      ..lineTo(46, 65)
      ..cubicTo(29, 65, 20, 72, 20, 82)
      ..cubicTo(20, 93, 29, 99, 46, 99)
      ..lineTo(108, 99);
    final Paint railPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 8;

    canvas.save();
    canvas.translate(0, -10);
    canvas.drawPath(railPath, railPaint..color = rail);
    canvas.restore();
    canvas.drawPath(railPath, railPaint..color = motion);
    canvas.save();
    canvas.translate(0, 10);
    canvas.drawPath(railPath, railPaint..color = rail);
    canvas.restore();

    canvas.drawCircle(const Offset(64, 65), 9.5, Paint()..color = background);
    canvas.drawCircle(const Offset(64, 65), 8, Paint()..color = target);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SeekoMarkPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.rail != rail ||
      oldDelegate.motion != motion ||
      oldDelegate.target != target;
}
