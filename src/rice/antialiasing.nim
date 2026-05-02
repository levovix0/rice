import std/[tables]
import ./[gl, contexts]


type
  OpenglVersion* = enum
    opengl_es3
    opengl3
    opengl4

  AntialiasedFrameBuffer* = object
    fbo*: FrameBuffers
    col*: Texture
    depth*: Texture
    size*: IVec2
    version*: OpenglVersion

  PushedAntialiasedFrameBuffer* = object
    hasDepth*: bool
    version*: OpenglVersion
    fb*: PushedFrameBuffer

const aafbShaderId = -1


proc `==`*(aafb: AntialiasedFrameBuffer, _: typeof(nil)): bool = aafb.fbo.len == 0 or aafb.col.raw == 0

proc hasDepth*(this: AntialiasedFrameBuffer): bool =
  this.depth != nil

proc resize*(ctx: DrawContext, this: var AntialiasedFrameBuffer, size: IVec2)


proc newAntialiasedFrameBuffer*(ctx: DrawContext, size: IVec2, depth = false, version = OpenglVersion.low): AntialiasedFrameBuffer =
  result.fbo = newFrameBuffers(1)
  result.version = version
  
  result.col = if result.version != opengl_es3: newTexture() else: Texture()
  if depth:
    result.depth = if result.version != opengl_es3: newTexture() else: Texture()
  
  ctx.resize(result, size)


proc resize*(ctx: DrawContext, this: var AntialiasedFrameBuffer, size: IVec2) =
  if this.fbo.len == 0:
    this = ctx.newAntialiasedFrameBuffer(size)
    return
  if this.size == size: return
  this.size = size

  if this.version == opengl_es3:
    this.col = newTexture(kind = Texture2dMultisample)

  glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, this.col.raw)
  if this.version == opengl3:
    glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA.GlInt, size.x.GlInt, size.y.GlInt, GL_TRUE)
  else:
    glTexStorage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA8, size.x.GlInt, size.y.GlInt, GL_TRUE)
  glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)

  if this.hasDepth:
    if this.version == opengl_es3:
      this.depth = newTexture(kind = Texture2dMultisample)

    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, this.depth.raw)
    if this.version == opengl3:
      glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_DEPTH_COMPONENT.GlInt, size.x.GlInt, size.y.GlInt, GL_TRUE)
    else:
      glTexStorage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_DEPTH_COMPONENT32F, size.x.GlInt, size.y.GlInt, GL_TRUE)
    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)

  glBindFrameBuffer(GL_FRAMEBUFFER, this.fbo[0])
  glFrameBufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D_MULTISAMPLE, this.col.raw, 0)
  if this.hasDepth: glFrameBufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D_MULTISAMPLE, this.depth.raw, 0)
  glBindFrameBuffer(GL_FRAMEBUFFER, ctx.fbo)


proc push*(ctx: DrawContext, aafb: AntialiasedFrameBuffer): PushedAntialiasedFrameBuffer =
  if aafb.version == opengl3: glEnable(GL_MULTISAMPLE)
  if aafb.hasDepth: glEnable(GL_DEPTH_TEST)
  PushedAntialiasedFrameBuffer(
    fb: ctx.push(FrameBuffer(fbo: aafb.fbo, tex: aafb.col, size: aafb.size)),
    version: aafb.version,
    hasDepth: aafb.hasDepth,
  )


proc pop*(ctx: DrawContext, ef: PushedAntialiasedFrameBuffer) =
  ctx.pop ef.fb
  if ef.version == opengl3: glDisable(GL_MULTISAMPLE)
  if ef.hasDepth: glDisable(GL_DEPTH_TEST)


proc blit*(read: GlUint, draw: GlUint, size: IVec2, offset = vec2()) =
  glBindFrameBuffer(GL_READ_FRAMEBUFFER, read)
  glBindFrameBuffer(GL_DRAW_FRAMEBUFFER, draw)
  glBlitFrameBuffer(
    0, 0,
    size.x, size.y,
    offset.x.round.int32, offset.y.round.int32,
    size.x, size.y,
    GL_COLOR_BUFFER_BIT, GL_NEAREST.GlEnum
  )
  glBindFrameBuffer(GL_READ_FRAMEBUFFER, 0)
  glBindFrameBuffer(GL_DRAW_FRAMEBUFFER, 0)


proc blit*(read: AntialiasedFrameBuffer, draw: GlUint, offset = vec2()) =
  blit(read.fbo[0], draw, read.size, offset)

proc blit*(readDraw: PushedAntialiasedFrameBuffer, offset = vec2()) =
  blit(readDraw.fb.fbo, readDraw.fb.prevFbo, readDraw.fb.size, offset)



proc draw*(ctx: DrawContext, aafb: AntialiasedFrameBuffer, transform = mat4()) =
  ## draw antialiased onto other framebuffer
  let transform = ctx.viewportToGlMatrix * transform

  const vert = """
    #version 310 es
    precision highp float;
    precision highp sampler2DMS;

    in vec2 ipos;
    out vec2 uv;
    uniform mat4 transform;
    uniform vec2 aafbSize;

    void main() {
      uv = ipos;
      gl_Position = transform * vec4(ipos.xy * aafbSize, vec2(0.0, 1.0));
    }
  """

  const frag = """
    #version 310 es
    precision highp float;
    precision highp sampler2DMS;

    uniform sampler2DMS gltex;

    in vec2 uv;
    out vec4 glCol;

    void main() {
      ivec2 uvi = ivec2(vec2(textureSize(gltex)) * uv);
      glCol = (texelFetch(gltex, uvi, 0) + texelFetch(gltex, uvi, 1) + texelFetch(gltex, uvi, 2) + texelFetch(gltex, uvi, 3)) / 4.0;
    }
  """

  type AafbShader = ref object of RootObj
    id: Shader
    transform: OpenglUniform[Mat4]
    aafbSize: OpenglUniform[Vec2]

  if not ctx.shaders.hasKey aafbShaderId:
    let shader = AafbShader(id: newShader({GL_VERTEX_SHADER: vert, GL_FRAGMENT_SHADER: frag}))
    shader.transform = OpenglUniform[Mat4] shader.id["transform"]
    shader.aafbSize = OpenglUniform[Vec2] shader.id["aafbSize"]
    ctx.shaders[aafbShaderId] = shader
  let shader = ctx.shaders[aafbShaderId].AafbShader

  use shader.id
  shader.transform.uniform = transform
  shader.aafbSize.uniform = aafb.size.vec2
  
  glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, aafb.col.raw)
  draw ctx.rect
  glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)



when isMainModule:
  import std/[times]
  import pkg/[siwin, bumpy, chroma]
  import ./[primitives, transform]

  let win = newSiwinGlobals().newOpenglWindow()
  
  loadExtensions()
  let ctx = newDrawContext()
  var aafb = ctx.newAntialiasedFrameBuffer(win.size)  #! <----

  var time = 0'f32

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)

  win.eventsHandler.onRender = proc(e: RenderEvent) =
    ctx.resize(aafb, e.window.size)  #! <----
    let winFbo = ctx.push aafb  #! <----

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
      rotateZ(time / 4, origin = vec3(rect.xy + rect.wh/2, 0)),
    )

    ctx.pop winFbo  #! <----
    blit winFbo  #! <----
    # ctx.draw aafb  #! <----

  win.eventsHandler.onTick = proc(e: TickEvent) =
    time += e.deltaTime.inMicroseconds / 1_000_000
    redraw win
  
  run win




