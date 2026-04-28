# Slug Algorithm Reference Notes (from slug-webgpu)

## Data Structures

### Curve Texture (RGBA32Float, width=4096)
- Each curve = 2 texels:
  - Texel 0: (p0x, p0y, p1x, p1y)
  - Texel 1: (p2x, p2y, 0, 0)
- Coordinates are in em-space (font units)

### Band Texture (RGBA32Uint, width=4096)
- Per glyph layout: [hBand headers...] [vBand headers...] [curve index lists...]
- Each header texel: (curveCount, offsetFromGlyphLoc, 0, 0)
- Each curve ref texel: (curveTexX, curveTexY, 0, 0)
- Headers must not straddle row boundaries

### Vertex Attributes (5 x vec4<f32> = 80 bytes/vertex)
- location(0) pos: (objX, objY, normalX, normalY)
- location(1) tex: (emX, emY, packedGlyphLoc, packedBandMax)
  - tex.z = bitcast<f32>((glyphLocY << 16) | glyphLocX)
  - tex.w = bitcast<f32>((bandMaxY << 16) | bandMaxX)
- location(2) jac: (invScale, 0, 0, invScale) — inverse Jacobian
- location(3) bnd: (bandScaleX, bandScaleY, bandOffsetX, bandOffsetY)
- location(4) col: (r, g, b, a)

### Per-glyph quad: 4 vertices + 6 indices (2 triangles)

## Band Organization
- Default bandCount = 8 per axis (horizontal + vertical)
- Curves sorted: h-bands by descending max x, v-bands by descending max y
- Band transform: maps em-space to band indices
  - bandScaleX = vBandCount / width
  - bandScaleY = hBandCount / height
  - bandOffsetX = -xMin * bandScaleX
  - bandOffsetY = -yMin * bandScaleY

## Curve Extraction
- Line segments → degenerate quadratics (with epsilon bow for diagonals)
- Cubic beziers → split at midpoint into 2 quadratics
- stbtt_vertex types: vmove=1, vline=2, vcurve=3, vcubic=4

## Vertex Shader
- Uses SlugDilate for sub-pixel dilation
- Uses SlugUnpack to extract glyph/band info from packed tex.zw
- MVP matrix in uniform buffer

## Fragment Shader
- SlugRender: main rendering function
- Processes horizontal bands then vertical bands
- CalcRootCode: determines which roots contribute
- SolveHorizPoly/SolveVertPoly: solve quadratic for ray intersections
- CalcCoverage: combines x/y coverage with weights
- Override constants: SLUG_EVENODD, SLUG_WEIGHT

## Simplified Nebula Adaptation Plan
For Nebula's Phase 4.1, we simplified the reference implementation:
1. S0: Use stbtt_GetGlyphShape to extract curves, pack into Nelua arrays
2. S1: Generate simplified WGSL (no dilation, orthographic projection)
3. S2: NebulaSlugVertex with 4 attributes (pos, tex, bnd, col) — skip jac for now
4. Use Storage Buffers instead of textures for curve/band data (simpler in WebGPU)

## Phase 4.2.2 Upgrades (D-4.1-A / D-4.1-B cleared)
1. **D-4.1-A**: Adaptive band count (4/8/16 based on curve density) + FNV-1a hash merging of equivalent adjacent bands. Per-glyph `h_band_count`/`v_band_count` fields replace global `BAND_COUNT=8`.
2. **D-4.1-B**: NebulaSlugVertex expanded to 5 x vec4<f32> (80 bytes/vertex). New `jac` attribute carries inverse Jacobian for affine transform support. `slug_dilate` function added to WGSL for sub-pixel dilation compensation.
3. **D-4.1-C**: Storage Buffer vs texture benchmark deferred to Phase 4.2.3 decision gate.
