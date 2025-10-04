import unittest, vmath
import rice

test "signals and properties":
  var c = new Component
  check c.size == vec2(0, 0)

  c.size{} = vec2(1, 1)
  check c.size == vec2(1, 1)
  
  var b: bool
  connect c.size.changed, c, proc(c: Component, v: Vec2) =
    b = true
  
  c.size[] = vec2(10, 10)
  check c.size == vec2(10, 10)
  check b


test "simple siwin+opengl application":
  let app = new SiwinOpenglApp
  let ma = new MouseArea
  app.root = ma
  run app
