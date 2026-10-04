# Sword trail plan

**Goal:** A smooth, coherent flame trail that preserves the sword blade's actual trajectory. Build and verify the geometry before polishing the effect. Attack timing can be added later.

## 1. Establish a geometry baseline

- In `sword.tscn`, temporarily hide `SwingTrailCore` and `Embers`.
- Give `SwingTrail` a plain, opaque debug material with no noise or glow.
- Record what happens during fast swings, reversals, movement, and camera rotation. Distinguish a jagged outline from surfaces folding over each other.

**Done when:** We can identify geometry defects without transparency or shader effects obscuring them.

## 2. Sample the actual blade motion

- In `extension/src/Sword.zig`, store the world positions of `BladeBase` and `BladeTip` together with a timestamp.
- Retain approximately 0.15–0.25 seconds of history instead of a fixed number of frames; cap sample count to bound memory and upload cost.
- Add a sample when the blade moves or rotates far enough, with a maximum time gap so the trail still updates during slow motion.
- Interpolate between samples to smooth the surface. Interpolation improves the shape but cannot reconstruct movement missed between rendered frames.

**Done when:** Trail length is consistent across frame rates and follows the blade without large straight-edged jumps.

## 3. Build one continuous ribbon

- Generate connected cross-sections from the smoothed base and tip paths.
- Give the mesh continuous UVs: one axis represents age/distance along the trail; the other runs from blade base to tip.
- Preserve the current allocation-free vertex upload and calculate bounds from the generated vertices.
- Inspect with the opaque debug material before adding transparency.

**Done when:** A normal swing produces one continuous surface, not visibly separate quads.

## 4. Deal with folds, not just their appearance

- Detect sharp direction reversals, excessive rotation between sections, and new sections crossing recent sections.
- Trim the history or start a new trail at those points rather than connecting the blade through a fold.
- Test from multiple camera angles: a 3D surface can also overlap in screen space even if it does not intersect in 3D.

**Done when:** Common attack motions do not create doubled-up patches. Arbitrary crossing motion may still require splitting the trail.

## 5. Add the flame appearance

- Render the broad flame and bright core in **one main material pass** instead of drawing the same triangles twice.
- Animate flame detail across the UVs using a small texture flipbook or animated noise; use the texture's alpha to shape the silhouette.
- Fade and erode the tail by sample age. Start with ordinary alpha blending; avoid additive blending on potentially overlapping parts of the main surface.
- Re-enable sparse embers only after the main flame reads as one shape.

**Done when:** The effect looks cohesive without rectangular seams or bright overlap patches.

## 6. Synchronize and validate

- Later, start and stop sampling during the fast part of the sword animation. On stop, let existing samples expire rather than hiding the trail instantly.
- Check fast and slow swings, reversals, player movement, camera movement, and low FPS.
- Adjust lifetime, width, color, and glow only after those cases look stable.

Implement steps 1–3 as the first milestone; do not try to fix geometry issues by adding more shader layers.
