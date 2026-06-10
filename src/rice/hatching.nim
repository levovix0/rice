import pkg/[vmath, chroma, shady]
import ./[contexts, gl]


proc fillHatching*(
  ctx: DrawContext,
  mesh: Mesh,
  color1, color2: Color,
  dir: Vec3,
  l1, l2: float32,
  transform: Mat4 = mat4()
) =
  let transform = ctx.viewportToGlMatrix * transform

  let shader = ctx.makeShader:
    proc vert =
      var pos {.inp.}: Vec3
      var uv {.out.}: Vec3
      gl_Position = @(transform) * vec4(pos.x, pos.y, pos.z, 1)
      uv = pos

    proc frag =
      var glCol {.outGl.}: Vec4
      if uv.dot(@(dir.normalize.Vec3)) mod (@(l1) + @(l2)) > @(l1):
        glCol = @(color2.vec4)
      else:
        glCol = @(color1.vec4)

  useAndPassUniforms shader
  draw mesh
