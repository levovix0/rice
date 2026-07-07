import std/[sets]
import pkg/[vmath, opengl]
import pkg/pixie/images as pixie
import pkg/pixie/common

when (compiles do: import pkg/imageman):
  import pkg/imageman/[images as imagemanImages, colors as imagemanColors]
  const hasImageman* = true
else:
  const hasImageman* = false

export vmath, opengl

# todo: import only needed functions from opengl, instead of full huge bundle


type
  Buffers* = ref BuffersObj
  BuffersObj = object
    n: int32
    obj: UncheckedArray[GlUint]

  VertexArrays* = ref VertexArraysObj
  VertexArraysObj = object
    n: int32
    obj: UncheckedArray[GlUint]
  
  Shader* = ref ShaderObj
  ShaderObj = object
    obj: GlUint

  FrameBuffers* = ref FrameBuffersObj
  FrameBuffersObj = object
    n: int32
    obj: UncheckedArray[GlUint]
  
  ShaderCompileDefect* = object of Defect


  MeshFlag* = enum
    hasIndices
    hasEdgeTbo

  Mesh* = object
    kind*: GlEnum
    len*: int
    vao*: VertexArrays
    bo*: Buffers
    flags*: set[MeshFlag]
    tbo*: TextureBuffer # currently used only for edges

  OpenglUniform*[T] = distinct GlInt

  TextureKind* = enum
    Texture2d
    Texture2dMultisample

  Texture* = ref TextureObj
  TextureObj = object
    raw*: GlUint
    kind*: TextureKind

  TextureBuffer* = ref TextureBufferObj
  TextureBufferObj = object
    tex*: GlUint
    buf*: GlUint
    len*: int

{.push, warning[Effect]: off.}
proc `=destroy`(x: TextureBufferObj) =
  if x.tex != 0:
    glDeleteTextures(1, x.tex.unsafeAddr)
  if x.buf != 0:
    glDeleteBuffers(1, x.buf.unsafeAddr)
{.pop.}


const rice_max_opengl_error_len {.intdefine.} = 512


var freeTextures*: HashSet[GlUint]


# -------- Buffers, VertexArrays --------
template makeOpenglObjectSeq(t, tobj, T, gen, del, newp) =
  proc `=destroy`(xobj {.inject.}: tobj) =
    if xobj.n != 0:
      del(xobj.n, cast[ptr T](xobj.obj.addr))

  proc newp*(n: int): t =
    if n == 0: return
    assert n in 1..int32.high
    unsafeNew result, int32.sizeof + n * T.sizeof
    result.n = n.int32
    gen(n.int32, cast[ptr T](result.obj.addr))

  proc len*(x: t): int =
    if x == nil: 0
    else: x.n

  proc `[]`*(x: t, i: int): T =
    if i notin 0..<x.len:
      raise IndexDefect.newException("index " & $i & " out of range 0..<" & $x.len)
    x.obj[i]


{.push, warning[Effect]: off.}
makeOpenglObjectSeq Buffers, BuffersObj, GlUint, glGenBuffers, glDeleteBuffers, newBuffers
makeOpenglObjectSeq VertexArrays, VertexArraysObj, GlUint, glGenVertexArrays, glDeleteVertexArrays, newVertexArrays
makeOpenglObjectSeq FrameBuffers, FrameBuffersObj, GlUint, glGenFrameBuffers, glDeleteFrameBuffers, newFrameBuffers
{.pop.}


when defined(gcc):
  {.passc: "-fcompare-debug-second".}  # seems like it hides warning about "passing flexieble array ABI changed in GCC 4.4"
  # i don't care, gcc


# -------- helpers --------
proc arrayBufferData*[T](data: openarray[T], usage: GlEnum = GlStaticDraw) =
  glBufferData(GlArrayBuffer, data.len * T.sizeof, data.unsafeaddr, usage)

proc elementArrayBufferData*[T](data: openarray[T], usage: GlEnum = GlStaticDraw) =
  glBufferData(GlElementArrayBuffer, data.len * T.sizeof, data.unsafeaddr, usage)

template withVertexArray*(vao: GlUint, body) =
  glBindVertexArray(vao)
  block: body
  glBindVertexArray(0)


proc loadTexture*(obj: GlUint, size: IVec2, data: pointer) =
  ## assumes data is encoded as uint 8-bit-per-component rgbx (like in pixie)
  glBindTexture(GlTexture2d, obj)
  glTexImage2D(GlTexture2d, 0, GlRgba.GLint, size.x.GLsizei, size.y.GLsizei, 0, GlRgba, GlUnsignedByte, data)
  glGenerateMipmap(GlTexture2d)
  glBindTexture(GlTexture2d, 0)

proc loadTexture*(obj: GlUint, img: pixie.Image) =
  obj.loadTexture(ivec2(img.width.int32, img.height.int32), img.data[0].addr)

when hasImageman:
  proc loadTexture*(obj: GlUint, img: imagemanImages.Image[imagemanColors.ColorRgbau]) =
    obj.loadTexture(ivec2(img.width.int32, img.height.int32), img.data[0].addr)



# -------- Shader --------
{.push, warning[Effect]: off.}
proc `=destroy`(x: ShaderObj) =
  if x.obj != 0:
    glDeleteProgram(x.obj)
{.pop.}

proc newShader*(shaders: openarray[(GlEnum, string)]): Shader =
  new result

  var shad = newSeq[GlUint](shaders.len)

  proc free =
    for x in shad:
      if x != 0: glDeleteShader(x)

  for i, (k, s) in shaders:
    var cs = s.cstring
    shad[i] = glCreateShader(k)
    glShaderSource(shad[i], 1, cast[cstringArray](cs.addr), nil)
    glCompileShader(shad[i])
    if (var success: GlInt; glGetShaderiv(shad[i], GlCompileStatus, success.addr); success != GlTrue.GlInt):
      var buffer: array[rice_max_opengl_error_len, char]
      glGetShaderInfoLog(shad[i], rice_max_opengl_error_len, nil, cast[cstring](buffer.addr))
      free()
      raise ShaderCompileDefect.newException("failed to compile shader " & $(i+1) & ": " & $cast[cstring](buffer.addr))
  
  defer: free()

  result.obj = glCreateProgram()
  for i, x in shad:
    glAttachShader(result.obj, x)
  glLinkProgram(result.obj)
  if (var success: GlInt; glGetProgramiv(result.obj, GlLinkStatus, success.addr); success != GlTrue.GlInt):
    var buffer: array[rice_max_opengl_error_len, char]
    glGetProgramInfoLog(result.obj, rice_max_opengl_error_len, nil, cast[cstring](buffer.addr))
    # todo: delete gl shader programm?
    raise ShaderCompileDefect.newException("failed to link shader program: " & $cast[cstring](buffer.addr))

proc use*(x: Shader) =
  glUseProgram(x.obj)

proc `[]`*(x: Shader, name: string, onlyIfExists = false): GlInt =
  result = glGetUniformLocation(x.obj, name)
  if result == -1:
    if onlyIfExists:
      raise KeyError.newException("shader has no uniform " & name & " (is it unused?)")

proc `uniform=`*(i: GlInt, value: GlFloat) =
  if i != -1:
    glUniform1f(i, value)

proc `uniform=`*(i: GlInt, value: Vec2) =
  if i != -1:
    glUniform2f(i, value.x, value.y)

proc `uniform=`*(i: GlInt, value: Vec3) =
  if i != -1:
    glUniform3f(i, value.x, value.y, value.z)

proc `uniform=`*(i: GlInt, value: Vec4) =
  if i != -1:
    glUniform4f(i, value.x, value.y, value.z, value.w)

proc `uniform=`*(i: GlInt, value: Mat3) =
  if i != -1:
    glUniformMatrix3fv(i, 1, GlFalse, cast[ptr GlFloat](value.unsafeaddr))

proc `uniform=`*(i: GlInt, value: Mat4) =
  if i != -1:
    glUniformMatrix4fv(i, 1, GlFalse, cast[ptr GlFloat](value.unsafeaddr))

proc `uniform=`*(i: GlInt, value: int) =
  if i != -1:
    glUniform1i(i, value.GlInt)

proc `uniform=`*(i: GlInt, value: openArray[Vec2]) =
  if i != -1 and value.len > 0:
    glUniform2fv(i, value.len.GlSizei, cast[ptr GlFloat](value[0].addr))

proc `uniform=`*[T](x: OpenglUniform[T], value: T) =
  `uniform=`(x.GlInt, value)



# -------- Texture buffer --------
proc newTextureBuffer*[T](data: openArray[T], format: GlEnum = GlRgba32f): TextureBuffer =
  # btf why codebase uses unsafe addr if it deprecated in new versions
  if data.len == 0: return
  result = TextureBuffer(len: data.len)

  glGenTextures(1, result.tex.addr)
  glGenBuffers(1, result.buf.addr)
  glBindBuffer(GlTextureBuffer, result.buf)
  glBufferData(GlTextureBuffer, data.len * T.sizeof, data[0].addr, GlStaticDraw)
  glBindTexture(GlTextureBuffer, result.tex)
  glTexBuffer(GlTextureBuffer, format, result.buf)
  glBindTexture(GlTextureBuffer, 0)
  glBindBuffer(GlTextureBuffer, 0)



# -------- Mesh --------
proc makeAttributes(t: type) =
  when t is tuple:
    var i = 0
    var offset = 0
    var x: t
    for x in x.fields:
      type t2 = x.typeof
      glVertexAttribPointer i.uint32, t2.sizeof div GlFloat.sizeof, cGlFloat, GlFalse, t.sizeof.GlSizei, cast[pointer](offset)
      glEnableVertexAttribArray i.uint32
      inc i
      inc offset, t2.sizeof
  else:
    glVertexAttribPointer 0, t.sizeof div GlFloat.sizeof, cGlFloat, GlFalse, t.sizeof.GlSizei, nil
    glEnableVertexAttribArray 0


proc newMesh*[T](vert: openarray[T], idx: openarray[GlUint], kind = GlTriangles): Mesh =
  result.vao = newVertexArrays(1)
  result.bo = newBuffers(2)
  result.len = idx.len
  result.kind = kind
  result.flags = {MeshFlag.hasIndices}

  withVertexArray result.vao[0]:
    glBindBuffer GlArrayBuffer, result.bo[0]
    arrayBufferData vert
    glBindBuffer GlElementArrayBuffer, result.bo[1]
    elementArrayBufferData idx
    makeAttributes T

proc newMesh*[T](vert: openarray[T], kind = GlTriangles, edgeTbo = false): Mesh =
  result.vao = newVertexArrays(1)
  result.bo = newBuffers(1)
  result.len = vert.len
  result.kind = kind
  result.flags = {}

  withVertexArray result.vao[0]:
    glBindBuffer GlArrayBuffer, result.bo[0]
    arrayBufferData vert
    makeAttributes T

  when T is Vec2:
    if edgeTbo:
      # you can get correct result in case of triangle fan
      # otherwise, detecting edges realy hard, so:
      assert:
        vert.len >= 3 and
        kind == GlTriangleFan

      var edges: seq[Vec4] = @[]

      for i in 0 ..< vert.len:
        let j = (i + 1) mod vert.len
        edges.add vec4(vert[i].x, vert[i].y, vert[j].x, vert[j].y)

      result.tbo = newTextureBuffer(edges, GlRgba32f)
      result.flags.incl hasEdgeTbo
  else:
    if edgeTbo:
      raise ValueError.newException "edgeTbo flag supported only for Vec2"


proc draw*(x: Mesh, kind: GLenum = x.kind) =
  if x.len == 0: return
  let bindTbo =
    hasEdgeTbo in x.flags and
    x.tbo != nil

  if bindTbo:
    glBindTexture(GlTextureBuffer, x.tbo.tex)

  withVertexArray x.vao[0]:
    if hasIndices in x.flags:
      glDrawElements(kind, x.len.GlSizei, GlUnsignedInt, nil)
    else:
      glDrawArrays(kind, 0, x.len.GlSizei)

  if bindTbo:
    glBindTexture(GlTextureBuffer, 0)



#* ------------- textures ------------- *#

const rice_render_texturesToAllocateIfNoFree {.intdefine.} = 8

proc `=destroy`(texture: TextureObj) =
  if texture.raw == 0: return
  if texture.kind == Texture2d and freeTextures.len < rice_render_texturesToAllocateIfNoFree:
    freeTextures.incl texture.raw
    try:
      texture.raw.loadTexture(pixie.newImage(1, 1))  # load empty image to force opengl use less memory
    except GlError, PixieError:
      discard
  
  else:
    try:
      glDeleteTextures(1, texture.raw.addr)
    except GlError:
      discard


proc newTexture*(kind: TextureKind = Texture2d): Texture =
  case kind
  of Texture2dMultisample:
    var id: GlUint
    glGenTextures(1, id.addr)
    result = Texture(
      raw: id,
      kind: kind
    )
  
  of Texture2d:
    if freeTextures.len == 0:
      var newTextureGlUids: array[rice_render_texturesToAllocateIfNoFree, GlUint]
      glGenTextures(rice_render_texturesToAllocateIfNoFree, newTextureGlUids[0].addr)
      for i in 0..<rice_render_texturesToAllocateIfNoFree:
        freeTextures.incl newTextureGlUids[i]
    
    result = Texture(
      raw: freeTextures.pop,
      kind: kind
    )


proc load*(texture: Texture, image: pixie.Image) =
  texture.raw.loadTexture(image)

proc newTexture*(image: pixie.Image): Texture =
  result = newTexture()
  result.load(image)


when hasImageman:
  proc load*(texture: Texture, image: imagemanImages.Image[imagemanColors.ColorRgbau]) =
    texture.raw.loadTexture(image)

  proc newTexture*(image: imagemanImages.Image[imagemanColors.ColorRgbau]): Texture =
    result = newTexture()
    result.load(image)
