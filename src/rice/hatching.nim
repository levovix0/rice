import pkg/[vmath, chroma]
import ./[contexts, gl]


const
  hatchVertSrc = """
#version 300 es
precision highp float;

in vec3 pos;
out vec3 uv;
uniform mat4 u_transform;

void main() {
  gl_Position = u_transform * vec4(pos.x, pos.y, pos.z, 1.0);
  uv = pos;
}
"""
  hatchFragSrc = """
#version 300 es
precision highp float;

in vec3 uv;
out vec4 glCol;
uniform vec3 u_dir;
uniform float u_l1;
uniform float u_l2;
uniform vec4 u_color2;
uniform vec4 u_color1;

void main() {
  if (u_l1 < mod(dot(uv, u_dir), u_l1 + u_l2)) {
    glCol = u_color2;
  } else {
    glCol = u_color1;
  }
}
"""
  hatchAAFragSrc = """
#version 300 es
precision highp float;

in vec3 uv;
out vec4 glCol;
uniform float u_l1;
uniform float u_l2;
uniform vec3 u_dir;
uniform vec4 u_color1;
uniform vec4 u_color2;

void main() {
  float period = u_l1 + u_l2;
  float s = dot(uv, u_dir);
  float dsdx = dFdx(vec2(s, s)).x;
  float dsdy = dFdy(vec2(s, s)).x;
  float coverage = 0.0;
  for(int i = 0; i < 4; i++) {
    for(int j = 0; j < 4; j++) {
      float ox = (float(i) + 0.5) / 4.0 - 0.5;
      float oy = (float(j) + 0.5) / 4.0 - 0.5;
      float ss = (float(s) + float(dsdx) * ox) + float(dsdy) * oy;
      if (float(u_l1) < mod(ss, float(period))) {
        coverage = coverage + 0.0625;
      }
    };
  }
  glCol = mix(u_color1, u_color2, float(coverage));
}
"""


proc fillHatching*(
  ctx: DrawContext,
  mesh: Mesh,
  color1, color2: Color,
  dir: Vec3,
  l1, l2: float32,
  transform: Mat4 = mat4()
) =
  let transform = ctx.viewportToGlMatrix * transform

  let shader = ctx.getShader(5001, hatchVertSrc, hatchFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_dir"].uniform = dir.normalize.Vec3
  shader["u_l1"].uniform = l1
  shader["u_l2"].uniform = l2
  shader["u_color2"].uniform = color2.vec4
  shader["u_color1"].uniform = color1.vec4
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

  let shader = ctx.getShader(5002, hatchVertSrc, hatchAAFragSrc)

  shader.use()
  shader["u_transform"].uniform = transform
  shader["u_dir"].uniform = dir.normalize.Vec3
  shader["u_l1"].uniform = l1
  shader["u_l2"].uniform = l2
  shader["u_color1"].uniform = color1.vec4
  shader["u_color2"].uniform = color2.vec4
  draw mesh
