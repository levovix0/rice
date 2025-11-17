# Rice
Rice (from russian "рис.", shorthened form of word "drawing")

a work-in-progress 2D/3D GPU rendering library


```nim
when isMainModule:
  import std/[times]
  import pkg/[siwin, rice]

  let win = newSiwinGlobals(title = "Rice example").newOpenglWindow()
  
  loadExtensions()
  let ctx = newDrawContext()

  var time = 0'f32

  win.eventsHandler.onResize = proc(e: ResizeEvent) =
    glViewport 0, 0, e.size.x.GlInt, e.size.y.GlInt
    ctx.updateDrawingAreaSize(e.size)


  win.eventsHandler.onRender = proc(e: RenderEvent) =
    glClearColor(0.1, 0.1, 0.1, 1)
    glClear(GL_COLOR_BUFFER_BIT)

    let (vw, vh) = (e.window.size.x, e.window.size.y)

    ctx.viewportMatrix = combine(
      scale(vec3(2 / vw, -2 / vh, 1)),
      translate(vec3(-1, 1, 0)),
    )

    var rect = rect(vw/2 - 400/2, vh/2 - 200/2, 400, 200)
    ctx.fillRect(
      rect,
      color(1, 0.2, 0.2),
      rotateZ(origin = vec3(rect.xy + rect.wh/2, 0), time / 4),
    )

  win.eventsHandler.onTick = proc(e: TickEvent) =
    time += e.deltaTime.inMicroseconds / 1_000_000
    redraw win
  
  run win
```

see tests/t1_basic for a more complex example
