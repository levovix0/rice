import vmath
import render

{.experimental: "overloadableEnums".}

type
  Signal*[T] = object
    ## simple signal event system
    ## only components can be connected to signals
    ## one signal can be connected to multiple components
    ## one component can connect to multiple signals
    ## one signal can be connected to one component only once
    ## connection can be removed
    connected*: seq[(Component, proc(c: Component, v: T))]
  
  Property*[T] = object
    v: T
    changed*: Signal[T]

  ComponentFlag* = enum
    invisible
    collapsed
    uninteractive

  Component* = ref object of RootObj
    parent* {.cursor.}: Component
    connected*: seq[ptr Signal[void]]
    flags*: set[ComponentFlag]
    
    size*: Property[Vec2]


#* ------------- Signal ------------- *#

proc disconnect*[T](s: var Signal[T]) =
  for (c, _) in s.connected:
    for i, x in c.connected:
      if x == cast[ptr Signal[void]](s.addr):
        c.connected.del i
        break
  s.connected = @[]

proc `=destroy`*[T](s: var Signal[T]) =
  disconnect s

proc emit*[T](s: Signal[T], v: T) =
  let connected = s.connected
  for (c, f) in connected:
    f(c, v)


proc disconnect*(c: Component) =
  for s in c.connected:
    for i, x in s.connected:
      if x[0] == c:
        s.connected.del i
        break
  c.connected = @[]

proc disconnect*[T](s: var Signal[T], c: Component) =
  for i, x in c.connected:
    if x == cast[ptr Signal[void]](s.addr):
      c.connected.del i
      break
  for i, x in s.connected:
    if x[0] == c:
      s.connected.del i
      break

proc connect*[T](s: var Signal[T], c: Component, f: proc(c: Component, v: T)) =
  if cast[ptr Signal[void]](s.addr) in c.connected: return
  s.connected.add (c, f)
  c.connected.add cast[ptr Signal[void]](s.addr)


#* ------------- Property ------------- *#

proc `val=`*[T](p: var Property[T], v: T) =
  ## note: p.changed will be emitted even if new value is same as previous value
  p.v = v
  emit p.changed, p.v

proc `[]=`*[T](p: var Property[T], v: T) = p.val = v

proc val*[T](p: Property[T]): T = p.v
proc `[]`*[T](p: Property[T]): T = p.v

proc unsafeVal*[T](p: var Property[T]): var T = p.v
proc `{}`*[T](p: Property[T]): T = p.v

proc `unsafeVal=`*[T](p: var Property[T], v: T) =
  ## same as val=, but does not emit p.changed
  p.v = v

proc `{}=`*[T](p: var Property[T], v: T) = p.unsafeVal = v

converter toValue*[T](p: Property[T]): T = p[]


#* ------------- Component ------------- *#

method childCount*(c: Component): int {.base.} = 0

method child*(c: Component, idx: int): Component {.base.} =
  nil

method posToChild*(c: Component, idx: int, pos: Vec2): Vec2 {.base.} =
  pos

method posFromChild*(c: Component, idx: int, pos: Vec2): Vec2 {.base.} =
  pos

method render*(c: Component, r: Render) {.base.} =
  discard

method resize*(c: Component, size: Vec2) {.base.} =
  c.size[] = size
  c.size.changed.emit size

method childsAt*(c: Component, pos: Vec2): seq[int] {.base.} =
  discard
