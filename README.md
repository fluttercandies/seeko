<p align="center">
  <img src="assets/brand/seeko-mark-light.svg" alt="Seeko logo" width="104" height="104">
</p>

<h1 align="center">Seeko</h1>

<p align="center">
  High-performance target navigation and synchronization for Flutter's native scrollables.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/fluttercandies/seeko/actions/workflows/quality.yml"><img src="https://github.com/fluttercandies/seeko/actions/workflows/quality.yml/badge.svg" alt="quality checks"></a>
  <a href="https://github.com/fluttercandies/seeko/actions/workflows/platforms.yml"><img src="https://github.com/fluttercandies/seeko/actions/workflows/platforms.yml/badge.svg" alt="platform compile checks"></a>
  <a href="https://pub.dev/packages/seeko"><img src="https://img.shields.io/pub/v/seeko.svg" alt="pub package"></a>
  <a href="https://pub.dev/packages/seeko/score"><img src="https://img.shields.io/pub/points/seeko" alt="pub points"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

Seeko adds target-aware commands, natural cancellable motion, observable state,
and scalable synchronization while keeping Flutter's `ListView`, `GridView`,
`CustomScrollView`, `PageView`, and `NestedScrollView` in charge of rendering,
physics, semantics, and lifecycle. There is no replacement widget hierarchy to
learn.

## Install

```bash
flutter pub add seeko
```

The package supports Flutter `>=3.27.0` and Dart `>=3.6.0`.

## Quick start

Use `SeekoController` anywhere Flutter accepts a `ScrollController`:

```dart
import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final SeekoController _controller = SeekoController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      itemCount: 100,
      itemBuilder: (context, index) => ListTile(
        title: Text('Message $index'),
      ),
    );
  }

  Future<void> showTheMiddle() async {
    await _controller.animateToTarget(
      ScrollTarget.progress(0.5),
      placement: const ScrollPlacement.nearest(),
    );
  }
}
```

The inherited Flutter pixel APIs remain available when that is all you need:

```dart
_controller.jumpTo(240);
await _controller.animateTo(
  640,
  duration: const Duration(milliseconds: 320),
  curve: Curves.easeOutCubic,
);
```

## Target navigation

`ScrollTarget` makes the destination explicit. Choose the smallest integration
that provides the guarantee your screen needs:

| Need | Use | Guarantee |
| --- | --- | --- |
| Pixels or content progress | `ScrollTarget.offset`, `.progress`, `.edge` | Works with every attached native scrollable |
| A mounted child | `SeekoTag` plus `.key`, `.index`, or `.mounted` | Exact reveal with placement and obstruction handling |
| An unmounted item in a large or variable-height list | `SeekoIndexedSliver` | Layout-aware index/key resolution without building the items in between |

Tag only children that need semantic navigation:

```dart
SeekoTag(
  controller: _controller,
  targetKey: 'message-$index',
  index: index,
  child: Text('Message $index'),
);

final result = await _controller.animateToTarget(
  ScrollTarget.key('message-42'),
  placement: const ScrollPlacement.center(),
);
```

Every target command returns a typed `ScrollResult`. It tells you whether the
target completed exactly, was clamped, was interrupted by the user, is not
loaded, or is unsupported by the current integration. Invalid arguments throw
an `ArgumentError` or `RangeError`; expected runtime outcomes do not disappear
into a silent `Future<void>`.

## Motion and placement

Use `jumpToTarget` for immediate positioning and `animateToTarget` for motion:

```dart
await _controller.animateToTarget(
  ScrollTarget.edge(ScrollEdge.trailing),
  motion: const ScrollMotion.adaptive(),
  placement: const ScrollPlacement.end(),
);
```

Motion policies include adaptive, instant, explicit duration, velocity, and
spring. Placement includes start, center, end, nearest, visible, and exact
target/viewport anchors. An obstruction resolver can keep pinned headers,
keyboard insets, or floating controls out of the effective viewport. A user
drag, wheel event, keyboard action, scrollbar, or accessibility action can
take over an in-flight command.

## Synchronize scrollables

Give each view its own controller and let a group map their logical positions:

```dart
final left = SeekoController();
final right = SeekoController();
final group = ScrollSyncGroup.progress();

group.add(left, id: 'left');
group.add(right, id: 'right');

ListView(controller: left, children: leftChildren);
ListView(controller: right, children: rightChildren);
```

Built-in mappings cover pixels, transaction deltas, normalized progress, viewport
fraction, and semantic anchors. Members can join, leave, mute, or become
offstage at runtime. A group has one leader transaction at a time, so feedback
loops do not accumulate as views are added.

## Common patterns

The same primitives cover the scrolling patterns that normally require custom
coordination code:

- **Category navigation:** tag section headers in the content list and connect
  the category rail with `SeekoSectionCoordinator`. A category tap resolves a
  target; content scrolling updates the active category.
- **Horizontal section tabs:** use a horizontal controller for the tab rail and
  the section coordinator for the vertical content list. Selection and content
  position remain bidirectional.
- **Forms and focus:** `ensureFocusVisible` and
  `ensureFirstFormErrorVisible` reveal the field without hiding it behind a
  keyboard or pinned header.
- **Nested headers:** `SeekoNestedScrollBinding` coordinates an outer
  `NestedScrollView` and its selected inner position.
- **Grids and tables:** `SeekoIndexedGridSliver`, `SeekoTwoDimensionalController`,
  `SeekoTableLayout`, and `SeekoTreeTableController` provide cell/key targets,
  frozen panes, expansion anchoring, and keyboard navigation without replacing
  Flutter's native composition.
- **Pages and open data:** `SeekoPageControllerAdapter` and
  `SeekoOpenScrollAdapter` preserve cancellation, restoration, loading bounds,
  and stable identity for pages, carousels, and bidirectional timelines.

## Observe state

Subscribe only when a screen needs it. State is coalesced to at most one
structurally distinct snapshot per frame:

```dart
ValueListenableBuilder<ScrollSnapshot>(
  valueListenable: _controller.state,
  builder: (context, snapshot, child) {
    return Text(
      '${snapshot.phase.name} · ${(snapshot.progress ?? 0) * 100}%',
    );
  },
);
```

`ScrollSnapshot` exposes logical pixels, extents, progress, phase, velocity,
visible tagged targets, the current anchor, active command, and synchronization
origin. High-frequency raw events are opt-in.

## Performance and boundaries

Seeko keeps optional indexes, observers, and synchronization state out of the
normal controller path. Long-distance navigation uses sparse extent metadata
and does not animate through every intermediate item. Synchronization work is
linear in the number of active members, with one shared transaction rather than
one animation controller per view.

No library can promise a fixed frame rate for arbitrary application code:
expensive item builds, image decoding, shaders, and platform composition still
belong to the app. For an unbuilt child whose extent is unknown, a plain
`ScrollController` cannot derive an exact offset; use an indexed primitive or a
driver with an explicit extent/key contract.

## Migration

- From `scroll_to_index`: replace `AutoScrollController` with
  `SeekoController` and `AutoScrollTag` with `SeekoTag`; inspect the typed
  `ScrollResult`.
- From `linked_scroll_controller`: create one `SeekoController` per view and
  choose the mapping that matches the content domain.
- From `scrollable_positioned_list`: keep a native `CustomScrollView` and use
  `SeekoIndexedSliver` when exact unmounted index/key navigation is required;
  `SeekoTag` is the minimal mounted-target path.

## Example and reference

The [`example`](example/README.md) app contains runnable routes for target navigation,
category rails, horizontal tabs, obstruction-aware forms, grids, nested scroll,
pages, open data, two-dimensional cells, tables, and multi-view synchronization.

```bash
cd example
flutter run -d macos
```

Read the [migration guide](MIGRATION.md), [changelog](CHANGELOG.md),
[contributing guide](CONTRIBUTING.md), [security policy](SECURITY.md),
[code of conduct](CODE_OF_CONDUCT.md), and [brand guide](assets/brand/BRAND.md)
for project-specific details.

## License

Seeko is available under the [MIT License](LICENSE).
