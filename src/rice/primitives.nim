import pkg/[bumpy, chroma, vmath, shady]
import ./[gl, transform, contexts]


## this module defines functions to draw (stroke) and fill 2D
##   lines, rectangles, round rectangles, circles
## in 3D space, using triangulation at vertex shader time
## stroke can be with/without thickness (without thickness this uses GL_LINES)


var
  # opengl global variable gl_VertexID, declared as wrong type in shady
  # todo: make a PR
  gl_VertexID: int32


proc rotate*(v: Vec3, axis: Vec3, angle: float32): Vec3 =
  let axisNorm = axis / length(axis)
  v * cos(angle) + cross(v, axisNorm) * sin(angle) + axisNorm * v.dot(axisNorm) * (1 - cos(angle))




proc lineShape(t: float32, startPoint, endPoint: Vec3): Vec4 =
  ## returns points of a line
  return vec4(startPoint + (endPoint - startPoint) * t, 1)

proc rectShape(t: float32, size: Vec2, center: Vec3, plane: Mat4): Vec4 =
  ## returns points of a rect
  let i = ((t mod 1) * 4).round.int
  let x = (if i == 1 or i == 2: 1'f32 else: 0'f32) - 0.5
  let y = (if i == 2 or i == 3: 1'f32 else: 0'f32) - 0.5
  return center.vec4(1) + plane * vec4(vec2(x*size.x, y*size.y), vec2(0, 0))

proc roundRectShape(t: float32, size: Vec2, center: Vec3, plane: Mat4, tl, tr, bl, br: float32): Vec4 =
  ## returns points of a round rect
  ## tl - top left radius
  ## tr - top right radius
  ## bl - bottom left radius
  ## br - bottom right radius
  let i = ((t mod 1) * 4).floor.int
  var p = vec2(0, 0)
  case i
  of 0:
    p = vec2(bl, bl) + vec2(-bl, 0).rotate(((t * 4) mod 1) * (PI/2))
  of 1:
    p = vec2(size.x-br, br) + vec2(0, -br).rotate(((t * 4) mod 1) * (PI/2))
  of 2:
    p = vec2(size.x-tr, size.y-tr) + vec2(tr, 0).rotate(((t * 4) mod 1) * (PI/2))
  of 3:
    p = vec2(tl, size.y-tl) + vec2(0, tl).rotate(((t * 4) mod 1) * (PI/2))
  else: discard
  return center.vec4(1) + plane * vec4(p - size/2, vec2(0, 0))

proc circleShape(t: float32, radius: float32, center: Vec3, plane: Mat4): Vec4 =
  ## returns points of a circle
  return center.vec4(1) + plane * vec4(vec2(radius, 0).rotate(t * (PI * 2)), vec2(0, 0))

proc capsuleShape(t: float32, a, b, dir, perp: Vec3, radius: float32): Vec4 =
  ## returns points of a capsule outline (segment with round caps)
  ## t in [0, 0.5) — semicircle around a, t in [0.5, 1) — semicircle around b
  var pos: Vec3
  if t < 0.5:
    let angle = float32 PI/2 + t * (PI * 2)
    pos = a + radius * (cos(angle) * dir + sin(angle) * perp)
  else:
    let angle = float32 -(PI/2) + (t - 0.5) * (PI * 2)
    pos = b + radius * (cos(angle) * dir + sin(angle) * perp)
  return vec4(pos, 1)



# --- Line ---

proc drawLine*(
  ctx: DrawContext,
  color: Color,
  a = vec3(0, 0, 0), b = vec3(1, 0, 0),
  transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * lineShape(
        gl_VertexID.float32,
        @(a), @(b)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_LINES, 2)


proc drawLine*(
  ctx: DrawContext,
  color: Color, thickness: float32,
  a = vec3(0, 0, 0), b = vec3(1, 0, 0),
  normal = vec3(0, 0, 1), transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform
  let y = (b - a).rotate(normal, PI/2)

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * (lineShape(
        (gl_VertexID.float32 / 2).floor,
        @(a), @(b)
      ) + (@(y / length(y)) * ((gl_VertexID.float32 mod 2) - 0.5) * @(thickness)).vec4(0))
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, 4)



# --- Rect ---

proc drawRect*(
  ctx: DrawContext,
  color: Color,
  size = vec2(1, 1),
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * rectShape(
        gl_VertexID.float32 / 4,
        @(size),
        @(center), @(plane)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_LINE_LOOP, 4)


proc drawRect*(
  ctx: DrawContext,
  color: Color, thickness: float32,
  size = vec2(1, 1),
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * rectShape(
        (gl_VertexID.float32 / 2).floor / 4,
        @(size) - vec2(1, 1) * (gl_VertexID.float32 mod 2) * @(thickness) * 2,
        @(center), @(plane)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, 10)


proc fillRect*(
  ctx: DrawContext,
  color: Color,
  size = vec2(1, 1),
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * rectShape(
        gl_VertexID.float32 / 4,
        @(size),
        @(center), @(plane)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_TRIANGLE_FAN, 4)



# --- Round rect ---

proc drawRoundRect*(
  ctx: DrawContext,
  color: Color,
  size: Vec2, tl, tr, bl, br: float32,
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 64,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * roundRectShape(
        gl_VertexID.float32 / @(pointCount.float32),
        @(size),
        @(center), @(plane),
        @(tl), @(tr), @(bl), @(br)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_LINE_LOOP, pointCount)


proc drawRoundRect*(
  ctx: DrawContext,
  color: Color, thickness: float32,
  size: Vec2, tl, tr, bl, br: float32,
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 64,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.makeShader:
    proc vert =
      let thk = (gl_VertexID.float32 mod 2) * @(thickness)
      gl_Position = @(transform) * roundRectShape(
        (gl_VertexID.float32 / 2).floor / @(pointCount.float32),
        @(size) - vec2(1, 1) * thk * 2,
        @(center), @(plane),
        max(0, @(tl) - thk), max(0, @(tr) - thk), max(0, @(bl) - thk), max(0, @(br) - thk)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, pointCount * 2 + 2)


proc fillRoundRect*(
  ctx: DrawContext,
  color: Color,
  size: Vec2, tl, tr, bl, br: float32,
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 64,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * roundRectShape(
        gl_VertexID.float32 / @(pointCount.float32),
        @(size),
        @(center), @(plane),
        @(tl), @(tr), @(bl), @(br)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_TRIANGLE_FAN, pointCount)



# --- Circle ---

proc drawCircle*(
  ctx: DrawContext,
  color: Color,
  radius: float32 = 1,
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * circleShape(
        gl_VertexID.float32 / @(pointCount.float32),
        @(radius),
        @(center), @(plane)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_LINE_LOOP, pointCount)


proc drawCircle*(
  ctx: DrawContext,
  color: Color, thickness: float32,
  radius: float32 = 1,
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * circleShape(
        (gl_VertexID.float32 / 2).floor / @(pointCount.float32),
        @(radius) - (gl_VertexID.float32 mod 2) * @(thickness),
        @(center), @(plane)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, pointCount * 2 + 2)


proc fillCircle*(
  ctx: DrawContext,
  color: Color,
  radius: float32 = 1,
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let plane = normal.toAngles.fromAngles

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * circleShape(
        gl_VertexID.float32 / @(pointCount.float32),
        @(radius),
        @(center), @(plane)
      )
    
    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_TRIANGLE_FAN, pointCount)




# --- Capsule (round line) ---

proc fillCapsule*(
  ctx: DrawContext,
  color: Color,
  a = vec3(0, 0, 0), b = vec3(1, 0, 0),
  radius: float32 = 0.5,
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let dir = normalize(b - a)
  let perp = cross(normal, dir)

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * capsuleShape(
        gl_VertexID.float32 / @(pointCount.float32),
        @(a), @(b), @(dir.Vec3), @(perp.Vec3), @(radius)
      )

    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_TRIANGLE_FAN, pointCount)


proc drawCapsule*(
  ctx: DrawContext,
  color: Color,
  a = vec3(0, 0, 0), b = vec3(1, 0, 0),
  radius: float32 = 0.5,
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let dir = normalize(b - a)
  let perp = cross(normal, dir)

  let shader = ctx.makeShader:
    proc vert =
      gl_Position = @(transform) * capsuleShape(
        gl_VertexID.float32 / @(pointCount.float32),
        @(a), @(b), @(dir.Vec3), @(perp.Vec3), @(radius)
      )

    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_LINE_LOOP, pointCount)


proc drawCapsule*(
  ctx: DrawContext,
  color: Color, thickness: float32,
  a = vec3(0, 0, 0), b = vec3(1, 0, 0),
  radius: float32 = 0.5,
  normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  let transform = ctx.viewportToGlMatrix * transform
  let dir = normalize(b - a)
  let perp = cross(normal, dir)

  let shader = ctx.makeShader:
    proc vert =
      let thk = (gl_VertexID.float32 mod 2) * @(thickness)
      gl_Position = @(transform) * capsuleShape(
        (gl_VertexID.float32 / 2).floor / @(pointCount.float32),
        @(a), @(b), @(dir.Vec3), @(perp.Vec3), @(radius) - thk
      )

    proc frag =
      var glCol {.outGl.}: Vec4 = @(color.vec4)

  useAndPassUniforms shader
  draw ctx.emptyMesh(GL_TRIANGLE_STRIP, pointCount * 2 + 2)



proc fillRect*(ctx: DrawContext, rect: Rect, color: Color, transform: Mat4 = mat4()) =
  ctx.fillRect(color=color, size=rect.wh, center=(rect.xy + rect.wh/2).vec3(0), normal=vec3(0, 0, 1), transform=transform)

proc drawRoundRect*(
  ctx: DrawContext,
  color: Color,
  size: Vec2, radius: float32,
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  ctx.drawRoundRect(color=color, size=size, tl=radius, tr=radius, bl=radius, br=radius, center=center, normal=normal, transform=transform, pointCount=pointCount)

proc drawRoundRect*(
  ctx: DrawContext,
  color: Color, thickness: float32,
  size: Vec2, radius: float32,
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  ctx.drawRoundRect(color=color, thickness=thickness, size=size, tl=radius, tr=radius, bl=radius, br=radius, center=center, normal=normal, transform=transform, pointCount=pointCount)

proc fillRoundRect*(
  ctx: DrawContext,
  color: Color,
  size: Vec2, radius: float32,
  center = vec3(0), normal = vec3(0, 0, 1), transform = mat4(),
  pointCount: int = 32,
) =
  ctx.fillRoundRect(color=color, size=size, tl=radius, tr=radius, bl=radius, br=radius, center=center, normal=normal, transform=transform, pointCount=pointCount)


proc drawLine*(ctx: DrawContext, color: Color, a, b: Vec2, transform: Mat4 = mat4()) =
  ctx.drawLine(color=color, a=vec3(a.x, a.y, 0), b=vec3(b.x, b.y, 0), transform=transform)




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

