import strutils, sequtils
const RAM_SIZE = 1024
var RAM: array[1024, int]
var BUS: seq[string] = @[]
var Pins: array[32, bool]

var otest: int

proc stripQuotes(s: string): string =
  if s.len >= 2 and s[0] == '"' and s[^1] == '"': return s[1..^2]
  else: return s

echo "[APU-TRAN] print -> \"hello world\""

RAM[0] = 5

echo "[APU-MEM] RAM[0] <- 5"
echo "[TRAN-PULSE] pin 3 width 2ns"
echo "Hello world"
otest = 100 + 100 + 8739487 - 348237
echo otest
echo 1 + 1
proc fn_test() =

  echo "test1234"

  echo "Xin chào"
