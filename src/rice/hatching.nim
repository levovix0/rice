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


proc fillHatchingAA*(
  ctx: DrawContext,
  mesh: Mesh,
  color1, color2: Color,
  dir: Vec3,
  l1, l2: float32,
  transform: Mat4 = mat4()
) =
  ## same as fillHatching, but with manual 4x4 subpixel antialiasing in the fragment shader
  let transform = ctx.viewportToGlMatrix * transform

  let shader = ctx.makeShader:
    proc vert =
      var pos {.inp.}: Vec3
      var uv {.out.}: Vec3
      gl_Position = @(transform) * vec4(pos.x, pos.y, pos.z, 1)
      uv = pos

    proc frag =
      var glCol {.outGl.}: Vec4
      let period = @(l1) + @(l2)
      let s = uv.dot(@(dir.normalize.Vec3))
      # how much `s` changes per one screen pixel along x and y
      let dsdx = dFdx(vec2(s, s)).x
      let dsdy = dFdy(vec2(s, s)).x

      var coverage = 0.0
      for i in 0 ..< 4:
        for j in 0 ..< 4:
          # sample at the center of each of the 4x4 subpixels, offsets in [-0.5, 0.5)
          let ox = (float(i) + 0.5) / 4.0 - 0.5
          let oy = (float(j) + 0.5) / 4.0 - 0.5
          let ss = s + dsdx * ox + dsdy * oy
          if (ss mod period) > @(l1):
            coverage = coverage + 1.0 / 16.0

      glCol = mix(@(color1.vec4), @(color2.vec4), coverage)

  useAndPassUniforms shader
  draw mesh
