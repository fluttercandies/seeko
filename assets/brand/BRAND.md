# Seeko Brand Assets

## Mark

The frozen mark is **Synced S Rails**: three equal-width, round-ended rails form an abstract `S`; a solid target point aligns the center rail. The geometry communicates scrolling, multiple synchronized tracks, seeking, and final settlement without borrowing Flutter's diamond mark or another package's iconography.

The mark is intentionally text-free. `Seeko` is a separate wordmark rendered with the platform system sans in product UI.

## Source of truth

- `seeko-logo-source.svg`: canonical 128 × 128 light-surface geometry and palette metadata.
- `seeko-mark-light.svg`: distributable light-surface color variant.
- `seeko-mark-dark.svg`: dark-surface color variant.
- `seeko-mark-monochrome.svg`: single-ink variant for stamps and constrained output.
- `seeko-app-icon.svg`: opaque Deep Ink application field using the same canonical rail geometry.
- `seeko-social-preview.svg`: canonical 1280 x 640 repository and release preview artwork.
- `seeko-social-preview.png`: raster export of the canonical social preview.

All SVGs are pure vectors with no external fonts, linked bitmaps, filters, shadows, or gradients. PNG files are deterministic raster exports, never edited by hand.

## Palette

| Role | Hex | Use |
| --- | --- | --- |
| Seek Mint | `#16C79A` | Target, completion, primary action |
| Motion Blue | `#4C7DFF` | Motion and synchronization |
| Deep Ink | `#07111F` | Dark field and primary ink |
| Cloud | `#F8FAFC` | Light rail and light surface |

Measured WCAG contrast ratios:

- Cloud on Deep Ink: `18.10:1`.
- Seek Mint on Deep Ink: `8.72:1`.
- Motion Blue on Deep Ink: `5.13:1`.
- Cloud on Motion Blue: `3.53:1`, reserved for large/icon geometry, not body text.

## Geometry and clear space

- View box: `128 × 128`.
- Rail stroke: `8`, round caps and joins.
- Target: radius `8` with a `3` unit separation stroke.
- Application-icon artwork stays inside the `20…108` horizontal and `20…109` vertical range, preserving at least `15%` edge clearance and remaining inside common maskable-icon safe regions.
- Minimum standalone size: `16 px`. At this size use the supplied raster export; do not redraw or remove rails.

## Application icon

`seeko-app-icon.svg` is the launcher-icon source for Android, iOS, macOS, Windows, Linux, and Web. The opaque Deep Ink field is deliberate: it keeps the Cloud and Motion Blue rails stable across unknown desktop, Dock, taskbar, and browser backgrounds.

Platform files are generated at their native declared sizes. iOS receives no transparency. Web maskable exports retain the full background field and safe-area geometry. The Windows `.ico` contains multiple embedded resolutions. Linux installs the PNG next to the application bundle data and assigns it to the GTK window.

## Approved usage

- Preserve the original aspect ratio and clear space.
- Use the light, dark, or monochrome variant selected for the actual background.
- Use the application icon only as a square launcher/favicon asset.
- Keep status text alongside color in product UI.

## Prohibited usage

- Do not rotate, skew, outline, add shadows, apply gradients, or recolor individual rails outside the approved palette.
- Do not place the transparent mark on a background that makes any rail fall below `3:1` contrast.
- Do not merge the mark with the Flutter logo or put type inside the icon.
- Do not crop the rail endpoints or move the target point.
- Do not use the launcher square as an inline wordmark when a transparent mark is appropriate.

## Verification

`test/brand_assets_test.dart` verifies required variants and sizes, plus the Deep Ink background and Seek Mint center point in representative platform launcher icons. Platform build and visual checks remain required before release.
