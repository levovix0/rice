import std/[math, unittest]
import pkg/[siwin, chroma, bumpy]
import pkg/pixie/fonts
import pkg/pixie/paths {.all.} as pixiePaths
import rice
import ./camera


type
  DisplayMode = enum
    Solid        ## single GL_TRIANGLES mesh per glyph, white
    Filled       ## one colour per triangle (GL_TRIANGLES)
    TriangleWire ## triangle wireframe (GL_LINE_LOOP per triangle)
    RawLines     ## raw commandsToShapes contour outlines (GL_LINE_LOOP)

  GlyphPiece = object
    mesh: Mesh
    colorIdx: int


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


test "font holes":
  let win = newOpenglWindow(size = ivec2(800, 600))
  loadExtensions()

  let ctx = newDrawContext()
  var aafb = ctx.newAntialiasedFrameBuffer(win.size)

  when defined(test_system_font):
    let typeface = staticRead("/usr/share/fonts/TTF/Roboto-Regular.ttf").static.parseTtf()
  else:
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

    # Stages 2 & 3: triangulate all contours at once (holes handled by winding),
    # build wire and filled meshes
    var triIdx = 0
    var solidVerts: seq[Vec2]
    let tris = triangulate(contours)
    var t = 0
    while t + 2 < tris.len:
      let a = toScreen(tris[t])
      let b = toScreen(tris[t + 1])
      let c = toScreen(tris[t + 2])
      # Stage 2: wireframe — one GL_LINE_LOOP per triangle
      wirePieces[i].add GlyphPiece(
        mesh: newMesh([a, b, c], GL_LINE_LOOP),
        colorIdx: triIdx,
      )
      # Stage 3: filled — one GL_TRIANGLES mesh per triangle
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
        translate(pos),
        rot,
        scale(vec3(zoom)),
      )
      ctx.projection = combine(
        scale(2/vw, -2/vh, 1/1000)
      )

      let textTransform = translate(vec3(-vw/2, -vh/2, 0))

      case mode
      of Solid:
        for mesh in solidMeshes:
          ctx.fill2dMeshFlat(mesh, color(1, 1, 1), textTransform)
      of Filled:
        for glyphPieces in trianglePieces:
          for p in glyphPieces:
            ctx.fill2dMeshFlat(p.mesh, palette[p.colorIdx mod palette.len], textTransform)
      of TriangleWire:
        for glyphPieces in wirePieces:
          for p in glyphPieces:
            ctx.fill2dMeshFlat(p.mesh, palette[p.colorIdx mod palette.len], textTransform)
      of RawLines:
        for glyphPieces in rawPieces:
          for p in glyphPieces:
            ctx.fill2dMeshFlat(p.mesh, palette[p.colorIdx mod palette.len], textTransform)

      ctx.drawText(
        pos = ctx.viewportMatrix.inverse * vec3(0, vh/2 - 100, 0),
        arrangement = typeset(smallerFont, "mode: " & $mode),
        color = color(0.5, 0.5, 1, 1).vec4,
        origin = vec2(0.5, 0),
        axisYUp = false,
        transform = ctx.viewportMatrix.mat3.mat4.inverse,
      )

      ctx.drawText(
        pos = ctx.viewportMatrix.inverse * vec3(0, vh/2 - 50, 0),
        arrangement = typeset(smallerFont, "press `space` to switch rendering mode"),
        color = color(0.5, 0.5, 0.5, 1).vec4,
        origin = vec2(0.5, 0),
        axisYUp = false,
        transform = ctx.viewportMatrix.mat3.mat4.inverse,
      )

  addCameraMovement(win, pos, rot, zoom)

  run win
