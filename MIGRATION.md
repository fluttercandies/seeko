# Migration guide

This guide covers the implemented L1/L2 APIs, layout-aware L3 sliver
primitives, synchronization modes, and specialized adapters. Performance
qualification and platform evidence remain release checks; they do not change
which target and result semantics an API exposes.

## Adopt Seeko incrementally

Start with the smallest capability your screen needs:

1. Replace a native `ScrollController` with `SeekoController` for pixel,
   progress, edge, observation, and synchronization features.
2. Wrap only addressable mounted children in `SeekoTag` for key/index reveal.
3. Keep native `ListView`, `GridView`, and `CustomScrollView`. When exact
   unmounted key/index navigation is required, use `SeekoIndexedSliver` or
   `SeekoIndexedGridSliver` inside a native `CustomScrollView`; Seeko does not
   provide parallel high-level scroll widgets.

```dart
final controller = SeekoController();

ListView.builder(
  controller: controller,
  itemCount: items.length,
  itemBuilder: (context, index) {
    final item = items[index];
    return SeekoTag(
      controller: controller,
      targetKey: item.id,
      index: index,
      child: ItemTile(item),
    );
  },
);
```

Dispose controllers and synchronization groups you create. A group never
disposes its member controllers.

## From `scroll_to_index`

Replace:

- `AutoScrollController` with `SeekoController`.
- `AutoScrollTag` with `SeekoTag`.
- `scrollToIndex` with `animateToTarget(ScrollTarget.index(...))`.
- `highlight`-driven positioning assumptions with the returned `ScrollResult`.

```dart
final result = await controller.animateToTarget(
  ScrollTarget.key(itemId),
  placement: const ScrollPlacement.start(),
);

switch (result.outcome) {
  case ScrollOutcome.completed:
  case ScrollOutcome.clamped:
    break;
  default:
    handleNavigationFailure(result);
}
```

Important semantic difference: L2 does not report an unmounted child with
unknown extent as exact. It returns a typed unavailable/loading outcome instead
of performing an unbounded heuristic crawl. Use an indexed L3 primitive when
exact unmounted navigation and dynamic-extent correction are required.

## From `linked_scroll_controller`

Create one `SeekoController` per scrollable, then add each controller to a
`ScrollSyncGroup`:

```dart
final primary = SeekoController();
final secondary = SeekoController();
final sync = ScrollSyncGroup.progress();

sync.add(primary, id: 'primary');
sync.add(secondary, id: 'secondary');
```

Choose the mapping according to the relationship between the views:

| Mapping | Use when |
| --- | --- |
| `ScrollSyncGroup.pixels()` | Both views share the same logical pixel domain |
| `ScrollSyncGroup.delta()` | Views start at different origins but should move by the same delta |
| `ScrollSyncGroup.progress()` | Content extents differ but normalized progress should match |
| `ScrollSyncGroup.viewportFraction()` | Movement should scale with each viewport size |

Unlike listener-to-`jumpTo` linking, follower updates carry transaction origin
metadata and do not recursively start new leader transactions.

## From `scrollable_positioned_list`

For pixel, progress, mounted key/index, visibility, observation, or synchronized
views, return to a native Flutter scrollable and attach Seeko:

```dart
final controller = SeekoController();

ListView.builder(
  controller: controller,
  itemCount: items.length,
  itemBuilder: buildItem,
);
```

For exact navigation to unmounted dynamic items, migrate the body to a native
`CustomScrollView` with `SeekoIndexedSliver`, while keeping the same
`SeekoController`. The primitive reuses the application's `SliverChildDelegate`
and exposes typed outcomes, visible targets, anchor preservation, and adaptive
far navigation without adding a replacement `ListView`.

## Specialized surfaces

Use the smallest adapter that matches the content domain:

| Surface | Seeko integration | Key behavior |
| --- | --- | --- |
| Grid | `SeekoIndexedGridSliver` | Unmounted cell key/index navigation with fixed, responsive, or custom grid geometry |
| Nested scroll | `SeekoNestedScrollBinding` | One logical outer + selected-inner axis with explicit ambiguous-inner rejection |
| Remote target loading | `ScrollTargetLoader` on `SeekoController` | Bounded load/retry/deadline flow sharing the original command result |
| Bidirectional open data | `SeekoOpenDataController` + `SeekoOpenScrollAdapter` | Signed logical indices, stable-origin rebasing, and no fabricated normalized progress |
| Page/carousel | `SeekoPageControllerAdapter` | Composite page + item target, mount wait, cancellation, and restoration |
| Two-dimensional | `SeekoTwoDimensionalController` | Independent axes, cell/key target, visible-cell state, frozen panes, and dual-axis sync |
| Table/tree table | `SeekoTableLayout` + `SeekoTreeTableController` | Sparse row/column metadata, resize/reorder, expansion anchoring, and keyboard navigation |

`SeekoSectionCoordinator`, semantic section mappings, snap configuration,
focus/form helpers, and `ScrollPrefetchObserver` compose with these surfaces as
needed. All adapters preserve caller ownership unless an explicit ownership
parameter states otherwise.

## Existing controller adapter

Use `SeekoController.adapt` only when a third-party widget prevents replacing
its controller. The adapter requires an explicit `SeekoPositionBinding` and
must be rebound when the wrapped scrollable creates a new position.

```dart
final existing = ScrollController();
final binding = SeekoPositionBinding();
final seeko = SeekoController.adapt(
  existing,
  binding: binding,
  exclusiveProgrammaticWrites: true,
);
```

An adapted controller is a façade and must not be passed to the scrollable.
Continue passing `existing`, then bind its selected position after attachment.
Adapted controllers never claim strict synchronization or authoritative
programmatic results because external writes cannot be intercepted reliably.

## Pixel APIs and typed target APIs

Inherited `jumpTo(double)` and `animateTo(double)` preserve Flutter's API and
`Future<void>` contract. They replace conflicting Seeko commands but do not
accept Seeko conflict, boundary, resolution, or execution policies.

Use these methods when typed policy and outcome matter:

- `jumpToTarget`
- `animateToTarget`
- `ensureTargetVisible`
- `jumpBy`
- `animateBy`

## Dynamic data identity

Prefer stable keys for inserts, removals, and reorder operations. An index
target captures the stable key at submission when an index delegate is
available. Use `IndexTracking.liveSlot` only when the numeric slot itself is
the intended destination.

## Restoration

Process-local PageStorage restoration can use tagged semantic anchors directly.
Cross-process Flutter restoration requires a `SeekoKeyCodec` with a stable
namespace and schema version. Decode failures remain observable and follow an
explicit `SeekoRestorationPolicy`; Seeko does not silently reset to zero.

## Verification checklist

- Confirm every target is available at the capability level used by the screen.
- Exercise reverse, horizontal, and RTL directions used by the application.
- Verify user input interrupts programmatic motion as intended.
- Verify controller, group, binding, and coordinator ownership on dispose.
- Verify loader cancellation, revision changes, page/item mount boundaries, and
  dual-axis user interruption when those adapters are enabled.
- Compare notifications, physics, scrollbar, refresh, and restoration behavior
  before removing the previous scrolling package.
