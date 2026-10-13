# DocuVault design system

Reference: Flighty 4.11 (iOS 26). Follow it tightly. Light and dark: every token has both values and follows the phone (checkpoint 19).

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
| accent | #3A424C gunmetal (13 Oct, checkpoint 17b; was #2F6BFF); dark #A9B4C2 steel | selected tab, links, field labels, chips. Flat everywhere; the filled buttons (Scan, Unlock, keyboard Open/Done/Back) use the sheen gradient #22282F → #5C6672 → #22282F with a thin top highlight |
| navy-card | linear 160° #1B0F55 → #163C8C | Library / document stat card |
| red-card | linear 160° #5B0E0E → #8E1F1F | warnings, expiring, delays |
| green-card | linear 160° #0C4A2E → #1B7F4C | verified / vault OK |
| graphite-card | linear 160° #1C1C1E → #3A3A3C | neutral / OCR |
| lavender-tint | bg #F4EEFC · border #DCCFF3 · text #6E2FC4 | PRO-style banners, hints |
| card-inset-button | white 14% fill, 16pt radius | "All … Stats >" rows inside cards |

## Layout decisions (Evan, 11 Oct)
- No layered sheet. Regular full-screen views on `canvas`; no colour wash behind.
- Layout follows function. Summary cards appear only where a summary helps (Library header, OCR result, vault alerts). Lists and field tables stay plain.
- Tab bar: two floating glass pills. Left pill: Library · Vault · Settings. Right pill: Scan (left, gunmetal sheen circle) and Search (right, white circle with a black icon, like Photos). Scan and Search are colour-coded so they read at a glance.

## Shape & spacing
- Cards: radius 28, padding 24, full width minus 16 side gutter, 16 between cards.
- Circular glass buttons 56pt, hairline border, white 90% fill, SF Symbol 24pt regular.
- Chips: height 44, horizontal padding 20, radius 22, white fill, hairline border when selected; unselected is text only in ink2.
- Rows: 48pt leading icon, 16 gap, 72pt row height, no separators between the top action rows; thin separators in lists.
- Search field: height 64, radius 20, fill #F2F2F7, 22pt placeholder in ink2.
- Tab bar: custom floating bar (see Layout decisions). Glass material, hairline border, soft shadow.

## Motion
- Sheet appears with spring (response 0.45, damping 0.85).
- Card buttons press to 0.98 scale.

## Rules
- All category and label text in English.
- Numbers in stat cards use `.monospacedDigit()`.
- No dark theme. No heavy grey body text: body is ink; only secondary lines use ink2.

## Text (Evan, 13 Oct)
- Every label, pill, hint and each `·` segment starts with a capital: `Auto: SG region`, `DOB · Format`.
  Exceptions: the keyboard's `space` key, units (`60 s`), file paths, identifiers.
- Dates display as `12/MAR/1990` (`FillFormats.display`, `Date.dvDisplay`). Storage stays ISO.
