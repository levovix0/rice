import std/[strutils, strformat, enumutils, sequtils]
import pkg/vmath
import ../[gl]


type
  TokenKind = enum
    EofT

    SolidKw = "solid"
    FacetKw = "facet"
    NormalKw = "normal"
    OuterKw = "outer"
    LoopKw = "loop"
    VertexKw = "vertex"
    EndLoopKw = "endloop"
    EndFacetKw = "endfacet"
    EndSolidKw = "endsolid"

    IdentL
    FLoatL

  Token = object
    kind: TokenKind
    sI: Slice[int]

  StlAsciiParseError* = object of CatchableError


proc getStr(s: string, tok: Token): string =
  s[tok.sI]

proc getFloat(s: string, tok: Token): float =
  parseFloat(s[tok.sI])


proc nextToken(s: string, i: var int): Token =
  result = Token(sI: i..<i)
  if i >= s.len:
    return

  while true:
    case s[i]
    of {'_', 'a'..'z', 'A'..'Z', '\'', '"'}:
      result.kind = IdentL
      inc result.sI.b

      while true:
        inc i
        if i >= s.len or isSpaceAscii(s[i]):
          let s = s.getStr(result)
          result.kind = genEnumCaseStmt(TokenKind, s, default = IdentL, ord(SolidKw), ord(EndSolidKw), nimIdentNormalize)
          return
        inc result.sI.b
    
    of {'0'..'9', '-', '+'}:
      result.kind = FloatL
      inc result.sI.b

      while true:
        inc i
        if i >= s.len or s[i] notin {'0'..'9', '.', ',', 'e', '-', '+'}:
          return
        inc result.sI.b
    
    else:
      # assume space
      inc i
      if i >= s.len:
        return
      inc result.sI.a
      inc result.sI.b


proc eat(s: string, i: var int, kind: TokenKind) =
  let t = nextToken(s, i)
  if t.kind != kind:
    raise StlAsciiParseError.newException(&"expected {kind}, got {t.kind} at {t.sI.a}..{t.sI.b}")


proc eatOptional(s: string, i: var int, kind: TokenKind): bool =
  let iO = i
  let t = nextToken(s, i)
  if t.kind == kind:
    true
  else:
    i = iO
    false


proc parseStlAscii*(s: string, i: var int, v: var SomeFloat) =
  let t = nextToken(s, i)
  if t.kind != FloatL:
    raise StlAsciiParseError.newException(&"expected FloatL, got {t.kind} at {t.sI.a}..{t.sI.b}")
  v = (typeof(v))(s.getFloat(t))


proc parseStlAsciiGeneric*[SeqT](
  s: string, i: var int,
  v: var SeqT, elementT: typedesc
) =
  eat(s, i, SolidKw)
  discard eatOptional(s, i, IdentL)

  const needNormals = elementT is tuple[vertex: Vec3, normal: Vec3]

  while true:
    let t = nextToken(s, i)

    case t.kind
    of FacetKw:
      when needNormals:
        var normal: Vec3
        var hasNormal = false
      
      if eatOptional(s, i, NormalKw):
        when needNormals:
          hasNormal = true
          parseStlAscii(s, i, normal.x)
          parseStlAscii(s, i, normal.y)
          parseStlAscii(s, i, normal.z)
        else:
          eat(s, i, FloatL)
          eat(s, i, FloatL)
          eat(s, i, FloatL)
      
      eat(s, i, OuterKw)
      eat(s, i, LoopKw)

      var triangle: array[3, Vec3]

      for tI in 0..<3:
        eat(s, i, VertexKw)
        parseStlAscii(s, i, triangle[tI].x)
        parseStlAscii(s, i, triangle[tI].y)
        parseStlAscii(s, i, triangle[tI].z)

      when needNormals:
        if not hasNormal:
          normal = cross(triangle[1] - triangle[0], triangle[2] - triangle[0]).normalize
      
      when needNormals:
        v.add (vertex: triangle[0], normal: normal)
        v.add (vertex: triangle[1], normal: normal)
        v.add (vertex: triangle[2], normal: normal)
      else:
        #? maybe overengeneering? will anyone use theese?
        when compiles(v.add(triangle)):
          v.add triangle
        else:
          v.add triangle[0]
          v.add triangle[1]
          v.add triangle[2]

      eat(s, i, EndLoopKw)
      eat(s, i, EndFacetKw)
    
    of EndSolidKw:
      discard eatOptional(s, i, IdentL)
      break
    
    else:
      raise StlAsciiParseError.newException(&"expected facet or endsolid, got {t.kind} at {t.sI.a}..{t.sI.b}")


proc parseStlAscii*(
  s: string, i: var int,
  v: var seq[tuple[vertex: Vec3, normal: Vec3]]
) =
  parseStlAsciiGeneric(s, i, v, tuple[vertex: Vec3, normal: Vec3])

proc parseStlAscii*(
  s: string, i: var int,
  v: var seq[Vec3]
) =
  parseStlAsciiGeneric(s, i, v, Vec3)


proc parseStlAscii*(s: string, i: var int, v: var Shape) =
  var data: seq[tuple[vertex: Vec3, normal: Vec3]]
  parseStlAscii(s, i, data)
  v = newShape(data, GL_TRIANGLES)


proc parseStlAscii*(
  s: string, t: typedesc,
): t =
  var i = 0
  parseStlAscii(s, i, result)



when isMainModule:
  const data = staticRead("../../../tests/data/lever_mechanism.stl")
  
  let vertices = data.parseStlAscii(seq[Vec3])  #! <----
  # see also:
  #   data.parseStlAscii(seq[tuple[vertex: Vec3, normal: Vec3]])
  #   data.parseStlAscii(Shape)
  
  echo "vertex count: ", vertices.len

