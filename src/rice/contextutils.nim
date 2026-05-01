import ./[gl, contexts, antialiasing]


const PiF* = Pi.float32
  ## Pi, but float32


proc drawInsideImpl(ctx: DrawContext, buf: var AntialiasedFramebuffer, body: proc()) =
  resize(buf, ctx.fboSize)
  let prevFbo = ctx.push(buf)
  ctx.fbo = buf.fbo[0]
  
  try:
    body()

  finally:
    ctx.pop buf, prevFbo
    blit(buf, prevFbo.prevFbo)

template drawInside*(ctx: DrawContext, buf: var AntialiasedFramebuffer, body: untyped) =
  bind drawInsideImpl
  drawInsideImpl(ctx, buf, proc = body)


proc push_blendRgbx*(ctx: DrawContext) =
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

proc pop_blendRgbx*(ctx: DrawContext) =
  glDisable(GlBlend)


proc push_depthTest*(ctx: DrawContext) =
  glEnable(GlDepthTest)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

proc pop_depthTest*(ctx: DrawContext) =
  glDisable(GlDepthTest)


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


proc setFaceCulling*(ctx: DrawContext, enabled: bool, faceToKeep: FaceOrientation, frontFace: WindingOrder) =
  if enabled:
    glEnable(GL_CULL_FACE)
    
    glCullFace case faceToKeep
      of front: GL_FRONT
      of back: GL_BACK

    glFrontFace case frontFace
      of cw: GL_CW
      of ccw: GL_CCW
  else:
    glDisable(GL_CULL_FACE)



template withFaceCulling*(ctx: DrawContext, faceToKeep, frontFace, body: untyped) =
  bind setFaceCulling, glDisable, GL_CULL_FACE
  setFaceCulling(ctx, true, faceToKeep, frontFace)
  body
  glDisable(GL_CULL_FACE)

template withFaceCulling*(ctx: DrawContext, faceToKeep, body: untyped) =
  withFaceCulling(ctx, faceToKeep, WindingOrder.ccw, body)

template withFaceCulling*(ctx: DrawContext, body: untyped) =
  withFaceCulling(ctx, FaceOrientation.front, WindingOrder.ccw, body)


template set*(ctx: DrawContext, flag_name: untyped) =
  `push flag_name`(ctx)
  defer: `pop flag_name`(ctx)

