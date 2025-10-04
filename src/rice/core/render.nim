import unicode
import pixie

{.experimental: "overloadableEnums".}

type
  Render* = ref object of RootObj

  RenderFont* = ref object of RootObj
    fontSize*: float

  AlignedText* = object
    runes*: seq[Rune]
    rects*: seq[Rect]
    w*, h*: float
  
  RenderImage* = ref object of RootObj


method toRender*(r: Render, f: Font, size: float): RenderFont {.base.} =
  ## note: try to send font to render as rare as possible
  discard

method toRender*(r: Render, i: pointer, size: int, w, h: int): RenderImage {.base.} =
  ## send rgbx (rgb: byte, 0..a, a: byte, 0..255) image to render
  ## note: try to send image to render as rare as possible
  discard

proc toRender*(r: Render, i: Image): RenderImage =
  ## note: try to send image to render as rare as possible
  toRender(r, i.data[0].addr, i.data.len * 4, i.width, i.height)


method pushTransform*(r: Render, transform: Mat4, pixelScaleChange: Vec2 = vec2(1, 1)) {.base.} = discard
method popTransform*(r: Render) {.base.} = discard


method fillRect*(render: Render, color: Color, radius: float, size: Vec2, transform: Mat4) {.base.} = discard


proc alignedText*(
  text: sink seq[Rune],
  font: Font,
  fontSize: float,
  wrapWidth = 0,  ## don't wrap by default
  hAlign: HorizontalAlignment
): AlignedText =
  ## ! clear text from all control symbols (0..31) by yourself !

  result.runes = move text
  if result.runes.len == 0: return

  result.rects.setLen(result.runes.len)

  var
    x = 0.0
    y = 0.0
  for r in result.runes:
    ## todo
