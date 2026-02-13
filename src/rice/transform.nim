import pkg/vmath


proc combine*(a, b: Mat4): Mat4 =
  b * a

proc combine*(matrices: varargs[Mat4]): Mat4 =
  if matrices.len == 0: return mat4()
  
  result = matrices[0]
  for i in 1 .. matrices.high:
    result = matrices[i] * result


proc combine*(a, b: Mat3): Mat3 =
  b * a

proc combine*(matrices: varargs[Mat3]): Mat3 =
  if matrices.len == 0: return mat3()
  
  result = matrices[0]
  for i in 1 .. matrices.high:
    result = matrices[i] * result


proc rotateX*(angle: float32, origin: Vec3): Mat4 =
  combine(
    translate(-origin),
    rotateX(angle),
    translate(origin),
  )

proc rotateY*(angle: float32, origin: Vec3): Mat4 =
  combine(
    translate(-origin),
    rotateY(angle),
    translate(origin),
  )

proc rotateZ*(angle: float32, origin: Vec3): Mat4 =
  combine(
    translate(-origin),
    rotateZ(angle),
    translate(origin),
  )


# --- utils ---

proc mat3*(m: Mat4): Mat3 =
  mat3(
    m[0, 0], m[0, 1], m[0, 2],
    m[1, 0], m[1, 1], m[1, 2],
    m[2, 0], m[2, 1], m[2, 2],
  )

proc mat4*(m: Mat3): Mat4 =
  mat4(
    m[0, 0], m[0, 1], m[0, 2], 0,
    m[1, 0], m[1, 1], m[1, 2], 0,
    m[2, 0], m[2, 1], m[2, 2], 0,
    0,       0,       0,       1,
  )

proc vec2*(v: Vec4): Vec2 =
  vec2(v.x, v.y)

proc vec3*(v: Vec2): Vec3 =
  vec3(v.x, v.y, 0)
