import 'dart:async';

import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

import 'scenario_ui.dart';
import 'section_catalog.dart';

class VerticalCategorySyncPage extends StatefulWidget {
  const VerticalCategorySyncPage({super.key});

  @override
  State<VerticalCategorySyncPage> createState() =>
      _VerticalCategorySyncPageState();
}

class _VerticalCategorySyncPageState extends State<VerticalCategorySyncPage> {
  final SeekoController _categoryController = SeekoController(
    debugLabel: 'vertical-category-navigation',
  );
  final SeekoController _contentController = SeekoController(
    debugLabel: 'vertical-category-content',
  );
  late final SeekoSectionCoordinator<String> _coordinator;
  List<CatalogSection> _sections = catalogSections;
  ScrollResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _coordinator = SeekoSectionCoordinator<String>.tagged(
      contentController: _contentController,
      navigationController: _categoryController,
      initialSection: catalogSections.first.id,
      viewportAnchor: 0.12,
    );
  }

  @override
  void dispose() {
    _coordinator.dispose();
    _categoryController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _select(String section) async {
    final ScrollResult result = await _coordinator.select(section);
    if (mounted) setState(() => _lastResult = result);
  }

  void _rotateSections() {
    setState(() {
      _sections = <CatalogSection>[..._sections.skip(1), _sections.first];
    });
  }

  Future<void> _reset() async {
    setState(() => _sections = catalogSections);
    final ScrollResult result = await _coordinator.select(
      catalogSections.first.id,
      animated: false,
    );
    if (mounted) setState(() => _lastResult = result);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('vertical-category-sync-page'),
      child: Column(
        children: <Widget>[
          _ScenarioHeader(
            onReorder: _rotateSections,
            onReset: () => unawaited(_reset()),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: MediaQuery.sizeOf(context).width < 700 ? 124 : 190,
                  child: ValueListenableBuilder<String>(
                    valueListenable: _coordinator.selectedSection,
                    builder: (BuildContext context, String selected, _) {
                      return _CategoryRail(
                        controller: _categoryController,
                        sections: _sections,
                        selected: selected,
                        onSelected: (String id) => unawaited(_select(id)),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      ValueListenableBuilder<String>(
                        valueListenable: _coordinator.selectedSection,
                        builder: (BuildContext context, String selected, _) {
                          return _SelectionStatus(
                            selected: selected,
                            sections: _sections,
                            result: _lastResult,
                          );
                        },
                      ),
                      Expanded(
                        child: _SectionContent(
                          controller: _contentController,
                          sections: _sections,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioHeader extends StatelessWidget {
  const _ScenarioHeader({required this.onReorder, required this.onReset});

  final VoidCallback onReorder;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ScenarioPageHeader(
      title: 'Vertical Category Rail',
      description:
          'Tap a category to seek; scroll grouped content to drive selection '
          'back through the public section API.',
      actions: <Widget>[
        IconButton.filledTonal(
          tooltip: 'Reorder sections',
          onPressed: onReorder,
          icon: const Icon(Icons.swap_vert),
        ),
        IconButton.filledTonal(
          tooltip: 'Reset category scenario',
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt),
        ),
      ],
      status: const ScenarioStatusBadge(
        label: 'Bidirectional',
        icon: Icons.swap_vert,
        tone: ScenarioStatusTone.active,
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.controller,
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final SeekoController controller;
  final List<CatalogSection> sections;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        itemCount: sections.length,
        itemBuilder: (BuildContext context, int index) {
          final CatalogSection section = sections[index];
          final bool isSelected = section.id == selected;
          return SeekoTag(
            key: ValueKey<String>('vertical-nav-${section.id}'),
            controller: controller,
            targetKey: section.id,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Material(
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: Key('vertical-category-${section.id}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelected(section.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(section.icon, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            section.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SelectionStatus extends StatelessWidget {
  const _SelectionStatus({
    required this.selected,
    required this.sections,
    required this.result,
  });

  final String selected;
  final List<CatalogSection> sections;
  final ScrollResult? result;

  @override
  Widget build(BuildContext context) {
    final CatalogSection section = sectionById(sections, selected);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Selected: ${section.label}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ScenarioStatusBadge(
              label: result == null ? 'Ready' : result!.outcome.name,
              tone: scenarioToneForOutcome(result?.outcome.name),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionContent extends StatelessWidget {
  const _SectionContent({required this.controller, required this.sections});

  final SeekoController controller;
  final List<CatalogSection> sections;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final CatalogSection trailingSection = sections.last;
        final double trailingSectionExtent =
            54 +
            trailingSection.items.fold<double>(
              0,
              (double extent, CatalogItem item) => extent + item.height,
            );
        final double requiredTrailingSpace =
            constraints.maxHeight - trailingSectionExtent;
        final double trailingSpace = requiredTrailingSpace > 32
            ? requiredTrailingSpace
            : 32;
        return CustomScrollView(
          key: const Key('vertical-category-content'),
          controller: controller,
          slivers: <Widget>[
            for (final CatalogSection section in sections)
              SliverMainAxisGroup(
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: SeekoTag(
                      key: ValueKey<String>(
                        'vertical-content-anchor-${section.id}',
                      ),
                      controller: controller,
                      targetKey: SeekoSectionKey<String>.header(section.id),
                      child: const SizedBox.shrink(),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SectionHeaderDelegate(section: section),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final CatalogItem item = section.items[index];
                      return SeekoTag(
                        controller: controller,
                        targetKey: SeekoSectionKey<String>.item(
                          section.id,
                          index,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: item.height),
                          child: _CatalogItemCard(item: item),
                        ),
                      );
                    }, childCount: section.items.length),
                  ),
                ],
              ),
            SliverPadding(padding: EdgeInsets.only(bottom: trailingSpace)),
          ],
        );
      },
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SectionHeaderDelegate({required this.section});

  final CatalogSection section;

  @override
  double get minExtent => 54;

  @override
  double get maxExtent => 54;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: overlapsContent ? 2 : 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: <Widget>[
              Icon(section.icon, size: 20),
              const SizedBox(width: 10),
              Text(
                section.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeaderDelegate oldDelegate) =>
      oldDelegate.section != section;
}

class _CatalogItemCard extends StatelessWidget {
  const _CatalogItemCard({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(item.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(item.description),
            ],
          ),
        ),
      ),
    );
  }
}
