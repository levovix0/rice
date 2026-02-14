import pkg/[chroma, vmath, shady]
import ./[gl, transform, contexts, contextutils]



proc draw3dShapeFlat*(
  ctx: DrawContext,
  shape: Shape,
  color: Color,
  transform: Mat4 = mat4(),
) =
  let transform = combine(
    transform,
    ctx.viewportToGlMatrix,
  )

  let shader = ctx.makeShader:
    proc vert =
      var inPos {.inp.}: Vec3

      gl_Position = @(transform) * vec4(inPos, 1)
    
    proc frag =
      var glCol {.outGl.}: Vec4
      
      glCol = @(color.asRgbx.vec4)

  ctx.withPushPopIf blendRgbx, color.a != 1:
    useAndPassUniforms shader
    draw shape



proc draw3dShapeShadedByNormalsSingleSide*(
  ctx: DrawContext,
  shape: Shape,
  color: Color = color(1, 1, 1),
  shadowColor: Color = color(0.4, 0.4, 0.4),
  lightDir: Vec3 = vec3(-1, -1, -1).normalize,
  backlight: float = 0.6,
  transform: Mat4 = mat4(),
) =
  let view = ctx.viewportToGlMatrix

  let shader = ctx.makeShader:
    proc vert =
      var inPos {.inp.}: Vec3
      var inNormal {.inp.}: Vec3
      var gl_Position {.outGl.}: Vec4
      var color {.out.}: Vec4

      gl_Position = @(view) * @(transform) * vec4(inPos, 1)

      let normal = @(transform) * vec4(inNormal, 1)
      
      let lightV = dot(@(-lightDir.normalize), (normal / normal.length).xyz)
      let light =
        if lightV > 0: lightV
        else: -lightV * @(backlight)

      color = @(color.asRgbx.vec4) * light + @(shadowColor.asRgbx.vec4) * (1 - light)
    
    proc frag =
      var glCol {.outGl.}: Vec4

      glCol = color

  ctx.withPushPopIf blendRgbx, color.a != 1 or shadowColor.a != 1:
    useAndPassUniforms shader
    draw shape

