# Nexo Design System (Material 3)

Base principles aligned to current Material Design 3 guidance (Flutter + M3):

## 1) Color roles over hardcoded colors
- Use `Theme.of(context).colorScheme` roles.
- Prefer `surfaceContainer*` for layered surfaces.
- Use `primary/secondary/tertiary` for emphasis hierarchy.

## 2) Material 3 components first
- Navigation: `NavigationBar`
- Actions: `FilledButton` / `FilledButton.tonal`
- Choice: `SegmentedButton`, chips

## 3) Consistent tokens
- Spacing: `tokens/ds_spacing.dart`
- Radius: `tokens/ds_radius.dart`
- Motion: `tokens/ds_motion.dart`
- Typography: `tokens/ds_typography.dart`

## 4) Motion
- Fast: 150ms
- Standard: 250ms
- Emphasized: 380ms

## 5) Accessibility
- Keep high contrast using M3 on-colors.
- Respect minimum tap target and semantic labels.

## 6) Dynamic color (Material You)
- Enabled via `dynamic_color` package.
- App falls back to seeded `ColorScheme.fromSeed` when dynamic color is unavailable.
