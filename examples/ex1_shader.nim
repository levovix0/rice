import pkg/siwin
import rice


let win = newOpenglWindow()
opengl.loadExtensions()
let ctx = newDrawContext()


win.eventsHandler.onRender = proc(e: RenderEvent) =
  glViewport 0, 0, e.window.size.x.GlInt, e.window.size.y.GlInt
  ctx.updateDrawingAreaSize(e.window.size)

  glClearColor(0.1, 0.1, 0.1, 1)
  glClear(GL_COLOR_BUFFER_BIT)

  let shader = ctx.makeShader:
    proc vert =
      var pos {.inp.}: Vec2
      var uv {.out.}: Vec2

      gl_Position = vec4(pos.x, pos.y, 0, 1)
      uv = pos

    proc frag =
      var glColor {.outGl.}: Vec4

      glColor = vec4(uv.x, uv.y, 0, 1)

  useAndPassUniforms shader
  draw ctx.rect


run win

