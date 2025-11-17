import pkg/vmath


proc combine*(a, b: Mat4): Mat4 =
  b * a


proc combine*(matrices: varargs[Mat4]): Mat4 =
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
