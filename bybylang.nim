# bybylang.nim - BybyLang AOT executable + Nim code generation + auto compile release

import strutils, os, osproc, tables, sequtils

# --------------------------
# Helpers
# --------------------------
proc stripQuotes(s: string): string =
  if s.len >= 2 and s[0] == '"' and s[^1] == '"':
    return s[1..^2]
  else:
    return s

proc parseIntSafe(s: string): int =
  try:
    return parseInt(s)
  except:
    return 0

# --------------------------
# Types & Globals
# --------------------------
type
  Mode = enum
    Low, Mid, High

  Token = object
    sym: string
    text: string

  ValueKind = enum
    IntVal, StrVal

  Value = object
    kind: ValueKind
    ival: int
    sval: string

const RAM_SIZE = 1024

var
  RAM: array[RAM_SIZE, int]
  BUS: seq[string] = @[]
  Pins: array[32, bool]
  quietMode = false
  ignoreErrors = false
  symTable = initTable[string, Value]()
  funcTable = initTable[string, seq[Token]]()

proc initSymTable()=
  symTable = initTable[string, Value]()

# --------------------------
# APU / HW helpers
# --------------------------
proc apuTran(name: string, payload: string) =
  if not quietMode:
    echo "[APU-TRAN] ", name, " -> ", payload

proc apuMem(action: string, target: string, value: string) =
  if action == "write":
    if target.startsWith("RAM"):
      let idx = parseIntSafe(target.replace("RAM", ""))
      if idx >= 0 and idx < RAM_SIZE:
        RAM[idx] = parseIntSafe(value)
    if not quietMode:
      echo "[APU-MEM] ", target, " <- ", value
  else:
    if not quietMode:
      echo "[APU-MEM] ", target, " -> ", (if target.startsWith("RAM"): $RAM[parseIntSafe(target.replace("RAM", ""))] else: "?")

proc apuCore(id: int, cmd: string) =
  if not quietMode:
    echo "[APU-CORE] ", id, " ", cmd

proc apuPin(pin: int, state: string) =
  if pin >= 0 and pin < Pins.high:
    Pins[pin] = (state == "high")
  if not quietMode:
    echo "[APU-PIN] pin ", pin, " set ", state

proc bitSend(bits: string) =
  BUS.add(bits)
  if not quietMode:
    echo "[BIT-SEND] ", bits

proc bitRecv() =
  if BUS.len > 0:
    let b = BUS[0]
    delete(BUS, 0)
    if not quietMode:
      echo "[BIT-RECV] ", b
  else:
    if not quietMode:
      echo "[BIT-RECV] empty"

proc memMap(target: string) =
  if not quietMode:
    echo "[MEM-MAP] ", target

proc memPush(target: string, value: string) =
  if not quietMode:
    echo "[MEM-PUSH] ", target, " <- ", value

proc tranPulse(pin: int, width: string) =
  if not quietMode:
    echo "[TRAN-PULSE] pin ", pin, " width ", width

# --------------------------
# Expression evaluator
# --------------------------
proc evaluateExpression(s: string): Value =
  let ss = s.strip()
  if ss.len >= 2 and ss[0] == '"' and ss[^1] == '"':
    return Value(kind: StrVal, ival: 0, sval: stripQuotes(ss))
  # try integer (detect parse success)
  try:
    let ii = parseInt(ss)
    return Value(kind: IntVal, ival: ii, sval: "")
  except:
    discard
  # simple binary + operations (a + b)
  if ss.contains("+"):
    var parts = ss.split("+")
    var sum = 0
    for p in parts:
      let t = p.strip()
      if symTable.contains(t):
        let v = symTable[t]
        if v.kind == IntVal: sum.inc(v.ival) else: discard
      else:
        sum.inc(parseIntSafe(t))
    return Value(kind: IntVal, ival: sum, sval: "")
  # fallback: variable lookup
  if symTable.contains(ss):
    return symTable[ss]
  # default
  return Value(kind: StrVal, ival: 0, sval: ss)

# --------------------------
# Tokenizer
# --------------------------
proc tokenize(content: string): seq[Token] =
  var res: seq[Token] = @[]
  for line in content.split('\n'):
    let tline = line.strip()
    if tline.len == 0: continue
    if tline.startsWith("print"):
      res.add(Token(sym: "print", text: tline))
    elif tline.startsWith("function"):
      # function NAME
      let name = tline.split()[1]
      res.add(Token(sym: "function", text: name))
    elif tline.contains("=") and not tline.startsWith("apu"):
      res.add(Token(sym: "assign", text: tline))
    elif tline.startsWith("apu") or tline.startsWith("tran") or tline.startsWith("bit") or tline.startsWith("mem"):
      res.add(Token(sym: "hwcmd", text: tline))
    else:
      res.add(Token(sym: "other", text: tline))
  return res

# --------------------------
# Runner BybyLang
# --------------------------
proc runBybyLang(tokens: seq[Token]) =
  var modeEnum: Mode = Low
  var i = 0
  while i < tokens.len:
    let t = tokens[i]
    try:
      case t.sym
      of "mode":
        let m = parseIntSafe(t.text)
        case m
        of 1: modeEnum = Low
        of 2: modeEnum = Mid
        of 3: modeEnum = High
        else:
          if not ignoreErrors:
            echo "[ERROR] Invalid mode: ", m
            quit(1)
        if not quietMode:
          echo "[MODE] ", modeEnum
      of "function":
        let name = t.text.strip()
        var body: seq[Token] = @[]
        i.inc
        while i < tokens.len and not (tokens[i].sym == "other" and tokens[i].text.strip() == name):
          body.add(tokens[i])
          i.inc
        funcTable[name] = body
      of "hwcmd":
        if t.text.startsWith("apu tran"):
          let parts = t.text.split("with")
          let name = stripQuotes(parts[0].split()[2].strip())
          let payload = parts[1].strip()
          apuTran(name, payload)
        elif t.text.startsWith("apu mem"):
          let parts = t.text.split("with")
          let left = parts[0].split()
          let action = left[2]
          let target = stripQuotes(left[3])
          let rawVal = parts[1].strip()
          let ev = evaluateExpression(rawVal)
          if ev.kind == StrVal:
            apuMem(action, target, ev.sval)
          else:
            apuMem(action, target, $ev.ival)
        elif t.text.startsWith("apu core"):
          apuCore(1, "run")
        elif t.text.startsWith("apu pin"):
          let words = t.text.split()
          let pin = parseIntSafe(words[2])
          let state = words[4]
          apuPin(pin, state)
        elif t.text.startsWith("bit send"):
          let bits = t.text.split()[2]
          bitSend(bits)
        elif t.text.startsWith("bit recv"):
          bitRecv()
        elif t.text.startsWith("mem map"):
          let target = stripQuotes(t.text.split()[2])
          memMap(target)
        elif t.text.startsWith("mem push"):
          let parts = t.text.split("with")
          let target = stripQuotes(parts[0].split()[2])
          let value = parts[1].strip()
          memPush(target, value)
        elif t.text.startsWith("tran pulse"):
          let words = t.text.split()
          let pin = parseIntSafe(words[3])
          let width = words[^1]
          tranPulse(pin, width)
        else:
          if not quietMode:
            echo "[HW] ", t.text
      of "print":
        let raw = t.text.replace("print", "").strip()
        let v = evaluateExpression(raw)
        if v.kind == StrVal:
          echo v.sval
        else:
          echo v.ival
      of "assign":
        var parts = t.text.split("=")
        if parts.len >= 2:
          var name = parts[0].replace("let", "").strip()
          var expr = parts[1..^1].join("=").strip()
          let v = evaluateExpression(expr)
          symTable[name] = v
      of "other":
        if funcTable.contains(t.text.strip()):
          let body = funcTable[t.text.strip()]
          runBybyLang(body)
        else:
          if not quietMode:
            echo "[UNKNOWN] ", t.text
      else:
        if not quietMode:
          echo "[UNKNOWN] ", t.text
    except:
      if not ignoreErrors:
        raise
    i.inc

# --------------------------
# Generate Nim code + compile to binary release
# --------------------------
proc generateNimCode(tokens: seq[Token], outFile: string) =
  var nimFile = outFile
  if not nimFile.endsWith(".nim"):
    nimFile &= ".nim"

  var code = newSeq[string]()
  code.add("import strutils, sequtils")
  code.add("const RAM_SIZE = " & $RAM_SIZE)
  code.add("var RAM: array[" & $RAM_SIZE & ", int]")
  code.add("var BUS: seq[string] = @[]")
  code.add("var Pins: array[32, bool]")
  code.add("")
  
  # First, collect all variables used in assignments
  var varNames = newSeq[string]()
  for t in tokens:
    if t.sym == "assign":
      let parts = t.text.split("=")
      if parts.len >= 1:
        let name = parts[0].replace("let", "").strip()
        if not varNames.contains(name):
          varNames.add(name)
  
  # Emit variable declarations at the top
  for name in varNames:
    code.add("var " & name & ": int")
  code.add("")

  code.add("proc stripQuotes(s: string): string =")
  code.add("  if s.len >= 2 and s[0] == '\"' and s[^1] == '\"': return s[1..^2]")
  code.add("  else: return s")
  code.add("")

  # pre-scan functions
  var funcBodiesLocal = initTable[string, seq[Token]]()
  var skip = initTable[int, bool]()
  var j = 0
  while j < tokens.len:
    if tokens[j].sym == "function":
      let fname = tokens[j].text.strip()
      var body: seq[Token] = @[]
      var k = j + 1
      while k < tokens.len and not (tokens[k].sym == "other" and tokens[k].text.strip() == fname):
        body.add(tokens[k])
        skip[k] = true
        k.inc
      funcBodiesLocal[fname] = body
      skip[j] = true
      if k < tokens.len: skip[k] = true
      j = k + 1
    else:
      j.inc

  # emit top-level
  for idx in 0 ..< tokens.len:
    if skip.contains(idx): continue
    let t = tokens[idx]
    if t.sym == "print":
      let raw = t.text.replace("print", "").strip()
      if raw.startsWith("\"") and raw.endsWith("\""):
        let esc = raw[1..^2].replace("\"", "\\\"")
        code.add("echo \"" & esc & "\"")
      else:
        # For expressions and variables, evaluate them
        code.add("echo " & raw)
    elif t.sym == "hwcmd":
      if t.text.startsWith("apu tran"):
        let parts = t.text.split("with")
        let name = stripQuotes(parts[0].split()[2].strip())
        let payload = parts[1].strip()
        code.add("echo \"[APU-TRAN] " & name.replace("\"","\\\"") & " -> " & payload.replace("\"","\\\"") & "\"\n")
      elif t.text.startsWith("apu mem"):
        let parts = t.text.split("with")
        let left = parts[0].split()
        let action = left[2]
        let target = stripQuotes(left[3])
        let value = parts[1].strip()
        if action == "write":
          let idx = target.replace("RAM", "")
          code.add("RAM[" & idx & "] = " & value & "\n")
          code.add("echo \"[APU-MEM] RAM[" & idx & "] <- " & value & "\"")
        else:
          code.add("echo \"[APU-MEM] " & target & " -> \" & $RAM[0]")
      elif t.text.startsWith("tran pulse"):
        let parts = t.text.split()
        let pin = parseIntSafe(parts[3])
        let width = parts[^1]
        code.add("echo \"[TRAN-PULSE] pin " & $pin & " width " & width & "\"")
    elif t.sym == "assign":
      let parts = t.text.split("=")
      if parts.len >= 2:
        let name = parts[0].replace("let", "").strip()
        let expr = parts[1..^1].join("=").strip()
        if expr.startsWith("\"") and expr.endsWith("\""):
          # String assignment (not supported in current version)
          code.add("# String assignment not yet supported: " & name)
        else:
          # For numeric expressions, emit as-is
          code.add(name & " = " & expr)
    elif t.sym == "other":
      let nm = t.text.strip()
      if funcBodiesLocal.contains(nm):
        code.add("fn_" & nm & "()\n")

  # emit functions
  for k, v in funcBodiesLocal:
    code.add("proc fn_" & k & "() =\n")
    for tk in v:
      if tk.sym == "print":
        let raw = tk.text.replace("print", "").strip()
        if raw.startsWith("\"") and raw.endsWith("\""):
          let esc = raw[1..^2].replace("\"", "\\\"")
          code.add("  echo \"" & esc & "\"\n")
        else:
          code.add("  echo (" & raw & ")\n")
      elif tk.sym == "assign":
        let parts = tk.text.split("=")
        if parts.len >= 2:
          let name = parts[0].replace("let", "").strip()
          let expr = parts[1..^1].join("=").strip()
          code.add("  " & name & " = " & expr & "\n")
      elif tk.sym == "hwcmd":
        if tk.text.startsWith("apu tran"):
          let parts = tk.text.split("with")
          let aname = stripQuotes(parts[0].split()[2].strip())
          let payload = parts[1].strip()
          code.add("  echo \"[APU-TRAN] " & aname.replace("\"","\\\"") & " -> " & payload.replace("\"","\\\"") & "\"\n")
        elif tk.text.startsWith("apu mem"):
          let parts = tk.text.split("with")
          let left = parts[0].split()
          let action = left[2]
          let target = stripQuotes(left[3])
          let value = parts[1].strip()
          if action == "write":
            let idx = target.replace("RAM", "")
            code.add("  RAM[" & idx & "] = " & value)
            code.add("  echo \"[APU-MEM] RAM[" & idx & "] <- " & value & "\"")
          else:
            code.add("  echo \"[APU-MEM] " & target & " -> \" & $RAM[0]")
      else:
        let esc = tk.text.replace("\"", "\\\"")
        code.add("  echo \"" & esc & "\"")

  # write file with newlines
  writeFile(nimFile, code.join("\n"))
  echo "[INFO] Generated Nim code to ", nimFile

  # compile
  let cmd = "nim c -d:release -o:" & outFile & " " & nimFile
  let res = execProcess(cmd)
  echo res
  echo "[INFO] Built executable: ", outFile

# --------------------------
# Main
# --------------------------
proc main() =
  var inputFile = ""
  var args = commandLineParams()
  var aotFile = ""
  initSymTable()
  for i, a in args:
    if a == "--ignore-errors":
      ignoreErrors = true
    elif a == "--quiet":
      quietMode = true
    elif a.startsWith("--aot="):
      aotFile = a.split('=')[1]
    elif i == 0 or inputFile == "":
      inputFile = a

  if inputFile == "":
    echo "Usage: ./bybylang <file.bybylang> [--ignore-errors] [--quiet] [--aot=output]"
    quit(1)

  if not fileExists(inputFile):
    echo "[ERROR] File not found: ", inputFile
    quit(1)

  let fileContent = readFile(inputFile)
  let tokens = tokenize(fileContent)

  if aotFile != "":
    generateNimCode(tokens, aotFile)
  else:
    runBybyLang(tokens)

main()
