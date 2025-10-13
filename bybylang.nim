# bybylang.nim - BybyLang AOT executable + Nim code generation + auto compile release
# Hỗ trợ cơ chế function: define function bằng "function NAME" ... kết thúc bằng một dòng chỉ chứa NAME
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
# Types
# --------------------------
type
  Mode = enum
    Low, Mid, High

  Token = object
    sym: string
    text: string
    indent: int
# --------------------------
# RAM / Bus / Pins giả lập
# --------------------------
const RAM_SIZE = 1024
var RAM: array[0..RAM_SIZE-1, int]
var BUS: seq[string] = @[]
var Pins: array[0..31, bool]

var ignoreErrors = false
var quietMode = false

# function table lưu body token
var funcTable = initTable[string, seq[Token]]()

# --------------------------
# Lexer đơn giản
# --------------------------


proc tokenizeLine(line: string): Token =
  var tok: Token
  # Đếm số khoảng trắng đầu dòng để xác định cấp indent
  tok.indent = line.len - line.strip(chars={' ', '\t'}).len

  # Loại bỏ khoảng trắng đầu cuối để xử lý cú pháp
  let clean = line.strip()

  if clean.len == 0:
    tok.sym = "empty"
    tok.text = ""
  elif clean.startsWith("function "):
    tok.sym = "function"
    tok.text = clean.replace("function ", "")
  elif clean.startsWith("print "):
    tok.sym = "print"
    tok.text = clean
  else:
    tok.sym = "other"
    tok.text = clean

  return tok

# Đọc file .bybylang và chuyển thành danh sách tokens
proc tokenizeFile(filename: string): seq[Token] =
  var tokens: seq[Token] = @[]
  for line in lines(filename):
    let t = tokenizeLine(line)
    tokens.add(t)
  return tokens
# --------------------------
# Hardware-level functions
# --------------------------
proc apuTran(name: string, payload: string) =
  BUS.add(payload)
  if not quietMode:
    echo "[APU-TRAN] ", name, " -> ", payload

proc apuMem(action: string, target: string, value: string) =
  let ramAddr = parseIntSafe(target.replace("RAM",""))
  if ramAddr < 0 or ramAddr >= RAM_SIZE:
    if not ignoreErrors:
      echo "[ERROR] Invalid RAM address: ", ramAddr
      quit(1)
    return
  if action == "write":
    RAM[ramAddr] = parseIntSafe(value)
    if not quietMode:
      echo "[APU-MEM] RAM[", ramAddr, "] <- ", value
  elif action == "read":
    if not quietMode:
      echo "[APU-MEM] RAM[", ramAddr, "] -> ", RAM[ramAddr]

proc apuCore(mode: int, code: string) =
  if not quietMode:
    echo "[APU-CORE] Mode: ", mode, ", running: ", code

proc apuPin(pin: int, state: string) =
  if pin < 0 or pin > 31:
    if not ignoreErrors:
      echo "[ERROR] Invalid pin: ", pin
      quit(1)
    return
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
# Runner BybyLang with function mechanism
# --------------------------
proc runBybyLang(tokens: seq[Token]) =
  # first pass: extract function bodies
  funcTable = initTable[string, seq[Token]]()
  var i = 0
  while i < tokens.len:
    let t = tokens[i]
    if t.sym == "function":
      let fname = t.text.strip()
      var body: seq[Token] = @[]
      i.inc
      while i < tokens.len and not (tokens[i].sym == "other" and tokens[i].text.strip() == fname):
        body.add(tokens[i])
        i.inc
      # if termination line exists, skip it too
      funcTable[fname] = body
      # continue from next (i currently at terminator or past end)
    else:
      i.inc

  # second pass: execute top-level (skip function bodies and terminators)
  var modeEnum: Mode = Low
  i = 0
  while i < tokens.len:
    let t = tokens[i]
    # skip tokens that are inside function bodies or function header or terminator
    if t.sym == "function":
      # skip header and skip to matching terminator
      let fname = t.text.strip()
      i.inc
      while i < tokens.len and not (tokens[i].sym == "other" and tokens[i].text.strip() == fname):
        i.inc
      # skip terminator if present
      i.inc
      continue
    # skip a standalone terminator (already processed)
    if t.sym == "other" and funcTable.contains(t.text.strip()):
      # this is terminator line, skip
      i.inc
      continue

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
          let value = parts[1].strip()
          apuMem(action, target, value)
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
        let msg = t.text.replace("print", "").strip()
        # allow simple variable echo or literal
        if msg.len >= 2 and msg[0] == '"' and msg[^1] == '"':
          echo msg[1..^2]
        else:
          echo msg
      of "component":
        if not quietMode:
          echo "[COMPONENT] ", t.text
      of "other":
        # if token matches a function call (name) then run its body
        let nm = t.text.strip()
        if funcTable.contains(nm):
          if not quietMode:
            echo "[CALL] function ", nm
          # execute function body tokens (simple recursion)
          runBybyLang(funcTable[nm])
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
  var funcBodiesLocal = initTable[string, seq[Token]]()
  var idx = 0

  # --- tách thân hàm bằng indent ---
  while idx < tokens.len:
    let t = tokens[idx]
    if t.sym == "function":
      let fname = t.text.strip()
      let baseIndent = t.indent
      var body: seq[Token] = @[]
      idx.inc
      while idx < tokens.len and tokens[idx].indent > baseIndent:
        body.add(tokens[idx])
        idx.inc
      funcBodiesLocal[fname] = body
    else:
      idx.inc

  # --- khởi tạo file ---
  var nimFile = outFile
  if not nimFile.endsWith(".nim"): nimFile &= ".nim"

  var code = newSeq[string]()
  code.add("import strutils, sequtils")
  code.add("const RAM_SIZE = 1024")
  code.add("var RAM: array[0..RAM_SIZE-1, int]")
  code.add("var BUS: seq[string] = @[]")
  code.add("var Pins: array[0..31, bool]")
  code.add("")
  code.add("proc stripQuotes(s: string): string =")
  code.add("  if s.len >= 2 and s[0] == '\"' and s[^1] == '\"': return s[1..^2]")
  code.add("  else: return s")
  code.add("")

  # --- thu thập tên hàm ---
  var funcNames: seq[string] = @[]
  for k, _ in funcBodiesLocal:
    funcNames.add(k)
  var varNames: seq[string] = @[]

  # --- 1. Sinh tất cả proc trước ---
  for k, v in funcBodiesLocal:
    code.add("")
    code.add("proc " & k & "() =")
    var localVars: seq[string] = @[]
    for tk in v:
      if tk.sym == "print":
        var raw = tk.text.replace("print", "").strip()
        code.add("  echo " & raw)
      elif tk.sym == "other":
        let line = tk.text.strip()
        if line.startsWith("call "):
          let fname = line.split()[1]
          if fname in funcNames:
            code.add("  " & fname & "()")
          else:
            code.add("  {.compileTimeError: \"Function " & fname & " not found\".}")
        elif line in funcNames:
          code.add("  " & line & "()")
        elif line.contains("="):
          let parts = line.split("=")
          if parts.len >= 2:
            let left = parts[0].strip()
            let right = parts[1..^1].join("=").strip()
            if left notin localVars:
              localVars.add(left)
              code.add("  var " & left & " = " & right)
            else:
              code.add("  " & left & " = " & right)
        else:
          discard
      else:
        discard

  # --- 2. Sinh top-level code ---
  code.add("")
  idx = 0
  while idx < tokens.len:
    let t = tokens[idx]
    if t.sym == "print":
      var raw = t.text.replace("print", "").strip()
      code.add("echo " & raw)
    elif t.sym == "other":
      let line = t.text.strip()
      if line.startsWith("call "):
        let fname = line.split()[1]
        if fname in funcNames:
          code.add(fname & "()")  # gọi trực tiếp, không echo
        else:
          code.add("{.compileTimeError: \"Function " & fname & " not found\".}")
      elif line.contains("="):
        let parts = line.split("=")
        if parts.len >= 2:
          let left = parts[0].strip()
          let right = parts[1..^1].join("=").strip()
          code.add("var " & left & " = " & right)
      else:
        discard
    idx.inc

  writeFile(nimFile, code.join("\n"))
  echo "[INFO] Generated Nim code to ", nimFile
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
  discard initTable[string, seq[Token]]()
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

  # --- Sửa tại đây ---
  let tokens = tokenizeFile(inputFile)

  if aotFile != "":
    generateNimCode(tokens, aotFile)
  else:
    runBybyLang(tokens)

main()
