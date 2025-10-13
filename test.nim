import strutils, sequtils
const RAM_SIZE = 1024
var RAM: array[0..RAM_SIZE-1, int]
var BUS: seq[string] = @[]
var Pins: array[0..31, bool]

proc stripQuotes(s: string): string =
  if s.len >= 2 and s[0] == '"' and s[^1] == '"': return s[1..^2]
  else: return s


proc testtest() =
  echo "test1234"
  echo "Xin chào"

proc test() =
  echo "test1234"
  echo "Xin chào"

echo "Hello world"
echo "test1234"
echo "Xin chào"
test()
var otest = 100 + 100 + 8739487 - 34827 + 48384 - 5455
echo otest
echo 1 + 1 + 10383487 - 438744
echo "test1234"
echo "Xin chào"
testtest()