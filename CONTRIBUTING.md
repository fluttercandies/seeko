# Contributing to Seeko

Thank you for improving Seeko. Contributions must preserve native Flutter
scroll behavior, typed failure semantics, measurable performance, and the
progressive L1/L2/L3 capability boundary.

## Development prerequisites

- Flutter 3.27.0 or newer for the root package.
- Dart 3.6.0 or newer for the root package.
- Flutter 3.32.0 / Dart 3.8.0 or newer for the independent example and its
  development-only Cockpit shell.
- Melos 6.3.2, resolved from the root `dev_dependencies`.
- Xcode and CocoaPods when building the macOS/iOS example shells.

Resolve the workspace from the repository root:

```bash
flutter pub get
dart run melos list
```

Use `flutter pub get --no-example` when validating only the Flutter 3.27.0
minimum root package with Dart 3.6.0.

## Design boundaries

- Do not add `SeekoListView`, `SeekoGridView`, `SeekoPageView`, or another
  high-level replacement widget family.
- Keep public declarations exported only through `package:seeko/seeko.dart`.
- Unsupported capabilities must return or throw documented typed outcomes;
  never silently report a degraded search as exact.
- One `SeekoController` owns at most one active `ScrollPosition`; use one
  controller per view and coordinate them with a synchronization group.
- Features that are disabled or unused must not add listeners, streams,
  tickers, or allocation to the scroll hot path.
- Do not depend on Flutter private APIs as a public contract.

## Development workflow

Use test-driven development for feature and bug changes:

1. Add the smallest test that demonstrates the desired public behavior.
2. Run it and confirm it fails for the intended reason.
3. Implement the minimal production change.
4. Run the focused test again.
5. Run the full quality suite before requesting review.

Production code must not contain `TODO`, `FIXME`, mock business behavior,
temporary fallbacks, or per-frame debug logging.

## Required quality commands

Run from the repository root:

```bash
dart fix --apply
dart format .
dart analyze
dart run melos run test
dart run melos run benchmark:smoke
dart run melos run example:build:macos
dart pub publish --dry-run
```

All commands must complete with zero errors, warnings, and failures before a
release-oriented change is considered ready.

## Tests

- Pure target, placement, scheduler, extent, motion, restoration, and mapping
  logic belongs in fast root unit/property tests.
- Flutter controller, position, lifecycle, input, notification, and semantics
  behavior belongs in root widget tests.
- Product scenario interactions and responsive UI belong in `example/test`.
- Regressions require a test that fails before the fix.
- Performance work requires both a correctness test and reproducible benchmark
  evidence against the native baseline.

Do not weaken thresholds, exclude a failing test, or remove a supported matrix
entry to make a change pass.

## Example and Cockpit

The production example must not import `flutter_cockpit`. Cockpit integration
lives only under `example/cockpit` and wraps the real public application root.

Each scenario needs:

- A stable route and Flutter keys for meaningful actions and results.
- Deterministic local data rather than a fake remote service.
- Useful semantics, tooltips, keyboard focus, and reduced-motion behavior.
- Visible command outcome and diagnostics without debug logging in production.
- An automated widget test and, when the capability is available, a Cockpit
  black-box journey.

## Performance changes

Explain the expected complexity and allocation behavior in the change
description. For hot-path changes, include:

- Device, OS, display refresh rate, Flutter/engine revision, and build mode.
- Native baseline and Seeko result using the same child tree and seed.
- P50/P95/P99 UI/raster timings, presented-frame ratios, memory, and GC.
- Raw machine-readable result and timeline artifact.

Do not claim 120 Hz qualification from debug/profile tooling, a 60 Hz display,
Cockpit screenshots, or a simulator.

## Documentation

Update English and Chinese README sections together when public behavior,
compatibility, or minimum versions change. Code samples must use real exported
APIs. Mark planned and experimental behavior explicitly.

Update `CHANGELOG.md` for user-visible changes and `MIGRATION.md` for breaking
or replacement-package guidance.

## Commit messages

Use Conventional Commits in English:

```text
feat(sync): add viewport-fraction mapping
fix(example): constrain compact controls sheet
docs: clarify mounted target capability
perf(position): remove tick allocation
```

Keep each commit buildable and fully tested. Do not include unrelated cleanup.

## Reporting security issues

Do not open a public issue for a suspected vulnerability. Follow
[`SECURITY.md`](SECURITY.md).

