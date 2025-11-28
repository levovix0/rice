import std/[tables, macros, sequtils]
import pkg/[shady, pixie]
import pkg/fusion/[astdsl]
import ./[transform, gl, text as renderText]

# todo: remove dependency on fusion


when hasImageman:
  import pkg/imageman/[images as imagemanImages, colors as imagemanColors]


type
  FaceOrientation* = enum
    front
    back
  
  WindingOrder* = enum
    cw   # clockwise
    ccw  # counter-clockwise


  DrawContext* = ref object
    rect*: Shape

    shaders*: Table[int, RootRef]
    
    px*: Vec2  ## size of a pixel
    wh*: Vec2  ## size of the drawing area in pixels

    fbo*: GlUint = 0
    fboSize*: IVec2
    
    offset*: Vec2

    glyphBuffer*: GlyphBuffer

    viewportToGlMatrix*: Mat4
    glToViewportMatrix*: Mat4



#* ------------- makeShader macros ------------- *#

var newShaderId {.compileTime.}: int = 1


proc allPragmas(n: NimNode): seq[NimNode] =
  if n.kind == nnkPragmaExpr:
    for x in n[1]:
      result.add x
  elif n.kind == nnkPragma:
    for x in n:
      result.add x

proc nameIdent(n: NimNode): NimNode =
  result = n
  if result.kind == nnkPragmaExpr: result = n[0]
  if result.kind == nnkPostfix: result = n[1]


proc hasAndPop[T](arr: var seq[T], v: T): bool =
  let i = arr.find v
  if i != -1:
    arr.delete i
    return true
  return false


proc fixVmathTypes(n: NimNode): NimNode =
  result = n
  if result.kind == nnkBracketExpr:
    if   result[0] == bindSym("GVec4") and result[1] == bindSym("float32"): result = bindSym("Vec4")
    elif result[0] == bindSym("GVec4") and result[1] == bindSym("float64"): result = bindSym("DVec4")
    elif result[0] == bindSym("GVec4") and result[1] == bindSym("int32"):   result = bindSym("IVec4")
    
    elif result[0] == bindSym("GVec3") and result[1] == bindSym("float32"): result = bindSym("Vec3")
    elif result[0] == bindSym("GVec3") and result[1] == bindSym("float64"): result = bindSym("DVec3")
    elif result[0] == bindSym("GVec3") and result[1] == bindSym("int32"):   result = bindSym("IVec3")
    
    elif result[0] == bindSym("GVec2") and result[1] == bindSym("float32"): result = bindSym("Vec2")
    elif result[0] == bindSym("GVec2") and result[1] == bindSym("float64"): result = bindSym("DVec2")
    elif result[0] == bindSym("GVec2") and result[1] == bindSym("int32"):   result = bindSym("IVec2")
    
    elif result[0] == bindSym("GMat4") and result[1] == bindSym("float32"): result = bindSym("Mat4")
    elif result[0] == bindSym("GMat4") and result[1] == bindSym("float64"): result = bindSym("DMat4")
    
    elif result[0] == bindSym("GMat3") and result[1] == bindSym("float32"): result = bindSym("Mat3")
    elif result[0] == bindSym("GMat3") and result[1] == bindSym("float64"): result = bindSym("DMat3")
    
    elif result[0] == bindSym("GMat3") and result[1] == bindSym("float32"): result = bindSym("Mat2")
    elif result[0] == bindSym("GMat3") and result[1] == bindSym("float64"): result = bindSym("DMat2")

    else:
      result[1] = result[1].fixVmathTypes


proc makeShaderViaShady(
  ctx: NimNode,
  version: NimNode,
  uniforms: Table[string, NimNode],
  id: int,
  vert: NimNode,
  frag: NimNode,
  shaderT: NimNode,
  shaderX: NimNode,
): NimNode =
  result = buildAst(stmtList):
    vert
    frag

    typeSection:
      typeDef:
        shaderT
        empty()
        refTy:
          objectTy:
            empty()
            ofInherit:
              bindSym"RootObj"
            recList:
              identDefs(ident "shader"):
                bindSym"Shader"
                empty()

              for n, t in uniforms:
                identDefs(ident n):
                  bracketExpr bindSym"OpenglUniform": t
                  empty()
    
    ifExpr:
      elifBranch:
        call bindSym"not":
          call bindSym"hasKey":
            dotExpr(ctx, ident "shaders")
            newLit id
        stmtList:
          letSection:
            identDefs(shaderX, empty(), call(bindSym"new", shaderT))
          
          asgn dotExpr(shaderX, ident"shader"):
            call bindSym"newShader":
              tableConstr:
                exprColonExpr:
                  ident "GlVertexShader"
                  call bindSym"toGLSL":
                    vert[0]
                    version
                exprColonExpr:
                  ident "GlFragmentShader"
                  call bindSym"toGLSL":
                    frag[0]
                    version
          
          for n, t in uniforms:
            asgn dotExpr(shaderX, ident n):
              call bracketExpr(bindSym"OpenglUniform", t):
                bracketExpr:
                  dotExpr(shaderX, ident "shader")
                  newLit n
          
          call bindSym"[]=":
            dotExpr(ctx, ident "shaders")
            newLit id
            call bindSym"RootRef": shaderX
    
    call shaderT: call(bindSym"[]", dotExpr(ctx, ident "shaders"), newLit id)


macro makeShaderImpl(ctx: DrawContext, body: untyped, uniforms: typed): auto =
  let id = newShaderId
  inc newShaderId
  type
    ShaderKind = enum
      vert
      frag
  var
    bodies: array[ShaderKind, NimNode] = [newStmtList(), newStmtList()]
    params: array[ShaderKind, seq[NimNode]]
    uniformsTable: Table[string, NimNode]  # name -> type
    uniformsInitTable: Table[string, NimNode]  # name -> init value
  
  var version: NimNode = newLit "300 es"
  var origBody = body
  var body = body
  if body.kind != nnkStmtList:
    body = newStmtList(body)
  
  template subTraverse(body: NimNode, outBody: var NimNode) {.dirty.} =
    traverse body, outBody, kind, uniforms, uniformsTable, uniformsInitTable, params

  template subTraverseParams(body: NimNode) {.dirty.} =
    traverseParams body, kind, uniformsTable, params

  proc traverse(
    body: NimNode,
    outBody: var NimNode,
    kind: ShaderKind,
    uniforms: NimNode,
    uniformsTable: var Table[string, NimNode],
    uniformsInitTable: var Table[string, NimNode],
    params: var array[ShaderKind, seq[NimNode]],
  ) =

    # @uniformIdx
    if body.kind == nnkPrefix and body.len == 2 and body[0] == ident("@") and body[1].kind == nnkIntLit:
      let uniformIdx = body[1].intVal
      let typedUniform = uniforms[uniformIdx]
      
      let name = (if typedUniform.kind in {nnkSym, nnkIdent}: "u_" & typedUniform.strVal else: "uniform_" & $uniformIdx)
      # todo: deduce name for uniforms like `this.my.x` as "this_my_x"
      uniformsTable[name] = typedUniform.getTypeInst.fixVmathTypes
      uniformsInitTable[name] = typedUniform
      
      let nameIdent = ident(name)
      nameIdent.copyLineInfo(body[1])
      
      let inst = nnkIdentDefs.newTree(
        nameIdent,
        nnkBracketExpr.newTree(bindSym("Uniform"), typedUniform.getTypeInst.fixVmathTypes),
        newEmptyNode(),
      )
      if inst notin params[kind]: params[kind].add inst
      outBody.add nameIdent
      
    
    # var name {.inp.}: Typ
    elif body.kind == nnkVarSection:
      var newVars = nnkVarSection.newTree()
      newVars.copyLineInfo(body)
      for body in body:
        for varName in body[0..^3]:
          var pragmas = varName.allPragmas
          var keepVar = true

          if pragmas.hasAndPop(ident("inp")) or pragmas.hasAndPop(ident("input")):
            keepVar = false
            params[kind].add nnkIdentDefs.newTree(
              varName.nameIdent,
              body[^2],
              body[^1],
            )

          elif pragmas.hasAndPop(nnkOutTy.newTree) or pragmas.hasAndPop(ident("output")):
            keepVar = false
            params[kind].add nnkIdentDefs.newTree(
              varName.nameIdent,
              nnkVarTy.newTree(body[^2]),
              body[^1],
            )
            params[kind.succ].add nnkIdentDefs.newTree(
              varName.nameIdent,
              body[^2],
              body[^1],
            )

          elif pragmas.hasAndPop(ident("outGl")) or pragmas.hasAndPop(ident("outputGl")):
            keepVar = false
            params[kind].add nnkIdentDefs.newTree(
              varName.nameIdent,
              nnkVarTy.newTree(body[^2]),
              body[^1],
            )

          if pragmas.hasAndPop(ident("inout")):
            keepVar = false
            error("todo: {.inout.}", varName)
          
          if keepVar:
            var newN = nnkIdentDefs.newTree(
              varName.nameIdent,
              body[^2],
              body[^1],
            )
            newN.copyLineInfo(body)
            if pragmas.len != 0:
              newN[0] = nnkPragmaExpr.newTree(newN[0], nnkPragma.newTree(pragmas))
            newVars.add newN
      outBody.add newVars
      
    
    elif body.len != 0:
      var newN = body.kind.newTree
      newN.copyLineInfo(body)
      for i in 0..<body.len: subTraverse body[i], newN
      outBody.add newN
    else:
      outBody.add body

  proc traverseParams(
    body: NimNode,
    kind: ShaderKind,
    uniformsTable: var Table[string, NimNode],
    params: var array[ShaderKind, seq[NimNode]],
  ) =
    if body[0].kind != nnkEmpty:
      error("shader proc must not have return value. Use `var glCol {.outGl.}: Vec4` instead", body[0])

    for param in body[1..^1]:
      params[kind].add param
      if param[^2].kind == nnkBracketExpr and param[^2][0] == ident("Uniform"):
        for name in param[0..^3]:
          uniformsTable[name.repr] = param[^2][1]
      

  for x in body:
    # {.version: ver.}
    if x.kind == nnkPragma and x.len == 1 and x[0].kind == nnkExprColonExpr and x[0][0] == ident("version"):
      version = x[0][1]
    
    # proc vert = body
    elif x.kind == nnkProcDef and x[0] == ident("vert"):
      let kind = ShaderKind.vert
      subTraverseParams x.params
      subTraverse x[^1], bodies[kind]

    # proc frag = body
    elif x.kind == nnkProcDef and x[0] == ident("frag"):
      let kind = ShaderKind.frag
      subTraverseParams x.params
      subTraverse x[^1], bodies[kind]
  
  if bodies[vert] == nil:
    (error("vert shader proc not defined", origBody))
  if bodies[frag] == nil:
    (error("frag shader proc not defined", origBody))

  let shaderT = nskType.genSym("ShaderT")

  result = makeShaderViaShady(
    ctx, version, uniformsTable, id,
    nnkProcDef.newTree(
      nskProc.genSym("vert"),
      newEmptyNode(),
      newEmptyNode(),
      nnkFormalParams.newTree(
        newEmptyNode() & params[vert]
      ),
      newEmptyNode(),
      newEmptyNode(),
      bodies[vert]
    ),
    nnkProcDef.newTree(
      nskProc.genSym("frag"),
      newEmptyNode(),
      newEmptyNode(),
      nnkFormalParams.newTree(
        newEmptyNode() & params[frag]
      ),
      newEmptyNode(),
      newEmptyNode(),
      bodies[frag]
    ),
    shaderT,
    nskLet.genSym("shaderX"),
  )

  var useAndPassUniformsBody = newStmtList()
  useAndPassUniformsBody.add nnkCall.newTree(
    ident("use"),
    nnkDotExpr.newTree(
      ident("shaderX"),
      ident("shader")
    )
  )

  for k, v in uniformsInitTable:
    useAndPassUniformsBody.add nnkAsgn.newTree(
      nnkDotExpr.newTree(
        nnkDotExpr.newTree(
          ident("shaderX"),
          ident(k)
        ),
        ident("uniform")
      ),
      v
    )

  result.insert result.len - 1, nnkTemplateDef.newTree(
    ident("useAndPassUniforms"),
    newEmptyNode(),
    newEmptyNode(),
    nnkFormalParams.newTree(
      newEmptyNode(),
      nnkIdentDefs.newTree(
        ident("shaderX"),
        shaderT,
        newEmptyNode()
      )
    ),
    nnkPragma.newTree(
      ident("dirty")
    ),
    newEmptyNode(),
    useAndPassUniformsBody,
  )


macro makeShader*(ctx: DrawContext, body: untyped): auto =
  var uniforms = nnkTupleConstr.newTree()

  proc traverse(body: NimNode, uniforms: var NimNode) =
    # @(expr)
    if body.kind == nnkPrefix and body.len == 2 and body[0] == ident("@") and body[1].kind == nnkPar:
      # pass @(expr) to next macros as typed expr
      var i = uniforms.find(body[1])
      if i == -1:
        uniforms.add body[1]
        i = uniforms.len - 1
      let initExpr = body[1]
      body[1] = newLit(i)
      body[1].copyLineInfo(initExpr)
    
    if body.len != 0:
      for x in body: traverse x, uniforms
  
  traverse body, uniforms
  
  result = newCall(
    bindSym("makeShaderImpl"),
    ctx,
    body,
    uniforms,
  )



#* ------------- utils ------------- *#

proc mat4*(x: Mat2): Mat4 =
  ## note: this function exists in Glsl, but do not in vmath
  mat4(
    x[0, 0], x[0, 1], 0, 0,
    x[1, 0], x[1, 1], 0, 0,
    0,       0,       1, 0,
    0,       0,       0, 1,
  )


proc vec4*(color: chroma.Color): Vec4 =
  vec4(color.r, color.g, color.b, color.a)


proc passTransform*(ctx: DrawContext, shader: tuple|object|ref object, pos = vec2(), size = vec2(10, 10), angle: float32 = 0, flipY = false) =
  shader.transform.uniform =
    translate(vec3(ctx.px*(vec2(pos.x, -pos.y) - ctx.wh - (if flipY: vec2(0, size.y) else: vec2())), 0)) *
    scale(if flipY: vec3(1, -1, 1) else: vec3(1, 1, 1)) *
    rotate(angle, vec3(0, 0, 1))
  shader.size.uniform = size
  shader.px.uniform = ctx.px


var gltex*: Uniform[Sampler2d]  # workaround shady#9

proc transformation*(glpos: var Vec4, pos: var Vec2, size, px, ipos: Vec2, transform: Mat4) =
  let scale = vec2(px.x * size.x, px.y * -size.y)
  glpos = transform * mat2(scale.x, 0, 0, scale.y).mat4 * vec4(ipos, vec2(0, 1))
  pos = vec2(ipos.x * size.x, ipos.y * size.y)



proc `viewportMatrix=`*(ctx: DrawContext, mat: Mat4) =
  ctx.viewportToGlMatrix = mat
  ctx.glToViewportMatrix = mat.inverse



proc windowToGlNormalizedMatrix*(ctx: DrawContext): Mat4 =
  ## returns matrix for converting from view plane coordinates [0..window.w, 0..window.h] (with y down)
  ## to opengl view plane coordinates [-1..1, -1..1] (with y up)
  combine(
    scale(vec3(ctx.px.x, -ctx.px.y, 1 / 2000)),
    translate(vec3(-1, 1, 0)),
  )

proc glNormalizedToWindowMatrix*(ctx: DrawContext): Mat4 =
  ## returns matrix for converting from opengl view plane coordinates [-1..1, -1..1] (with y up)
  ## to view plane coordinates [0..window.w, 0..window.h] (with y down)
  combine(
    translate(vec3(1, -1, 0)),
    scale(vec3(ctx.wh.x / 2, -ctx.wh.y / 2, 2000)),
  )


proc newDrawContext*: DrawContext =
  new result

  result.rect = newShape(
    [
      vec2(0, 1),   # top left
      vec2(0, 0),   # bottom left
      vec2(1, 0),   # bottom right
      vec2(1, 1),   # top right
    ], [
      0'u32, 1, 2,
      2, 3, 0,
    ]
  )

  result.viewportMatrix = mat4()


proc updateDrawingAreaSize*(ctx: DrawContext, size: IVec2) =
  ## update size
  ctx.px = vec2(2'f32 / size.x.float32, 2'f32 / size.y.float32)
  ctx.wh = ivec2(size.x, -size.y).vec2 / 2
  ctx.fboSize = size



proc drawText*(ctx: DrawContext, pos: Vec3, arrangement: Arrangement, color: Vec4, origin: Vec2 = vec2(0.5, 0.5)) =
  if arrangement == nil or arrangement.fonts.len == 0:
    return

  let pos = ctx.viewportToGlMatrix * pos

  let shader = ctx.makeShader:
    proc vert(transform: Uniform[Vec4], placement: Uniform[Vec4]) =
      var gl_Position {.outGl.}: Vec4
      var uv {.out.}: Vec2
      var ipos {.inp.}: Vec2
      
      gl_Position = vec4(transform.xy + ipos * transform.zw, vec2(0, 1))
      uv = placement.xy + ipos * placement.zw

    proc frag =
      var glCol {.outGl.}: Vec4

      let col = gltex.texture(uv)
      glCol = vec4(@(color).rgb * @(color).a, @(color).a) * col.r

  useAndPassUniforms shader
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  let family = ctx.glyphBuffer.families.mgetOrPut(arrangement.fonts[0].glyphFamily, GlyphFamilyBuffer()).addr

  var prevTexture = -1.Gluint
  let box = arrangement.computeBounds()

  for i, rune in arrangement.runes:
    var rect = arrangement.selectionRects[i]
    rect.wh = rect.wh + vec2(2, 2)
    
    # todo: force pixie to adjust text to pixel grid while generating arrangement, for better alligning
    
    shader.transform.uniform =
      vec4(
        pos.xy + rect.xy * ctx.px - vec2(box.w - box.x, -(box.h - box.y)) * origin * ctx.px,
        vec2(rect.w, -rect.h) * ctx.px
      )

    let texPlacement = family[].renderIfNeeded(rune, arrangement.fonts[0], rect.wh)
    shader.placement.uniform =
      vec4(
        vec2(texPlacement.x.float, texPlacement.y.float) /
        vec2(rice_glyphBuffer_textureSize, rice_glyphBuffer_textureSize),

        rect.wh /
        vec2(rice_glyphBuffer_textureSize, rice_glyphBuffer_textureSize)
      )
    
    if prevTexture != texPlacement.texture:
      glBindTexture(GlTexture2d, texPlacement.texture)
      glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
      prevTexture = texPlacement.texture

    draw ctx.rect
  
  glBindTexture(GlTexture2d, 0)
  glDisable(GlBlend)
