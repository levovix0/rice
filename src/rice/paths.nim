import std/[algorithm, tables]
import pkg/[bumpy, chroma, vmath]
import pkg/pixie/paths {.all.} as pixiePaths
import ./[gl, contexts]

export pixiePaths.WindingRule


type
  ScanEdge = object
    a, b: Vec2      # a.y < b.y always
    winding: int32  # +1 if the contour ran downward (a -> b), -1 if upward


proc cross2(a, b: Vec2): float32 =
  a.x * b.y - a.y * b.x

proc xAt(e: ScanEdge, y: float32): float32 =
  let t = clamp((y - e.a.y) / (e.b.y - e.a.y), 0, 1)
  e.a.x + (e.b.x - e.a.x) * t


proc triangulate*(polygons: openarray[Polygon], windingRule = NonZero): seq[Vec2] =
  ## Triangulates a set of closed contours into a single list of non-overlapping
  ## GL_TRIANGLES vertices (3 per triangle) using a scanline (trapezoidal) decomposition.
  ##
  ## Contours are arbitrary: they may self-intersect, intersect each other, share no
  ## vertices, fully or partially overlap. The filled region is defined by the winding
  ## rule, so with NonZero overlapping same-winding contours are united and an
  ## opposite-winding contour is subtracted (cuts a hole), even when its edges cross
  ## edges of other contours.

  # 1. Collect non-horizontal edges (horizontal edges never change scanline winding).
  var edges: seq[ScanEdge]
  var pmin = vec2(float32.high, float32.high)
  var pmax = vec2(-float32.high, -float32.high)
  for poly in polygons:
    for i in 0 ..< poly.len:
      let p = poly[i]
      let q = poly[(i + 1) mod poly.len]
      pmin = min(pmin, p)
      pmax = max(pmax, p)
      if p.y < q.y:
        edges.add ScanEdge(a: p, b: q, winding: 1)
      elif p.y > q.y:
        edges.add ScanEdge(a: q, b: p, winding: -1)
  if edges.len == 0: return

  let eps = max(max(pmax.x - pmin.x, pmax.y - pmin.y) * 1e-6, 1e-12)

  # 2. Split edges at every pairwise crossing, so that inside any horizontal slab
  #    the left-to-right order of edges is the same along the slab's whole height.
  #    Both sub-edges of a pair share the exact same split point.
  var cuts = newSeq[seq[(float64, Vec2)]](edges.len)
  for i in 0 ..< edges.len:
    let (ia, ib) = (edges[i].a, edges[i].b)
    for j in i + 1 ..< edges.len:
      let (ja, jb) = (edges[j].a, edges[j].b)
      if ia.y > jb.y or ja.y > ib.y: continue
      if max(ia.x, ib.x) < min(ja.x, jb.x) or max(ja.x, jb.x) < min(ia.x, ib.x): continue

      let d1x = (ib.x - ia.x).float64
      let d1y = (ib.y - ia.y).float64
      let d2x = (jb.x - ja.x).float64
      let d2y = (jb.y - ja.y).float64
      let denom = d1x * d2y - d1y * d2x
      # parallel and collinear-overlapping edges need no split: within a slab they
      # stay at the same x, the span between them is degenerate and gets dropped
      if abs(denom) < 1e-12: continue

      let wx = (ja.x - ia.x).float64
      let wy = (ja.y - ia.y).float64
      let t = (wx * d2y - wy * d2x) / denom
      let u = (wx * d1y - wy * d1x) / denom

      const pe = 1e-6
      if t < -pe or t > 1 + pe or u < -pe or u > 1 + pe: continue
      let p = vec2((ia.x.float64 + d1x * t).float32, (ia.y.float64 + d1y * t).float32)
      if t > pe and t < 1 - pe: cuts[i].add (t, p)
      if u > pe and u < 1 - pe: cuts[j].add (u, p)

  var splitEdges: seq[ScanEdge]
  for i in 0 ..< edges.len:
    if cuts[i].len == 0:
      splitEdges.add edges[i]
    else:
      cuts[i].sort proc(x, y: (float64, Vec2)): int = cmp(x[0], y[0])
      var prev = edges[i].a
      for (_, p) in cuts[i]:
        if p.y > prev.y:
          splitEdges.add ScanEdge(a: prev, b: p, winding: edges[i].winding)
          prev = p
      if edges[i].b.y > prev.y:
        splitEdges.add ScanEdge(a: prev, b: edges[i].b, winding: edges[i].winding)

  # 3. Horizontal slabs between consecutive distinct y's of all edge endpoints.
  #    Every edge either fully spans a slab or doesn't reach its midline at all.
  var ys = newSeqOfCap[float32](splitEdges.len * 2)
  for e in splitEdges:
    ys.add e.a.y
    ys.add e.b.y
  ys.sort()
  var slabs = @[ys[0]]
  for y in ys:
    if y - slabs[^1] > eps: slabs.add y
  if slabs.len < 2: return

  let epsArea2 = eps * eps * 2  # cross2 is twice the triangle area

  template emitTrapezoid(li, ri: int, ty, by: float32) =
    let le = splitEdges[li]
    let re = splitEdges[ri]
    let lt = vec2(le.xAt(ty), ty)
    let rt = vec2(re.xAt(ty), ty)
    let lb = vec2(le.xAt(by), by)
    let rb = vec2(re.xAt(by), by)
    # a side narrower than float32 rounding noise is a single point
    # (e.g. a wedge between two edges meeting at their crossing) -> one triangle
    let topPoint = abs(rt.x - lt.x) < eps
    let botPoint = abs(rb.x - lb.x) < eps
    if not topPoint and abs(cross2(rt - lt, rb - lt)) > epsArea2:
      result.add lt
      result.add rt
      result.add rb
    if not botPoint and abs(cross2(rb - lt, lb - lt)) > epsArea2:
      result.add lt
      result.add rb
      result.add lb

  # 4. Sweep the slabs top to bottom accumulating winding left to right.
  #    A filled span bounded by the same edge pair across consecutive slabs is
  #    merged into one trapezoid (spans: edge pair -> y where the region started).
  var spans: Table[(int, int), float32]
  var active: seq[(float32, float32, int)]  # (x at slab midline, x at slab bottom, edge index)

  for si in 0 ..< slabs.len - 1:
    let y0 = slabs[si]
    let y1 = slabs[si + 1]
    let midY = (y0 + y1) * 0.5

    active.setLen 0
    for idx, e in splitEdges:
      if e.a.y < midY and e.b.y > midY:
        active.add (e.xAt(midY), e.xAt(y1), idx)
    active.sort proc(a, b: (float32, float32, int)): int =
      result = cmp(a[0], b[0])
      if result == 0: result = cmp(a[1], b[1])

    var newSpans: Table[(int, int), float32]
    var w = 0'i32
    for k in 0 ..< max(active.len - 1, 0):
      w += splitEdges[active[k][2]].winding
      let inside =
        case windingRule
        of NonZero: w != 0
        of EvenOdd: (w and 1) != 0
      if inside:
        let key = (active[k][2], active[k + 1][2])
        newSpans[key] = spans.getOrDefault(key, y0)

    for key, startY in spans:
      if key notin newSpans:
        emitTrapezoid(key[0], key[1], startY, y0)
    spans = newSpans

  for key, startY in spans:
    emitTrapezoid(key[0], key[1], startY, slabs[^1])


proc triangulate*(poly: Polygon, windingRule = NonZero): seq[Vec2] =
  ## Triangulates an arbitrary (possibly self-intersecting) polygon,
  ## returns GL_TRIANGLES vertex list (3 vertices per triangle)
  triangulate([poly], windingRule)


proc toMesh*(
  path: Path,
  pixelScale: float = 1,
  windingRule = NonZero,
): Mesh =
  ## triangulates path into a single GL_TRIANGLES mesh of non-overlapping triangles;
  ## handles holes, unions and subtractions of arbitrarily intersecting contours
  let verts = triangulate(pixiePaths.commandsToShapes(path, true, pixelScale), windingRule)
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
  ## triangulates stroke of the path into a single GL_TRIANGLES mesh;
  ## overlapping stroke pieces are united, so translucent strokes don't double-blend
  let shapes = pixiePaths.strokeShapes(
    path.commandsToShapes(true, pixelScale),
    strokeWidth, lineCap, lineJoin, miterLimit, dashes, pixelScale
  )
  let verts = triangulate(shapes, NonZero)
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
  windingRule = NonZero,
) =
  fill2dMeshFlat(ctx, path.toMesh(pixelScale, windingRule), color, transform)


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
