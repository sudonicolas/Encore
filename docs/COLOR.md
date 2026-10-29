# Colour

Encore's colour follows three rules:

1. **Native first.** Inside the app, almost everything uses macOS's own colours: label
   and secondary label, materials, the user's accent colour for selection, and the
   system's orange, red and green for status. Encore should feel like part of the Mac,
   not a skin on it.
2. **One accent, used for one thing.** The only colour Encore adds is the *sparkle*,
   Apple blue fading into a muted pastel lavender. It marks what Apple Intelligence
   wrote (smart titles, writing-tools results) and nothing else, so it keeps its meaning.
3. **One ground, outside the app.** The icon's field is bordeaux: a deep, desaturated
   red, lighter at the top and darker at the bottom. The App Store backdrops are
   warm, sun-baked earth: sand deepening to clay. Neither ever shows inside the app's UI.

## Why these colours

- **Complementary temperature, low saturation.** Bordeaux, clay and sand (OKLCH hue
  about 20–78°) sit opposite blue and lavender (about 255–300°) on the colour wheel.
  Placing complements side by side makes each look more vivid (simultaneous contrast),
  so the "Apple Intelligence" accent stands out on the App Store's sand without needing
  much saturation. That keeps the palette calm.
- **Chroma is kept low.** The previous indigo field ran at OKLCH chroma 0.19–0.23, close
  to the most saturated violet sRGB can show. The new field is 0.03–0.09, and the accent
  0.07–0.17, at its bluest where it needs to read as Apple blue. Research on emotional
  response to colour (Valdez & Mehrabian, 1994) links saturation with arousal and
  lightness with pleasantness. Light, low-chroma earth tones read as warm and relaxed
  rather than loud.
- **Warm neutrals feel analogue.** Bordeaux, sand, clay and umber recall leather
  bindings, paper, pottery and wood: fitting for an app about things you keep.
- **Blue and lavender say "intelligence" the way macOS does.** Apple Intelligence's own
  glow runs through blue and purple, so the sparkle is recognisable without imitating it.

## The mark

A circular **e**, cream on bordeaux. Its crossbar runs through the centre of the circle,
and its lower arc runs on past the bowl into a right-angle arrowhead: **e** for Encore, and
the arrow of a copy coming back round, an encore. One shape, two readings, and nothing
else in it.

It is built from the circle, so every part lines up with every other:

- **True circle.** The ring is a real circle (no oval, no optical bulge), centred on the
  icon's centre, with the crossbar through its middle.
- **Arrowhead from the arc.** The lower arc runs to 45° and carries on straight along its
  own tangent, so the join is seamless and the arrow points exactly up and to the right.
  The head is a right angle with one horizontal and one vertical leg of equal length.
- **A square ink box.** The vertical leg ends flush with the bottom of the circle and the
  arrow's right edge stays inside the ring's, so the mark's ink box is an exact square.
- **One stroke of air.** The gap between the crossbar and the arrow's horizontal leg is the
  same thickness as the stroke. At the heaviest menu bar weights the arrow can only clear
  the crossbar.

The icon and the menu bar symbols are generated from that one geometry by
`tools/make-mark.py`, so they cannot drift apart.

- **Drawn, not borrowed.** The previous icons were a stack of document cards and, before
  this, a letter E. The menu bar glyph was SF Symbols' `rectangle.stack`. Stacked sheets
  are Apple's own vocabulary (`doc.on.doc` is Apple's clipboard in Spotlight), and a system
  symbol is by definition not a logo. A letterform is outside that vocabulary entirely —
  Apple ships no letter icons — so there is nothing for it to be confused with. See
  [`APP_STORE.md`](APP_STORE.md) on guideline 5.2.5.
- **No sparkle.** Sparkles are everywhere now. The Apple Intelligence features are
  something Encore does, not what it is.
- **The same shape everywhere.** The menu bar glyph is Encore's own SF Symbol,
  `encore.mark` in `Resources/Assets.xcassets`, built from the template SF Symbols
  exports and compiled into the app's `Assets.car` alongside the icon. It is the icon's
  mark redrawn as outlines at SF Symbols' stroke weights and optical size (ink 15 × 15 pt
  at 14 pt, in family with `rectangle.stack` at 14.88 × 16 and `square.and.arrow.down` at
  12.88 × 14.62), so it sits beside system glyphs rather than shouting over them. All nine
  weight/scale variants are generated, so it tracks the user's menu bar text weight like
  any system symbol. When a copy is recorded it flashes to `encore.mark.fill`, a heavier
  form — the menu bar briefly showing the app icon's own mark.
- **Flat, like ink.** The mark is not Liquid Glass: it is drawn in solid cream, so it
  reads as a printed letter on a bordeaux binding rather than a lit object, and holds its
  shape at any size.
- **Legible small.** The counters are a full stroke wide, so the bowl and the arrow stay
  open at 32 px in Launchpad and at 16 pt in the menu bar.
- **Unique by colour.** Cream on bordeaux. Almost nothing on the Mac is deep red, so it's
  easy to pick out in the Dock, Launchpad and the App Store.

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
| Icon field | bordeaux `#6E1C2D` → deep bordeaux `#501120` (Display P3) |
| Icon mark | cream `#F8F3EA`, flat (no glass), neutral shadow |
| Icon mark geometry | circle of ink radius 280 centred on 1024, stroke 60 (21%) |
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
neutral grey on purpose: no brown, no ripple, no glow, so the bordeaux icon and the desktop
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
