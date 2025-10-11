import pkg/[bumpy, chroma, vmath, shady]
import ./[gl, transform, contexts]


proc push_blendRgbx*(ctx: DrawContext) =
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

proc pop_blendRgbx*(ctx: DrawContext) =
  glDisable(GlBlend)


when false:  # never used
  proc push_multisampling*(ctx: DrawContext) =
    glEnable(GlMultisample)

  proc pop_multisampling*(ctx: DrawContext) =
    glDisable(GlMultisample)


template withPushPop*(ctx: DrawContext, name, body: untyped) =
  `push name`(ctx)
  body
  `pop name`(ctx)

template withPushPopIf*(ctx: DrawContext, name, cond, body: untyped) =
  let b = cond
  if b: `push name`(ctx)
  body
  if b: `pop name`(ctx)



proc fillRect*(ctx: DrawContext, rect: Rect, color: Color, transform: Mat4 = mat4()) =
  let transform = combine(
    scale(vec3(rect.w, rect.h, 1)),
    translate(vec3(rect.x, rect.y, 0)),
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

  ctx.withPushPopIf blendRgbx, color.a != 1:
    useAndPassUniforms shader
    draw ctx.rect




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

    ctx.viewportMatrix = combine(
      scale(vec3(2 / vw, -2 / vh, 1)),
      translate(vec3(-1, 1, 0)),
    )

    var rect = rect(vw/2 - 400/2, vh/2 - 200/2, 400, 200)
    ctx.fillRect(
      rect,
      color(1, 0.2, 0.2),
      rotateZ(origin = vec3(rect.xy + rect.wh/2, 0), time / 4),
    )  #! <----

  win.eventsHandler.onTick = proc(e: TickEvent) =
    time += e.deltaTime.inMicroseconds / 1_000_000
    redraw win
  
  run win

