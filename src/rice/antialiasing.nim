import ./[gl]


type
  AntialiasedFramebuffer* = object
    fbo*: Framebuffers
    col*: Texture
    depth*: Texture
    size*: IVec2


proc newAntialiasedFramebuffer*(depth = false): AntialiasedFramebuffer =
  result.fbo = newFrameBuffers(1)
  result.col = newTexture()
  if depth:
    result.depth = newTexture()


proc hasDepth*(this: AntialiasedFramebuffer): bool =
  this.depth != nil


proc resize*(this: var AntialiasedFramebuffer, size: IVec2) =
  this.size = size

  glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, this.col.raw)
  glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA.GlInt, size.x.GlInt, size.y.GlInt, GL_TRUE)
  glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)

  if this.hasDepth:
    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, this.depth.raw)
    glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_DEPTH_COMPONENT.GlInt, size.x.GlInt, size.y.GlInt, GL_TRUE)
    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)

  glBindFramebuffer(GL_FRAMEBUFFER, this.fbo[0])
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D_MULTISAMPLE, this.col.raw, 0)
  if this.hasDepth: glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D_MULTISAMPLE, this.depth.raw, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)


proc startDraw*(this: AntialiasedFramebuffer) =
  glBindFramebuffer(GL_FRAMEBUFFER, this.fbo[0])

  glEnable(GL_MULTISAMPLE)
  if this.hasDepth: glEnable(GL_DEPTH_TEST)


proc endDraw*(this: AntialiasedFramebuffer, nextFbo: GlUint) =
  glBindFramebuffer(GL_FRAMEBUFFER, nextFbo)

  glDisable(GL_MULTISAMPLE)
  if this.hasDepth: glDisable(GL_DEPTH_TEST)


proc blit*(read: AntialiasedFramebuffer, draw: GlUint) =
  glBindFramebuffer(GL_READ_FRAMEBUFFER, read.fbo[0])
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw)
  glBlitFramebuffer(0, 0, read.size.x, read.size.y, 0, 0, read.size.x, read.size.y, GL_COLOR_BUFFER_BIT, GL_NEAREST.GlEnum)



when isMainModule:
  import std/[times]
  import pkg/[siwin, bumpy, chroma]
  import ./[contexts, primitives, transform]

  let win = newSiwinGlobals().newOpenglWindow()
  
  loadExtensions()
  let ctx = newDrawContext()
  var aafb = newAntialiasedFramebuffer()  #! <----

  var time = 0'f32

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)
    aafb.resize(e.size)  #! <----


  win.eventsHandler.onRender = proc(e: RenderEvent) =
    startDraw aafb  #! <----

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
    )

    endDraw aafb, 0  #! <----
    blit aafb, 0  #! <----

  win.eventsHandler.onTick = proc(e: TickEvent) =
    time += e.deltaTime.inMicroseconds / 1_000_000
    redraw win
  
  run win




