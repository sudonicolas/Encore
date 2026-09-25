# Colour

Encore's colour follows three rules:

1. **Native first.** Inside the app, almost everything uses macOS's own colours: label
   and secondary label, materials, the user's accent colour for selection, and the
   system's orange, red and green for status. Encore should feel like part of the Mac,
   not a skin on it.
2. **One accent, used for one thing.** The only colour Encore adds is the *sparkle*,
   Apple blue fading into a muted pastel lavender. It marks what Apple Intelligence
   wrote (smart titles, writing-tools results) and nothing else, so it keeps its meaning.
3. **Earth underneath.** The brand's ground (the app icon's field and the App Store
   backdrops) is warm, sun-baked earth: sand deepening to clay. It never shows inside
   the app's UI.

## Why these colours

- **Complementary temperature, low saturation.** Clay and sand (OKLCH hue about 45–78°)
  sit opposite blue and lavender (about 255–300°) on the colour wheel. Placing
  complements side by side makes each look more vivid (simultaneous contrast), so the
  "Apple Intelligence" accent stands out on the App Store's sand without needing much
  saturation. That keeps the palette calm.
- **Chroma is kept low.** The previous indigo field ran at OKLCH chroma 0.19–0.23, close
  to the most saturated violet sRGB can show. The new field is 0.03–0.09, and the accent
  0.07–0.17, at its bluest where it needs to read as Apple blue. Research on emotional
  response to colour (Valdez & Mehrabian, 1994) links saturation with arousal and
  lightness with pleasantness. Light, low-chroma earth tones read as warm and relaxed
  rather than loud.
- **Warm neutrals feel analogue.** Sand, clay and umber recall paper, pottery and wood:
  fitting for an app about things you keep.
- **Blue and lavender say "intelligence" the way macOS does.** Apple Intelligence's own
  glow runs through blue and purple, so the sparkle is recognisable without imitating it.

## The icon

A stack of clippings: the newest in front, earlier ones stepping back behind it, each a
little narrower. That's all a clipboard history is, and all the icon needs to say.

- **No sparkle.** Sparkles are everywhere now. The Apple Intelligence features are
  something Encore does, not what it is.
- **Three lines of text** on the front card are the one detail that says "things you
  copied" rather than just "cards". They're still readable at 32 px.
- **The same shape everywhere.** The menu bar glyph is SF Symbols' `rectangle.stack`,
  the icon's silhouette in outline. When a copy is recorded it flashes to
  `checkmark.rectangle.stack.fill`. Apple's own clipboard (in Spotlight) is two sheets
  offset diagonally (`doc.on.doc`); a vertical stack reads as history instead.
- **Unique by material, not ornament.** Liquid Glass cards on a clay field. Very few
  icons on the Mac are terracotta, so it's easy to spot in the Dock, Launchpad and the
  App Store.

## Palette

Values were designed in OKLCH (perceptually uniform) and converted to sRGB / Display P3.

### Sparkle (in the app): `Utilities/Brand.swift`

| Token | Light | Dark | Light, Increase Contrast | Dark, Increase Contrast |
|---|---|---|---|---|
| `Brand.blue` | `#2073D2` | `#6EAFF7` | `#0052B4` | `#A3CCF7` |
| `Brand.lavender` | `#816EAB` | `#CBBAEB` | `#65508E` | `#DDD0F7` |

`Brand.sparkle` is the blue → lavender gradient. With Increase Contrast, glyphs switch to
solid `Brand.blue`, which reads more crisply than a gradient at small sizes. The Apple
Intelligence result card is tinted with 8% lavender.

### Status: `Utilities/StatusColors.swift`

The system's orange, red and green hues, darkened in Light Mode and lightened in Dark
Mode until they're readable. They're unchanged by this redesign. See
[`ACCESSIBILITY.md`](ACCESSIBILITY.md).

### Brand ground (icon and App Store only)

| Role | Colour |
|---|---|
| Icon field | clay `#D4AF90` → terracotta `#B1765B` |
| Icon card text lines | umber `#6D4D3E` at 40% |
| Backdrop field | sand `#F2E6D4` → clay `#DAB69B`, soft lavender glow |
| Backdrop ripple | umber-terracotta `#805138` (`rippleShadow`), white highlight |
| Backdrop headline | ink `#3A2A20` |
| Backdrop subhead | secondary ink `#5C483E` |
| Backdrop eyebrow | deep blue `#1C62B6` → deep lavender `#6B5499` |

The field also carries a ripple: concentric, wobbled rings radiating from the same point
as the Apple Intelligence glow (`RippleField` in `tools/screenshots/Scenes.swift`), each
stroked once in white and once in `rippleShadow` like a crest catching the sun over a
shadowed trough. It exists so Liquid Glass has real texture to refract — a flat two-colour
field barely reads as glass at all. The ripple is masked to zero opacity behind the words
(`Stage.TextZone`), so it never touches the pixels the ratios below were measured against;
only the field's own two colours do.

Four of the five portrait slides (hero, writing tools, lookups, privacy) put light UI on a
**night** ground instead, so the sand desktop and Settings window pop against it. Night is
neutral grey on purpose: no brown, no ripple, no glow, so the clay icon and the desktop
are the only warm things on the slide. The smart-titles slide stays on sand, since its
History window is already dark.

| Role | Colour |
|---|---|
| Night ground | `#1E1E21` → `#101012`, faint white lift behind the words |
| Night headline and body | `#F5F5F7` |
| Night subhead | `#AEAEB2` |
| Night eyebrow and icons | blue `#6EAFF7` → lavender `#CBBAEB` (the sparkle's Dark values) |

## Accessibility

Every pairing was checked with WCAG 2 contrast ratios, with APCA as a second opinion,
against the lightest and darkest surfaces each colour can sit on: white, light glass
(`#E8E8E8`), dark glass (`#3A3A3C`) and near-black (`#1C1C1E`).

| Pairing | Required | Worst case |
|---|---|---|
| Sparkle glyph, Light / Dark | 3:1 (icon) | 3.6:1 / 4.9:1 |
| Sparkle glyph, Increase Contrast | 4.5:1 | 5.5:1 |
| Backdrop headline on field | 4.5:1 | 7.3:1 |
| Backdrop subhead on field | 4.5:1 | 4.5:1 |
| Backdrop eyebrow (large text) | 3:1 | 3.2:1 |
| Night headline and body | 4.5:1 | 13.5:1 |
| Night subhead | 4.5:1 | 6.7:1 |
| Night eyebrow and icons | 3:1 | 6.4:1 |

The night ratios are measured on the rendered slides, against the lightest pixel of the
ground behind the words (`#28282A`, the centre of the lift).

Colour is never the only signal: the sparkle glyph is labelled "Title by Apple
Intelligence" for VoiceOver, and status colours always come with an icon and text.
