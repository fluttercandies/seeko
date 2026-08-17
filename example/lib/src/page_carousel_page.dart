import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';

class PageCarouselPage extends StatefulWidget {
  const PageCarouselPage({super.key});

  @override
  State<PageCarouselPage> createState() => _PageCarouselPageState();
}

class _PageCarouselPageState extends State<PageCarouselPage> {
  static const int _pageCount = 5;

  late final PageController _pageController;
  late final List<SeekoController> _itemControllers;
  late final SeekoPageControllerAdapter _adapter;
  SeekoPageItemResult? _lastResult;
  SeekoPageRestorationState? _savedState;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.86);
    _itemControllers = List<SeekoController>.generate(
      _pageCount,
      (int page) => SeekoController(debugLabel: 'carousel-page-$page'),
    );
    _adapter = SeekoPageControllerAdapter(
      pageController: _pageController,
      itemControllerForPage: (int page) =>
          page >= 0 && page < _itemControllers.length
          ? _itemControllers[page]
          : null,
      pageCount: _pageCount,
    );
  }

  Future<void> _seek({required bool animated}) async {
    final SeekoPageItemTarget target = SeekoPageItemTarget(
      page: animated ? 4 : 2,
      item: ScrollTarget.key(animated ? 'page-4-item-5' : 'page-2-item-5'),
      itemPlacement: const ScrollPlacement.center(),
    );
    final SeekoPageItemResult result = animated
        ? await _adapter.animateToTarget(target)
        : await _adapter.jumpToTarget(target);
    if (mounted) setState(() => _lastResult = result);
  }

  Future<void> _reset() async {
    final SeekoPageItemResult result = await _adapter.jumpToTarget(
      SeekoPageItemTarget.page(0),
    );
    if (mounted) setState(() => _lastResult = result);
  }

  void _captureRestoreState() {
    _savedState = _adapter.captureRestorationState();
    if (mounted) setState(() {});
  }

  Future<void> _restoreSavedState() async {
    final SeekoPageRestorationState? state = _savedState;
    if (state == null) return;
    final SeekoPageItemResult result = await _adapter.restore(state);
    if (mounted) setState(() => _lastResult = result);
  }

  void _stop() {
    _adapter.stop();
    if (mounted) {
      setState(() => _lastResult = null);
    }
  }

  @override
  void dispose() {
    _adapter.dispose();
    _pageController.dispose();
    for (final SeekoController controller in _itemControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('page-carousel-page'),
      child: Column(
        children: <Widget>[
          ScenarioPageHeader(
            title: 'Page + Item Navigation',
            description:
                'A composite command crosses a native viewport-fraction '
                'PageView, waits for its list, then reveals the item.',
            actions: <Widget>[
              IconButton.filledTonal(
                key: const Key('page-carousel-jump'),
                tooltip: 'Jump to page 3 and its item',
                onPressed: () => unawaited(_seek(animated: false)),
                icon: const Icon(Icons.skip_next),
              ),
              IconButton.filledTonal(
                key: const Key('page-carousel-animate'),
                tooltip: 'Animate to page 5 and its item',
                onPressed: () => unawaited(_seek(animated: true)),
                icon: const Icon(Icons.view_carousel_outlined),
              ),
              IconButton.filledTonal(
                key: const Key('page-carousel-reset'),
                tooltip: 'Reset carousel',
                onPressed: () => unawaited(_reset()),
                icon: const Icon(Icons.restart_alt),
              ),
              IconButton.filledTonal(
                key: const Key('page-carousel-capture'),
                tooltip: 'Capture page and item restoration state',
                onPressed: _captureRestoreState,
                icon: const Icon(Icons.bookmark_add_outlined),
              ),
              IconButton.filledTonal(
                key: const Key('page-carousel-restore'),
                tooltip: 'Restore the captured page and item',
                onPressed: _savedState == null
                    ? null
                    : () => unawaited(_restoreSavedState()),
                icon: const Icon(Icons.restore_rounded),
              ),
              IconButton.filledTonal(
                key: const Key('page-carousel-stop'),
                tooltip: 'Stop active page or item motion',
                onPressed: _stop,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
            status: ScenarioStatusBadge(
              label: _lastResult?.outcome.name ?? 'Ready',
              widgetKey: const Key('page-carousel-result'),
              tone: scenarioToneForOutcome(_lastResult?.outcome.name),
              icon: Icons.view_carousel_outlined,
            ),
          ),
          const Divider(height: 1),
          ValueListenableBuilder<int?>(
            valueListenable: _adapter.currentPage,
            builder: (BuildContext context, int? page, _) {
              return ScenarioPaneHeader(
                title: 'Page ${(page ?? 0) + 1} of $_pageCount',
                description: _lastResult?.itemResult == null
                    ? _savedState == null
                          ? 'Drag to take control, or run a composite command'
                          : 'Saved page ${_savedState!.page + 1} · drag or restore'
                    : 'Item result: ${_lastResult!.itemResult!.outcome.name}',
                trailing: ScenarioStatusBadge(
                  label: '86% viewport',
                  icon: Icons.fit_screen,
                ),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: Semantics(
              label: 'Carousel with five independently scrollable pages',
              child: PageView.builder(
                key: const Key('page-carousel-view'),
                controller: _pageController,
                itemCount: _pageCount,
                padEnds: true,
                itemBuilder: (BuildContext context, int page) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
                    child: _CarouselCard(
                      page: page,
                      controller: _itemControllers[page],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({required this.page, required this.controller});

  final int page;
  final SeekoController controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = <Color>[
      colors.primary,
      colors.secondary,
      colors.tertiary,
      colors.error,
      colors.primary,
    ][page];
    return Semantics(
      label: 'Carousel page ${page + 1}',
      child: Material(
        key: Key('page-carousel-card-$page'),
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            ScenarioPaneHeader(
              title: 'Collection ${page + 1}',
              description: 'Independent native ListView · 18 stable items',
              trailing: Icon(Icons.collections_bookmark, color: accent),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(
              child: ListView.builder(
                key: Key('page-carousel-list-$page'),
                controller: controller,
                itemCount: 18,
                itemExtent: 72,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (BuildContext context, int index) {
                  final String itemKey = 'page-$page-item-$index';
                  return SeekoTag(
                    key: ValueKey<String>(itemKey),
                    controller: controller,
                    targetKey: itemKey,
                    index: index,
                    child: Semantics(
                      label: 'Page ${page + 1}, item ${index + 1}',
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: accent.withValues(alpha: 0.14),
                          foregroundColor: accent,
                          child: Text('${index + 1}'),
                        ),
                        title: Text('Collection item ${index + 1}'),
                        subtitle: Text(itemKey),
                        trailing: const Icon(Icons.drag_handle),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
