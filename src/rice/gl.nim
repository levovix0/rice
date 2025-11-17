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


  ShapeFlag = enum
    hasIndices
  
  Shape* = object
    kind: GlEnum
    len: int
    vao: VertexArrays
    bo: Buffers
    flags: set[ShapeFlag]


  OpenglUniform*[T] = distinct GlInt

  Texture* = ref TextureObj
  TextureObj = object
    glid: GlUint


var freeTextures*: HashSet[GlUint]


# -------- Buffers, VertexArrays --------
template makeOpenglObjectSeq(t, tobj, T, gen, del, newp) =
  proc `=destroy`(xobj {.inject.}: tobj) =
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
      var buffer: array[512, char]
      glGetShaderInfoLog(shad[i], 512, nil, cast[cstring](buffer.addr))
      free()
      raise ShaderCompileDefect.newException("failed to compile shader " & $(i+1) & ": " & $cast[cstring](buffer.addr))
  
  defer: free()

  result.obj = glCreateProgram()
  for i, x in shad:
    glAttachShader(result.obj, x)
  glLinkProgram(result.obj)
  if (var success: GlInt; glGetProgramiv(result.obj, GlLinkStatus, success.addr); success != GlTrue.GlInt):
    var buffer: array[512, char]
    glGetProgramInfoLog(result.obj, 512, nil, cast[cstring](buffer.addr))
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

proc `uniform=`*(i: GlInt, value: Mat4) =
  if i != -1:
    glUniformMatrix4fv(i, 1, GlFalse, cast[ptr GlFloat](value.unsafeaddr))


proc `uniform=`*[T](x: OpenglUniform[T], value: T) =
  x.GlInt.uniform = value


# -------- Shape --------
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


proc newShape*[T](vert: openarray[T], idx: openarray[GlUint], kind = GlTriangles): Shape =
  result.vao = newVertexArrays(1)
  result.bo = newBuffers(2)
  result.len = idx.len
  result.kind = kind
  result.flags = {ShapeFlag.hasIndices}

  withVertexArray result.vao[0]:
    glBindBuffer GlArrayBuffer, result.bo[0]
    arrayBufferData vert
    glBindBuffer GlElementArrayBuffer, result.bo[1]
    elementArrayBufferData idx
    makeAttributes T


proc newShape*[T](vert: openarray[T], kind = GlTriangles): Shape =
  result.vao = newVertexArrays(1)
  result.bo = newBuffers(1)
  result.len = vert.len
  result.kind = kind
  result.flags = {}

  withVertexArray result.vao[0]:
    glBindBuffer GlArrayBuffer, result.bo[0]
    arrayBufferData vert
    makeAttributes T


proc draw*(x: Shape) =
  assert x.len != 0, "trying to draw empty shape, probably uninitialized"
  withVertexArray x.vao[0]:
    if hasIndices in x.flags:
      glDrawElements(x.kind, x.len.GlSizei, GlUnsignedInt, nil)
    else:
      glDrawArrays(x.kind, 0, x.len.GlSizei)



#* ------------- textures ------------- *#

const rice_render_texturesToAllocateIfNoFree {.intdefine.} = 8

proc `=destroy`(texture: TextureObj) =
  freeTextures.incl texture.glid
  try:
    texture.glid.loadTexture(pixie.newImage(1, 1))  # load empty image to force opengl use less memory
  except GlError, PixieError:
    discard


proc raw*(texture: Texture): GlUint =
  texture.glid


proc newTexture*(): Texture =
  if freeTextures.len == 0:
    var newTextureGlUids: array[rice_render_texturesToAllocateIfNoFree, GlUint]
    glGenTextures(rice_render_texturesToAllocateIfNoFree, newTextureGlUids[0].addr)
    for i in 0..<rice_render_texturesToAllocateIfNoFree:
      freeTextures.incl newTextureGlUids[i]
  
  new result
  result.glid = freeTextures.pop


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
