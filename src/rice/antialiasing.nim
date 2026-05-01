import std/[tables]
import ./[gl, contexts]


type
  OpenglVersion* = enum
    opengl_es3
    opengl3
    opengl4

  AntialiasedFramebuffer* = object
    fbo*: Framebuffers
    col*: Texture
    depth*: Texture
    size*: IVec2
    version*: OpenglVersion

const aafbShaderId = -1


proc newAntialiasedFramebuffer*(depth = false, version = OpenglVersion.low): AntialiasedFramebuffer =
  result.fbo = newFrameBuffers(1)
  result.version = version
  
  result.col = if result.version != opengl_es3: newTexture() else: Texture()
  if depth:
    result.depth = if result.version != opengl_es3: newTexture() else: Texture()


proc hasDepth*(this: AntialiasedFramebuffer): bool =
  this.depth != nil


proc resize*(this: var AntialiasedFramebuffer, size: IVec2) =
  if this.size == size: return
  this.size = size

  if this.version == opengl_es3:
    this.col = newTexture(forceNew = true)

  glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, this.col.raw)
  if this.version == opengl3:
    glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA.GlInt, size.x.GlInt, size.y.GlInt, GL_TRUE)
  else:
    glTexStorage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA8, size.x.GlInt, size.y.GlInt, GL_TRUE)
  glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)

  if this.hasDepth:
    if this.version == opengl_es3:
      this.depth = newTexture(forceNew = true)

    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, this.depth.raw)
    if this.version == opengl3:
      glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_DEPTH_COMPONENT.GlInt, size.x.GlInt, size.y.GlInt, GL_TRUE)
    else:
      glTexStorage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_DEPTH_COMPONENT32F, size.x.GlInt, size.y.GlInt, GL_TRUE)
    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)

  glBindFramebuffer(GL_FRAMEBUFFER, this.fbo[0])
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D_MULTISAMPLE, this.col.raw, 0)
  if this.hasDepth: glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D_MULTISAMPLE, this.depth.raw, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)


proc push*(ctx: DrawContext, aafb: AntialiasedFramebuffer): PushedFrameBuffer =
  if aafb.version == opengl3: glEnable(GL_MULTISAMPLE)
  if aafb.hasDepth: glEnable(GL_DEPTH_TEST)
  ctx.push(FrameBuffer(fbo: aafb.fbo, tex: aafb.col, size: aafb.size))


proc pop*(ctx: DrawContext, aafb: AntialiasedFramebuffer, ef: PushedFrameBuffer) =
  if aafb.version == opengl3: glDisable(GL_MULTISAMPLE)
  if aafb.hasDepth: glDisable(GL_DEPTH_TEST)
  ctx.pop ef


proc blit*(read: AntialiasedFramebuffer, draw: GlUint, offset = vec2()) =
  glBindFramebuffer(GL_READ_FRAMEBUFFER, read.fbo[0])
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw)
  glBlitFramebuffer(
    0, 0,
    read.size.x, read.size.y,
    offset.x.round.int32, offset.y.round.int32,
    read.size.x, read.size.y,
    GL_COLOR_BUFFER_BIT, GL_NEAREST.GlEnum
  )


proc draw*(ctx: DrawContext, aafb: AntialiasedFramebuffer, transform = mat4()) =
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
  var aafb = newAntialiasedFramebuffer()  #! <----

  var time = 0'f32

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)

  win.eventsHandler.onRender = proc(e: RenderEvent) =
    aafb.resize(e.window.size)  #! <----
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

    ctx.pop aafb, winFbo  #! <----
    blit aafb, winFbo.fbo  #! <----
    # ctx.draw aafb  #! <----

  win.eventsHandler.onTick = proc(e: TickEvent) =
    time += e.deltaTime.inMicroseconds / 1_000_000
    redraw win
  
  run win




