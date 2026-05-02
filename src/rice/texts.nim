import std/[unicode, tables, math]
import pkg/[chroma, shady, bumpy]
import pkg/pixie/[fonts, images, paints]
import ./[gl, contexts]


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

  glBindTexture(GlTexture2d, placement.texture)
  glTexSubImage2D(GlTexture2d, 0, placement.x, placement.y, w, h, GlRgba, GlUnsignedByte, image.data[0].addr)


proc renderIfNeeded*(familyBuffer: var GlyphFamilyBuffer, rune: Rune, font: Font, size: Vec2): GlyphPlacement =
  let placement = familyBuffer.placements.mgetOrPut(rune, GlyphPlacement()).addr

  if placement[].texture == 0:
    render(familyBuffer, placement[], rune, font, size)

  result = placement[]


proc glyphFamily*(font: Font): GlyphFamily =
  GlyphFamily(
    typefaceId: cast[int](font.typeface),
    size: font.size,
    underline: font.underline,
    strikethrough: font.strikethrough,
    noKerningAdjustments: font.noKerningAdjustments
  )



proc drawText*(
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

  let pos = ctx.viewportToGlMatrix * transform * pos

  let shader = ctx.makeShader:
    proc vert(transform: Uniform[Vec4], placement: Uniform[Vec4]) =
      var gl_Position {.outGl.}: Vec4
      var uv {.out.}: Vec2
      var ipos {.inp.}: Vec2
      
      gl_Position = vec4(transform.xy + ipos * transform.zw, vec2(0, 1))
      uv = placement.xy + ipos * placement.zw

    proc frag =
      var glCol {.outGl.}: Vec4

      let col = gltex.texture(uv)
      glCol = vec4(@(color).rgb * @(color).a, @(color).a) * col.r

  useAndPassUniforms shader
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  let family = ctx.glyphBuffer.families.mgetOrPut(arrangement.fonts[0].glyphFamily, GlyphFamilyBuffer()).addr

  var prevTexture = -1.Gluint
  let box = arrangement.computeBounds()

  for i, rune in arrangement.runes:
    var rect = arrangement.selectionRects[i]
    rect.wh = rect.wh + vec2(2, 2)
    
    # todo: force pixie to adjust text to pixel grid while generating arrangement, for better alligning

    let offset =
      if exactBoundaries: vec2(box.x, -box.y) * ctx.px + vec2(box.w, -box.h) * origin * ctx.px
      else: vec2(box.w + box.x, -(box.h + box.y)) * origin * ctx.px
    
    shader.transform.uniform =
      vec4(
        pos.xy + vec2(rect.x, -rect.y) * ctx.px - offset,
        vec2(rect.w, -rect.h) * ctx.px
      )

    let texPlacement = family[].renderIfNeeded(rune, arrangement.fonts[0], rect.wh)
    shader.placement.uniform =
      vec4(
        vec2(texPlacement.x.float, texPlacement.y.float) /
        vec2(rice_glyphBuffer_textureSize, rice_glyphBuffer_textureSize),

        rect.wh /
        vec2(rice_glyphBuffer_textureSize, rice_glyphBuffer_textureSize)
      )
    
    if prevTexture != texPlacement.texture:
      glBindTexture(GlTexture2d, texPlacement.texture)
      glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
      prevTexture = texPlacement.texture

    draw ctx.rect
  
  glBindTexture(GlTexture2d, 0)
  glDisable(GlBlend)
