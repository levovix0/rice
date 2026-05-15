import std/algorithm
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

proc toConvexHulls*(poly: Polygon): seq[Polygon] =
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


proc signedArea*(poly: Polygon): float32 =
  ## Positive = CCW (counter-clockwise), negative = CW.
  for i in 0..<poly.len:
    let j = (i + 1) mod poly.len
    result += poly[i].x * poly[j].y - poly[j].x * poly[i].y
  result *= 0.5f32


proc fanStart(poly: Polygon): int =
  ## Returns the vertex index from which GL_TRIANGLE_FAN covers the polygon without artifacts.
  ## For a convex polygon any vertex works; this handles near-degenerate cases from bridging.
  let n = poly.len
  if n < 3: return 0
  let wantPos = signedArea(poly) >= 0
  for i in 0..<n:
    var ok = true
    for k in 1..<n - 1:
      let a = area(poly[i], poly[(i + k) mod n], poly[(i + k + 1) mod n])
      if wantPos and a < 0: ok = false; break
      if not wantPos and a > 0: ok = false; break
    if ok: return i
  return 0

proc rotatePoly(poly: Polygon, start: int): Polygon =
  result = newSeqOfCap[Vec2](poly.len)
  for k in 0..<poly.len:
    result.add poly[(start + k) mod poly.len]


proc bridgeHole*(outer: Polygon, hole: Polygon): Polygon =
  ## Merges hole into outer creating a single simple polygon via a horizontal bridge.
  ## Expects outer to be CCW (positive area) and hole to be CW (negative area).

  # Find the rightmost vertex of the hole
  var mIdx = 0
  for i in 1..<hole.len:
    if hole[i].x > hole[mIdx].x:
      mIdx = i
  let m = hole[mIdx]

  # Find the nearest outer edge hit by a rightward ray from m
  var bestIx = float32.high
  var bestI = -1

  for i in 0..<outer.len:
    let j = (i + 1) mod outer.len
    let a = outer[i]
    let b = outer[j]
    if (a.y <= m.y) != (b.y <= m.y):
      let ix = a.x + (m.y - a.y) / (b.y - a.y) * (b.x - a.x)
      if ix >= m.x and ix < bestIx:
        bestIx = ix
        bestI = i

  if bestI == -1:
    return outer

  let j = (bestI + 1) mod outer.len
  let bridgeIdx = if outer[bestI].x >= outer[j].x: bestI else: j

  result = newSeqOfCap[Vec2](outer.len + hole.len + 2)
  for i in 0..bridgeIdx:
    result.add outer[i]
  for i in 0..<hole.len:
    result.add hole[(mIdx + i) mod hole.len]
  result.add hole[mIdx]
  for i in bridgeIdx..<outer.len:
    result.add outer[i]


proc removeHoles*(contours: seq[Polygon]): seq[Polygon] =
  ## Merges hole contours into their outer polygons via a bridge.
  ## A hole is an inner contour with opposite winding to its enclosing outer (non-zero fill rule).
  ## Inner contours with the same winding as their outer are additive — returned as separate polygons.
  if contours.len <= 1:
    return contours

  var centroids = newSeq[Vec2](contours.len)
  for i, poly in contours:
    var c = vec2(0, 0)
    for v in poly: c += v
    centroids[i] = c / float32(poly.len)

  var areas = newSeq[float32](contours.len)
  for i, poly in contours: areas[i] = abs(signedArea(poly))

  # Find the smallest enclosing polygon for each contour.
  var outerOf = newSeq[int](contours.len)
  for i in 0..<contours.len: outerOf[i] = -1

  for i in 0..<contours.len:
    var bestArea = float32.high
    for j in 0..<contours.len:
      if i == j: continue
      if areas[j] > areas[i] and contours[j].overlaps(centroids[i]):
        if areas[j] < bestArea:
          bestArea = areas[j]
          outerOf[i] = j

  var polys = newSeq[Polygon](contours.len)
  for i in 0..<contours.len: polys[i] = contours[i]

  # True hole = opposite winding to its enclosing outer (non-zero rule: winding cancels to 0).
  # Same winding = additive sub-shape (winding accumulates, area stays filled).
  var isHole = newSeq[bool](contours.len)
  for i in 0..<contours.len:
    if outerOf[i] != -1:
      isHole[i] = signedArea(contours[i]) * signedArea(contours[outerOf[i]]) < 0

  # Ensure outer contours and additive inner contours are CCW for Bayazit
  for i in 0..<contours.len:
    if outerOf[i] == -1 or not isHole[i]:
      if signedArea(polys[i]) < 0:
        polys[i].reverse()

  # Merge each true hole into its outer polygon
  for i in 0..<contours.len:
    if isHole[i]:
      var hole = polys[i]
      if signedArea(hole) > 0:
        hole.reverse()
      polys[outerOf[i]] = bridgeHole(polys[outerOf[i]], hole)

  for i in 0..<contours.len:
    if outerOf[i] == -1 or not isHole[i]:
      result.add polys[i]


proc decomposeConvex*(path: Path, pixelScale: float = 1): seq[Polygon] =
  ## Returns convex polygons covering the filled area of path, holes handled correctly.
  var contours: seq[Polygon]
  for shape in pixiePaths.commandsToShapes(path, true, pixelScale):
    contours.add shape
  for poly in contours.removeHoles():
    for convex in poly.toConvexHulls():
      result.add rotatePoly(convex, fanStart(convex))


proc toMeshes*(
  path: Path,
  pixelScale: float = 1,  # the less pixelScale are, the less points are created for triangulation
): seq[Mesh] =
  ## triangulates path, sends it to GPU; handles holes in contours correctly
  let shapes = pixiePaths.commandsToShapes(path, true, pixelScale)
  for poly in shapes.removeHoles():
    for convexShape in poly.toConvexHulls:
      result.add newMesh(rotatePoly(convexShape, fanStart(convexShape)), GL_TRIANGLE_FAN)


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
      result.add newMesh(rotatePoly(convexShape, fanStart(convexShape)), GL_TRIANGLE_FAN)


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
  var aafb = ctx.newAntialiasedFramebuffer(win.size)

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)


  win.eventsHandler.onRender = proc(e: RenderEvent) =
    ctx.resize(aafb, e.window.size)
    let psh = ctx.push aafb

    glClearColor(0.1, 0.1, 0.1, 1)
    glClear(GL_COLOR_BUFFER_BIT)

    let (vw, vh) = (e.window.size.x, e.window.size.y)

    ctx.viewport = combine(
      scale(2 / vw, -2 / vh),
      translate(-1, 1),
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

    ctx.pop psh
    blit psh
  
  run win


