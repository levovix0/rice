import pkg/[bumpy, chroma, vmath]
import pkg/pixie/paths {.all.} as pixiePaths
import ./[gl, contexts]


proc area(a, b, c: Vec2): float =
  (b.x - a.x)*(c.y - a.y) - (b.y - a.y)*(c.x - a.x)

proc leftOn(a, b, c: Vec2): bool = area(a, b, c) >= 0
proc right(a, b, c: Vec2): bool = area(a, b, c) < 0
proc rightOn(a, b, c: Vec2): bool = area(a, b, c) <= 0

proc sqdist(a, b: Vec2): float =
  (a.x - b.x)^2 + (a.y - b.y)^2

proc isReflex(poly: Polygon, i: int): bool =
  let
    prev = poly[(i - 1 + poly.len) mod poly.len]
    curr = poly[i]
    next = poly[(i + 1) mod poly.len]
  right(prev, curr, next)

proc segmentsIntersect(a, b, c, d: Vec2): bool =
  if max(a.x,b.x) < min(c.x,d.x): return false
  if max(c.x,d.x) < min(a.x,b.x): return false
  if max(a.y,b.y) < min(c.y,d.y): return false
  if max(c.y,d.y) < min(a.y,b.y): return false

  area(a,b,c) * area(a,b,d) <= 0 and
  area(c,d,a) * area(c,d,b) <= 0

proc canSee(poly: Polygon, i, j: int): bool =
  let
    a = poly[i]
    b = poly[j]

  if isReflex(poly, i):
    if (
      leftOn(poly[i], poly[(i-1+poly.len) mod poly.len], poly[j]) and
      rightOn(poly[i], poly[(i+1) mod poly.len], poly[j])
    ):
      return false
  else:
    if (
      rightOn(poly[i], poly[(i+1) mod poly.len], poly[j]) or
      leftOn(poly[i], poly[(i-1+poly.len) mod poly.len], poly[j])
    ):
      return false

  if isReflex(poly, j):
    if (
      leftOn(poly[j], poly[(j-1+poly.len) mod poly.len], poly[i]) and
      rightOn(poly[j], poly[(j+1) mod poly.len], poly[i])
    ):
      return false
  else:
    if (
      rightOn(poly[j], poly[(j+1) mod poly.len], poly[i]) or
      leftOn(poly[j], poly[(j-1+poly.len) mod poly.len], poly[i])
    ):
      return false

  for k in 0..<poly.len:
    let k1 = (k + 1) mod poly.len
    if k == i or k1 == i or k == j or k1 == j:
      continue
    if segmentsIntersect(a, b, poly[k], poly[k1]):
      return false

  return true

proc slice(poly: Polygon, i, j: int): (Polygon, Polygon) =
  var p1, p2: Polygon

  var k = i
  while true:
    p1.add(poly[k])
    if k == j: break
    k = (k + 1) mod poly.len

  k = j
  while true:
    p2.add(poly[k])
    if k == i: break
    k = (k + 1) mod poly.len

  (p1, p2)

proc isConvex(poly: Polygon): bool =
  for i in 0..<poly.len:
    if isReflex(poly, i):
      return false
  return true

proc decompose(poly: Polygon, result: var seq[Polygon]) =
  for i in 0..<poly.len:
    if isReflex(poly, i):
      var bestJ = -1
      var bestDist = float.high

      for j in 0..<poly.len:
        if canSee(poly, i, j):
          let d = sqdist(poly[i], poly[j])
          if d < bestDist:
            bestDist = d
            bestJ = j

      if bestJ != -1:
        let (p1, p2) = slice(poly, i, bestJ)
        decompose(p1, result)
        decompose(p2, result)
        return

  result.add(poly)

proc toConvexHulls(poly: Polygon): seq[Polygon] =
  ## splits polygon of arbitrary shape into pieces, drawable corretly via GL_TRIANGLE_FAN
  ## uses Bayazit algorithm https://github.com/Crackshell/bayazit.h
  result = @[]
  if poly.len < 3: return
  if isConvex(poly): return @[poly]
  decompose(poly, result)


proc toConvexHulls*(
  path: Path,
  pixelScale: float = 1,  # the less pixelScale are, the less points are created for triangulation
): seq[Polygon] =
  ## triangulates path on CPU
  for shape in pixiePaths.commandsToShapes(path, true, pixelScale):
    result.add shape.toConvexHulls

proc toConvexHullsStroke*(
  path: Path,
  strokeWidth: float32,
  lineCap: LineCap,
  lineJoin: LineJoin,
  miterLimit: float32 = defaultMiterLimit,
  dashes: seq[float32] = @[],
  pixelScale: float = 1,  # the less pixelScale are, the less points are created for triangulation
): seq[Polygon] =
  ## triangulates stroke of the path on CPU
  for shape in pixiePaths.strokeShapes(path.commandsToShapes(true, pixelScale), strokeWidth, lineCap, lineJoin, miterLimit, dashes, pixelScale):
    result.add shape.toConvexHulls


proc toMeshes*(
  path: Path,
  pixelScale: float = 1,  # the less pixelScale are, the less points are created for triangulation
): seq[Mesh] =
  ## triangulates path, sends it to GPU
  let shapes = pixiePaths.commandsToShapes(path, true, pixelScale)
  for shape in shapes:
    for convexShape in shape.toConvexHulls:
      result.add newMesh(convexShape, GL_TRIANGLE_FAN)


proc toStrokeMeshes*(
  path: Path,
  strokeWidth: float32,
  lineCap: LineCap,
  lineJoin: LineJoin,
  miterLimit: float32 = defaultMiterLimit,
  dashes: seq[float32] = @[],
  pixelScale: float = 1,  # the less pixelScale are, the less points are created for triangulation
): seq[Mesh] =
  ## triangulates stroke of the path, sends it to GPU
  let shapes = pixiePaths.strokeShapes(path.commandsToShapes(true, pixelScale), strokeWidth, lineCap, lineJoin, miterLimit, dashes, pixelScale)
  for shape in shapes:
    for convexShape in shape.toConvexHulls:
      result.add newMesh(convexShape, GL_TRIANGLE_FAN)


proc drawWithSolidColor*(
  ctx: DrawContext,
  meshes: openArray[Mesh],
  color: Color,
  transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform

  let shader = ctx.makeShader:
    proc vert =
      var ipos {.inp.}: Vec2

      gl_Position = @(transform) * vec4(ipos.xy, vec2(0, 1))
    
    proc frag =
      var glCol {.outGl.}: Vec4
      
      glCol = @(color.vec4)

  useAndPassUniforms shader
  
  for mesh in meshes:
    draw mesh


proc fillPath*(
  ctx: DrawContext,
  path: Path,
  color: Color,
  transform = mat4(),
  pixelScale: float = 1,
) =
  drawWithSolidColor(ctx, path.toMeshes(pixelScale), color, transform)



proc strokePath*(
  ctx: DrawContext,
  path: Path,
  color: Color,
  transform = mat4(),
  strokeWidth: float32 = 1.0,
  lineCap = ButtCap,
  lineJoin = MiterJoin,
  miterLimit = defaultMiterLimit,
  dashes: seq[float32] = @[],
  pixelScale: float = 1,
) =
  drawWithSolidColor(ctx, path.toStrokeMeshes(strokeWidth, lineCap, lineJoin, miterLimit, dashes, pixelScale), color, transform)



when isMainModule:
  import pkg/[siwin]
  import ./[transform, antialiasing]

  let win = newOpenglWindow()
  opengl.loadExtensions()
  let ctx = newDrawContext()
  var aafb = newAntialiasedFramebuffer()

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)


  win.eventsHandler.onRender = proc(e: RenderEvent) =
    aafb.resize(e.window.size)
    startDraw aafb

    glClearColor(0.1, 0.1, 0.1, 1)
    glClear(GL_COLOR_BUFFER_BIT)

    let (vw, vh) = (e.window.size.x, e.window.size.y)

    ctx.viewport = combine(
      scale(vec3(2 / vw, -2 / vh, 1)),
      translate(vec3(-1, 1, 0)),
    )

    var heart = parsePath """
      M 20 60
      A 40 40 90 0 1 100 60
      A 40 40 90 0 1 180 60
      Q 180 120 100 180
      Q 20 120 20 60
      z
    """

    ctx.fillPath(heart, color(1, 1, 1))  #! <----
    ctx.fillPath(heart, color(1, 1, 1), pixelScale = 1/16, transform = translate vec3(200, 0, 0))  #! <----

    ctx.strokePath(heart, color(1, 1, 1), strokeWidth = 5, transform = translate vec3(400, 0, 0))  #! <----
    ctx.strokePath(heart, color(1, 1, 1), strokeWidth = 5, lineCap=RoundCap, lineJoin=RoundJoin, pixelScale = 1/16, transform = translate vec3(600, 0, 0))  #! <----

    endDraw aafb, 0
    blit aafb, 0
  
  run win


