import std/[unittest, algorithm]
import pkg/[siwin, chroma, bumpy]
import rice
import ./camera


proc almostOverlapsTriangle*(p: Vec2, p1, p2, p3: Vec2, eps = 1e-6): bool =
  let areaX = abs((p2.x - p1.x) * (p3.y - p1.y) - (p3.x - p1.x) * (p2.y - p1.y))
  let area1 = abs((p1.x - p.x) * (p2.y - p.y) - (p2.x - p.x) * (p1.y - p.y))
  let area2 = abs((p2.x - p.x) * (p3.y - p.y) - (p3.x - p.x) * (p2.y - p.y))
  let area3 = abs((p3.x - p.x) * (p1.y - p.y) - (p1.x - p.x) * (p3.y - p.y))
  (area1 + area2 + area3) < areaX + eps




test "triangle union":
  let win = newOpenglWindow()
  loadExtensions()

  let ctx = newDrawContext()
  var aafb = ctx.newAntialiasedFramebuffer(win.size)

  var rot = mat4()
  var pos = vec3(8, 3.5, 0)
  var zoom = 0.15'f32


  type TriCase = object
    a, b: Polygon
    meshA, meshB: Mesh
    unionMesh, subMesh: Mesh
    unionWire, subWire: seq[Mesh]
    offset: Vec3

  proc wireframes(tris: seq[Vec2]): seq[Mesh] =
    var t = 0
    while t + 2 < tris.len:
      result.add newMesh([tris[t], tris[t + 1], tris[t + 2]], GL_LINE_LOOP)
      inc t, 3

  # different mutual arrangements; all triangles wound the same way,
  # so that union works (subtraction reverses b)
  let arrangements = [
    # crossing: a vertex of each triangle is inside the other
    (Polygon @[vec2(0, 0), vec2(1.5, 1), vec2(0, 2)],
     Polygon @[vec2(0.5, 0), vec2(2, 1), vec2(0.5, 2)]),
    # disjoint
    (Polygon @[vec2(0, 0), vec2(0.9, 0.5), vec2(0, 1)],
     Polygon @[vec2(1.1, 1), vec2(2, 1.5), vec2(1.1, 2)]),
    # touching vertex-to-vertex at (1, 1)
    (Polygon @[vec2(0, 0), vec2(1, 1), vec2(0, 2)],
     Polygon @[vec2(1, 1), vec2(2, 0), vec2(2, 2)]),
    # vertex of b lies on an edge of a: (0.75, 0.5) is on (0,0)-(1.5,1)
    (Polygon @[vec2(0, 0), vec2(1.5, 1), vec2(0, 2)],
     Polygon @[vec2(0.75, 0.5), vec2(2, 0.2), vec2(2, 1.2)]),
    # hexagram: edges cross, but no vertex is inside the other triangle
    (Polygon @[vec2(1, 0), vec2(2, 1.73), vec2(0, 1.73)],
     Polygon @[vec2(1, 2.31), vec2(0, 0.58), vec2(2, 0.58)]),
    # b fully inside a
    (Polygon @[vec2(0, 0), vec2(2, 0), vec2(1, 2)],
     Polygon @[vec2(0.7, 0.4), vec2(1.3, 0.4), vec2(1, 1.2)]),
  ]

  var cases: seq[TriCase]
  for i, (a, b) in arrangements:
    var bcw = b
    bcw.reverse()
    let unionTris = triangulate([a, b])
    let subTris = triangulate([a, bcw])
    cases.add TriCase(
      a: a, b: b,
      meshA: newMesh(a, GL_TRIANGLES),
      meshB: newMesh(b, GL_TRIANGLES),
      unionMesh: newMesh(unionTris, GL_TRIANGLES),
      subMesh: newMesh(subTris, GL_TRIANGLES),
      unionWire: wireframes(unionTris),
      subWire: wireframes(subTris),
      offset: vec3(i.float32 * 3, 0, 0),
    )


  proc render(e: RenderEvent) =
    glClearColor(0.1, 0.1, 0.1, 1)
    glClear(GL_COLOR_BUFFER_BIT)

    push_blendRgbx(ctx)

    let (vw, vh) = (e.window.size.x, e.window.size.y)

    ctx.viewport = combine(
      translate(-pos),
      rot,
      scale(vec3(zoom)),
      scale(vec3(vh / vw, -1, 1/1000))
    )

    for c in cases:
      # row 0: source triangles, overlap double-blends; vertices inside the other triangle marked
      ctx.fill2dMeshFlat(c.meshA, color(1, 0.4, 0.4, 0.5), translate(c.offset))
      ctx.fill2dMeshFlat(c.meshB, color(0.4, 0.4, 1, 0.5), translate(c.offset))

      for p in c.a:
        if p.almostOverlapsTriangle(c.b[0], c.b[1], c.b[2]):
          ctx.drawCircle(color(1, 1, 1), radius = 1/20, center = p.vec3(0) + c.offset)
      for p in c.b:
        if p.almostOverlapsTriangle(c.a[0], c.a[1], c.a[2]):
          ctx.drawCircle(color(1, 1, 1), radius = 1/20, center = p.vec3(0) + c.offset)

      # row 1: union — one mesh of non-overlapping triangles,
      # translucent fill stays uniform, no double-blending in the overlap
      let unionOffset = c.offset + vec3(0, 3, 0)
      ctx.fill2dMeshFlat(c.unionMesh, color(0.4, 1, 0.4, 0.5), translate(unionOffset))
      for wire in c.unionWire:
        ctx.fill2dMeshFlat(wire, color(1, 1, 1, 0.5), translate(unionOffset))

      # row 2: subtraction — a minus reversed-winding b
      let subOffset = c.offset + vec3(0, 6, 0)
      ctx.fill2dMeshFlat(c.subMesh, color(1, 1, 0.4, 0.5), translate(subOffset))
      for wire in c.subWire:
        ctx.fill2dMeshFlat(wire, color(1, 1, 1, 0.5), translate(subOffset))

    pop_blendRgbx(ctx)



  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.resize(aafb, e.size)
    ctx.updateDrawingAreaSize(e.size)


  win.eventsHandler.onRender = proc(e: RenderEvent) =
    ctx.drawInside aafb: render(e)


  var mpos = vec2()
  win.eventsHandler.onMouseButton = proc(e: MouseButtonEvent) =
    mpos = e.window.mouse.pos


  addCameraMovement(win, pos, rot, zoom, axisYUp = false)


  run win
