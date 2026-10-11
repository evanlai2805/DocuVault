# DocuVault design system

Reference: Flighty 4.11 (iOS 26). Follow it tightly. Light theme only.

## Type — SF Pro, system font, no custom fonts
| Role | Spec |
|---|---|
| Screen title | `.largeTitle` bold, 34pt, tracking −0.4, left aligned, sits on the white sheet |
| Hero headline (onboarding / what's new) | 48pt bold, line height 1.05 |
| Card title | 22pt semibold, UPPERCASE, `fontWidth(.condensed)`, tracking +0.5 |
| Card sub-label | 13pt medium, UPPERCASE, condensed, tracking +1.0, 70% white |
| Stat label | 15pt medium, UPPERCASE, condensed, tracking +1.0, 70% white |
| Stat value | 44pt bold, rounded numerals off (default SF), −1 tracking |
| Stat footnote | 17pt regular, 70% white |
| Row title | 20pt semibold |
| Row subtitle | 17pt regular, secondary grey |
| Section header | 15pt regular, UPPERCASE, tracking +0.5, secondary grey |
| Chip | 20pt medium |
| Button in card | 20pt medium, white |
| Empty state title | 24pt semibold, secondary grey; subtitle 20pt regular, secondary grey |

## Colour
| Token | Value | Use |
|---|---|---|
| sheet | #FFFFFF | main surface |
| canvas | #F2F2F7 | behind lists (iOS systemGroupedBackground) |
| ink | #000000 | titles |
| ink2 | #8A8A8E | secondary text (iOS secondaryLabel) |
| hairline | #E5E5EA | chip borders, separators |
| accent | #2F6BFF | selected tab, links, primary button |
| navy-card | linear 160° #1B0F55 → #163C8C | Library / document stat card |
| red-card | linear 160° #5B0E0E → #8E1F1F | warnings, expiring, delays |
| green-card | linear 160° #0C4A2E → #1B7F4C | verified / vault OK |
| graphite-card | linear 160° #1C1C1E → #3A3A3C | neutral / OCR |
| lavender-tint | bg #F4EEFC · border #DCCFF3 · text #6E2FC4 | PRO-style banners, hints |
| card-inset-button | white 14% fill, 16pt radius | "All … Stats >" rows inside cards |

## Shape & spacing
- Sheet top radius 40. Sheet sits over a soft gradient header (we have no map; use a blurred colour wash from the document's card colour).
- Cards: radius 28, padding 24, full width minus 16 side gutter, 16 between cards.
- Circular glass buttons 56pt, hairline border, white 90% fill, SF Symbol 24pt regular.
- Chips: height 44, horizontal padding 20, radius 22, white fill, hairline border when selected; unselected is text only in ink2.
- Rows: 48pt leading icon, 16 gap, 72pt row height, no separators between the top action rows; thin separators in lists.
- Search field: height 64, radius 20, fill #F2F2F7, 22pt placeholder in ink2.
- Tab bar: native iOS 26 `TabView` with a `Tab(role: .search)` — floating pill + separate circular search.

## Motion
- Sheet appears with spring (response 0.45, damping 0.85).
- Card buttons press to 0.98 scale.

## Rules
- All category and label text in English.
- Numbers in stat cards use `.monospacedDigit()`.
- No dark theme. No heavy grey body text: body is ink; only secondary lines use ink2.
