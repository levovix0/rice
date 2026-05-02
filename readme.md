# Rice
Rice (from russian "рис.", shorthened form of word "drawing")

a work-in-progress 2D/3D GPU rendering library


```nim
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


## Compile switches

- ```nim
  const rice_max_opengl_error_len {.intdefine.} = 512
  ```
  specifies how long errors in opengl may be, if you encounter an opengl error that looks like it was cut out, try increasing this parameter


## Fat

A good library must be simple (to read and to modify), fast, well-documented and composable.

Rice is not a good library.

- rice uses shady to define shaders in nim code. And wraps it in yet another macros, that allows to inject uniforms to them. Convinient shader creation API is exported and is meant to be used, if provided functional is not enough. This significantly slows dows compile time, compared to writing shaders in GLSL. If only nim had working IC...
- rice uses pixie (to draw text). Pixie is a huge dependency by itself and has it's own dependencies. Simply installing it using atlas takes up 300 Mb of disk space.

I suppose the rice can be split into base/glue (that defines what is Mesh, DrawContext, etc), framebuffer and atlas texture manager, SDF 2d shape renderer (for UI), 3d renderer with simple lights (for CADs), 3d forward+ renderer (for games), mesh/scene file readers and writers.

Also, text should be rendered on GPU, instead of "rendering it to atlas on CPU via pixie, sending this atlas to GPU, and bliting it from atlas letter by letter"

