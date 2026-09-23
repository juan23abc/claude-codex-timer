# App icon artwork

`Logo.png` preserves the user-supplied `claude_codex timer.png`. `AppIcon.png` is the cream-background macOS icon, edited with the built-in image generation tool.

The build resizes `AppIcon.png` into the standard macOS icon representations and packages them as `Resources/AppIcon.icns`. To regenerate manually:

```sh
mkdir -p .build/AppIcon.iconset
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
```

## Rights and attribution

The supplied artwork combines Claude and OpenAI brand symbols. The project's MIT license does not grant rights to third-party trademarks or relicense third-party artwork. Before public distribution, confirm that the included source logo and generated icon may be distributed under the applicable brand terms, or replace them with original artwork. Claude Codex Timer is an independent project and is not endorsed by either provider.

## Image generation prompt

Use case: precise-object-edit
 Asset type: finished macOS app icon, square 1024 by 1024 PNG with transparent outer margins.
 Input image: edit target, the supplied combined terracotta Claude rays / black OpenAI knot / central clock logo.
 Primary request: Make this exact supplied logo the foreground of a polished native Apple-style macOS app icon with a beautiful light cream background.
 Composition: one front-facing icon only. Center the existing logo, uniformly scaled to occupy about 69 percent of the full canvas width and height, with generous comfortable padding inside a rounded-square tile. Preserve the source silhouette, terracotta and black colors, relative proportions, overlapping geometry, and clock hands exactly. Do not redesign or reinterpret the logo. Keep the clock's pale circular face.
 Background: rounded-square squircle tile approximately 90 percent of the canvas, centered, with smoothly rounded corners. Use a restrained smooth warm ivory at the upper left (#FFF9ED) to soft cream (#E9DDC5) at the lower right. Very subtle luminous top edge and delicate soft shadow below the tile for familiar macOS icon depth. Clean satin finish. Outside the tile is genuinely transparent.
 Style: crisp graphic logo over premium subtle cream gradient, clear at small Dock sizes.
 Constraints: single app icon, no text, no extra symbols, no extra clock details, no mockup, no scenery, no checkerboard rendered into the background. Preserve the logo faithfully; change only background and fit/padding.

## Refinement prompt

Use case: precise-object-edit
 Edit target: supplied cream rounded-square app icon.
 Make one targeted cleanup: give the icon a flawlessly clean smooth transparent silhouette, removing every stray white fleck, haze, or speck outside the rounded-square tile. Outside the icon must be truly transparent alpha zero, including the corners. The tile interior must be fully opaque. Keep a very small smooth soft drop shadow immediately below the tile only.
 Keep the logo's silhouette, scale, central clock, terracotta and black colors, cream gradient, tile position and rounded corners unchanged. Retain the gentle upper highlight but soften the chunky lower bevel so the overall result is a tasteful native macOS app icon with understated depth. Crisp premium finish. Square PNG, preferably 1024 by 1024. No mockup or text.
