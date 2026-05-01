import std/[tables, macros, sequtils, options, strutils, sets]
import pkg/[shady, chroma, bumpy]
import pkg/pixie/[images, fonts]
import ./[transform, gl, text as renderText]

export shady.gl_Position, shady.gl_VertexID


when hasImageman:
  import pkg/imageman/[images as imagemanImages, colors as imagemanColors]


type
  FaceOrientation* = enum
    front
    back
  
  WindingOrder* = enum
    cw   # clockwise
    ccw  # counter-clockwise

  
  FrameBuffer* = ref object
    fbo*: FrameBuffers
    tex*: Texture
    size*: IVec2

  PushedFrameBuffer* = object
    fbo*, prevFbo*: GlUint
    size*, prevSize*: IVec2


  DrawContext* = ref object
    emptyVao*: VertexArrays
    rect*: Mesh
    line*: Mesh

    shaders*: Table[int, RootRef]
    # parametrizedShaders*: Table[seq[int], RootRef]
    
    px*: Vec2  ## size of a pixel
    wh*: Vec2  ## size of the drawing area in pixels

    fbo*: GlUint = 0
    fboSize*: IVec2
    
    offset*: Vec2

    glyphBuffer*: GlyphBuffer

    viewportMatrix*: Mat4 = mat4()
    projectionMatrix*: Mat4 = mat4()
    viewportToGlMatrix*: Mat4 = mat4()
    glToViewportMatrix*: Mat4 = mat4()

    freeFrameBuffers: seq[FrameBuffer]
    unusedFrameBuffers: HashSet[GlUint]
  

  ShaderClosure*[Signature] = ref object
    cpuCallback*: Signature
    glslCode*: string
  

  ShaderKind = enum
    vert
    frag



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


proc tryMangle(n: NimNode): Option[string] =
  if n.kind in {nnkSym, nnkIdent}: return some(n.strVal)
  if n.kind in {nnkDotExpr, nnkConv} and n.len == 2:
    let a = tryMangle(n[0])
    let b = tryMangle(n[1])
    if a.isSome and b.isSome:
      return some(a.get & "_" & b.get)
  # return none(typeof(result))


proc makeShaderViaShady(
  ctx: NimNode,
  version: NimNode,
  uniforms: Table[string, NimNode],  # name -> type
  id: int,
  vert: NimNode,
  frag: NimNode,
  shaderT: NimNode,
  shaderX: NimNode,
  replacements: array[ShaderKind, tuple[comptime, runtime: seq[(string, NimNode)]]],
): NimNode =
  var uniformsNodes: seq[NimNode]
  for n, t in uniforms:
    uniformsNodes.add nnkIdentDefs.newTree(
      ident(n),
      nnkBracketExpr.newTree(bindSym("OpenglUniform"), t),
      newEmptyNode()
    )

  var uniformsNodes2: seq[NimNode]
  for n, t in uniforms:
    uniformsNodes2.add nnkAsgn.newTree(
      nnkDotExpr.newTree(shaderX, ident(n)),
      nnkCall.newTree(
        nnkBracketExpr.newTree(bindSym("OpenglUniform"), t),
        nnkBracketExpr.newTree(
          nnkDotExpr.newTree(shaderX, ident("shader")),
          newLit(n)
        )
      )
    )

  var shaderCode = [
    ShaderKind.vert: nnkCall.newTree(
      bindSym("toGLSL"),
      vert[0],
      version
    ),
    ShaderKind.frag: nnkCall.newTree(
      bindSym("toGLSL"),
      frag[0],
      version
    )
  ]

  for kind, replacements in replacements:
    if replacements.comptime.len != 0:
      for (k, v) in replacements.comptime:
        shaderCode[kind] = newCall(
          bindSym("replace"),
          shaderCode[kind],
          newLit(k),
          v
        )
      shaderCode[kind] = newCall(ident("static"), shaderCode[kind])

    for (k, v) in replacements.runtime:
      shaderCode[kind] = newCall(
        bindSym("replace"),
        shaderCode[kind],
        newLit(k),
        v
      )


  result = nnkStmtList.newTree(
    vert,
    frag,

    nnkTypeSection.newTree(
      nnkTypeDef.newTree(
        shaderT,
        newEmptyNode(),
        nnkRefTy.newTree(
          nnkObjectTy.newTree(
            newEmptyNode(),
            nnkOfInherit.newTree(
              bindSym("RootObj"),
            ),
            nnkRecList.newTree(
              @[
                nnkIdentDefs.newTree(
                  ident("shader"),
                  bindSym("Shader"),
                  newEmptyNode()
                )
              ] & uniformsNodes
            )
          )
        )
      )
    ),

    nnkIfExpr.newTree(
      nnkElifBranch.newTree(
        nnkCall.newTree(
          bindSym("not"),
          nnkCall.newTree(
            bindSym("hasKey"),
            nnkDotExpr.newTree(ctx, ident "shaders"),  # todo: use parametrizedShaders instead when has runtime insertions
            newLit(id),
          )
        ),
        nnkStmtList.newTree(
          @[
            nnkLetSection.newTree(
              nnkIdentDefs.newTree(shaderX, newEmptyNode(), nnkCall.newTree(bindSym("new"), shaderT)),
            ),
            
            nnkAsgn.newTree(
              nnkDotExpr.newTree(shaderX, ident("shader")),
              nnkCall.newTree(
                bindSym("newShader"),
                nnkTableConstr.newTree(
                  nnkExprColonExpr.newTree(
                    ident("GlVertexShader"),
                    shaderCode[ShaderKind.vert],
                  ),
                  nnkExprColonExpr.newTree(
                    ident("GlFragmentShader"),
                    shaderCode[ShaderKind.frag],
                  )
                )
              )
            ),
          ] & uniformsNodes2 & @[
            nnkCall.newTree(
              bindSym("[]="),
              nnkDotExpr.newTree(ctx, ident("shaders")),
              newLit(id),
              nnkCall.newTree(bindSym("RootRef"), shaderX),
            ),
          ]
        )
      )
    ),
    
    nnkCall.newTree(
      shaderT,
      nnkCall.newTree(bindSym"[]", nnkDotExpr.newTree(ctx, ident("shaders")), newLit(id)),
    )
  )


macro makeShaderImpl(
  ctx: DrawContext,
  body: untyped,
  uniforms: typed,
  comptimeInsertions: typed,
  comptimeInsertionTypes: untyped,
  runtimeInsertions: typed,
  runtimeInsertionTypes: untyped,
): auto =
  result = newStmtList()

  let id = newShaderId
  inc newShaderId

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

  var
    comptimeInsertionsDecl: seq[NimNode]
    runtimeInsertionsDecl: seq[NimNode]
    comptimeInsertionStubs: seq[NimNode]
    runtimeInsertionStubs: seq[NimNode]

  for i, x in comptimeInsertions:
    comptimeInsertionsDecl.add nnkConstDef.newTree(
      nskConst.genSym("comptimeInsertion"),
      newEmptyNode(),
      nnkPrefix.newTree(ident("$"), x)
    )
    comptimeInsertionStubs.add nnkIdentDefs.newTree(
      nskLet.genSym("comptimeInsertion_" & $i & "_stub"),
      newEmptyNode(),
      newCall(bindSym("default"), comptimeInsertionTypes[i])
    )

  for i, x in runtimeInsertions:
    runtimeInsertionsDecl.add nnkIdentDefs.newTree(
      nskLet.genSym("runtimeInsertion"),
      newEmptyNode(),
      nnkPrefix.newTree(ident("$"), x)
    )
    runtimeInsertionStubs.add nnkIdentDefs.newTree(
      nskLet.genSym("comptimeInsertion_" & $i & "_stub"),
      newEmptyNode(),
      newCall(bindSym("default"), runtimeInsertionTypes[i])
    )

  var replacements: array[ShaderKind, tuple[comptime, runtime: seq[(string, NimNode)]]]
  
  template subTraverse(body: NimNode, outBody: var NimNode) {.dirty.} =
    traverse(
      body, outBody, kind,
      uniforms, uniformsTable, uniformsInitTable,
      params,
      comptimeInsertions, comptimeInsertionTypes,
      runtimeInsertions, runtimeInsertionTypes,
      comptimeInsertionsDecl, runtimeInsertionsDecl,
      comptimeInsertionStubs, runtimeInsertionStubs,
      replacements,
    )

  template subTraverseParams(body: NimNode) {.dirty.} =
    traverseParams body, kind, uniformsTable, params

  proc traverse(
    body: NimNode,
    outBody: var NimNode,
    kind: ShaderKind,
    uniforms: NimNode,
    uniformsTable: var Table[string, NimNode],  # name -> type
    uniformsInitTable: var Table[string, NimNode],  # name -> init value
    params: var array[ShaderKind, seq[NimNode]],
    comptimeInsertions: NimNode,
    comptimeInsertionTypes: NimNode,
    runtimeInsertions: NimNode,
    runtimeInsertionTypes: NimNode,
    comptimeInsertionsDecl: seq[NimNode],
    runtimeInsertionsDecl: seq[NimNode],
    comptimeInsertionStubs: seq[NimNode],
    runtimeInsertionStubs: seq[NimNode],
    replacements: var array[ShaderKind, tuple[comptime, runtime: seq[(string, NimNode)]]]
  ) =

    # @uniformIdx
    if body.kind == nnkPrefix and body.len == 2 and body[0] == ident("@") and body[1].kind == nnkIntLit:
      let uniformIdx = body[1].intVal
      let typedUniform = uniforms[uniformIdx]
      
      let name = (let n = typedUniform.tryMangle; if n.isSome: "u_" & n.get else: "uniform_" & $uniformIdx)
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

    # typIdx@!exprIdx
    elif body.kind == nnkInfix and body.len == 3 and body[0] == ident("@!") and body[2].kind == nnkIntLit:
      outBody.add comptimeInsertionStubs[body[2].intVal][0]
      replacements[kind].comptime.add (
        comptimeInsertionStubs[body[2].intVal][0].strVal,
        comptimeInsertionsDecl[body[2].intVal][0]
      )

    # typIdx@?exprIdx
    elif body.kind == nnkInfix and body.len == 3 and body[0] == ident("@?") and body[2].kind == nnkIntLit:
      outBody.add runtimeInsertionStubs[body[2].intVal][0]
      replacements[kind].runtime.add (
        runtimeInsertionStubs[body[2].intVal][0].strVal,
        runtimeInsertionsDecl[body[2].intVal][0]
      )
    
    # var name {.inp.}: Typ
    elif body.kind == nnkVarSection:
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
            var defsCurrent = nnkIdentDefs.newTree(
              varName.nameIdent,
              nnkVarTy.newTree(body[^2]),
            )
            var defsNext = nnkIdentDefs.newTree(
              varName.nameIdent,
              body[^2],
            )
            subTraverse(body[^1], defsCurrent)
            subTraverse(body[^1], defsNext)
            params[kind].add defsCurrent
            params[kind.succ].add defsNext
            if body[^1].kind != nnkEmpty:
              var asgn = nnkAsgn.newTree(varName.nameIdent)
              subTraverse(body[^1], asgn)
              outBody.add asgn

          elif pragmas.hasAndPop(ident("outGl")) or pragmas.hasAndPop(ident("outputGl")):
            keepVar = false
            var defs = nnkIdentDefs.newTree(
              varName.nameIdent,
              nnkVarTy.newTree(body[^2]),
            )
            subTraverse(body[^1], defs)
            params[kind].add defs
            if body[^1].kind != nnkEmpty:
              var asgn = nnkAsgn.newTree(varName.nameIdent)
              subTraverse(body[^1], asgn)
              outBody.add asgn

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
            outBody.add nnkVarSection.newTree(newN)
    
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

  let vertProcname = nskProc.genSym("vert")
  let fragProcname = nskProc.genSym("frag")

  if comptimeInsertionsDecl.len != 0:
    result.add nnkConstSection.newTree(comptimeInsertionsDecl)
    result.add nnkLetSection.newTree(comptimeInsertionStubs)

  if runtimeInsertionsDecl.len != 0:
    result.add nnkLetSection.newTree(runtimeInsertionsDecl)
    result.add nnkLetSection.newTree(runtimeInsertionStubs)

  result.add makeShaderViaShady(
    ctx, version, uniformsTable, id,
    nnkProcDef.newTree(
      vertProcname,
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
      fragProcname,
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
    replacements,
  )[0..^1]


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
  
  when defined(rice_debugShaders):
    let lineInfo = $body.lineInfo
    result.insert result.len - 1, quote do:
      static:
        echo "vert shader defined at ", `lineInfo`
        echo toGLSL(`vertProcname`, `version`)
        echo "frag shader defined at ", `lineInfo`
        echo toGLSL(`fragProcname`, `version`)


macro makeShader*(ctx: DrawContext, body: untyped): auto =
  var uniforms = nnkTupleConstr.newTree()
  var comptimeInsertions = nnkTupleConstr.newTree()
  var comptimeInsertionTypes = nnkTupleConstr.newTree()
  var runtimeInsertions = nnkTupleConstr.newTree()
  var runtimeInsertionTypes = nnkTupleConstr.newTree()

  proc traverse(body: NimNode, uniforms: var NimNode) =
    # @(expr)
    if body.kind == nnkPrefix and body.len == 2 and body[0] == ident("@") and body[1].kind == nnkPar:
      # pass `@(0)` in body and typed `expr` to next macros
      var i = uniforms.find(body[1])
      if i == -1:
        uniforms.add body[1]
        i = uniforms.len - 1
      let initExpr = body[1]
      body[1] = newLit(i)
      body[1].copyLineInfo(initExpr)

    # typ@!(expr)
    elif body.kind == nnkInfix and body.len == 3 and body[0] == ident("@!") and body[2].kind == nnkPar:
      # pass `0@!(0)` in body, untyped `typ` and typed `expr` to next macros
      var i = comptimeInsertions.find(body[1])
      if i == -1:
        comptimeInsertions.add body[2]
        comptimeInsertionTypes.add body[1]
        i = comptimeInsertions.len - 1
      let initExpr = body[1]
      body[1] = newLit(i)
      body[2] = newLit(i)
      body[1].copyLineInfo(initExpr)

    # @?(expr)
    elif body.kind == nnkInfix and body.len == 3 and body[0] == ident("@?") and body[2].kind == nnkPar:
      # pass `0@?(0)` in body, untyped `typ` and typed `expr` to next macros
      var i = runtimeInsertions.find(body[1])
      if i == -1:
        runtimeInsertions.add body[2]
        runtimeInsertionTypes.add body[1]
        i = runtimeInsertions.len - 1
      let initExpr = body[1]
      body[1] = newLit(i)
      body[2] = newLit(i)
      body[1].copyLineInfo(initExpr)
    
    if body.len != 0:
      for x in body: traverse x, uniforms
  
  traverse body, uniforms
  
  result = newCall(
    bindSym("makeShaderImpl"),
    ctx,
    body,
    uniforms,
    comptimeInsertions,
    comptimeInsertionTypes,
    runtimeInsertions,
    runtimeInsertionTypes,
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

proc color*(v: Vec4): chroma.Color =
  chroma.Color(r: v.x, g: v.y, b: v.z, a: v.w)


proc round*(v: Vec2): Vec2 =
  vec2(round(v.x), round(v.y))

proc ceil*(v: Vec2): Vec2 =
  vec2(ceil(v.x), ceil(v.y))

proc floor*(v: Vec2): Vec2 =
  vec2(floor(v.x), floor(v.y))


proc passTransform*(ctx: DrawContext, shader: tuple|object|ref object, pos = vec2(), size = vec2(10, 10), angle: float32 = 0, flipY = false) =
  shader.transform.uniform =
    translate(vec3(ctx.px*(vec2(pos.x, -pos.y) - ctx.wh - (if flipY: vec2(0, size.y) else: vec2())), 0)) *
    scale(if flipY: vec3(1, -1, 1) else: vec3(1, 1, 1)) *
    rotate(angle, vec3(0, 0, 1))
  shader.size.uniform = size
  shader.px.uniform = ctx.px


var gltex*: Uniform[Sampler2d]  # workaround shady#9
# todo: Sampler2dMS

proc transformation*(glpos: var Vec4, pos: var Vec2, size, px, ipos: Vec2, transform: Mat4) =
  let scale = vec2(px.x * size.x, px.y * -size.y)
  glpos = transform * mat2(scale.x, 0, 0, scale.y).mat4 * vec4(ipos, vec2(0, 1))
  pos = vec2(ipos.x * size.x, ipos.y * size.y)



proc `viewport=`*(ctx: DrawContext, mat: Mat4) =
  ctx.viewportMatrix = mat
  ctx.viewportToGlMatrix = combine(ctx.viewportMatrix, ctx.projectionMatrix)
  ctx.glToViewportMatrix = inverse(ctx.viewportToGlMatrix)

proc `projection=`*(ctx: DrawContext, mat: Mat4) =
  ctx.projectionMatrix = mat
  ctx.viewportToGlMatrix = combine(ctx.viewportMatrix, ctx.projectionMatrix)
  ctx.glToViewportMatrix = inverse(ctx.viewportToGlMatrix)



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


proc emptyMesh*(ctx: DrawContext, kind: GlEnum, vertexCount: int): Mesh =
  Mesh(vao: ctx.emptyVao, kind: kind, len: vertexCount)


proc newDrawContext*: DrawContext =
  new result

  result.emptyVao = newVertexArrays(1)

  result.rect = newMesh(
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

  result.line = newMesh(
    [
      0'f32,
      1'f32,
    ],
    kind = GL_LINES
  )

  result.viewportMatrix = mat4()


proc updateDrawingAreaSize*(ctx: DrawContext, size: IVec2) =
  ## update size
  ctx.px = vec2(2'f32 / size.x.float32, 2'f32 / size.y.float32)
  ctx.wh = ivec2(size.x, -size.y).vec2 / 2
  ctx.fboSize = size



proc drawText*(ctx: DrawContext, pos: Vec3, arrangement: Arrangement, color: Vec4, origin: Vec2 = vec2(0.5, 0.5), transform = mat4()) =
  if arrangement == nil or arrangement.fonts.len == 0:
    return

  let pos = ctx.viewportToGlMatrix * transform * pos

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
        pos.xy + vec2(rect.x, -rect.y) * ctx.px - vec2(box.w + box.x, -(box.h + box.y)) * origin * ctx.px,
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



# ===================
# --- FrameBuffer ---
# ===================

proc requireFrameBufferWithExactOrBiggerSize*(ctx: DrawContext, minSize: IVec2): FrameBuffer =
  ## get or resize or create a frameBuffer with size.x >= minSize.x and size.y >= minSize.y
  let minSize = ivec2(max(minSize.x, 1), max(minSize.y, 1))
  
  var i = 0
  while i < ctx.freeFrameBuffers.len:
    template ef: untyped = ctx.freeFrameBuffers[i]

    if ef.size.x >= minSize.x and ef.size.y >= minSize.y:
      ctx.unusedFrameBuffers.excl ef.fbo[0]
      result = ef
      ctx.freeFrameBuffers.del i
      return
    
    inc i
  
  # no available free buffer with size that is at least `minSize`

  if ctx.freeFrameBuffers.len != 0:
    # resize existing framebuffer
    template ef: untyped = ctx.freeFrameBuffers[0]
    result = ef

    ef.size = ivec2(max(minSize.x, ef.size.x), max(minSize.y, ef.size.y))

    let prevFbo = ctx.fbo
    
    glBindFramebuffer(GlFramebuffer, ef.fbo[0])
    glBindTexture(GlTexture2d, ef.tex.raw)
    glTexImage2D(GlTexture2d, 0, GlRgba.Glint, ef.size.x, ef.size.y, 0, GlRgba, GlUnsignedByte, nil)
    glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
    glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
    glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, ef.tex.raw, 0)
        
    glBindFramebuffer(GlFramebuffer, prevFbo)
    
    ctx.freeFrameBuffers.del 0
  
  else:
    # create new framebuffer
    new result

    template ef: untyped = result
    ef.size = minSize

    ef.fbo = newFrameBuffers(1)
    ef.tex = newTexture()

    let prevFbo = ctx.fbo
    
    glBindFramebuffer(GlFramebuffer, ef.fbo[0])
    glBindTexture(GlTexture2d, ef.tex.raw)
    glTexImage2D(GlTexture2d, 0, GlRgba.Glint, ef.size.x, ef.size.y, 0, GlRgba, GlUnsignedByte, nil)
    glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
    glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
    glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, ef.tex.raw, 0)
        
    glBindFramebuffer(GlFramebuffer, prevFbo)


proc requireFrameBuffer*(ctx: DrawContext, size: IVec2): FrameBuffer =
  ## get or create a framebuffer with exact size
  let size = ivec2(max(size.x, 1), max(size.y, 1))
  
  var i = 0
  while i < ctx.freeFrameBuffers.len:
    template ef: untyped = ctx.freeFrameBuffers[i]

    if ef.size == size:
      ctx.unusedFrameBuffers.excl ef.fbo[0]
      result = ef
      ctx.freeFrameBuffers.del i
      return
    
    inc i
  
  # no available free buffer with size that is at least `size`
  # create new framebuffer
  new result

  template ef: untyped = result
  ef.size = size

  ef.fbo = newFrameBuffers(1)
  ef.tex = newTexture()

  let prevFbo = ctx.fbo
  
  glBindFramebuffer(GlFramebuffer, ef.fbo[0])
  glBindTexture(GlTexture2d, ef.tex.raw)
  glTexImage2D(GlTexture2d, 0, GlRgba.Glint, ef.size.x, ef.size.y, 0, GlRgba, GlUnsignedByte, nil)
  glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
  glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
  glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, ef.tex.raw, 0)
      
  glBindFramebuffer(GlFramebuffer, prevFbo)


proc free*(ctx: DrawContext, ef: FrameBuffer) =
  ## allow to reuse framebuffer
  assert ctx.freeFrameBuffers.allIt(it.fbo[0] != ef.fbo[0]), "framebuffer freed twice"
  ctx.freeFrameBuffers.add ef


proc deleteUnusedFrameBuffers*(ctx: DrawContext) =
  ## remove all buffers that was allowed to reuse, but has not been reused
  var c = 0
  for efFbo in ctx.unusedFrameBuffers:
    var i = 0
    while i < ctx.freeFrameBuffers.len:
      template ef: untyped = ctx.freeFrameBuffers[i]
      if ef.fbo[0] == efFbo:
        ctx.freeFrameBuffers.del i
        inc c
      else:
        inc i


proc markAllFreeFrameBuffersAsUnused*(ctx: DrawContext) =
  for ef in ctx.freeFrameBuffers:
    ctx.unusedFrameBuffers.incl ef.fbo[0]


proc push*(ctx: DrawContext, ef: FrameBuffer): PushedFrameBuffer =
  ## set current framebuffer
  result = PushedFrameBuffer(
    fbo: ef.fbo[0],
    size: ef.size,
    prevFbo: ctx.fbo,
    prevSize: ctx.fboSize,
  )
  ctx.fbo = ef.fbo[0]
  ctx.fboSize = ef.size
  glBindFramebuffer(GlFramebuffer, ef.fbo[0])

  glViewport 0, 0, ef.size.x.GLsizei, ef.size.y.GLsizei
  ctx.updateDrawingAreaSize(ef.size)


proc pop*(ctx: DrawContext, ef: PushedFrameBuffer) =
  ## reset current framebuffer
  assert ctx.fbo == ef.fbo
  assert ctx.fboSize == ef.size
  ctx.fbo = ef.prevFbo
  ctx.fboSize = ef.prevSize
  
  glBindFramebuffer(GlFramebuffer, ctx.fbo)

  glViewport 0, 0, ctx.fboSize.x.GLsizei, ctx.fboSize.y.GLsizei
  ctx.updateDrawingAreaSize(ctx.fboSize)



# =======================
# --- Shader closures ---
# =======================

macro makeShaderClosure*[T: proc](body: T): ShaderClosure[T] =
  ## todo
  quote do: ShaderClosure[proc()]()



when isMainModule:
  import pkg/[siwin]

  let win = newOpenglWindow()
  opengl.loadExtensions()
  let ctx = newDrawContext()

  # todo:
  # let colorizer = makeShaderClosure proc(t: float32): Vec4 =
  #   mix(vec4(1, 0, 0, 1), vec4(0, 1, 0, 1), t)

  # let sinSampler = makeShaderClosure proc(t: float32): Vec4 =
  #   vec4(t, sin(t * @!(PI)), 0, 1)

  # todo:
  # let colorizer = """
  #   vec4 colorize(t: float32) {
  #     return mix(vec4(1, 0, 0, 1), vec4(0, 1, 0, 1), t);
  #   }
  # """

  win.eventsHandler.onRender = proc(e: RenderEvent) =
    glClearColor(0.1, 0.1, 0.1, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    glViewport(0, 0, e.window.size.x, e.window.size.y)

    let numPoints = e.window.size.x
    
    # todo:
    # let shader = ctx.makeShader:
    #   proc vert =
    #     gl_Position = `proc@?`(sinSampler)(gl_VertexID.float32 / @(numPoints.float32))
    #
    #   proc frag =
    #     var glCol {.outGl.}: Vec4
    #
    #     glCol = `proc@?`(colorizer)(t)

    let shader = ctx.makeShader:
      proc vert =
        var t {.out.}: float32

        t = gl_VertexID.float32 / @(numPoints.float32)
        gl_Position = vec4(t * 2 - 1, sin(t * 2 * PI), 0, 1)
    
      proc frag =
        var glCol {.outGl.}: Vec4
    
        # todo:
        # `outside@?`(colorizer)
        # glCol = Vec4@!("colorizer(t)")
        
        glCol = vec4(float32@!("atan(t, 1.0 - t)"), 0, 0, 1)
    
    useAndPassUniforms shader
    glDrawArrays(GL_LINE_STRIP, 0, numPoints)

  run win

