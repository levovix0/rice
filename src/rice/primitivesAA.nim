## drawing primitives with fragment shader antialiasing

import pkg/[vmath, chroma]
import ./[gl, contexts]


const
  rectVertSrc = """
#version 300 es
precision highp float;

void transformation(inout vec4 glpos, inout vec2 pos, vec2 size, vec2 px, vec2 ipos, mat4 transform);

void transformation(
  inout vec4 glpos,
  inout vec2 pos,
  vec2 size,
  vec2 px,
  vec2 ipos,
  mat4 transform
) {
  vec2 scale = vec2(px.x * size.x, px.y * - (size.y));
  glpos = (transform * mat4(mat2(scale.x, 0.0, 0.0, scale.y))) * vec4(ipos, vec2(0.0, 1.0));
  pos = vec2(ipos.x * size.x, ipos.y * size.y);
}

out vec2 pos;
in vec2 ipos;
uniform mat4 transform;
uniform vec2 size;
uniform vec2 px;

void main() {
  transformation(gl_Position, pos, vec2(size), vec2(px), ipos, mat4(transform));
}
"""
  imageVertSrc = """
#version 300 es
precision highp float;

void transformation(inout vec4 glpos, inout vec2 pos, vec2 size, vec2 px, vec2 ipos, mat4 transform);

void transformation(
  inout vec4 glpos,
  inout vec2 pos,
  vec2 size,
  vec2 px,
  vec2 ipos,
  mat4 transform
) {
  vec2 scale = vec2(px.x * size.x, px.y * - (size.y));
  glpos = (transform * mat4(mat2(scale.x, 0.0, 0.0, scale.y))) * vec4(ipos, vec2(0.0, 1.0));
  pos = vec2(ipos.x * size.x, ipos.y * size.y);
}

out vec2 pos;
out vec2 uv;
in vec2 ipos;
uniform mat4 transform;
uniform vec2 size;
uniform vec2 px;
uniform vec2 imPos;
uniform vec2 imSizeK;

void main() {
  transformation(gl_Position, pos, vec2(size), vec2(px), ipos, mat4(transform));
  uv = ipos * imSizeK + imPos;
}
"""
  iconVertSrc = """
#version 300 es
precision highp float;

void transformation(inout vec4 glpos, inout vec2 pos, vec2 size, vec2 px, vec2 ipos, mat4 transform);

void transformation(
  inout vec4 glpos,
  inout vec2 pos,
  vec2 size,
  vec2 px,
  vec2 ipos,
  mat4 transform
) {
  vec2 scale = vec2(px.x * size.x, px.y * - (size.y));
  glpos = (transform * mat4(mat2(scale.x, 0.0, 0.0, scale.y))) * vec4(ipos, vec2(0.0, 1.0));
  pos = vec2(ipos.x * size.x, ipos.y * size.y);
}

out vec2 pos;
out vec2 uv;
in vec2 ipos;
uniform mat4 transform;
uniform vec2 size;
uniform vec2 px;

void main() {
  transformation(gl_Position, pos, vec2(size), vec2(px), ipos, mat4(transform));
  uv = ipos;
}
"""
  rectFragSrc = """
#version 300 es
precision highp float;

float roundRect(vec2 pos, vec2 size, float radius);

float roundRect(
  vec2 pos,
  vec2 size,
  float radius
) {
  float result;
  if (radius == 0.0) {
    result = 1.0;
    return result;
  }
  if ((pos.x < radius) && (pos.y < radius)) {
    float d = length(pos - vec2(radius, radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  } else if ((size.x - radius < pos.x) && (pos.y < radius)) {
    float d = length(pos - vec2(size.x - radius, radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  } else if ((pos.x < radius) && (size.y - radius < pos.y)) {
    float d = length(pos - vec2(radius, size.y - radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  } else if ((size.x - radius < pos.x) && (size.y - radius < pos.y)) {
    float d = length(pos - vec2(size.x - radius, size.y - radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  }
  result = 1.0;
  return result;
}

out vec4 glCol;
in vec2 pos;
uniform float radius;
uniform vec2 size;
uniform vec4 color;

void main() {
  glCol = vec4((vec4(color)).rgb * (vec4(color)).a, (vec4(color)).a) * roundRect(pos, vec2(size), float(float(radius)));
}
"""
  rectStrokeFragSrc = """
#version 300 es
precision highp float;

float roundRectStroke(vec2 pos, vec2 size, float radius, float borderWidth);
float strokeTiling(vec2 pos, vec2 size, vec2 tileSize, vec2 tileSecondSize, float radius, float borderWidth);

float roundRectStroke(
  vec2 pos,
  vec2 size,
  float radius,
  float borderWidth
) {
  float result;
  if ((pos.x < radius + borderWidth) && (pos.y < radius + borderWidth)) {
    float d = length((pos - vec2(radius, radius)) - vec2(borderWidth, borderWidth));
    result = float(min(max(float((radius + borderWidth) - d) + 0.5, 0.0), 1.0) * (1.0 - min(max(float(radius - d) + 0.5, 0.0), 1.0)));
    return result;
  } else if (((size.x - radius) - borderWidth < pos.x) && (pos.y < radius + borderWidth)) {
    float d = length((pos - vec2(size.x - radius, radius)) - vec2(- (borderWidth), borderWidth));
    result = float(min(max(float((radius + borderWidth) - d) + 0.5, 0.0), 1.0) * (1.0 - min(max(float(radius - d) + 0.5, 0.0), 1.0)));
    return result;
  } else if ((pos.x < radius + borderWidth) && ((size.y - radius) - borderWidth < pos.y)) {
    float d = length((pos - vec2(radius, size.y - radius)) - vec2(borderWidth, - (borderWidth)));
    result = float(min(max(float((radius + borderWidth) - d) + 0.5, 0.0), 1.0) * (1.0 - min(max(float(radius - d) + 0.5, 0.0), 1.0)));
    return result;
  } else if (((size.x - radius) - borderWidth < pos.x) && ((size.y - radius) - borderWidth < pos.y)) {
    float d = length((pos - vec2(size.x - radius, size.y - radius)) - vec2(- (borderWidth), - (borderWidth)));
    result = float(min(max(float((radius + borderWidth) - d) + 0.5, 0.0), 1.0) * (1.0 - min(max(float(radius - d) + 0.5, 0.0), 1.0)));
    return result;
  } else if (pos.x < borderWidth) {
    result = 1.0;
    return result;
  } else if (pos.y < borderWidth) {
    result = 1.0;
    return result;
  } else if (size.x - borderWidth < pos.x) {
    result = 1.0;
    return result;
  } else if (size.y - borderWidth < pos.y) {
    result = 1.0;
    return result;
  }
  result = 0.0;
  return result;
}
float strokeTiling(
  vec2 pos,
  vec2 size,
  vec2 tileSize,
  vec2 tileSecondSize,
  float radius,
  float borderWidth
) {
  float result;
  if (tileSize == size) {
    result = 0.0;
    return result;
  }
  if (((((pos.x < radius + borderWidth) && (pos.y < radius + borderWidth)) || (((size.x - radius) - borderWidth < pos.x) && (pos.y < radius + borderWidth))) || ((pos.x < radius + borderWidth) && ((size.y - radius) - borderWidth < pos.y))) || (((size.x - radius) - borderWidth < pos.x) && ((size.y - radius) - borderWidth < pos.y))) {
    result = 0.0;
    return result;
  } else {
    if ((pos.x <= borderWidth) || (size.x - borderWidth <= pos.x)) {
      float y = pos.y;
      while(0.0 < y) {
        if (y < tileSize.y) {
          result = 0.0;
          return result;
        }
        y -= tileSize.y;
        if (y < tileSecondSize.y) {
          result = 1.0;
          return result;
        }
        y -= tileSecondSize.y;
      }
    } else {
      float x = pos.x;
      while(0.0 < x) {
        if (x < tileSize.x) {
          result = 0.0;
          return result;
        }
        x -= tileSize.x;
        if (x < tileSecondSize.x) {
          result = 1.0;
          return result;
        }
        x -= tileSecondSize.x;
      }
    }
    result = 1.0;
    return result;
  }
}

out vec4 glCol;
in vec2 pos;
uniform float radius;
uniform vec2 size;
uniform vec4 color;
uniform float borderWidth;
uniform vec2 tileSize;
uniform vec2 tileSecondSize;
uniform vec4 secondColor;

void main() {
  if (0.0 < strokeTiling(pos, vec2(size), vec2(tileSize), vec2(tileSecondSize), float(radius), float(borderWidth))) {
    glCol = vec4((vec4(secondColor)).rgb * (vec4(secondColor)).a, (vec4(secondColor)).a) * roundRectStroke(pos, vec2(size), float(float(radius)), float(float(borderWidth)));
  } else {
    glCol = vec4((vec4(color)).rgb * (vec4(color)).a, (vec4(color)).a) * roundRectStroke(pos, vec2(size), float(float(radius)), float(float(borderWidth)));
  }
}
"""
  imageFragSrc = """
#version 300 es
precision highp float;

uniform highp sampler2D gltex;

float roundRect(vec2 pos, vec2 size, float radius);

float roundRect(
  vec2 pos,
  vec2 size,
  float radius
) {
  float result;
  if (radius == 0.0) {
    result = 1.0;
    return result;
  }
  if ((pos.x < radius) && (pos.y < radius)) {
    float d = length(pos - vec2(radius, radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  } else if ((size.x - radius < pos.x) && (pos.y < radius)) {
    float d = length(pos - vec2(size.x - radius, radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  } else if ((pos.x < radius) && (size.y - radius < pos.y)) {
    float d = length(pos - vec2(radius, size.y - radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  } else if ((size.x - radius < pos.x) && (size.y - radius < pos.y)) {
    float d = length(pos - vec2(size.x - radius, size.y - radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  }
  result = 1.0;
  return result;
}

out vec4 glCol;
in vec2 pos;
in vec2 uv;
uniform float radius;
uniform vec2 size;
uniform vec4 color;

void main() {
  vec4 c = texture(gltex, uv);
  glCol = (vec4(c.rgb, c.a) * roundRect(pos, vec2(size), float(float(radius)))) * vec4((vec4(color)).rgb * (vec4(color)).a, (vec4(color)).a);
}
"""
  iconFragSrc = """
#version 300 es
precision highp float;

uniform highp sampler2D gltex;

float roundRect(vec2 pos, vec2 size, float radius);

float roundRect(
  vec2 pos,
  vec2 size,
  float radius
) {
  float result;
  if (radius == 0.0) {
    result = 1.0;
    return result;
  }
  if ((pos.x < radius) && (pos.y < radius)) {
    float d = length(pos - vec2(radius, radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  } else if ((size.x - radius < pos.x) && (pos.y < radius)) {
    float d = length(pos - vec2(size.x - radius, radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  } else if ((pos.x < radius) && (size.y - radius < pos.y)) {
    float d = length(pos - vec2(radius, size.y - radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  } else if ((size.x - radius < pos.x) && (size.y - radius < pos.y)) {
    float d = length(pos - vec2(size.x - radius, size.y - radius));
    result = float(min(max(float(radius - d) + 0.5, 0.0), 1.0));
    return result;
  }
  result = 1.0;
  return result;
}

out vec4 glCol;
in vec2 pos;
in vec2 uv;
uniform float radius;
uniform vec2 size;
uniform vec4 color;

void main() {
  vec4 col = texture(gltex, uv);
  glCol = (vec4((vec4(color)).rgb * (vec4(color)).a, (vec4(color)).a) * col.a) * roundRect(pos, vec2(size), float(float(radius)));
}
"""
  shadowRectFragSrc = """
#version 300 es
precision highp float;

float distanceRoundRect(vec2 pos, vec2 size, float radius, float blurRadius);

float distanceRoundRect(
  vec2 pos,
  vec2 size,
  float radius,
  float blurRadius
) {
  float result;
  if ((pos.x < radius + blurRadius) && (pos.y < radius + blurRadius)) {
    float d = length(pos - vec2(radius + blurRadius, radius + blurRadius));
    result = min(max(((radius + blurRadius) - d) / blurRadius, 0.0), 1.0);
  } else if (((size.x - radius) - blurRadius < pos.x) && (pos.y < radius + blurRadius)) {
    float d = length(pos - vec2((size.x - radius) - blurRadius, radius + blurRadius));
    result = min(max(((radius + blurRadius) - d) / blurRadius, 0.0), 1.0);
  } else if ((pos.x < radius + blurRadius) && ((size.y - radius) - blurRadius < pos.y)) {
    float d = length(pos - vec2(radius + blurRadius, (size.y - radius) - blurRadius));
    result = min(max(((radius + blurRadius) - d) / blurRadius, 0.0), 1.0);
  } else if (((size.x - radius) - blurRadius < pos.x) && ((size.y - radius) - blurRadius < pos.y)) {
    float d = length(pos - vec2((size.x - radius) - blurRadius, (size.y - radius) - blurRadius));
    result = min(max(((radius + blurRadius) - d) / blurRadius, 0.0), 1.0);
  } else if (pos.x < blurRadius) {
    result = min(max(pos.x / blurRadius, 0.0), 1.0);
  } else if (pos.y < blurRadius) {
    result = min(max(pos.y / blurRadius, 0.0), 1.0);
  } else if (size.x - blurRadius < pos.x) {
    result = min(max((size.x - pos.x) / blurRadius, 0.0), 1.0);
  } else if (size.y - blurRadius < pos.y) {
    result = min(max((size.y - pos.y) / blurRadius, 0.0), 1.0);
  } else {
    result = 1.0;
  }
  result *= result;
  return result;
}

out vec4 glCol;
in vec2 pos;
uniform float radius;
uniform float blurRadius;
uniform vec2 size;
uniform vec4 color;

void main() {
  glCol = vec4((vec4(color)).rgb * (vec4(color)).a, (vec4(color)).a) * distanceRoundRect(pos, vec2(size), float(float(radius)), float(float(blurRadius)));
}
"""


proc fillRect*(
  ctx: DrawContext,
  pos: Vec2, size: Vec2,
  color: Color = color(1, 1, 1),
  radius: float32 = 0,
  blend: bool = true,
  angle: float32 = 0,
) =
  let shader = ctx.getShader(2001, rectVertSrc, rectFragSrc)
  
  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  shader.use()
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader["radius"].uniform = radius
  shader["color"].uniform = color.vec4
  draw ctx.rect
  if blend: glDisable(GlBlend)

proc drawRect*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, angle: float32) {.deprecated: "use fillRect instead".} =
  fillRect(ctx, pos, size, col.color, radius, blend, angle)


proc drawRect*(
  ctx: DrawContext,
  pos: Vec2, size: Vec2,
  color: Color = color(1, 1, 1),
  thickness: float32 = 0,
  radius: float32 = 0,
  blend: bool = true,
  angle: float32 = 0,
  tiled: bool = false,
  tileSize: Vec2 = vec2(),
  tileSecondSize: Vec2 = vec2(),
  secondColor: Color = color(0, 0, 0, 0),
) =
  let shader = ctx.getShader(2002, rectVertSrc, rectStrokeFragSrc)
  
  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  shader.use()
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader["radius"].uniform = radius
  shader["color"].uniform = color.vec4
  shader["borderWidth"].uniform = thickness
  if tiled:
    shader["tileSize"].uniform = tileSize
    shader["tileSecondSize"].uniform = tileSecondSize
  else:
    shader["tileSize"].uniform = size
    shader["tileSecondSize"].uniform = vec2(0, 0)
  shader["secondColor"].uniform = secondColor.vec4
  draw ctx.rect
  if blend: glDisable(GlBlend)


proc drawRectStroke*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, angle: float32, borderWidth: float32, tiled: bool, tileSize: Vec2, tileSecondSize: Vec2, secondColor: Vec4) {.deprecated: "use drawRect instead".} =
  drawRect(ctx, pos, size, col.color, borderWidth, radius, blend, angle, tiled, tileSize, tileSecondSize, secondColor.color)


proc drawImage*(
  ctx: DrawContext,
  pos: Vec2, size: Vec2, tex: GlUint,
  color: Color = color(1, 1, 1),
  radius: float32 = 0,
  blend: bool = true,
  angle: float32 = 0,
  flipY = false,
  imagePos = vec2(),
  imageSize = vec2(),
) =
  let shader = ctx.getShader(2003, imageVertSrc, imageFragSrc)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  let imageSize = if imageSize == vec2(): size else: imageSize
  var imPos = imagePos / imageSize
  if flipY: imPos.y -= (size.y / imageSize.y)

  shader.use()
  ctx.passTransform(shader, pos=pos, size=size, angle=angle, flipY=flipY)
  shader["radius"].uniform = radius
  shader["color"].uniform = color.vec4
  shader["imPos"].uniform = imPos
  shader["imSizeK"].uniform = size / imageSize
  glBindTexture(GlTexture2d, tex)
  draw ctx.rect
  glBindTexture(GlTexture2d, 0)
  if blend: glDisable(GlBlend)


proc drawIcon*(
  ctx: DrawContext,
  pos: Vec2, size: Vec2, tex: GlUint,
  color: Color = color(1, 1, 1),
  radius: float32 = 0,
  blend: bool = true,
  angle: float32 = 0,
) =
  # draw image (with solid color)
  let shader = ctx.getShader(2004, iconVertSrc, iconFragSrc)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  shader.use()
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader["radius"].uniform = radius
  shader["color"].uniform = color.vec4
  glBindTexture(GlTexture2d, tex)
  draw ctx.rect
  glBindTexture(GlTexture2d, 0)
  if blend: glDisable(GlBlend)


proc drawShadowRect*(
  ctx: DrawContext,
  pos: Vec2, size: Vec2, blurRadius: float32,
  color: Color = color(1, 1, 1),
  radius: float32 = 0,
  angle: float32 = 0,
) =
  let shader = ctx.getShader(2005, rectVertSrc, shadowRectFragSrc)

  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  
  shader.use()
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader["radius"].uniform = radius
  shader["color"].uniform = color.vec4
  shader["blurRadius"].uniform = blurRadius
  draw ctx.rect
  
  glDisable(GlBlend)


