import ./[gl, contexts, antialiasing]

const PiF* = Pi.float32
  ## Pi, but float32


proc drawInsideImpl(ctx: DrawContext, buf: var AntialiasedFramebuffer, body: proc()) =
  let old_fbo = ctx.fbo
  let old_fboSize = ctx.fboSize
  
  resize(buf, ctx.fboSize)
  startDraw(buf)
  ctx.fbo = buf.fbo[0]
  
  try:
    body()

  finally:
    endDraw(buf, old_fbo)
    blit(buf, old_fbo)
    
    ctx.fbo = old_fbo
    ctx.fboSize = old_fboSize

template drawInside*(ctx: DrawContext, buf: var AntialiasedFramebuffer, body: untyped) =
  bind drawInsideImpl
  drawInsideImpl(ctx, buf, proc = body)


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

