import pkg/[chroma, vmath]
import ./[gl, transform, contexts, contextutils]


const
  flat3dVertSrc = """
#version 300 es
precision highp float;

in vec3 inPos;
uniform mat4 u_transform;

void main() {
  gl_Position = u_transform * vec4(inPos, 1.0);
}
"""
  flat3dFragSrc = """
#version 300 es
precision highp float;

out vec4 glCol;
uniform vec4 u_color;

void main() {
  glCol = u_color;
}
"""
  shaded3dVertSrc = """
#version 300 es
precision highp float;

in vec3 inPos;
in vec3 inNormal;
out vec4 color;
uniform mat4 u_view;
uniform mat4 u_transform;
uniform vec3 u_negLightDir;
uniform float u_backlight;
uniform vec4 u_color;
uniform vec4 u_shadowColor;

void main() {
  gl_Position = (u_view * u_transform) * vec4(inPos, 1.0);
  vec4 normal = u_transform * vec4(inNormal, 1.0);
  float lightV = dot(u_negLightDir, (normal / length(normal)).xyz);
  float light = ((0.0 < lightV) ? (lightV) : (float(float(- (lightV)) * u_backlight)));
  color = u_color * light + u_shadowColor * (1.0 - light);
}
"""
  shaded3dFragSrc = """
#version 300 es
precision highp float;

in vec4 color;
out vec4 glCol;

void main() {
  glCol = color;
}
"""


proc fill3dMeshFlat*(
  ctx: DrawContext,
  mesh: Mesh,
  color: Color,
  transform: Mat4 = mat4(),
) =
  let transform = combine(
    transform,
    ctx.viewportToGlMatrix,
  )

  let shader = ctx.getShader(4001, flat3dVertSrc, flat3dFragSrc)

  ctx.withPushPopIf blendRgbx, color.a != 1:
    shader.use()
    shader["u_transform"].uniform = transform
    shader["u_color"].uniform = color.asRgbx.vec4
    draw mesh



proc fill3dMeshShadedByNormalsSingleSide*(
  ctx: DrawContext,
  mesh: Mesh,
  color: Color = color(1, 1, 1),
  shadowColor: Color = color(0.4, 0.4, 0.4),
  lightDir: Vec3 = vec3(-1, -1, -1).normalize,
  backlight: float = 0.6,
  transform: Mat4 = mat4(),
) =
  let view = ctx.viewportToGlMatrix

  let shader = ctx.getShader(4002, shaded3dVertSrc, shaded3dFragSrc)

  ctx.withPushPopIf blendRgbx, color.a != 1 or shadowColor.a != 1:
    shader.use()
    shader["u_view"].uniform = view
    shader["u_transform"].uniform = transform
    shader["u_negLightDir"].uniform = -lightDir.normalize
    shader["u_backlight"].uniform = backlight
    shader["u_color"].uniform = color.asRgbx.vec4
    shader["u_shadowColor"].uniform = shadowColor.asRgbx.vec4
    draw mesh

