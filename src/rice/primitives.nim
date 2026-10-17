import pkg/[bumpy, chroma, vmath]
import ./[gl, transform, contexts]


## this module defines functions to draw (stroke) and fill 2D
##   lines, rectangles, round rectangles, circles
## in 3D space, using triangulation at vertex shader time
## stroke can be with/without thickness (without thickness this uses GL_LINES)


proc rotate*(v: Vec3, axis: Vec3, angle: float32): Vec3 =
  let axisNorm = axis / length(axis)
  v * cos(angle) + cross(v, axisNorm) * sin(angle) + axisNorm * v.dot(axisNorm) * (1 - cos(angle))



const
  lineVertSrc = """
#version 300 es
precision highp float;

vec4 lineShape(float t, vec3 startPoint, vec3 endPoint);

vec4 lineShape(
  float t,
  vec3 startPoint,
  vec3 endPoint
) {
  vec4 result;
  // returns points of a line
  result = vec4(startPoint + (endPoint - startPoint) * t, 1.0);
  return result;
}

uniform mat4 u_transform;
uniform vec3 u_a;
uniform vec3 u_b;

void main() {
  gl_Position = u_transform * lineShape(float(gl_VertexID), u_a, u_b);
}
"""
  lineThickVertSrc = """
#version 300 es
precision highp float;

vec4 lineShape(float t, vec3 startPoint, vec3 endPoint);

vec4 lineShape(
  float t,
  vec3 startPoint,
  vec3 endPoint
) {
  vec4 result;
  // returns points of a line
  result = vec4(startPoint + (endPoint - startPoint) * t, 1.0);
  return result;
}

uniform mat4 u_transform;
uniform vec3 u_a;
uniform vec3 u_b;
uniform vec3 u_y;
uniform float u_thickness;

void main() {
  gl_Position = u_transform * (lineShape(floor(float(gl_VertexID) / 2.0), u_a, u_b) + vec4((u_y * float(float(mod(float(gl_VertexID), 2.0)) - 0.5)) * u_thickness, 0.0));
}
"""
  rectVertSrc = """
#version 300 es
precision highp float;

vec4 rectShape(float t, vec2 size, vec3 center, mat4 plane);

vec4 rectShape(
  float t,
  vec2 size,
  vec3 center,
  mat4 plane
) {
  vec4 result;
  // returns points of a rect
  int i = int(round(mod(t, 1.0) * 4.0));
  float x = float((((i == 1) || (i == 2)) ? (1.0) : (0.0))) - 0.5;
  float y = float((((i == 2) || (i == 3)) ? (1.0) : (0.0))) - 0.5;
  result = vec4(center, 1.0) + plane * vec4(vec2(float(x * float(size.x)), float(y * float(size.y))), vec2(0.0, 0.0));
  return result;
}

uniform mat4 u_transform;
uniform vec2 u_size;
uniform vec3 u_center;
uniform mat4 u_plane;

void main() {
  gl_Position = u_transform * rectShape(float(gl_VertexID) / 4.0, u_size, u_center, u_plane);
}
"""
  rectThickVertSrc = """
#version 300 es
precision highp float;

vec4 rectShape(float t, vec2 size, vec3 center, mat4 plane);

vec4 rectShape(
  float t,
  vec2 size,
  vec3 center,
  mat4 plane
) {
  vec4 result;
  // returns points of a rect
  int i = int(round(mod(t, 1.0) * 4.0));
  float x = float((((i == 1) || (i == 2)) ? (1.0) : (0.0))) - 0.5;
  float y = float((((i == 2) || (i == 3)) ? (1.0) : (0.0))) - 0.5;
  result = vec4(center, 1.0) + plane * vec4(vec2(float(x * float(size.x)), float(y * float(size.y))), vec2(0.0, 0.0));
  return result;
}

uniform mat4 u_transform;
uniform vec2 u_size;
uniform float u_thickness;
uniform vec3 u_center;
uniform mat4 u_plane;

void main() {
  gl_Position = u_transform * rectShape(floor(float(gl_VertexID) / 2.0) / 4.0, u_size - ((vec2(1.0, 1.0) * mod(float(gl_VertexID), 2.0)) * u_thickness) * 2.0, u_center, u_plane);
}
"""
  roundRectVertSrc = """
#version 300 es
precision highp float;

vec4 roundRectShape(float t, vec2 size, vec3 center, mat4 plane, float tl, float tr, float bl, float br);
vec2 rotate(vec2 v, float angle_rad);

vec4 roundRectShape(
  float t,
  vec2 size,
  vec3 center,
  mat4 plane,
  float tl,
  float tr,
  float bl,
  float br
) {
  vec4 result;
  // returns points of a round rect
  // tl - top left radius
  // tr - top right radius
  // bl - bottom left radius
  // br - bottom right radius
  int i = int(floor(mod(t, 1.0) * 4.0));
  vec2 p = vec2(0.0, 0.0);
  switch(i) {
  case 0:{
    p = vec2(bl, bl) + rotate(vec2(- (bl), 0.0), float(float(mod(t * 4.0, 1.0)) * 1.5707963267948966));
  }; break;
  case 1:{
    p = vec2(size.x - br, br) + rotate(vec2(0.0, - (br)), float(float(mod(t * 4.0, 1.0)) * 1.5707963267948966));
  }; break;
  case 2:{
    p = vec2(size.x - tr, size.y - tr) + rotate(vec2(tr, 0.0), float(float(mod(t * 4.0, 1.0)) * 1.5707963267948966));
  }; break;
  case 3:{
    p = vec2(tl, size.y - tl) + rotate(vec2(0.0, tl), float(float(mod(t * 4.0, 1.0)) * 1.5707963267948966));
  }; break;
  default: {
    ;
  }; break;
  }
  result = vec4(center, 1.0) + plane * vec4(p - size / 2.0, vec2(0.0, 0.0));
  return result;
}
vec2 rotate(
  vec2 v,
  float angle_rad
) {
  vec2 result;
  result = v * cos(angle_rad) + vec2(- (v.y), v.x) * sin(angle_rad);
  return result;
}

uniform mat4 u_transform;
uniform float u_pointCount;
uniform vec2 u_size;
uniform vec3 u_center;
uniform mat4 u_plane;
uniform float u_tl;
uniform float u_tr;
uniform float u_bl;
uniform float u_br;

void main() {
  gl_Position = u_transform * roundRectShape(float(gl_VertexID) / u_pointCount, u_size, u_center, u_plane, u_tl, u_tr, u_bl, u_br);
}
"""
  roundRectThickVertSrc = """
#version 300 es
precision highp float;

vec4 roundRectShape(float t, vec2 size, vec3 center, mat4 plane, float tl, float tr, float bl, float br);
vec2 rotate(vec2 v, float angle_rad);

vec4 roundRectShape(
  float t,
  vec2 size,
  vec3 center,
  mat4 plane,
  float tl,
  float tr,
  float bl,
  float br
) {
  vec4 result;
  // returns points of a round rect
  // tl - top left radius
  // tr - top right radius
  // bl - bottom left radius
  // br - bottom right radius
  int i = int(floor(mod(t, 1.0) * 4.0));
  vec2 p = vec2(0.0, 0.0);
  switch(i) {
  case 0:{
    p = vec2(bl, bl) + rotate(vec2(- (bl), 0.0), float(float(mod(t * 4.0, 1.0)) * 1.5707963267948966));
  }; break;
  case 1:{
    p = vec2(size.x - br, br) + rotate(vec2(0.0, - (br)), float(float(mod(t * 4.0, 1.0)) * 1.5707963267948966));
  }; break;
  case 2:{
    p = vec2(size.x - tr, size.y - tr) + rotate(vec2(tr, 0.0), float(float(mod(t * 4.0, 1.0)) * 1.5707963267948966));
  }; break;
  case 3:{
    p = vec2(tl, size.y - tl) + rotate(vec2(0.0, tl), float(float(mod(t * 4.0, 1.0)) * 1.5707963267948966));
  }; break;
  default: {
    ;
  }; break;
  }
  result = vec4(center, 1.0) + plane * vec4(p - size / 2.0, vec2(0.0, 0.0));
  return result;
}
vec2 rotate(
  vec2 v,
  float angle_rad
) {
  vec2 result;
  result = v * cos(angle_rad) + vec2(- (v.y), v.x) * sin(angle_rad);
  return result;
}

uniform float u_thickness;
uniform mat4 u_transform;
uniform float u_pointCount;
uniform vec2 u_size;
uniform vec3 u_center;
uniform mat4 u_plane;
uniform float u_tl;
uniform float u_tr;
uniform float u_bl;
uniform float u_br;

void main() {
  float thk = mod(float(gl_VertexID), 2.0) * u_thickness;
  gl_Position = u_transform * roundRectShape(floor(float(gl_VertexID) / 2.0) / u_pointCount, u_size - (vec2(1.0, 1.0) * thk) * 2.0, u_center, u_plane, max(0.0, u_tl - thk), max(0.0, u_tr - thk), max(0.0, u_bl - thk), max(0.0, u_br - thk));
}
"""
  circleVertSrc = """
#version 300 es
precision highp float;

vec4 circleShape(float t, float radius, vec3 center, mat4 plane);
vec2 rotate(vec2 v, float angle_rad);

vec4 circleShape(
  float t,
  float radius,
  vec3 center,
  mat4 plane
) {
  vec4 result;
  // returns points of a circle
  result = vec4(center, 1.0) + plane * vec4(rotate(vec2(radius, 0.0), float(float(t) * 6.283185307179586)), vec2(0.0, 0.0));
  return result;
}
vec2 rotate(
  vec2 v,
  float angle_rad
) {
  vec2 result;
  result = v * cos(angle_rad) + vec2(- (v.y), v.x) * sin(angle_rad);
  return result;
}

uniform mat4 u_transform;
uniform float u_pointCount;
uniform float u_radius;
uniform vec3 u_center;
uniform mat4 u_plane;

void main() {
  gl_Position = u_transform * circleShape(float(gl_VertexID) / u_pointCount, u_radius, u_center, u_plane);
}
"""
  circleThickVertSrc = """
#version 300 es
precision highp float;

vec4 circleShape(float t, float radius, vec3 center, mat4 plane);
vec2 rotate(vec2 v, float angle_rad);

vec4 circleShape(
  float t,
  float radius,
  vec3 center,
  mat4 plane
) {
  vec4 result;
  // returns points of a circle
  result = vec4(center, 1.0) + plane * vec4(rotate(vec2(radius, 0.0), float(float(t) * 6.283185307179586)), vec2(0.0, 0.0));
  return result;
}
vec2 rotate(
  vec2 v,
  float angle_rad
) {
  vec2 result;
  result = v * cos(angle_rad) + vec2(- (v.y), v.x) * sin(angle_rad);
  return result;
}

uniform mat4 u_transform;
uniform float u_pointCount;
uniform float u_radius;
uniform float u_thickness;
uniform vec3 u_center;
uniform mat4 u_plane;

void main() {
  gl_Position = u_transform * circleShape(floor(float(gl_VertexID) / 2.0) / u_pointCount, u_radius - mod(float(gl_VertexID), 2.0) * u_thickness, u_center, u_plane);
}
"""
  capsuleVertSrc = """
#version 300 es
precision highp float;

vec4 capsuleShape(float t, vec3 a, vec3 b, vec3 dir, vec3 perp, float radius);

vec4 capsuleShape(
  float t,
  vec3 a,
  vec3 b,
  vec3 dir,
  vec3 perp,
  float radius
) {
  vec4 result;
  // returns points of a capsule outline (segment with round caps)
  // t in [0, 0.5) — semicircle around a, t in [0.5, 1) — semicircle around b
  vec3 pos = vec3(0.0);
  if (float(t) < 0.5) {
    float angle = float(1.5707963267948966 + float(t) * 6.283185307179586);
    pos = a + radius * (cos(angle) * dir + sin(angle) * perp);
  } else {
    float angle = float(-1.5707963267948966 + (float(t) - 0.5) * 6.283185307179586);
    pos = b + radius * (cos(angle) * dir + sin(angle) * perp);
  }
  result = vec4(pos, 1.0);
  return result;
}

uniform mat4 u_transform;
uniform float u_pointCount;
uniform vec3 u_a;
uniform vec3 u_b;
uniform vec3 u_dir;
uniform vec3 u_perp;
uniform float u_radius;

void main() {
  gl_Position = u_transform * capsuleShape(float(gl_VertexID) / u_pointCount, u_a, u_b, u_dir, u_perp, u_radius);
}
"""
  capsuleThickVertSrc = """
#version 300 es
precision highp float;

vec4 capsuleShape(float t, vec3 a, vec3 b, vec3 dir, vec3 perp, float radius);

vec4 capsuleShape(
  float t,
  vec3 a,
  vec3 b,
  vec3 dir,
  vec3 perp,
  float radius
) {
  vec4 result;
  // returns points of a capsule outline (segment with round caps)
  // t in [0, 0.5) — semicircle around a, t in [0.5, 1) — semicircle around b
  vec3 pos = vec3(0.0);
  if (float(t) < 0.5) {
    float angle = float(1.5707963267948966 + float(t) * 6.283185307179586);
    pos = a + radius * (cos(angle) * dir + sin(angle) * perp);
  } else {
    float angle = float(-1.5707963267948966 + (float(t) - 0.5) * 6.283185307179586);
    pos = b + radius * (cos(angle) * dir + sin(angle) * perp);
  }
  result = vec4(pos, 1.0);
  return result;
}

uniform float u_thickness;
uniform mat4 u_transform;
uniform float u_pointCount;
uniform vec3 u_a;
uniform vec3 u_b;
uniform vec3 u_dir;
uniform vec3 u_perp;
uniform float u_radius;

void main() {
  float thk = mod(float(gl_VertexID), 2.0) * u_thickness;
  gl_Position = u_transform * capsuleShape(floor(float(gl_VertexID) / 2.0) / u_pointCount, u_a, u_b, u_dir, u_perp, u_radius - thk);
}
"""
  solidColorFragSrc = """
#version 300 es
precision highp float;

uniform vec4 u_color;
out vec4 glCol;

void main() {
  glCol = u_color;
}
"""


# --- Line ---

proc drawLine*(
  ctx: DrawContext,
  a, b: Vec3,
  color: Color = color(1, 1, 1),
  transform: Mat4 = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform

  let shader = ctx.getShader(1001, lineVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_a"].uniform = a
  shader["u_b"].uniform = b
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_LINES, 2)


proc drawLine*(
  ctx: DrawContext,
  a, b: Vec3,
  thickness: float32,
  color: Color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform
  let y = (b - a).rotate(normal, PI/2)

  let shader = ctx.getShader(1002, lineThickVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_a"].uniform = a
  shader["u_b"].uniform = b
  shader["u_y"].uniform = y / length(y)
  shader["u_thickness"].uniform = thickness
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, 4)



# --- Rect ---

proc drawRect*(
  ctx: DrawContext,
  center: Vec3, size: Vec2,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.getShader(1003, rectVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_size"].uniform = size
  shader["u_center"].uniform = center
  shader["u_plane"].uniform = plane
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_LINE_LOOP, 4)


proc drawRect*(
  ctx: DrawContext,
  center: Vec3, size: Vec2,
  thickness: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.getShader(1004, rectThickVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_size"].uniform = size
  shader["u_thickness"].uniform = thickness
  shader["u_center"].uniform = center
  shader["u_plane"].uniform = plane
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, 10)


proc fillRect*(
  ctx: DrawContext,
  center: Vec3, size: Vec2,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.getShader(1005, rectVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_size"].uniform = size
  shader["u_center"].uniform = center
  shader["u_plane"].uniform = plane
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_TRIANGLE_FAN, 4)



# --- Round rect ---

proc drawRoundRect*(
  ctx: DrawContext,
  center: Vec3, size: Vec2,
  tl, tr, bl, br: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 64,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.getShader(1006, roundRectVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_pointCount"].uniform = pointCount.float32
  shader["u_size"].uniform = size
  shader["u_center"].uniform = center
  shader["u_plane"].uniform = plane
  shader["u_tl"].uniform = tl
  shader["u_tr"].uniform = tr
  shader["u_bl"].uniform = bl
  shader["u_br"].uniform = br
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_LINE_LOOP, pointCount)


proc drawRoundRect*(
  ctx: DrawContext,
  center: Vec3, size: Vec2,
  tl, tr, bl, br: float32,
  thickness: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 64,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.getShader(1007, roundRectThickVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_thickness"].uniform = thickness
  shader["u_transform"].uniform = transform
  shader["u_pointCount"].uniform = pointCount.float32
  shader["u_size"].uniform = size
  shader["u_center"].uniform = center
  shader["u_plane"].uniform = plane
  shader["u_tl"].uniform = tl
  shader["u_tr"].uniform = tr
  shader["u_bl"].uniform = bl
  shader["u_br"].uniform = br
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, pointCount * 2 + 2)


proc fillRoundRect*(
  ctx: DrawContext,
  center: Vec3, size: Vec2,
  tl, tr, bl, br: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 64,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.getShader(1008, roundRectVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_pointCount"].uniform = pointCount.float32
  shader["u_size"].uniform = size
  shader["u_center"].uniform = center
  shader["u_plane"].uniform = plane
  shader["u_tl"].uniform = tl
  shader["u_tr"].uniform = tr
  shader["u_bl"].uniform = bl
  shader["u_br"].uniform = br
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_TRIANGLE_FAN, pointCount)



# --- Circle ---

proc drawCircle*(
  ctx: DrawContext,
  center: Vec3, radius: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.getShader(1009, circleVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_pointCount"].uniform = pointCount.float32
  shader["u_radius"].uniform = radius
  shader["u_center"].uniform = center
  shader["u_plane"].uniform = plane
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_LINE_LOOP, pointCount)


proc drawCircle*(
  ctx: DrawContext,
  center: Vec3, radius: float32,
  thickness: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.getShader(1010, circleThickVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_pointCount"].uniform = pointCount.float32
  shader["u_radius"].uniform = radius
  shader["u_thickness"].uniform = thickness
  shader["u_center"].uniform = center
  shader["u_plane"].uniform = plane
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, pointCount * 2 + 2)


proc fillCircle*(
  ctx: DrawContext,
  center: Vec3, radius: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.getShader(1011, circleVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_pointCount"].uniform = pointCount.float32
  shader["u_radius"].uniform = radius
  shader["u_center"].uniform = center
  shader["u_plane"].uniform = plane
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_TRIANGLE_FAN, pointCount)




# --- Capsule (round line) ---

proc fillCapsule*(
  ctx: DrawContext,
  a, b: Vec3, radius: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let dir = normalize(b - a)
  let perp = cross(normal, dir)

  let shader = ctx.getShader(1012, capsuleVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_pointCount"].uniform = pointCount.float32
  shader["u_a"].uniform = a
  shader["u_b"].uniform = b
  shader["u_dir"].uniform = dir.Vec3
  shader["u_perp"].uniform = perp.Vec3
  shader["u_radius"].uniform = radius
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_TRIANGLE_FAN, pointCount)


proc drawCapsule*(
  ctx: DrawContext,
  a, b: Vec3, radius: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let dir = normalize(b - a)
  let perp = cross(normal, dir)

  let shader = ctx.getShader(1013, capsuleVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_pointCount"].uniform = pointCount.float32
  shader["u_a"].uniform = a
  shader["u_b"].uniform = b
  shader["u_dir"].uniform = dir.Vec3
  shader["u_perp"].uniform = perp.Vec3
  shader["u_radius"].uniform = radius
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_LINE_LOOP, pointCount)


proc drawCapsule*(
  ctx: DrawContext,
  a, b: Vec3, radius: float32,
  thickness: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let dir = normalize(b - a)
  let perp = cross(normal, dir)

  let shader = ctx.getShader(1014, capsuleThickVertSrc, solidColorFragSrc)

  shader.use()
  shader["u_thickness"].uniform = thickness
  shader["u_transform"].uniform = transform
  shader["u_pointCount"].uniform = pointCount.float32
  shader["u_a"].uniform = a
  shader["u_b"].uniform = b
  shader["u_dir"].uniform = dir.Vec3
  shader["u_perp"].uniform = perp.Vec3
  shader["u_radius"].uniform = radius
  shader["u_color"].uniform = color.vec4
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, pointCount * 2 + 2)



proc fillRect*(ctx: DrawContext, rect: Rect, color: Color, transform: Mat4 = mat4()) =
  ctx.fillRect(color=color, size=rect.wh, center=(rect.xy + rect.wh/2).vec3(0), normal=vec3(0, 0, 1), transform=transform)

proc drawRoundRect*(
  ctx: DrawContext,
  center: Vec3, size: Vec2, radius: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  ctx.drawRoundRect(color=color, size=size, tl=radius, tr=radius, bl=radius, br=radius, center=center, normal=normal, transform=transform, pointCount=pointCount)

proc drawRoundRect*(
  ctx: DrawContext,
  center: Vec3, size: Vec2, radius: float32,
  thickness: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  ctx.drawRoundRect(color=color, thickness=thickness, size=size, tl=radius, tr=radius, bl=radius, br=radius, center=center, normal=normal, transform=transform, pointCount=pointCount)

proc fillRoundRect*(
  ctx: DrawContext,
  center: Vec3, size: Vec2, radius: float32,
  color = color(1, 1, 1),
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  ctx.fillRoundRect(color=color, size=size, tl=radius, tr=radius, bl=radius, br=radius, center=center, normal=normal, transform=transform, pointCount=pointCount)


proc drawLine*(ctx: DrawContext, a, b: Vec2, color: Color, transform: Mat4 = mat4()) =
  ctx.drawLine(a=vec3(a.x, a.y, 0), b=vec3(b.x, b.y, 0), color=color, transform=transform)




when isMainModule:
  import std/[times]
  import pkg/[siwin]

  let win = newOpenglWindow()
  opengl.loadExtensions()
  let ctx = newDrawContext()

  var time = 0'f32

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)


  win.eventsHandler.onRender = proc(e: RenderEvent) =
    glClearColor(0.1, 0.1, 0.1, 1)
    glClear(GL_COLOR_BUFFER_BIT)

    let (vw, vh) = (e.window.size.x, e.window.size.y)

    ctx.viewport = combine(
      scale(vec3(2 / vw, -2 / vh, 1)),
      translate(vec3(-1, 1, 0)),
    )

    ctx.fillRect(
      size = vec2(400, 200),
      center = vec3(vw/2, vh/2, 0),
      color = color(1, 0.2, 0.2),
      transform = rotateZ(
        origin = vec3(vw/2, vh/2, 0),
        angle = time / 4
      ),
    )  #! <----
    ctx.drawRect(
      size = vec2(400, 200),
      center = vec3(vw/2, vh/2, 0),
      color = color(0.2, 1, 0.2),
      transform = rotateZ(
        origin = vec3(vw/2, vh/2, 0),
        angle = (time + 1) / 4
      ),
    )  #! <----
    ctx.drawRect(
      size = vec2(400, 200),
      center = vec3(vw/2, vh/2, 0),
      color = color(0.2, 0.2, 1),
      thickness = 5,
      transform = rotateZ(
        origin = vec3(vw/2, vh/2, 0),
        angle = (time + 2) / 4
      ),
    )  #! <----

    ctx.fillRoundRect(
      size = vec2(200, 100),
      center = vec3(vw/2, vh/2, 0),
      color = color(1, 1, 1),
      radius = 20,
      transform = rotateZ(
        origin = vec3(vw/2, vh/2, 0),
        angle = time / 4
      ),
    )  #! <----
    ctx.drawRoundRect(
      size = vec2(200, 100),
      center = vec3(vw/2, vh/2, 0),
      color = color(0.2, 1, 0.2),
      radius = 20,
      transform = rotateZ(
        origin = vec3(vw/2, vh/2, 0),
        angle = (time + 1) / 4
      ),
    )  #! <----
    ctx.drawRoundRect(
      size = vec2(200, 100),
      center = vec3(vw/2, vh/2, 0),
      color = color(0.2, 0.2, 1),
      radius = 20,
      thickness = 5,
      transform = rotateZ(
        origin = vec3(vw/2, vh/2, 0),
        angle = (time + 2) / 4
      ),
    )  #! <----

    var center = vec3(vw/2, vh/2, 0)
    ctx.drawLine(a = center, b = center + vec3(100, 0, 0), color = color(1, 0.6, 0.6))   #! <----
    ctx.drawLine(a = center, b = center + vec3(0, 100, 0), color = color(0.2, 1, 0.2))   #! <----
    ctx.drawLine(a = center, b = center + vec3(0, 0, 100), color = color(0.2, 0.2, 1))   #! <----
    center += vec3(300, 300, 0)
    ctx.drawLine(a = center, b = center + vec3(100, 0, 0), color = color(1, 0.6, 0.6), thickness = 5)   #! <----
    ctx.drawLine(a = center, b = center + vec3(0, 100, 0), color = color(0.2, 1, 0.2), thickness = 5)   #! <----
    ctx.drawLine(a = center, b = center + vec3(0, 0, 100), color = color(0.2, 0.2, 1), thickness = 5)   #! <----

    ctx.fillCircle(radius = 50, color = color(1, 1, 1), center = vec3(vw/2 + 300, vh/2, 0))  #! <----
    ctx.drawCircle(radius = 50, color = color(1, 1, 1), center = vec3(vw/2 - 300, vh/2, 0))  #! <----

    ctx.drawCircle(radius = 50, thickness = 5, color = color(1, 1, 1), center = vec3(vw/2, vh/2 - 300, 0))  #! <----

  win.eventsHandler.onTick = proc(e: TickEvent) =
    time += e.deltaTime.inMicroseconds / 1_000_000
    redraw win
  
  run win

