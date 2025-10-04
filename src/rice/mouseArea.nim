import vmath, sequtils
import core

{.experimental: "overloadableEnums".}

type
  Button* = enum
    left
    right
    middle
    forward
    backward
  
  MouseArea* = ref object of Component
    clicked*: Signal[tuple[pos: Vec2, button: Button]]


template forEach(c: Component, pos1: Vec2, t: type, childsBefore: bool, body: untyped) =
  proc impl(c2: Component, pos2: Vec2) =
    if c2 == nil: return
    let cChilds = c2.childsAt(pos2).mapit((c2.child(it), c2.posToChild(it, pos2)))
    for (x, posChild) in cChilds:
      if uninteractive notin x.flags:
        if childsBefore:
          impl(x, posChild)
        if x of t:
          let obj {.inject.} = t(x)
          let pos {.inject.} = posChild
          block: body
        if not childsBefore:
          impl(x, posChild)

  impl(c, pos1)


proc emitMouseClicked*(c: Component, pos: Vec2, button: Button) =
  c.forEach pos, MouseArea, false:
    obj.clicked.emit (pos, button)
