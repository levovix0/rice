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

  ctx.fillCircle(0.5, color(1, 1, 1))


run win

