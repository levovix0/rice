import std/[unicode, tables, math]
import pkg/[chroma, shady, bumpy]
import pkg/pixie/[fonts, images, paints]
import ./[gl, contexts]

type
  TextDrawContext* = object
    family: ptr GlyphFamilyBuffer
    transform: OpenglUniform[Vec4]
    placement: OpenglUniform[Vec4]
    color*: OpenglUniform[Vec4]
    prevTexture: GlUint = (-1).GlUint
    font: Font


const rice_glyphBuffer_textureSize* {.intdefine.} = 1024

const ts = rice_glyphBuffer_textureSize


proc render(familyBuffer: var GlyphFamilyBuffer, placement: var GlyphPlacement, rune: Rune, font: Font, size: Vec2) =
  let w = size.x.ceil.int16
  let h = size.y.ceil.int16

  if familyBuffer.freeY + h > ts or familyBuffer.textures.len == 0:
    # we need new texture
    var textureId: GlUint
    glGenTextures(1, textureId.addr)
    familyBuffer.textures.add textureId

    glBindTexture(GlTexture2d, textureId)

    let buffer = alloc0(ts * ts * 4)

    glTexImage2D(GlTexture2d, 0, GlRgba.GLint, ts.GLsizei, ts.GLsizei, 0, GlRgba, GlUnsignedByte, buffer)
    glGenerateMipmap(GlTexture2d)

    glBindTexture(GlTexture2d, 0)

    dealloc buffer

    familyBuffer.freeX = 0
    familyBuffer.freeY = 0
    familyBuffer.freeH = h
  
  elif familyBuffer.freeX + w > ts:
    # we need new line
    familyBuffer.freeX = 0
    familyBuffer.freeY = familyBuffer.freeY + familyBuffer.freeH
    familyBuffer.freeH = h
  
  placement.texture = familyBuffer.textures[^1]
  placement.x = familyBuffer.freeX
  placement.y = familyBuffer.freeY
  
  familyBuffer.freeX = familyBuffer.freeX + w + 1
  if h > familyBuffer.freeH:
    familyBuffer.freeH = h
  
  if w == 0 or h == 0: return

  let image = newImage(w.int, h.int)
  image.fill(color(0, 0, 0, 0))

  let paint = font.paint
  font.paint = newPaint(SolidPaint)
  font.paint.color = color(1, 1, 1, 1)
  
  image.fillText(font.typeset($rune))

  font.paint = paint

  try:  # todo: sometimes crushes on big text sizes
    glBindTexture(GlTexture2d, placement.texture)
    glTexSubImage2D(GlTexture2d, 0, placement.x, placement.y, w, h, GlRgba, GlUnsignedByte, image.data[0].addr)
  except Glerror: discard


proc renderIfNeeded(familyBuffer: var GlyphFamilyBuffer, rune: Rune, font: Font, size: Vec2): GlyphPlacement =
  let placement = familyBuffer.placements.mgetOrPut(rune, GlyphPlacement()).addr

  if placement[].texture == 0:
    render(familyBuffer, placement[], rune, font, size)

  result = placement[]


proc glyphFamily(font: Font): GlyphFamily =
  GlyphFamily(
    typefaceId: cast[int](font.typeface),
    size: font.size,
    underline: font.underline,
    strikethrough: font.strikethrough,
    noKerningAdjustments: font.noKerningAdjustments
  )


proc startRasterTextDrawing*(ctx: DrawContext, font: Font): TextDrawContext =
  let shader = ctx.makeShader:
    proc vert(transform: Uniform[Vec4], placement: Uniform[Vec4]) =
      var gl_Position {.outGl.}: Vec4
      var uv {.out.}: Vec2
      var ipos {.inp.}: Vec2
      
      gl_Position = vec4(transform.xy + ipos * transform.zw, vec2(0, 1))
      uv = placement.xy + ipos * placement.zw

    proc frag(color: Uniform[Vec4]) =
      var glCol {.outGl.}: Vec4

      let col = gltex.texture(uv)
      glCol = vec4(color.rgb * color.a, color.a) * col.r

  use shader.shader

  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  glBindVertexArray(ctx.rect.vao[0])

  TextDrawContext(
    family: ctx.glyphBuffer.families.mgetOrPut(font.glyphFamily, GlyphFamilyBuffer()).addr,
    transform: shader.transform,
    placement: shader.placement,
    color: shader.color,
    font: font,
  )

proc endRasterTextDrawing*(ctx: DrawContext) =
  glBindTexture(GlTexture2d, 0)
  glDisable(GlBlend)
  glBindVertexArray(0)


proc fastRasterDrawRune*(
  ctx: DrawContext,
  rune: Rune,
  rect: Rect,
  context: var TextDrawContext,
) =

  var rect = rect
  rect.wh = rect.wh + vec2(2, 2)
  
  context.transform.uniform =
    vec4(
      rect.xy,
      vec2(rect.w, -rect.h) * ctx.px
    )

  let texPlacement = context.family[].renderIfNeeded(rune, context.font, rect.wh)
  context.placement.uniform =
    vec4(
      vec2(texPlacement.x.float, texPlacement.y.float) /
      vec2(rice_glyphBuffer_textureSize, rice_glyphBuffer_textureSize),

      rect.wh /
      vec2(rice_glyphBuffer_textureSize, rice_glyphBuffer_textureSize)
    )
  
  if context.prevTexture != texPlacement.texture:
    glBindTexture(GlTexture2d, texPlacement.texture)
    glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
    context.prevTexture = texPlacement.texture

  glDrawElements(ctx.rect.kind, ctx.rect.len.GlSizei, GlUnsignedInt, nil)


proc drawRasterText*(
  ctx: DrawContext,
  pos: Vec3,
  arrangement: Arrangement,
  color: Vec4,
  origin: Vec2 = vec2(0, 0),
  exactBoundaries = false,
  transform = mat4(),
) =
  if arrangement == nil or arrangement.fonts.len == 0:
    return

  var context = ctx.startRasterTextDrawing(arrangement.fonts[0])
  context.color.uniform = color

  let pos = ctx.viewportToGlMatrix * transform * pos
  let box = arrangement.computeBounds()

  let offset =
    if exactBoundaries: vec2(box.x, -box.y) * ctx.px + vec2(box.w, -box.h) * origin * ctx.px
    else: vec2(box.w + box.x, -(box.h + box.y)) * origin * ctx.px

  for i, rune in arrangement.runes:
    var rect = arrangement.selectionRects[i]
    rect.wh = rect.wh + vec2(2, 2)
    
    ctx.fastRasterDrawRune(rune, rect(pos.xy + vec2(rect.x, -rect.y) * ctx.px - offset, rect.wh), context)
  
  ctx.endRasterTextDrawing()
