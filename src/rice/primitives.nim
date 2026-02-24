import pkg/[bumpy, chroma, vmath, shady]
import ./[gl, transform, contexts, contextutils]


var
  # opengl global variable gl_VertexID, declared as wrong type in shady
  # todo: make a PR
  gl_VertexID: int32


proc fillRect*(ctx: DrawContext, rect: Rect, color: Color, transform: Mat4 = mat4()) =
  let transform = combine(
    scale vec3(rect.w, rect.h, 1),
    translate vec3(rect.x, rect.y, 0),
    transform,
    ctx.viewportToGlMatrix,
  )

  let shader = ctx.makeShader:
    proc vert =
      var ipos {.inp.}: Vec2

      gl_Position = @(transform) * vec4(ipos.xy, vec2(0, 1))
    
    proc frag =
      var glCol {.outGl.}: Vec4
      
      glCol = @(color.vec4)

  ctx.withPushPopIf blendRgbx, color.a != 1:  # todo: think of a better solution for managing the "state" of opengl
    useAndPassUniforms shader
    draw ctx.rect


proc drawLine*(ctx: DrawContext, a, b: Vec3, color: Color, transform: Mat4 = mat4()) =
  let d = b - a
  let transform = combine(
    mat4(
      d.x, d.y, d.z, 0,
      0,   0,   0,   0,
      0,   0,   0,   0,
      0,   0,   0,   1,
    ),
    translate(a),
    transform,
    ctx.viewportToGlMatrix,
  )

  let shader = ctx.makeShader:
    proc vert =
      var t {.inp.}: float32

      gl_Position = @(transform) * vec4(t, 0, 0, 1)
    
    proc frag =
      var glCol {.outGl.}: Vec4
      
      glCol = @(color.vec4)

  ctx.withPushPopIf blendRgbx, color.a != 1:
    useAndPassUniforms shader
    draw ctx.line


proc drawLine*(ctx: DrawContext, a, b: Vec2, color: Color, transform: Mat4 = mat4()) =
  drawLine(ctx, vec3(a.x, a.y, 0), vec3(b.x, b.y, 0), color, transform)


proc fillCircle*(
  ctx: DrawContext,
  radius: float32,
  color: Color,
  center: Vec3 = vec3(),
  normal: Vec3 = vec3(0, 0, 1),
  transform: Mat4 = mat4(),
  pointCount: int = 32,
) =
  let centerTransform = combine(
    translate center,
    transform,
    ctx.viewportToGlMatrix,
  )
  let normalTransform = transform.mat3 * ctx.viewportToGlMatrix.mat3 * normal.toAngles.fromAngles.mat3

  let shader = ctx.makeShader:
    proc vert =
      let pos =
        if gl_VertexID == 0: vec2(0, 0)
        else: vec2(@(radius), 0).rotate((gl_VertexID - 1).float32 * (PI * 2) / @(pointCount.float32))
      let center = @(centerTransform) * vec4(0, 0, 0, 1)
      gl_Position = center + vec4(@(normalTransform) * vec3(pos.x, pos.y, 0), 0)

    proc frag =
      var glCol {.outGl.}: Vec4
      
      glCol = @(color.vec4)
  
  useAndPassUniforms shader
  draw ctx.emptyShape(GL_TRIANGLE_FAN, pointCount + 2)



when isMainModule:
  import std/[times]
  import pkg/[siwin]

  let win = newOpenglWindow()
  opengl.loadExtensions()
  let ctx = newDrawContext()

  var time = 0'f32

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)


  win.eventsHandler.onRender = proc(e: RenderEvent) =
    glClearColor(0.1, 0.1, 0.1, 1)
    glClear(GL_COLOR_BUFFER_BIT)

    let (vw, vh) = (e.window.size.x, e.window.size.y)

    ctx.viewport = combine(
      scale(vec3(2 / vw, -2 / vh, 1)),
      translate(vec3(-1, 1, 0)),
    )

    var rect = rect(vw/2 - 400/2, vh/2 - 200/2, 400, 200)
    ctx.fillRect(
      rect,
      color(1, 0.2, 0.2),
      rotateZ(
        origin = vec3(rect.xy + rect.wh/2, 0),
        angle = time / 4
      ),
    )  #! <----

    let center = vec3(vw/2, vh/2, 0)
    ctx.drawLine(center, center + vec3(100, 0, 0), color(1, 0.6, 0.6))   #! <----
    ctx.drawLine(center, center + vec3(0, 100, 0), color(0.2, 1, 0.2))
    ctx.drawLine(center, center + vec3(0, 0, 100), color(0.2, 0.2, 1))

  win.eventsHandler.onTick = proc(e: TickEvent) =
    time += e.deltaTime.inMicroseconds / 1_000_000
    redraw win
  
  run win

