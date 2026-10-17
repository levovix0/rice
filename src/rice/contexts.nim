import std/[tables, sequtils, sets, unicode]
import pkg/chroma
import ./[transform, gl]


type  # for the ./rasterTexts module
  GlyphFamily* = object
    typefaceId*: int
    size*: float32
    underline*: bool
    strikethrough*: bool
    noKerningAdjustments*: bool

  GlyphPlacement* = object
    texture*: GlUint
    x*, y*: int16

  GlyphFamilyBuffer* = object
    placements*: Table[Rune, GlyphPlacement]
    textures*: seq[GlUint]
    freeX*, freeY*, freeH*: int16

  GlyphBuffer* = object
    families*: Table[GlyphFamily, GlyphFamilyBuffer]


type  # for the ./texts module
  GlyphMeshFamilyKey* = object
    typefaceId*: int

  GlyphMeshBuffer* = object
    meshes*: Table[Rune, Mesh]


type
  FaceOrientation* = enum
    front
    back
  
  WindingOrder* = enum
    cw   # clockwise
    ccw  # counter-clockwise

  
  FrameBuffer* = ref object
    fbo*: FrameBuffers
    tex*: Texture
    size*: IVec2

  PushedFrameBuffer* = object
    fbo*, prevFbo*: GlUint
    size*, prevSize*: IVec2


  DrawContext* = ref object
    emptyVao*: VertexArrays
    rect*: Mesh
    line*: Mesh

    shaders*: Table[int, RootRef]
    # parametrizedShaders*: Table[seq[int], RootRef]
    
    px*: Vec2  ## size of a pixel
    wh*: Vec2  ## size of the drawing area in pixels

    fbo*: GlUint = 0  ## current framebuffer (0 if is drawing directly on window)
    fboSize*: IVec2   ## size of current framebuffer in pixels
    
    offset*: Vec2

    glyphBuffer*: GlyphBuffer
    glyphMeshes*: Table[GlyphMeshFamilyKey, GlyphMeshBuffer]

    viewportMatrix*: Mat4 = mat4()
    projectionMatrix*: Mat4 = mat4()
    viewportToGlMatrix*: Mat4 = mat4()
    glToViewportMatrix*: Mat4 = mat4()

    freeFrameBuffers: seq[FrameBuffer]
    unusedFrameBuffers: HashSet[GlUint]
  

  GlShaderBox* = ref object of RootObj
    ## wraps Shader, so it can be stored in DrawContext.shaders
    shader*: Shader
  


#* ------------- utils ------------- *#

proc vec4*(color: chroma.Color): Vec4 =
  vec4(color.r, color.g, color.b, color.a)

proc vec4*(c: ColorRGBX): Vec4 =
  vec4(c.r.float32/255, c.g.float32/255, c.b.float32/255, c.a.float32/255)

proc color*(v: Vec4): chroma.Color =
  chroma.Color(r: v.x, g: v.y, b: v.z, a: v.w)


proc round*(v: Vec2): Vec2 =
  vec2(round(v.x), round(v.y))

proc ceil*(v: Vec2): Vec2 =
  vec2(ceil(v.x), ceil(v.y))

proc floor*(v: Vec2): Vec2 =
  vec2(floor(v.x), floor(v.y))


proc getShader*(ctx: DrawContext, id: int, vert, frag: string): Shader =
  ## returns shader, compiling it from glsl sources if not compiled yet;
  ## id must be unique for each pair of shader sources in the whole program
  if id notin ctx.shaders:
    ctx.shaders[id] = GlShaderBox(shader: newShader({GlVertexShader: vert, GlFragmentShader: frag}))
  GlShaderBox(ctx.shaders[id]).shader


proc passTransform*(ctx: DrawContext, shader: Shader, pos = vec2(), size = vec2(10, 10), angle: float32 = 0, flipY = false) =
  shader["transform"].uniform =
    translate(vec3(ctx.px*(vec2(pos.x, -pos.y) - ctx.wh - (if flipY: vec2(0, size.y) else: vec2())), 0)) *
    scale(if flipY: vec3(1, -1, 1) else: vec3(1, 1, 1)) *
    rotate(angle, vec3(0, 0, 1))
  shader["size"].uniform = size
  shader["px"].uniform = ctx.px


proc `viewport=`*(ctx: DrawContext, mat: Mat4) =
  ctx.viewportMatrix = mat
  ctx.viewportToGlMatrix = combine(ctx.viewportMatrix, ctx.projectionMatrix)
  ctx.glToViewportMatrix = inverse(ctx.viewportToGlMatrix)

proc `projection=`*(ctx: DrawContext, mat: Mat4) =
  ctx.projectionMatrix = mat
  ctx.viewportToGlMatrix = combine(ctx.viewportMatrix, ctx.projectionMatrix)
  ctx.glToViewportMatrix = inverse(ctx.viewportToGlMatrix)



proc windowToGlNormalizedMatrix*(ctx: DrawContext): Mat4 =
  ## returns matrix for converting from view plane coordinates [0..window.w, 0..window.h] (with y down)
  ## to opengl view plane coordinates [-1..1, -1..1] (with y up)
  combine(
    scale(vec3(ctx.px.x, -ctx.px.y, 1 / 2000)),
    translate(vec3(-1, 1, 0)),
  )

proc glNormalizedToWindowMatrix*(ctx: DrawContext): Mat4 =
  ## returns matrix for converting from opengl view plane coordinates [-1..1, -1..1] (with y up)
  ## to view plane coordinates [0..window.w, 0..window.h] (with y down)
  combine(
    translate(vec3(1, -1, 0)),
    scale(vec3(ctx.wh.x / 2, -ctx.wh.y / 2, 2000)),
  )


proc emptyMesh*(ctx: DrawContext, kind: GlEnum, vertexCount: int): Mesh =
  Mesh(vao: ctx.emptyVao, kind: kind, len: vertexCount)


proc newDrawContext*: DrawContext =
  new result

  result.emptyVao = newVertexArrays(1)

  result.rect = newMesh(
    [
      vec2(0, 1),   # top left
      vec2(0, 0),   # bottom left
      vec2(1, 0),   # bottom right
      vec2(1, 1),   # top right
    ], [
      0'u32, 1, 2,
      2, 3, 0,
    ]
  )

  result.line = newMesh(
    [
      0'f32,
      1'f32,
    ],
    kind = GL_LINES
  )

  result.viewportMatrix = mat4()


proc updateDrawingAreaSize*(ctx: DrawContext, size: IVec2) =
  ## update size
  ctx.px = vec2(2'f32 / size.x.float32, 2'f32 / size.y.float32)
  ctx.wh = ivec2(size.x, -size.y).vec2 / 2
  ctx.fboSize = size



# ===================
# --- FrameBuffer ---
# ===================
# todo: move to a new ./framebuffers module

proc requireFrameBufferWithExactOrBiggerSize*(ctx: DrawContext, minSize: IVec2): FrameBuffer =
  ## get or resize or create a frameBuffer with size.x >= minSize.x and size.y >= minSize.y
  let minSize = ivec2(max(minSize.x, 1), max(minSize.y, 1))
  
  var i = 0
  while i < ctx.freeFrameBuffers.len:
    template ef: untyped = ctx.freeFrameBuffers[i]

    if ef.size.x >= minSize.x and ef.size.y >= minSize.y:
      ctx.unusedFrameBuffers.excl ef.fbo[0]
      result = ef
      ctx.freeFrameBuffers.del i
      return
    
    inc i
  
  # no available free buffer with size that is at least `minSize`

  if ctx.freeFrameBuffers.len != 0:
    # resize existing framebuffer
    template ef: untyped = ctx.freeFrameBuffers[0]
    result = ef

    ef.size = ivec2(max(minSize.x, ef.size.x), max(minSize.y, ef.size.y))

    glBindFramebuffer(GlFramebuffer, ef.fbo[0])

    glBindTexture(GlTexture2d, ef.tex.raw)
    glTexImage2D(GlTexture2d, 0, GlRgba.Glint, ef.size.x, ef.size.y, 0, GlRgba, GlUnsignedByte, nil)
    glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
    glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
    glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, ef.tex.raw, 0)
        
    glBindFramebuffer(GlFramebuffer, ctx.fbo)

    ctx.freeFrameBuffers.del 0
  
  else:
    # create new framebuffer
    new result

    template ef: untyped = result
    ef.size = minSize

    ef.fbo = newFrameBuffers(1)
    ef.tex = newTexture()

    glBindFramebuffer(GlFramebuffer, ef.fbo[0])
    
    glBindTexture(GlTexture2d, ef.tex.raw)
    glTexImage2D(GlTexture2d, 0, GlRgba.Glint, ef.size.x, ef.size.y, 0, GlRgba, GlUnsignedByte, nil)
    glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
    glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
    glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, ef.tex.raw, 0)
        
    glBindFramebuffer(GlFramebuffer, ctx.fbo)


proc requireFrameBuffer*(ctx: DrawContext, size: IVec2): FrameBuffer =
  ## get or create a framebuffer with exact size
  let size = ivec2(max(size.x, 1), max(size.y, 1))
  
  var i = 0
  while i < ctx.freeFrameBuffers.len:
    template ef: untyped = ctx.freeFrameBuffers[i]

    if ef.size == size:
      ctx.unusedFrameBuffers.excl ef.fbo[0]
      result = ef
      ctx.freeFrameBuffers.del i
      return
    
    inc i
  
  # no available free buffer with size that is exactly `size`
  # create new framebuffer
  new result

  template ef: untyped = result
  ef.size = size

  ef.fbo = newFrameBuffers(1)
  ef.tex = newTexture()

  glBindFramebuffer(GlFramebuffer, ef.fbo[0])
  
  glBindTexture(GlTexture2d, ef.tex.raw)
  glTexImage2D(GlTexture2d, 0, GlRgba.Glint, ef.size.x, ef.size.y, 0, GlRgba, GlUnsignedByte, nil)
  glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
  glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
  glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, ef.tex.raw, 0)
      
  glBindFramebuffer(GlFramebuffer, ctx.fbo)


proc free*(ctx: DrawContext, ef: FrameBuffer) =
  ## allow to reuse framebuffer
  assert ctx.freeFrameBuffers.allIt(it.fbo[0] != ef.fbo[0]), "framebuffer freed twice"
  ctx.freeFrameBuffers.add ef


proc deleteUnusedFrameBuffers*(ctx: DrawContext) =
  ## remove all buffers that was allowed to reuse, but has not been reused
  var c = 0
  for efFbo in ctx.unusedFrameBuffers:
    var i = 0
    while i < ctx.freeFrameBuffers.len:
      template ef: untyped = ctx.freeFrameBuffers[i]
      if ef.fbo[0] == efFbo:
        ctx.freeFrameBuffers.del i
        inc c
      else:
        inc i


proc markAllFreeFrameBuffersAsUnused*(ctx: DrawContext) =
  for ef in ctx.freeFrameBuffers:
    ctx.unusedFrameBuffers.incl ef.fbo[0]


proc push*(ctx: DrawContext, ef: FrameBuffer): PushedFrameBuffer =
  ## set current framebuffer
  assert ctx.fbo != ef.fbo[0]
  result = PushedFrameBuffer(
    fbo: ef.fbo[0],
    size: ef.size,
    prevFbo: ctx.fbo,
    prevSize: ctx.fboSize,
  )
  ctx.fbo = ef.fbo[0]
  ctx.fboSize = ef.size
  glBindFramebuffer(GlFramebuffer, ef.fbo[0])

  glViewport 0, 0, ef.size.x.GLsizei, ef.size.y.GLsizei
  ctx.updateDrawingAreaSize(ef.size)


proc pop*(ctx: DrawContext, ef: PushedFrameBuffer) =
  ## reset current framebuffer
  assert ctx.fbo == ef.fbo
  assert ctx.fboSize == ef.size
  ctx.fbo = ef.prevFbo
  ctx.fboSize = ef.prevSize
  
  glBindFramebuffer(GlFramebuffer, ctx.fbo)

  glViewport 0, 0, ctx.fboSize.x.GLsizei, ctx.fboSize.y.GLsizei
  ctx.updateDrawingAreaSize(ctx.fboSize)
