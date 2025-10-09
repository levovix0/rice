import std/[unittest, times]
import pkg/[siwin, chroma, bumpy]
import rice


test "basic":
  let win = newSiwinGlobals().newOpenglWindow()
  
  loadExtensions()
  let ctx = newDrawContext()

  let fbo_col = newTexture()
  let fbo_depth = newTexture()
  var fbo = newFrameBuffers(1)

  var time = 0'f32

  var rot = toAngles(vec3(1, 1, 1)).fromAngles()
  
  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)
    ctx.viewportMatrix = scale(vec3(e.size.y / e.size.x, 1, 1))

    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, fbo_col.raw)
    glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA.GlInt, e.size.x.GlInt, e.size.y.GlInt, GL_TRUE)
    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)

    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, fbo_depth.raw)
    glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_DEPTH_COMPONENT.GlInt, e.size.x.GlInt, e.size.y.GlInt, GL_TRUE)
    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)

    glBindFramebuffer(GL_FRAMEBUFFER, fbo[0])
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D_MULTISAMPLE, fbo_depth.raw, 0)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D_MULTISAMPLE, fbo_col.raw, 0)
    glBindFramebuffer(GL_FRAMEBUFFER, 0)

  win.eventsHandler.onRender = proc(e: RenderEvent) =
    glBindFramebuffer(GL_FRAMEBUFFER, fbo[0])

    glClearColor(0.1, 0.1, 0.1, 1)
    glClearDepth(1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    glEnable(GL_MULTISAMPLE)
    glEnable(GL_DEPTH_TEST)

    let (vw, vh) = (e.window.size.x, e.window.size.y)

    for i in countdown(1, -1, 2):
      ctx.fillRect(
        rect(-0.25, -0.25, 0.5, 0.5),
        color(1, 0.2, 0.2).darken(if i < 0: 0.2 else: 0),
        combine(
          translate(vec3(0, 0, -0.25 * i.float32)),
          rotateY(float32 PI/2),
          rot,
        )
      )

      ctx.fillRect(
        rect(-0.25, -0.25, 0.5, 0.5),
        color(0.2, 1, 0.2).darken(if i < 0: 0.2 else: 0),
        combine(
          translate(vec3(0, 0, -0.25 * i.float32)),
          rotateX(float32 -PI/2),
          rot,
        )
      )

      ctx.fillRect(
        rect(-0.25, -0.25, 0.5, 0.5),
        color(0.2, 0.2, 1).darken(if i < 0: 0.2 else: 0),
        combine(
          translate(vec3(0, 0, -0.25 * i.float32)),
          rot,
        )
      )

    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    
    glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo[0])
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)
    glBlitFramebuffer(0, 0, vw, vh, 0, 0, vw, vh, GL_COLOR_BUFFER_BIT, GL_NEAREST.GlEnum)


  var mpos = vec2()
  win.eventsHandler.onMouseButton = proc(e: MouseButtonEvent) =
    if e.window.mouse.pressed == {MouseButton.right}:
      mpos = e.window.mouse.pos

  win.eventsHandler.onMouseMove = proc(e: MouseMoveEvent) =
    if e.window.mouse.pressed == {MouseButton.right}:
      let d = e.window.mouse.pos - mpos
      
      rot = combine(
        rot,
        rotateY(float32 d.x / e.window.size.x.float32 * 2*PI),
        rotateX(float32 d.y / e.window.size.y.float32 * 2*PI),
      )
      
      mpos = e.window.mouse.pos


  win.eventsHandler.onTick = proc(e: TickEvent) =
    time += e.deltaTime.inMicroseconds / 1_000_000
    redraw win
  
  run win

