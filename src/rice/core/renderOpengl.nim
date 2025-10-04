## uses OpenGl to draw looks

import siwin, pixie, shady
import gl, render

{.experimental: "overloadableEnums".}

type
  Shaders = object
    solid: tuple[
      shader: Shader,
      transform: GlInt,
      size: GlInt,
      px: GlInt,
      radius: GlInt,
      color: GlInt,
    ]

    image: tuple[
      shader: Shader,
      transform: GlInt,
    ]
    
    icon: tuple[
      shader: Shader,
      transform: GlInt,
      color: GlInt,
    ]

  OpenglRender* = ref object of Render
    rect: Shape
    shaders: Shaders
    blend: bool
    
    px: Vec2
    wh: Vec2


var tex: Uniform[Sampler2d]  # workaround shady#9


proc passTransform(r: OpenGlRender, shader: tuple, size: Vec2, transform: Mat4) =
  shader.transform.uniform = transform
  shader.size.uniform = size
  shader.px.uniform = r.px


proc mat4*(x: Mat2): Mat4 = discard
  ## note: this function exists in Glsl, but do not in vmath


proc initShaders: Shaders =
  proc transformation(glpos: var Vec4, pos: var Vec2, size, px, ipos: Vec2, transform: Mat4) =
    let scale = vec2(px.x * size.x, px.y * -size.y)
    glpos = transform * mat2(scale.x, 0, 0, scale.y).mat4 * vec4(ipos, vec2(0, 1))
    pos = vec2(ipos.x * size.x, ipos.y * size.y)

  proc roundRect(pos, size: Vec2, radius: float32): float32 =
    if radius == 0: return 1
    
    if pos.x < radius and pos.y < radius:
      let d = length(pos - vec2(radius, radius))
      return (radius - d + 0.5).max(0).min(1)
    
    elif pos.x > size.x - radius and pos.y < radius:
      let d = length(pos - vec2(size.x - radius, radius))
      return (radius - d + 0.5).max(0).min(1)
    
    elif pos.x < radius and pos.y > size.y - radius:
      let d = length(pos - vec2(radius, size.y - radius))
      return (radius - d + 0.5).max(0).min(1)
    
    elif pos.x > size.x - radius and pos.y > size.y - radius:
      let d = length(pos - vec2(size.x - radius, size.y - radius))
      return (radius - d + 0.5).max(0).min(1)

    return 1

  proc solidVert(
    gl_Position: var Vec4,
    pos: var Vec2,
    ipos: Vec2,
    transform: Uniform[Mat4],
    size: Uniform[Vec2],
    px: Uniform[Vec2],
  ) =
    transformation(gl_Position, pos, size, px, ipos, transform)

  proc solidFrag(
    glCol: var Vec4,
    pos: Vec2,
    radius: Uniform[float],
    size: Uniform[Vec2],
    color: Uniform[Vec4],
  ) =
    glCol = vec4(color.rgb * color.a, color.a) * roundRect(pos, size, radius)

  result.solid.shader = newShader {GlVertexShader: solidVert.toGLSL("330 core"), GlFragmentShader: solidFrag.toGLSL("330 core")}
  result.solid.transform = result.solid.shader["transform"]
  result.solid.size = result.solid.shader["size"]
  result.solid.px = result.solid.shader["px"]
  result.solid.radius = result.solid.shader["radius"]
  result.solid.color = result.solid.shader["color"]


  proc imageVert(
    gl_Position: var Vec4,
    uv: var Vec2,
    ipos: Vec2,
    transform: Uniform[Mat4],
  ) =
    gl_Position = transform * vec4(ipos, vec2(0, 1))
    uv = ipos

  proc imageFrag(
    glCol: var Vec4,
    uv: Vec2,
  ) =
    let color = tex.texture(uv)
    glCol = vec4(color.rgb, color.a)

  result.image.shader = newShader {GlVertexShader: imageVert.toGlsl("330 core"), GlFragmentShader: imageFrag.toGlsl("330 core")}
  result.image.transform = result.image.shader["transform"]


  proc iconFrag(
    glCol: var Vec4,
    uv: Vec2,
    color: Uniform[Vec4],
  ) =
    glCol = vec4(color.rgb * color.a, color.a) * tex.texture(uv).a

  result.icon.shader = newShader {GlVertexShader: imageVert.toGlsl("330 core"), GlFragmentShader: iconFrag.toGlsl("330 core")}
  result.icon.transform = result.icon.shader["transform"]
  result.icon.color = result.icon.shader["color"]


proc newOpenGlRenderer*(): OpenGlRender =
  new result
  result.blend = true

  result.shaders = initShaders()

  result.rect = newShape(
    [
      vec2(0, 1),   # top left
      vec2(0, 0),   # bottom left
      vec2(1, 0),   # bottom right
      vec2(1, 1),   # top right
    ],
    [
      0'u32, 1, 2,
      2, 3, 0,
    ]
  )


method fillRect*(render: OpenGlRender, color: Color, radius: float, size: Vec2, transform: Mat4) =
  if render.blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlZero)

  render.passTransform(render.shaders.solid, size, transform)
  render.shaders.solid.color.uniform = cast[Vec4](color)
  render.shaders.solid.radius.uniform = radius

  draw render.rect

  if render.blend:
    glDisable(GlBlend)
