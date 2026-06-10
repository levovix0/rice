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

proc signedArea(poly: Polygon): float32 =
  ## Positive for counter-clockwise, negative for clockwise.
  for i in 0..<poly.len:
    let j = (i + 1) mod poly.len
    result += poly[i].x * poly[j].y - poly[j].x * poly[i].y
  result *= 0.5


proc fanTriangulate(poly: Polygon, result: var seq[Vec2]) =
  ## Converts a (convex or semi-convex) polygon into GL_TRIANGLES points
  let n = poly.len
  # After bridging holes, the polygon may have a "dent" at the bridge seam, so
  # fanning from vertex 0 can produce wrongly-wound triangles. Find the first
  # vertex from which every fan triangle has the same sign as the polygon area.
  let wantPos = signedArea(poly) >= 0
  var start = 0
  block findStart:
    for i in 0..<n:
      var ok = true
      for k in 1..<n - 1:
        let a = area(poly[i], poly[(i + k) mod n], poly[(i + k + 1) mod n])
        if wantPos and a < 0: ok = false; break
        if not wantPos and a > 0: ok = false; break
      if ok: start = i; break findStart
  for i in 1..<n - 1:
    result.add poly[start]
    result.add poly[(start + i) mod n]
    result.add poly[(start + i + 1) mod n]

proc decompose(poly: Polygon, result: var seq[Vec2]) =
  ## Bayazit decomposition emitting GL_TRIANGLES vertices directly
  ## https://github.com/Crackshell/bayazit.h
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

  fanTriangulate(poly, result)

proc toTriangles*(poly: Polygon): seq[Vec2] =
  ## Triangulates an arbitrary polygon, returns GL_TRIANGLE vertex list (3 vertices per triangle)
  if poly.len < 3: return
  decompose(poly, result)


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


proc toMesh*(
  path: Path,
  pixelScale: float = 1,
): Mesh =
  ## triangulates path into a single GL_TRIANGLES mesh; handles holes correctly
  var verts: seq[Vec2]
  for poly in pixiePaths.commandsToShapes(path, true, pixelScale).removeHoles():
    verts.add poly.toTriangles()
  if verts.len > 0:
    result = newMesh(verts, GL_TRIANGLES)


proc toStrokeMesh*(
  path: Path,
  strokeWidth: float32 = 1.0,
  lineCap = ButtCap,
  lineJoin = MiterJoin,
  miterLimit: float32 = defaultMiterLimit,
  dashes: seq[float32] = @[],
  pixelScale: float = 1,
): Mesh =
  ## triangulates stroke of the path into a single GL_TRIANGLES mesh
  var verts: seq[Vec2]
  for shape in pixiePaths.strokeShapes(path.commandsToShapes(true, pixelScale), strokeWidth, lineCap, lineJoin, miterLimit, dashes, pixelScale):
    verts.add shape.toTriangles()
  if verts.len > 0:
    result = newMesh(verts, GL_TRIANGLES)


proc fill2dMeshFlat*(
  ctx: DrawContext,
  mesh: Mesh,
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
  draw mesh


proc fillPath*(
  ctx: DrawContext,
  path: Path,
  color: Color,
  transform = mat4(),
  pixelScale: float = 1,
) =
  fill2dMeshFlat(ctx, path.toMesh(pixelScale), color, transform)


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
  fill2dMeshFlat(ctx, path.toStrokeMesh(strokeWidth, lineCap, lineJoin, miterLimit, dashes, pixelScale), color, transform)



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


