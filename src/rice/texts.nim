import std/[unicode, tables, math]
import pkg/[shady, bumpy]
import pkg/pixie/fonts
import ./[gl, contexts, paths]

type
  TextDrawContext* = object
    meshFamily: ptr GlyphMeshBuffer
    transform: OpenglUniform[Mat4]
    color*: OpenglUniform[Vec4]
    font: Font


proc ensureMesh(buffer: var GlyphMeshBuffer, rune: Rune, typeface: Typeface, pixelScale: float32) =
  if rune notin buffer.meshes:
    buffer.meshes[rune] = typeface.getGlyphPath(rune).toMesh(pixelScale)


proc glyphFamily(font: Font): GlyphMeshFamilyKey =
  GlyphMeshFamilyKey(typefaceId: cast[int](font.typeface))


proc startTextDrawing*(ctx: DrawContext, font: Font): TextDrawContext =
  let shader = ctx.makeShader:
    proc vert(transform: Uniform[Mat4]) =
      var gl_Position {.outGl.}: Vec4
      var ipos {.inp.}: Vec2
      gl_Position = transform * vec4(ipos.xy, vec2(0, 1))

    proc frag(color: Uniform[Vec4]) =
      var glCol {.outGl.}: Vec4
      glCol = vec4(color.rgb * color.a, color.a)

  use shader.shader

  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  TextDrawContext(
    meshFamily: ctx.glyphMeshes.mgetOrPut(font.glyphFamily, GlyphMeshBuffer()).addr,
    transform: shader.transform,
    color: shader.color,
    font: font,
  )

proc endTextDrawing*(ctx: DrawContext) =
  glDisable(GlBlend)


proc fastDrawRune*(
  ctx: DrawContext,
  rune: Rune,
  textPos: Vec2,
  textToGl: Mat4,
  context: var TextDrawContext,
  pixelScale: float32 = 1/10,
) =
  context.transform.uniform =
    textToGl *
    translate(vec3(textPos.x, textPos.y, 0))

  context.meshFamily[].ensureMesh(rune, context.font.typeface, pixelScale)
  draw context.meshFamily[].meshes[rune]


proc fastDrawRune*(
  ctx: DrawContext,
  rune: Rune,
  rect: Rect,
  context: var TextDrawContext,
  pixelScale: float32 = 1/10,
) {.deprecated: "use ctx.fastDrawRune(Rune, Vec2, Mat4, ...) instead".} =
  let typeface = context.font.typeface
  let fontScale = context.font.size / typeface.scale
  let ascentPx = round((typeface.ascent + typeface.lineGap / 2) * fontScale)

  # baseline position in GL clip space: rect.xy is top-left of selection rect
  let baseline = vec2(rect.x, rect.y - ascentPx * ctx.px.y)

  # convert from font-unit space (y-down, baseline at 0) to GL clip space (y-up)
  context.transform.uniform =
    translate(vec3(baseline.x, baseline.y, 0)) *
    scale(vec3(fontScale * ctx.px.x, -(fontScale * ctx.px.y), 1))

  context.meshFamily[].ensureMesh(rune, typeface, pixelScale)
  draw context.meshFamily[].meshes[rune]


proc drawText*(
  ctx: DrawContext,
  pos: Vec3,
  arrangement: Arrangement,
  color: Vec4,
  origin: Vec2 = vec2(0, 0),
  exactBoundaries = false,
  transform = mat4(),
  pixelScale: float32 = 1/10,
  axisYUp = true,
) =
  ## transform is applied in text-local space (rotate/scale around text origin), then translated to pos.
  if arrangement == nil or arrangement.fonts.len == 0:
    return

  var context = ctx.startTextDrawing(arrangement.fonts[0])
  context.color.uniform = color
  
  let box = arrangement.computeBounds()
  var offset =
    if exactBoundaries: -(box.xy + box.wh * origin)
    else: -(box.xy + box.wh) * origin
  if axisYUp: offset.y = -offset.y

  let textToGl =
    ctx.viewportToGlMatrix *
    translate(pos) *
    transform *
    translate((offset).vec3(0)) *
    scale((1/context.font.typeface.scale).vec3) *
    scale(context.font.size.vec3) *
    scale(vec3(1, (if axisYUp: -1 else: 1), 1))

  for i, rune in arrangement.runes:
    ctx.fastDrawRune(rune, arrangement.positions[i] * (context.font.typeface.scale / context.font.size), textToGl, context, pixelScale)

  ctx.endTextDrawing()
