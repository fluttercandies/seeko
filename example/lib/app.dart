import 'package:flutter/material.dart';

import 'src/catalog_shell.dart';
import 'src/complex_sliver_page.dart';
import 'src/advanced_drivers_page.dart';
import 'src/diagnostics_lab_page.dart';
import 'src/grid_page.dart';
import 'src/horizontal_section_tabs_page.dart';
import 'src/multi_view_sync_page.dart';
import 'src/natural_motion_page.dart';
import 'src/obstruction_form_page.dart';
import 'src/open_timeline_page.dart';
import 'src/page_carousel_page.dart';
import 'src/page_sync_page.dart';
import 'src/progress_sync_page.dart';
import 'src/seeko_theme.dart';
import 'src/target_navigation_page.dart';
import 'src/tree_table_page.dart';
import 'src/two_dimensional_page.dart';
import 'src/two_dimensional_sync_page.dart';
import 'src/vertical_category_sync_page.dart';

abstract final class SeekoRoutes {
  static const targetNavigation = '/target-navigation';
  static const progressSync = '/synchronized-views/progress';
  static const verticalCategories = '/synchronized-views/vertical-categories';
  static const horizontalSections = '/synchronized-views/horizontal-sections';
  static const multiViewSync = '/synchronized-views/multi-view';
  static const naturalMotion = '/natural-motion';
  static const complexSlivers = '/complex-slivers';
  static const obstructionForms = '/obstructions-and-forms';
  static const twoDimensional = '/two-dimensional';
  static const twoDimensionalSync = '/two-dimensional/sync';
  static const openTimeline = '/chat-and-paging/open-timeline';
  static const pageCarousel = '/page-view/carousel';
  static const pageSync = '/page-view/sync';
  static const treeTable = '/two-dimensional/tree-table';
  static const grid = '/grid';
  static const advancedDrivers = '/advanced-drivers';
  static const diagnosticsLab = '/diagnostics-performance';
}

class SeekoExampleApp extends StatelessWidget {
  const SeekoExampleApp({
    this.initialRoute = SeekoRoutes.targetNavigation,
    this.navigatorObservers = const <NavigatorObserver>[],
    super.key,
  });

  final String initialRoute;
  final List<NavigatorObserver> navigatorObservers;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seeko',
      debugShowCheckedModeBanner: false,
      navigatorObservers: navigatorObservers,
      theme: buildSeekoTheme(Brightness.light),
      darkTheme: buildSeekoTheme(Brightness.dark),
      initialRoute: initialRoute,
      onGenerateRoute: (RouteSettings settings) {
        final Widget? page = switch (settings.name) {
          SeekoRoutes.targetNavigation => const TargetNavigationPage(),
          SeekoRoutes.progressSync => const ProgressSyncPage(),
          SeekoRoutes.verticalCategories => const VerticalCategorySyncPage(),
          SeekoRoutes.horizontalSections => const HorizontalSectionTabsPage(),
          SeekoRoutes.multiViewSync => const MultiViewSyncPage(),
          SeekoRoutes.naturalMotion => const NaturalMotionPage(),
          SeekoRoutes.complexSlivers => const ComplexSliverPage(),
          SeekoRoutes.obstructionForms => const ObstructionFormPage(),
          SeekoRoutes.twoDimensional => const TwoDimensionalPage(),
          SeekoRoutes.twoDimensionalSync => const TwoDimensionalSyncPage(),
          SeekoRoutes.openTimeline => const OpenTimelinePage(),
          SeekoRoutes.pageCarousel => const PageCarouselPage(),
          SeekoRoutes.pageSync => const PageSyncPage(),
          SeekoRoutes.treeTable => const TreeTablePage(),
          SeekoRoutes.grid => const GridPage(),
          SeekoRoutes.advancedDrivers => const AdvancedDriversPage(),
          SeekoRoutes.diagnosticsLab => const DiagnosticsLabPage(),
          _ => null,
        };
        if (page == null) return null;
        return PageRouteBuilder<void>(
          settings: settings,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) =>
              CatalogShell(activeRoute: settings.name!, child: page),
        );
      },
    );
  }
}
