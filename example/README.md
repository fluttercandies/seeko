# Seeko Example

The example is a production-style capability catalog for the seeko package.
It keeps Flutter's native ListView, CustomScrollView, NestedScrollView,
PageView, and dual-axis scrollables intact while exposing the public Seeko
commands used to target, animate, observe, restore, and synchronize them.

## Run

Run flutter pub get, then flutter run -d macos from this directory.

macOS is the qualification target for runtime, accessibility, Cockpit, and
performance checks. Android, iOS, Web, Windows, and Linux projects are included
for compile compatibility checks.

## Scenarios

- Target navigation: pixel, index, key, mounted, custom, progress, edge,
  placement, cancellation, conflict, boundary, and reduced-motion policies.
- Synchronized views: progress, pixels, delta, viewport fraction, semantic,
  custom mappings, strict/natural physics, leader roles, late join, and
  member failure policies.
- Section coordination: a vertical category rail and a horizontal section-tab
  strip both drive selection from user scrolling and from navigation taps.
- Layout-aware surfaces: cross-sliver targets, indexed grids, nested scrolling,
  snap, focus/form reveal, prefetch hints, asynchronous target loading, and
  restoration codec/fallback.
- Advanced drivers: open bidirectional timeline, PageView + item navigation,
  PageView synchronization, two-dimensional cells, dual-axis synchronization,
  frozen panes, and tree-table keyboard/semantics navigation.

Every route has stable test IDs, semantic labels, deterministic keys, and a
visible typed outcome. Cockpit code lives under example/cockpit/ and is not
imported by production library code.
