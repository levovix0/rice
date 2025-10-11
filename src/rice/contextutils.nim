import ./[gl, contexts, antialiasing]


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

