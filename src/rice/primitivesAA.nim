import pkg/[vmath, shady]
import ./[gl, contexts]

## drawing primitives with fragment shader antialiasing
## todo: make api the same as in ./primitives


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


proc drawRect*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, angle: float32) =
  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      glCol = vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a) * roundRect(pos, size.Vec2, radius.float)
  
  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  draw ctx.rect
  if blend: glDisable(GlBlend)


proc drawRectStroke*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, angle: float32, borderWidth: float32, tiled: bool, tileSize: Vec2, tileSecondSize: Vec2, secondColor: Vec4) =
  proc roundRectStroke(pos, size: Vec2, radius: float32, borderWidth: float32): float32 =
    if pos.x < radius + borderWidth and pos.y < radius + borderWidth:
      let d = length(pos - vec2(radius, radius) - vec2(borderWidth, borderWidth))
      return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))
    
    elif pos.x > size.x - radius - borderWidth and pos.y < radius + borderWidth:
      let d = length(pos - vec2(size.x - radius, radius) - vec2(-borderWidth, borderWidth))
      return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))
    
    elif pos.x < radius + borderWidth and pos.y > size.y - radius - borderWidth:
      let d = length(pos - vec2(radius, size.y - radius) - vec2(borderWidth, -borderWidth))
      return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))
    
    elif pos.x > size.x - radius - borderWidth and pos.y > size.y - radius - borderWidth:
      let d = length(pos - vec2(size.x - radius, size.y - radius) - vec2(-borderWidth, -borderWidth))
      return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))

    elif pos.x < borderWidth: return 1
    elif pos.y < borderWidth: return 1
    elif pos.x > size.x - borderWidth: return 1
    elif pos.y > size.y - borderWidth: return 1
    return 0

  proc strokeTiling(pos, size, tileSize, tileSecondSize: Vec2, radius, borderWidth: float32): float32 =
    if tileSize == size: return 0

    if (
      (pos.x < radius + borderWidth and pos.y < radius + borderWidth) or
      (pos.x > size.x - radius - borderWidth and pos.y < radius + borderWidth) or
      (pos.x < radius + borderWidth and pos.y > size.y - radius - borderWidth) or
      (pos.x > size.x - radius - borderWidth and pos.y > size.y - radius - borderWidth)
    ):
      return 0
    else:
      if pos.x <= borderWidth or pos.x >= size.x - borderWidth:
        var y = pos.y
        while y > 0:
          if y < tileSize.y: return 0
          y -= tileSize.y
          if y < tileSecondSize.y: return 1
          y -= tileSecondSize.y
      else:
        var x = pos.x
        while x > 0:
          if x < tileSize.x: return 0
          x -= tileSize.x
          if x < tileSecondSize.x: return 1
          x -= tileSecondSize.x
      return 1


  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
      borderWidth: Uniform[float],
      tileSize: Uniform[Vec2],
      tileSecondSize: Uniform[Vec2],
      secondColor: Uniform[Vec4],
    ) =
      if strokeTiling(pos, size.Vec2, tileSize.Vec2, tileSecondSize.Vec2, radius, borderWidth) > 0:
        glCol =
          vec4(secondColor.Vec4.rgb * secondColor.Vec4.a, secondColor.Vec4.a) *
          roundRectStroke(pos, size.Vec2, radius.float, borderWidth.float)
      else:
        glCol =
          vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a) *
          roundRectStroke(pos, size.Vec2, radius.float, borderWidth.float)
  
  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  shader.borderWidth.uniform = borderWidth
  if tiled:
    shader.tileSize.uniform = tileSize
    shader.tileSecondSize.uniform = tileSecondSize
  else:
    shader.tileSize.uniform = size
    shader.tileSecondSize.uniform = vec2(0, 0)
  shader.secondColor.uniform = secondColor
  draw ctx.rect
  if blend: glDisable(GlBlend)


proc drawImage*(
  ctx: DrawContext,
  pos: Vec2,
  size: Vec2,
  tex: GlUint,
  color: Vec4,
  radius: float32,
  blend: bool,
  angle: float32,
  flipY = false,
  imagePos = vec2(),
  imageSize = vec2(),
) =
  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      uv: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
      imPos: Uniform[Vec2],
      imSizeK: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)
      uv = ipos * imSizeK + imPos

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      uv: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      let c = gltex.texture(uv)
      glCol = vec4(c.rgb, c.a) * roundRect(pos, size.Vec2, radius.float) * vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  let imageSize = if imageSize == vec2(): size else: imageSize
  var imPos = imagePos / imageSize
  if flipY: imPos.y -= (size.y / imageSize.y)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle, flipY=flipY)
  shader.radius.uniform = radius
  shader.color.uniform = color
  shader.imPos.uniform = imPos
  shader.imSizeK.uniform = size / imageSize
  glBindTexture(GlTexture2d, tex)
  draw ctx.rect
  glBindTexture(GlTexture2d, 0)
  if blend: glDisable(GlBlend)


proc drawIcon*(ctx: DrawContext, pos: Vec2, size: Vec2, tex: GlUint, col: Vec4, radius: float32, blend: bool, angle: float32) =
  # draw image (with solid color)
  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      uv: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)
      uv = ipos

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      uv: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      let col = gltex.texture(uv)
      glCol = vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a) * col.a * roundRect(pos, size.Vec2, radius.float)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  glBindTexture(GlTexture2d, tex)
  draw ctx.rect
  glBindTexture(GlTexture2d, 0)
  if blend: glDisable(GlBlend)


proc drawShadowRect*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, blurRadius: float32, angle: float32) =
  proc distanceRoundRect(pos, size: Vec2, radius: float32, blurRadius: float32): float32 =
    if pos.x < radius + blurRadius and pos.y < radius + blurRadius:
      let d = length(pos - vec2(radius + blurRadius, radius + blurRadius))
      result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
    
    elif pos.x > size.x - radius - blurRadius and pos.y < radius + blurRadius:
      let d = length(pos - vec2(size.x - radius - blurRadius, radius + blurRadius))
      result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
    
    elif pos.x < radius + blurRadius and pos.y > size.y - radius - blurRadius:
      let d = length(pos - vec2(radius + blurRadius, size.y - radius - blurRadius))
      result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
    
    elif pos.x > size.x - radius - blurRadius and pos.y > size.y - radius - blurRadius:
      let d = length(pos - vec2(size.x - radius - blurRadius, size.y - radius - blurRadius))
      result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
    
    elif pos.x < blurRadius:
      result = (pos.x / blurRadius).max(0).min(1)

    elif pos.y < blurRadius:
      result = (pos.y / blurRadius).max(0).min(1)
    
    elif pos.x > size.x - blurRadius:
      result = ((size.x - pos.x) / blurRadius).max(0).min(1)

    elif pos.y > size.y - blurRadius:
      result = ((size.y - pos.y) / blurRadius).max(0).min(1)
    
    else:
      result = 1
    
    result *= result

  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      radius: Uniform[float],
      blurRadius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      glCol = vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a) * distanceRoundRect(pos, size.Vec2, radius.float, blurRadius.float)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  
  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  shader.blurRadius.uniform = blurRadius
  draw ctx.rect
  if blend: glDisable(GlBlend)


