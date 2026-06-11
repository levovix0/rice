import std/[unittest]
import pkg/[vmath, bumpy]
import rice/paths

## Headless checks for the scanline triangulator.
## Filled area must equal the expected boolean-operation result: since triangles
## don't overlap, sum of |triangle areas| > expected means overlaps, < means gaps.


proc trisArea(tris: seq[Vec2]): float64 =
  var i = 0
  while i + 2 < tris.len:
    let a = tris[i]
    let b = tris[i + 1]
    let c = tris[i + 2]
    result += abs(
      (b.x - a.x).float64 * (c.y - a.y).float64 -
      (b.y - a.y).float64 * (c.x - a.x).float64
    ) / 2
    i += 3

proc windingAt(polys: openarray[Polygon], p: Vec2): int =
  for poly in polys:
    for i in 0 ..< poly.len:
      let a = poly[i]
      let b = poly[(i + 1) mod poly.len]
      if (a.y <= p.y) != (b.y <= p.y):
        let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
        if x > p.x:
          if b.y > a.y: inc result
          else: dec result

proc centroidsInside(tris: seq[Vec2], polys: openarray[Polygon]): bool =
  result = true
  var i = 0
  while i + 2 < tris.len:
    let c = (tris[i] + tris[i + 1] + tris[i + 2]) / 3
    if windingAt(polys, c) == 0:
      return false
    i += 3

proc sq(x, y, size: float32, cw = false): Polygon =
  if cw: @[vec2(x, y), vec2(x, y + size), vec2(x + size, y + size), vec2(x + size, y)]
  else: @[vec2(x, y), vec2(x + size, y), vec2(x + size, y + size), vec2(x, y + size)]


test "single square":
  let polys = [sq(0, 0, 2)]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - 4.0) < 1e-4
  check centroidsInside(tris, polys)

test "union of two overlapping squares":
  let polys = [sq(0, 0, 2), sq(1, 1, 2)]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - 7.0) < 1e-4
  check centroidsInside(tris, polys)

test "union of two coincident squares":
  let polys = [sq(0, 0, 2), sq(0, 0, 2)]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - 4.0) < 1e-4

test "union of two squares sharing an edge":
  let polys = [sq(0, 0, 1), sq(1, 0, 1)]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - 2.0) < 1e-4
  check centroidsInside(tris, polys)

test "subtraction: hole fully inside":
  let polys = [sq(0, 0, 3), sq(1, 1, 1, cw = true)]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - 8.0) < 1e-4
  check centroidsInside(tris, polys)

test "subtraction: hole crossing the outer boundary":
  # nonzero: A\B and B\A are filled (winding 1 and -1), the overlap cancels to 0
  let polys = [sq(0, 0, 2), sq(1, 1, 2, cw = true)]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - 6.0) < 1e-4
  check centroidsInside(tris, polys)

test "even-odd rule on two overlapping squares":
  let polys = [sq(0, 0, 2), sq(1, 1, 2)]
  let tris = triangulate(polys, EvenOdd)
  check abs(trisArea(tris) - 6.0) < 1e-4

test "self-intersecting bowtie":
  let polys = [Polygon @[vec2(0, 0), vec2(2, 2), vec2(2, 0), vec2(0, 2)]]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - 2.0) < 1e-4
  check centroidsInside(tris, polys)

test "union of two triangles (t4 case)":
  let triA = Polygon @[vec2(0, 0), vec2(1.5, 1), vec2(0, 2)]
  let triB = Polygon @[vec2(0.5, 0), vec2(2, 1), vec2(0.5, 2)]
  let tris = triangulate([triA, triB])
  # 1.5 + 1.5 - 2/3 overlap = 7/3
  check abs(trisArea(tris) - 7.0 / 3.0) < 1e-4
  check centroidsInside(tris, [triA, triB])

test "empty and degenerate input":
  check triangulate([Polygon @[]]).len == 0
  check triangulate([Polygon @[vec2(0, 0), vec2(1, 0)]]).len == 0
  check toTriangles(Polygon @[vec2(0, 0), vec2(1, 0), vec2(1, 1)]).len == 3

test "disjoint triangles":
  let polys = [
    Polygon @[vec2(0, 0), vec2(0.9, 0.5), vec2(0, 1)],
    Polygon @[vec2(1.1, 1), vec2(2, 1.5), vec2(1.1, 2)],
  ]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - 0.9) < 1e-4
  check centroidsInside(tris, polys)

test "triangles touching vertex-to-vertex":
  let polys = [
    Polygon @[vec2(0, 0), vec2(1, 1), vec2(0, 2)],
    Polygon @[vec2(1, 1), vec2(2, 0), vec2(2, 2)],
  ]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - 2.0) < 1e-4
  check centroidsInside(tris, polys)

test "vertex of one triangle lies on an edge of the other":
  # (0.75, 0.5) is on the edge (0,0)-(1.5,1); interiors don't overlap
  let polys = [
    Polygon @[vec2(0, 0), vec2(1.5, 1), vec2(0, 2)],
    Polygon @[vec2(0.75, 0.5), vec2(2, 0.2), vec2(2, 1.2)],
  ]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - (1.5 + 0.625)) < 1e-4
  check centroidsInside(tris, polys)

test "hexagram: edges cross, no vertex inside the other triangle":
  let polys = [
    Polygon @[vec2(1, 0), vec2(2, 1.73), vec2(0, 1.73)],
    Polygon @[vec2(1, 2.31), vec2(0, 0.58), vec2(2, 0.58)],
  ]
  let nonZeroArea = trisArea(triangulate(polys))
  let evenOddArea = trisArea(triangulate(polys, EvenOdd))
  # union = A + B - overlap, evenOdd = A + B - 2*overlap =>
  # 2*union - evenOdd = A + B exactly, whatever the overlap is
  check abs(2 * nonZeroArea - evenOddArea - (1.73 + 1.73)) < 1e-3
  check nonZeroArea > evenOddArea + 0.5  # the overlap hexagon is not degenerate
  check centroidsInside(triangulate(polys), polys)

test "subtraction of a fully nested triangle":
  let polys = [
    Polygon @[vec2(0, 0), vec2(2, 0), vec2(1, 2)],
    Polygon @[vec2(0.7, 0.4), vec2(1, 1.2), vec2(1.3, 0.4)],  # reversed winding
  ]
  let tris = triangulate(polys)
  check abs(trisArea(tris) - (2.0 - 0.24)) < 1e-4
  check centroidsInside(tris, polys)
