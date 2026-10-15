import pkg/siwin
import rice


let win = newOpenglWindow(size = ivec2(600, 600), transparent = true)
opengl.loadExtensions()
let ctx = newDrawContext()


proc sdfSegment(p: Vec2, a: Vec2, b: Vec2): float32 =
  let pa = p - a
  let ba = b - a
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)
  return length(pa - ba * h)


proc hashv(p: Vec2): float32 =
  var p2 = fract(p * vec2(123.34, 456.21))
  p2 += dot(p2, p2 + 45.32)
  return fract(p2.x * p2.y)

proc noise(p: Vec2): float32 =
  let i = floor(p)
  let f = fract(p)
  
  let u = f * f * (vec2(3.0) - f * 2)
  
  let a = hashv(i + vec2(0.0, 0.0))
  let b = hashv(i + vec2(1.0, 0.0))
  let c = hashv(i + vec2(0.0, 1.0))
  let d = hashv(i + vec2(1.0, 1.0))
  
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y

proc fbm(p: Vec2): float32 =
  var value = 0.0.float32
  var amplitude = 0.5.float32
  var frequency = 1.0.float32
  var pos = p
  
  for i in 0 ..< 5:
    value += amplitude * noise(pos * frequency)
    frequency *= 2.0
    amplitude *= 0.5
    
  return value

proc smstep(a: float32, b: float32, x: float32): float32 =
  let t = clamp((x - a) / (b - a), 0.0, 1.0)
  return t * t * (3.0 - 2.0 * t)

proc cloud(uv: Vec2, t: float32, scale: float32): float32 =
  let skyUv = uv * scale
  let wind = vec2(t * 0.05, t * 0.02)
  return smstep(0, 0.8, fbm(skyUv + wind))



win.eventsHandler.onRender = proc(e: RenderEvent) =
  glViewport 0, 0, e.window.size.x.GlInt, e.window.size.y.GlInt
  ctx.updateDrawingAreaSize(e.window.size)

  # glClearColor(0.1, 0.1, 0.1, 1)
  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT)

  push_blendRgbx ctx

  let baseTransform = combine(
    translate(-0.5, -0.5),
    scale(2, 2),
    (
      if e.window.size.x > e.window.size.y:
        scale(1 * (e.window.size.y / e.window.size.x), 1)
      else:
        scale(1, 1 * (e.window.size.x / e.window.size.y))
    ),
  )
  var transform = baseTransform

  let colorA = vec4(0.69, 0.84, 0.18, 1)
  let colorB = vec4(0.84, 0.32, 0.18, 1)

  let shader = ctx.makeShader:
    proc vert =
      var pos {.inp.}: Vec2
      var uv {.out.}: Vec2

      gl_Position = @(transform) * vec4(pos.x, pos.y, 0, 1)
      uv = pos

    proc frag =
      var glColor {.outGl.}: Vec4

      let c = (1 - cloud(uv, 70, 0.4).pow(0.8) * 2.4).clamp(0, 1)
      let distC = (uv - vec2(0.5, 0.5)).length
      let uv = uv +
        vec2(1, 0) * 0.6 * (cloud(uv, 22, 2) - 0.5) * (0.5 - distC).clamp(0, 1) +
        vec2(0, 1) * 0.6 * (cloud(uv, 11, 2) - 0.5) * (0.5 - distC).clamp(0, 1)
      let distA = sdfSegment(uv, vec2(0.2, 0.2), vec2(0.8, 0.8))
      let distB = sdfSegment(uv, vec2(0.8, 0.2), vec2(0.2, 0.8))

      if distA <= 0.2:
        let l = (1 - (distA.pow(5) * (0.35 / 0.2.pow(5))) - c).clamp(0, 1)
        glColor = @(colorA) * vec4(l*1.1, l, l, 1)
      elif distB <= 0.2:
        let l = (0.2 + (distA.pow(0.4) * (0.6 / 0.2.pow(0.4))) - (distB.pow(5) * (0.35 / 0.2.pow(5))) - c).clamp(0, 1)
        glColor = @(colorB) * vec4(l*1.1, l, l, 1)
      else:
        glColor = vec4(0, 0, 0, 0)

  useAndPassUniforms shader
  draw ctx.rect

  pop_blendRgbx ctx


run win

