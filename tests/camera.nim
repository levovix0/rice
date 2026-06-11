import pkg/[siwin, vmath]


template addCameraMovement*(win: Window, pos: var Vec3, rot: var Mat4, zoom: var float32, axisYUp: bool = true) =
  var mpos = vec2()
  win.eventsHandler.onMouseButton = proc(e: MouseButtonEvent) =
    mpos = e.window.mouse.pos

  win.eventsHandler.onMouseMove = proc(e: MouseMoveEvent) =
    let d = e.window.mouse.pos - mpos
    let dn = d / vec2(
      e.window.size.x.float32 * (e.window.size.y / e.window.size.x).float32,
      (if axisYUp: 1 else: -1) * e.window.size.y.float32
    ) * 2

    if e.window.mouse.pressed == {MouseButton.right}:
      let zv = vec2(
        ((if axisYUp: -1 else: 1) * (mpos.y / e.window.size.y.float32 - 0.5)).clamp(-1, 1) / 2,
        ((mpos.x / e.window.size.x.float32 - 0.5) / (e.window.size.y / e.window.size.x).float32).clamp(-1, 1) / 2
      ).normalize
      
      rot = combine(
        rot,
        rotateY[float32](dn.x * Pi),
        rotateX[float32](dn.y * Pi),
        rotateZ[float32](dn.x * Pi * zv.x),
        rotateZ[float32](dn.y * Pi * zv.y),
      )
    
    elif e.window.mouse.pressed == {MouseButton.middle}:
      pos = pos - rot.inverse * vec3(dn.x, -dn.y, 0) / zoom
      
    mpos = e.window.mouse.pos
    redraw win
  

  win.eventsHandler.onScroll = proc(e: ScrollEvent) =
    let sd = (-e.delta).clamp(-1, 1)
    
    zoom *= sd * 0.2 + 1

    let d = e.window.mouse.pos - e.window.size.vec2 / 2
    let dn = d / vec2(
      e.window.size.x.float32 * (e.window.size.y / e.window.size.x).float32,
      e.window.size.y.float32
    ) * 2 * -sd * 0.2 / zoom
    
    pos = pos - rot.inverse * vec3(dn.x, (if axisYUp: -1 else: 1) * dn.y, 0)
    redraw win

