import std/[unittest, times, sequtils, random]
import pkg/[siwin, chroma, bumpy, pixie]
import rice
import ./camera

randomize()


test "graph maker":
  type
    Node = object
      pos: Vec3
      name: string
    
    Edge = object
      a, b: int

    Scene = object
      nodes: seq[Node]
      edges: seq[Edge]
  
  
  const rootNode = 0


  let font = staticRead("data/Roboto-regular.ttf").static.parseTtf().newFont
  font.size = 12

  # const angleRand = 0.float32
  const angleRand = (Pi / 16).float32
  const distRand = (1e-4).float32

  proc relaxNodes(nI: int, nodes: var seq[Node], dt: float32, targetDistance: float32) =
    let p = nodes[nI].addr
    var posd = vec3()

    for i, node in nodes:
      if i == nI: continue
      let d =
        if node.pos == p.pos: vec3(
          rand(0'f32..(distRand * dt).float32),
          rand(0'f32..(distRand * dt).float32),
          rand(0'f32..(distRand * dt).float32),
        )
        else: p.pos - node.pos

      let l = d.length
      
      if l < targetDistance:
        posd += d * (targetDistance / l * dt).clamp(0, 1)
    
    posd = combine(
      rotateX(rand(0'f32..(angleRand * dt).float32)),
      rotateY(rand(0'f32..(angleRand * dt).float32)),
      rotateZ(rand(0'f32..(angleRand * dt).float32)),
    ) * posd
    p.pos += posd


  proc relaxEdges(edge: Edge, nodes: var seq[Node], dt: float32, targetLen: float32) =
    const eps = 1e-5
    let a = nodes[edge.a].addr
    let b = nodes[edge.b].addr
    let d = b.pos - a.pos
    let l = d.length
    var posd = vec3()
    
    if l < eps:
      posd = vec3(1, 0, 0).normalize * targetLen * dt
    elif abs(targetLen - l) < eps:
      discard
    else:
      posd = d * ((targetLen - l) / l * dt).clamp(-1, 1)
    
    posd = combine(
      rotateX(rand(0'f32..(angleRand * dt).float32)),
      rotateY(rand(0'f32..(angleRand * dt).float32)),
      rotateZ(rand(0'f32..(angleRand * dt).float32)),
    ) * posd
    
    if edge.a != rootNode: a.pos -= posd
    if edge.b != rootNode: b.pos += posd
  

  proc gravitate(node: var Node, dt: float32) =
    node.pos = node.pos * (1 - dt).clamp(0.5, 1)



  proc relax(scene: var Scene, dt: float32, targetLen: float32 = 0.001, targetDistance: float32 = 1) =
    for i in 0..scene.nodes.high:
      if i == rootNode: continue
      gravitate(scene.nodes[i], dt / 32)
      relaxNodes(i, scene.nodes, dt, targetDistance)
    
    for edge in scene.edges:
      relaxEdges(edge, scene.nodes, dt, targetLen)


  let win = newSiwinGlobals(preferedPlatform=x11).newOpenglWindow()
  loadExtensions()
  
  let ctx = newDrawContext()
  var aafb = newAntialiasedFramebuffer(depth = true)

  var rot = toAngles(vec3(1, 1, 1)).fromAngles()
  var pos = vec3()
  var zoom = 1'f32
  var scene = Scene(
    nodes: Node().repeat(30)
  )

  for i, n in scene.nodes.mpairs:
    n.name = $(i + 1)

  for i in 0..<(scene.nodes.len * 4):
    let i = i div 2
    for _ in 0..<10:
      let edge = Edge(
        a: rand((i - 3).clamp(0, scene.nodes.high)..(i + 3).clamp(0, scene.nodes.high)),
        b: rand((i - 3).clamp(0, scene.nodes.high)..(i + 3).clamp(0, scene.nodes.high)),
      )
      if edge.a != edge.b and edge notin scene.edges:
        scene.edges.add edge
        break


  proc render(e: RenderEvent) =
    glClearColor(0.1, 0.1, 0.1, 1)
    glClearDepth(1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    let (vw, vh) = (e.window.size.x, e.window.size.y)

    ctx.viewport = combine(
      translate(pos),
      rot,
      scale(vec3(zoom)),
      scale(vec3(vh / vw, 1, 1/1000))
    )

    for edge in scene.edges:
      let d = (scene.nodes[edge.b].pos - scene.nodes[edge.a].pos)

      ctx.fillRect(
        rect = rect(0, -0.5, 1, 1),
        color = color(1, 1, 1, 1) * 0.3,
        transform = combine(
          scale(vec3(1, 1/200 / zoom, 0)),
          mat4(
            d.x, d.y, d.z, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
          ),
          translate(scene.nodes[edge.a].pos),
        ),
      )
    
    for node in scene.nodes:
      ctx.fillRect(
        rect = rect(-0.5, -0.5, 1, 1),
        color = color(1, 1, 1, 1),
        transform = combine(
          rot.inverse,
          scale(vec3(1/100 / zoom)),
          translate(node.pos),
        ),
      )

      glDisable(GL_DEPTH_TEST)
      ctx.drawText(
        pos = node.pos,
        arrangement = typeset(font, node.name),
        color = color(1, 1, 1, 1).vec4,
        origin = vec2(0.5, -0.2),
      )
      glEnable(GL_DEPTH_TEST)
  

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)


  win.eventsHandler.onRender = proc(e: RenderEvent) =
    ctx.drawInside aafb: render(e)


  var mpos = vec2()
  win.eventsHandler.onMouseButton = proc(e: MouseButtonEvent) =
    mpos = e.window.mouse.pos


  addCameraMovement(win, pos, rot, zoom)


  win.eventsHandler.onTick = proc(e: TickEvent) =
    if Key.space in e.window.keyboard.pressed:
      let dt = e.deltaTime.inMicroseconds / 10_000_000
      for _ in 0..<10:
        relax(scene, dt)
      redraw win
  
  
  run win

