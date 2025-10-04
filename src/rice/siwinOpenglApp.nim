import siwin, core, mouseArea

{.experimental: "overloadableEnums".}

type
  SiwinOpenglApp* = ref object of Component
    window: Window
    root: Component


proc run*(app: SiwinOpenglApp) =
  app.window = newOpenglWindow()

  app.window.onClick = proc(e: ClickEvent) =
    app.emitMouseClicked(
      e.pos.vec2,
      case e.button
        of MouseButton.left: left
        of MouseButton.right: right
        of MouseButton.middle: middle
        of MouseButton.forward: forward
        of MouseButton.backward: backward
    )

  run app.window

proc root*(app: SiwinOpenglApp): Component = app.root
proc `root=`*(app: SiwinOpenglApp, v: Component) = app.root = v
