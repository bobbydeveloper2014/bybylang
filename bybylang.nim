# bybylang.nim - BybyLang AOT executable + Nim code generation + auto compile release

import strutils, os, osproc

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

# --------------------------
# RAM / Bus / Pins giả lập
# --------------------------
const RAM_SIZE = 1024
var RAM: array[RAM_SIZE, int]
var BUS: seq[string] = @[]
var Pins: array[32, bool]

var ignoreErrors = false
var quietMode = false

# --------------------------
# Lexer đơn giản
# --------------------------
proc tokenize(fileContent: string): seq[Token] =
  var tokens: seq[Token] = @[]
  for line in fileContent.splitLines():
    let t = line.strip()
    if t.len == 0: continue
    if t.startsWith("mode is"):
      tokens.add(Token(sym: "mode", text: t.split()[2]))
    elif t.startsWith("function"):
      tokens.add(Token(sym: "function", text: t.split()[1]))
    elif t.startsWith("component"):
      tokens.add(Token(sym: "component", text: t.split()[1]))
    elif t.startsWith("apu") or t.startsWith("bit") or t.startsWith("mem") or t.startsWith("tran"):
      tokens.add(Token(sym: "hwcmd", text: t))
    elif t.startsWith("print"):
      tokens.add(Token(sym: "print", text: t))
    else:
      tokens.add(Token(sym: "other", text: t))
  return tokens

# --------------------------
# Hardware-level functions
# --------------------------
proc apuTran(name: string, payload: string) =
  BUS.add(payload)
  if not quietMode:
    echo "[APU-TRAN] ", name, " -> ", payload

proc apuMem(action: string, target: string, value: string) =
  let ramAddr = parseInt(target.replace("RAM",""))
  if ramAddr < 0 or ramAddr >= RAM_SIZE:
    if not ignoreErrors:
      echo "[ERROR] Invalid RAM address: ", ramAddr
      quit(1)
    return
  if action == "write":
    RAM[ramAddr] = parseInt(value)
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
# Runner BybyLang
# --------------------------
proc runBybyLang(tokens: seq[Token]) =
  var modeEnum: Mode = Low
  for t in tokens:
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
        if not quietMode:
          echo "[FUNCTION] define: ", t.text
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
        echo msg
      of "component":
        if not quietMode:
          echo "[COMPONENT] ", t.text
      else:
        if not quietMode:
          echo "[UNKNOWN] ", t.text
    except:
      if not ignoreErrors:
        raise

# --------------------------
# Generate Nim code + compile to binary release
# --------------------------
proc generateNimCode(tokens: seq[Token], outFile: string) =
  # ensure .nim extension
  var nimFile = outFile
  if not nimFile.endsWith(".nim"):
    nimFile &= ".nim"

  var code = """
import strutils, sequtils
const RAM_SIZE = 1024
var RAM: array[0..RAM_SIZE-1, int]
var BUS: seq[string] = @[]
var Pins: array[0..31, bool]

proc stripQuotes(s: string): string =
  if s.len >= 2 and s[0] == '\"' and s[^1] == '\"': return s[1..^2]
  else: return s
"""

  for t in tokens:
    case t.sym
    of "print":
      let escMsg = t.text.replace("print","").strip().replace("\"", "\\\"")
      code &= "echo \"" & escMsg & "\"\n"
    of "hwcmd":
      if t.text.startsWith("apu tran"):
        let parts = t.text.split("with")
        let name = stripQuotes(parts[0].split()[2].strip())
        let payload = parts[1].strip()
        code &= "echo \"[APU-TRAN] " & name.replace("\"","\\\"") & " -> " & payload.replace("\"","\\\"") & "\"\n"
      elif t.text.startsWith("apu mem"):
        let parts = t.text.split("with")
        let left = parts[0].split()
        let action = left[2]
        let target = stripQuotes(left[3])
        let value = parts[1].strip()
        let idx = target.replace("RAM","")
        if action == "write":
          code &= "RAM[" & idx & "] = " & value & "\n"
          code &= "echo \"[APU-MEM] RAM[" & idx & "] <- " & value & "\"\n"
        else:
          code &= "echo \"[APU-MEM] RAM[" & idx & "] -> \" & $RAM[" & idx & "]\n"
      elif t.text.startsWith("tran pulse"):
        let words = t.text.split()
        let pin = parseIntSafe(words[3])
        let width = words[^1]
        code &= "echo \"[TRAN-PULSE] pin " & $pin & " width " & width & "\"\n"

  # write Nim code
  writeFile(nimFile, code)
  echo "[INFO] Generated Nim code to ", nimFile

  # compile Nim binary release
  let cmd = "nim c -d:release -o:" & outFile & " " & nimFile
  let res = execProcess(cmd)
  echo res
  echo "[INFO] Built executable: ", outFile

  # optional: remove nimFile if you want
  # removeFile(nimFile)

# --------------------------
# Main
# --------------------------
proc main() =
  var inputFile = ""
  var args = commandLineParams()
  var aotFile = ""
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
