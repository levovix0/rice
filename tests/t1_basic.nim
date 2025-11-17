import std/[unittest, times]
import pkg/[siwin, chroma, bumpy]
import rice


test "basic":
  let win = newSiwinGlobals().newOpenglWindow()
  loadExtensions()
  
  let ctx = newDrawContext()
  var aafb = newAntialiasedFramebuffer(depth = true)

  var time = 0'f32
  var rot = toAngles(vec3(1, 1, 1)).fromAngles()
  var to_display = 0


  let lever_mechanism = staticRead("data/lever_mechanism.stl").static.parseStlAscii(Shape)


  proc render(e: RenderEvent) =
    glClearColor(0.1, 0.1, 0.1, 1)
    glClearDepth(1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    let (vw, vh) = (e.window.size.x, e.window.size.y)

    case to_display mod 3
    of 0:
      ctx.viewportMatrix = combine(
        scale(vec3(2 / vw, -2 / vh, 1)),
        translate(vec3(-1, 1, 0)),
      )

      var rect = rect(vw/2 - 400/2, vh/2 - 200/2, 400, 200)
      ctx.fillRect(
        rect,
        color(1, 0.2, 0.2),
        combine(
          rotateZ(origin = vec3(rect.xy + rect.wh/2, 0), time / 4),
        )
      )


    of 1:
      ctx.viewportMatrix = scale(vec3(vh / vw, 1, 1))

      for i in countdown(1, -1, 2):
        ctx.fillRect(
          rect(-0.25, -0.25, 0.5, 0.5),
          color(1, 0.2, 0.2).darken(if i < 0: 0.2 else: 0),
          combine(
            translate(vec3(0, 0, -0.25 * i.float32)),
            rotateY(float32 PI/2),
            rot,
          )
        )

        ctx.fillRect(
          rect(-0.25, -0.25, 0.5, 0.5),
          color(0.2, 1, 0.2).darken(if i < 0: 0.2 else: 0),
          combine(
            translate(vec3(0, 0, -0.25 * i.float32)),
            rotateX(float32 -PI/2),
            rot,
          )
        )

        ctx.fillRect(
          rect(-0.25, -0.25, 0.5, 0.5),
          color(0.2, 0.2, 1).darken(if i < 0: 0.2 else: 0),
          combine(
            translate(vec3(0, 0, -0.25 * i.float32)),
            rot,
          )
        )
      
    of 2:
      ctx.viewportMatrix = scale(vec3(vh / vw, 1, 1/1000))

      ctx.draw3dShapeShadedByNormalsSingleSide(
        shape = lever_mechanism,
        # color = color(0.3, 0.79, 1).lighten(0.1),
        # shadowColor = color(0.23, 0.04, 0.38),
        lightDir = vec3(0, 0, 1),
        transform = combine(
          rotateX(float32 Pi / 2),
          translate(vec3(0, -0.5, 0)),
          rot,
        )
      )

      
    else: discard
  

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)

  win.eventsHandler.onRender = proc(e: RenderEvent) =
    ctx.drawInside aafb: render(e)

  var mpos = vec2()
  win.eventsHandler.onMouseButton = proc(e: MouseButtonEvent) =
    if e.window.mouse.pressed == {MouseButton.right}:
      mpos = e.window.mouse.pos

  win.eventsHandler.onMouseMove = proc(e: MouseMoveEvent) =
    if e.window.mouse.pressed == {MouseButton.right}:
      let d = e.window.mouse.pos - mpos

      let zv = vec2(
        (-(mpos.y / e.window.size.y.float32 - 0.5) * 4).clamp(-1, 1),
        ((mpos.x / e.window.size.x.float32 - 0.5) / (e.window.size.y / e.window.size.x).float32 * 4).clamp(-1, 1)
      ).normalize
      
      rot = combine(
        rot,
        rotateY(float32 d.x / e.window.size.x.float32 / (e.window.size.y / e.window.size.x).float32 * 2*PI),
        rotateX(float32 d.y / e.window.size.y.float32 * 2*PI),
        rotateZ(float32 d.x / e.window.size.x.float32 / (e.window.size.y / e.window.size.x).float32 * 2*PI * zv.x),
        rotateZ(float32 d.y / e.window.size.y.float32 * 2*PI * zv.y),
      )
      
      mpos = e.window.mouse.pos

  win.eventsHandler.onKey = proc(e: KeyEvent) =
    if e.pressed:
      case e.key
      of Key.right: inc to_display
      of Key.left:  dec to_display
      else: discard

  win.eventsHandler.onTick = proc(e: TickEvent) =
    time += e.deltaTime.inMicroseconds / 1_000_000
    redraw win
  
  
  run win

