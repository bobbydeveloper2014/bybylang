import strutils, sequtils
const RAM_SIZE = 1024
var RAM: array[0..RAM_SIZE-1, int]
var BUS: seq[string] = @[]
var Pins: array[0..31, bool]

proc stripQuotes(s: string): string =
  if s.len >= 2 and s[0] == '"' and s[^1] == '"':
    return s[1..^2]
  else:
    return s

proc apuTran(name: string, payload: string) =
  BUS.add(payload)
  echo "[APU-TRAN] ", name, " -> ", payload

proc apuMem(action: string, target: string, value: string) =
  var ramAddr = parseInt(target.replace("RAM", ""))
  if action == "write":
    RAM[ramAddr] = parseInt(value)
  elif action == "read":
    echo "[APU-MEM] RAM[", ramAddr, "] -> ", RAM[ramAddr]

proc apuCore(mode: int, code: string) =
  echo "[APU-CORE] Mode:", mode, " run:", code

proc apuPin(pin: int, state: string) =
  Pins[pin] = (state == "high")

proc bitSend(bits: string) =
  BUS.add(bits)

proc bitRecv() =
  if BUS.len > 0:
    echo BUS[0]
    delete(BUS, 0)
  else:
    echo "[BIT-RECV] empty"

proc memMap(target: string) =
  echo "[MEM-MAP] ", target

proc memPush(target: string, value: string) =
  echo "[MEM-PUSH] ", target, " <- ", value

proc tranPulse(pin: int, width: string) =
  echo "[TRAN-PULSE] pin ", pin, " width ", width


proc testtest() =
  echo "test1234"
  echo "Xin chào"

proc test() =
  echo "test1234"
  echo "Xin chào"

echo "Mode 1: Low-level"
apuTran("print", "hello world")
apuMem("write", "RAM0", "5")
tranPulse(3, "2ns")
echo "Hello world"
echo "test1234"
echo "Xin chào"
test()
var otest = 100 + 100 + 8739487 - 34827 + 48384 - 5455 + 500 - 90
echo otest
echo 1 + 1 + 10383487 - 438744
echo "test1234"
echo "Xin chào"
testtest()
echo 1234567890+987654321
echo 10000000-99999
echo 314135+271828
echo 9223372037-21474848
echo 999999999-8888888
echo 1234569+987654321
echo 1000000000-1
echo 77777777+222222223
echo 5555555-333333333
echo 313-8
for i in 1..5:
  echo "hi"
var i = 2
if i == 2:
  apuTran("core", "midstep")
elif i == 3:
  apuMem("write", "RAM1", "99")
else:
  echo "other"