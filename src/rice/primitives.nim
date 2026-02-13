import pkg/[bumpy, chroma, vmath, shady]
import ./[gl, transform, contexts, contextutils]



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
      var gl_Position {.outGl.}: Vec4

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
      var gl_Position {.outGl.}: Vec4

      gl_Position = @(transform) * vec4(t, 0, 0, 1)
    
    proc frag =
      var glCol {.outGl.}: Vec4
      
      glCol = @(color.vec4)

  ctx.withPushPopIf blendRgbx, color.a != 1:
    useAndPassUniforms shader
    draw ctx.line


proc drawLine*(ctx: DrawContext, a, b: Vec2, color: Color, transform: Mat4 = mat4()) =
  drawLine(ctx, vec3(a.x, a.y, 0), vec3(b.x, b.y, 0), color, transform)



when isMainModule:
  import std/[times]
  import pkg/[siwin]

  let win = newSiwinGlobals().newOpenglWindow()
  
  loadExtensions()
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

