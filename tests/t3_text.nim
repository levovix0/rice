import std/[math, unittest]
import pkg/[siwin, chroma, bumpy]
import pkg/pixie/fonts
import pkg/pixie/paths {.all.} as pixiePaths
import rice
import ./camera


const palette = [
  color(0.95, 0.30, 0.30),
  color(0.30, 0.85, 0.40),
  color(0.30, 0.45, 0.95),
  color(0.95, 0.85, 0.20),
  color(0.90, 0.35, 0.90),
  color(0.25, 0.90, 0.90),
  color(0.95, 0.60, 0.20),
  color(0.60, 0.25, 0.95),
  color(0.50, 0.90, 0.30),
  color(0.90, 0.50, 0.50),
  color(0.30, 0.60, 0.95),
  color(0.95, 0.70, 0.50),
]

type
  DisplayMode = enum
    Solid        ## single GL_TRIANGLES mesh per glyph, white
    Filled       ## one colour per triangle (GL_TRIANGLES)
    TriangleWire ## triangle wireframe (GL_LINE_LOOP per triangle)
    MergedLines  ## polygon outlines after removeHoles (GL_LINE_LOOP)
    RawLines     ## raw commandsToShapes contour outlines (GL_LINE_LOOP)

  GlyphPiece = object
    mesh: Mesh
    colorIdx: int


test "font holes":
  let win = newOpenglWindow(size = ivec2(800, 600))
  loadExtensions()

  let ctx = newDrawContext()
  var aafb = ctx.newAntialiasedFrameBuffer(win.size)

  let typeface = staticRead("data/Roboto-regular.ttf").static.parseTtf()

  let font = newFont(typeface)
  font.size = 80

  let smallerFont = newFont(typeface)
  smallerFont.size = 32

  let fontScale = font.size / typeface.scale
  let ascentPx  = round((typeface.ascent + typeface.lineGap / 2) * fontScale)

  let text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789"
  let arrangement = font.typeset(text, hAlign=CenterAlign, bounds = vec2(800 - 20, 600 - 20))

  var pos = vec3()
  var rot = mat4()
  var zoom = 1'f32

  # --- Precompute meshes for all display modes ---

  const textX      = 5f32
  const textY      = 5f32
  const pixelScale = 1f32

  var solidMeshes    = newSeq[Mesh](arrangement.runes.len)
  var trianglePieces = newSeq[seq[GlyphPiece]](arrangement.runes.len)
  var wirePieces     = newSeq[seq[GlyphPiece]](arrangement.runes.len)
  var mergedPieces   = newSeq[seq[GlyphPiece]](arrangement.runes.len)
  var rawPieces      = newSeq[seq[GlyphPiece]](arrangement.runes.len)

  for i, rune in arrangement.runes:
    let selRect = arrangement.selectionRects[i]
    let bx = textX + selRect.x
    let by = textY + selRect.y + ascentPx

    template toScreen(v: Vec2): Vec2 =
      vec2(bx + v.x * fontScale, by + v.y * fontScale)

    let path = typeface.getGlyphPath(rune)

    # Stage 1: raw subpath contours
    var contours: seq[Polygon]
    for shape in pixiePaths.commandsToShapes(path, true, pixelScale):
      contours.add shape
    for j, contour in contours:
      var poly: Polygon
      for v in contour: poly.add toScreen(v)
      rawPieces[i].add GlyphPiece(mesh: newMesh(poly, GL_LINE_LOOP), colorIdx: j)

    # Stage 2: after removeHoles — holes bridged into outer polygon
    let merged = contours.removeHoles()
    for j, poly in merged:
      var screenPoly: Polygon
      for v in poly: screenPoly.add toScreen(v)
      mergedPieces[i].add GlyphPiece(mesh: newMesh(screenPoly, GL_LINE_LOOP), colorIdx: j)

    # Stages 3 & 4: triangulate each merged polygon, build wire and filled meshes
    var triIdx = 0
    var solidVerts: seq[Vec2]
    for poly in merged:
      let tris = poly.toTriangles()
      var t = 0
      while t + 2 < tris.len:
        let a = toScreen(tris[t])
        let b = toScreen(tris[t + 1])
        let c = toScreen(tris[t + 2])
        # Stage 3: wireframe — one GL_LINE_LOOP per triangle
        wirePieces[i].add GlyphPiece(
          mesh: newMesh([a, b, c], GL_LINE_LOOP),
          colorIdx: triIdx,
        )
        # Stage 4: filled — one GL_TRIANGLES mesh per triangle
        trianglePieces[i].add GlyphPiece(
          mesh: newMesh([a, b, c], GL_TRIANGLES),
          colorIdx: triIdx,
        )
        solidVerts.add [a, b, c]
        inc triIdx
        inc t, 3

    # Solid: single GL_TRIANGLES mesh for the whole glyph
    if solidVerts.len > 0:
      solidMeshes[i] = newMesh(solidVerts, GL_TRIANGLES)

  var mode = Solid

  win.eventsHandler.onKey = proc(e: KeyEvent) =
    if e.pressed and e.key == Key.space:
      mode = DisplayMode((ord(mode) + 1) mod (ord(high(DisplayMode)) + 1))
      redraw e.window

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.resize(aafb, e.size)
    ctx.updateDrawingAreaSize(e.size)

  win.eventsHandler.onRender = proc(e: RenderEvent) =
    ctx.drawInside aafb:
      glClearColor(0.12, 0.12, 0.12, 1)
      glClear(GL_COLOR_BUFFER_BIT)

      let (vw, vh) = (e.window.size.x.float32, e.window.size.y.float32)
      ctx.viewport = combine(
        scale(2f32 / vw, -2f32 / vh, 1/1000),
        translate(-1f32, 1f32),
        translate(pos),
        rot,
        scale(vec3(zoom)),
      )

      case mode
      of Solid:
        for mesh in solidMeshes:
          ctx.fill2dMeshFlat(mesh, color(1, 1, 1))
      of Filled:
        for glyphPieces in trianglePieces:
          for p in glyphPieces:
            ctx.fill2dMeshFlat(p.mesh, palette[p.colorIdx mod palette.len])
      of TriangleWire:
        for glyphPieces in wirePieces:
          for p in glyphPieces:
            ctx.fill2dMeshFlat(p.mesh, palette[p.colorIdx mod palette.len])
      of MergedLines:
        for glyphPieces in mergedPieces:
          for p in glyphPieces:
            ctx.fill2dMeshFlat(p.mesh, palette[p.colorIdx mod palette.len])
      of RawLines:
        for glyphPieces in rawPieces:
          for p in glyphPieces:
            ctx.fill2dMeshFlat(p.mesh, palette[p.colorIdx mod palette.len])

      ctx.drawText(
        pos = vec3(0, -0.7, 0),
        arrangement = typeset(smallerFont, "mode: " & $mode),
        color = color(0.5, 0.5, 1, 1).vec4,
        origin = vec2(0.5, 0),
        transform = ctx.glToViewportMatrix,
      )

      ctx.drawText(
        pos = vec3(0, -0.85, 0),
        arrangement = typeset(smallerFont, "press `space` to switch rendering mode"),
        color = color(0.5, 0.5, 0.5, 1).vec4,
        origin = vec2(0.5, 0),
        transform = ctx.glToViewportMatrix,
      )

  addCameraMovement(win, pos, rot, zoom)

  run win
