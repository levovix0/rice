import std/[math, unittest]
import pkg/[siwin, chroma, bumpy]
import rice


proc circleCircle(cx, cy, r: float32, n = 48): Polygon =
  for i in 0..<n:
    let a = 2f32 * Pi * float32(i) / float32(n)
    result.add vec2(cx + r * cos(a), cy + r * sin(a))


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


test "holes":
  let win = newOpenglWindow(size = ivec2(1000, 540))
  loadExtensions()

  let ctx = newDrawContext()
  var aafb = ctx.newAntialiasedFrameBuffer(win.size)

  # Shape 1: rectangular frame with one square hole
  let frame: seq[Polygon] = @[
    @[vec2(20,20), vec2(280,20), vec2(280,480), vec2(20,480)],    # outer CCW (y-down)
    @[vec2(80,80), vec2(80,230), vec2(220,230), vec2(220,80)],    # upper hole
    @[vec2(80,280), vec2(80,420), vec2(220,420), vec2(220,280)],  # lower hole
  ]

  # Shape 2: annulus — two concentric circles (classic concentric case)
  let annulus: seq[Polygon] = @[
    circleCircle(170, 250, 200, 64),
    circleCircle(170, 250, 110, 48),
  ]

  # Shape 3: B-like — outer contour + two rounded bumps as holes
  let bShape: seq[Polygon] = block:
    # outer: tall rectangle with two rounded right bumps
    var outer: Polygon
    outer.add vec2(20, 20)
    outer.add vec2(100, 20)
    for i in 0..16:
      let a = -Pi/2 + Pi * float32(i) / 16f32
      outer.add vec2(100 + 75 * cos(a), 140 + 120 * sin(a))
    outer.add vec2(100, 260)
    for i in 0..16:
      let a = -Pi/2 + Pi * float32(i) / 16f32
      outer.add vec2(100 + 85 * cos(a), 370 + 110 * sin(a))
    outer.add vec2(100, 480)
    outer.add vec2(20, 480)

    var holeTop: Polygon
    for i in 0..24:
      let a = float32(i) / 24f32 * 2f32 * Pi
      holeTop.add vec2(80 + 50 * cos(a), 140 + 75 * sin(a))

    var holeBot: Polygon
    for i in 0..24:
      let a = float32(i) / 24f32 * 2f32 * Pi
      holeBot.add vec2(75 + 55 * cos(a), 370 + 70 * sin(a))

    @[outer, holeTop, holeBot]

  # Decompose contours → convex pieces with different colors
  proc drawDecomposed(ctx: DrawContext, contours: seq[Polygon], offset: Vec2) =
    let merged = contours.removeHoles()
    var idx = 0
    for poly in merged:
      for convex in poly.toConvexHulls():
        # shift each vertex by offset to place the shape on screen
        var shifted: Polygon
        for v in convex: shifted.add v + offset
        let mesh = newMesh(shifted, GL_TRIANGLE_FAN)
        ctx.drawWithSolidColor([mesh], palette[idx mod palette.len])
        inc idx


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
        scale(2f32 / vw, -2f32 / vh),
        translate(-1f32, 1f32),
      )

      ctx.drawDecomposed(frame, vec2(30, 30))
      ctx.drawDecomposed(annulus, vec2(350, 70))
      ctx.drawDecomposed(bShape, vec2(720, 30))


  run win
