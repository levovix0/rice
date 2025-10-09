import pkg/[bumpy, chroma, vmath, shady]
import ./[gl, transform, contexts]


proc push_blendRgbx* =
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

proc pop_blendRgbx* =
  glDisable(GlBlend)


proc push_multisampling* =
  glEnable(GlMultisample)

proc pop_multisampling* =
  glDisable(GlMultisample)


template withPushPop*(name, body: untyped) =
  `push name`()
  body
  `pop name`()

template withPushPopIf*(name, cond, body: untyped) =
  let b = cond
  if b: `push name`()
  body
  if b: `pop name`()


proc fillRect*(ctx: DrawContext, rect: Rect, color: Color, transform: Mat4 = mat4()) =
  let transform = combine(
    scale(vec3(rect.w, rect.h, 1)),
    translate(vec3(rect.x, rect.y, 0)),
    transform,
    ctx.viewportToGlMatrix,
  )

  let shader = ctx.makeShader:
    proc vert =
      var ipos {.inp.}: Vec2
      var gl_Position {.outGl.}: Vec4

      gl_Position = @(transform) * vec4(ipos.xy, vec2(0, 1))
    
    proc frag =
      var glCol {.outGl.}: Vec4
      
      glCol = @(color.vec4)

  withPushPopIf blendRgbx, color.a != 1:
    useAndPassUniforms shader
    draw ctx.rect





