# BybyLang

**BybyLang** is a programming language developed by Byby, allowing you to control virtual hardware (APU, BUS, RAM, Pins) or generate Nim code for direct execution. BybyLang supports **AOT compilation** for fast executable generation.

_BybyLang là một ngôn ngữ lập trình do Byby phát triển, cho phép điều khiển phần cứng ảo hoặc sinh ra mã Nim thực thi trực tiếp. BybyLang hỗ trợ chế độ biên dịch AOT, giúp bạn sinh file thực thi nhanh chóng.

You can find bybylangjit in https://github.com/bobbydeveloper2014/bybylangjit | 
Bạn có thể tìm bybylangjit ở https://github.com/bobbydeveloper2014/bybylangjit

## Main Features / Tính năng chính

- Supports 3 modes:
  - **Low**: Direct virtual hardware interaction
  - **Mid**: Intermediate code interaction
  - **High**: Python/Objective-C style coding

  _Hỗ trợ 3 chế độ: Low, Mid, High. Low thao tác phần cứng ảo, High giống Python._
- Simulates RAM, BUS, Pins
- Hardware-level commands: `apu tran`, `apu mem`, `bit send`, `mem push`, `tran pulse`
- Compile to Nim and auto-build executable

## Installation / Cài đặt

1. **Install Nim (recommended version: 2.2.x):**
    ```bash
    curl https://nim-lang.org/choosenim/init.sh -sSf | sh
    ```

2. **Clone BybyLang repository:**
    ```bash
    git clone https://github.com/bobbydeveloper2014/bybylang.git
    cd bybylang
    ```

3. **Run directly or build AOT:**
    ```bash
    nim c -r bybylang.nim
    ```

## Usage / Cách sử dụng

1. **Compile to Nim code and executable:**
    ```bash
    ./bybylang main.bybylang --aot=output
    ```
    `[--aot=output]` will generate:
     - `output.nim` (Nim code generated from BybyLang)
     - `output` (Nim executable built with `-d:release`)

2. **Additional options / Tuỳ chọn thêm:**
   - `--ignore-errors`: skip RAM/Pins errors
   - `--quiet`: no verbose log

## Basic Syntax / Cú pháp cơ bản

### Mode

- `mode is 1` # 1: Low, 2: Mid, 3: High
### Loop
```bybylang
while true:
  print "hello"
```
### Repeat time
```bybylang
for i in range(1, 5):
    print "hi"
```
### Function

```bybylang
function sayHello
  print "Hello, Byby!"
```
- Call function:
```bybylang
call sayHello
```
### If-elif-else
```bybylang
i = 2
if i == 2:
    apu tran "core" with "midstep"
elif i == 3:
    apu mem write "RAM1" with "99"
else:
    print "other"
```
### Hardware commands

- Write RAM:
```bash
apu mem write RAM0 with 5
```
- Read RAM:
```
apu mem read RAM0 with 0
```
- APU data transfer:
```bybylang
apu tran print with "hello world"
```
- Pin control:
```bybylang
tran pulse pin 3 width 2ns
apu pin 5 set high
```
- Bus operations:
```bybylang
bit send 101010
bit recv
mem map "RAM0"
mem push "RAM1" with 10
```
### Can embed nim code in bybylang code
echo "hello world"
### Print

- `print "Hello World"`

## Coding Tips / Gợi ý viết code

- Always declare `mode is <level>` at the top of the file
- Use `function` to define functions
- Hardware commands (`apu`, `bit`, `mem`, `tran`) only run in Low mode
- BybyLang files should use `.bybylang` extension

## Example BybyLang file (`main.bybylang`)

```bybylang
mode is 1
function sayHello
    print "Hello World"

apu mem write RAM0 with 5
apu tran print with "hello world"
tran pulse pin 3 width 2ns
call sayHello
```

_BybyLang giúp bạn khám phá và điều khiển phần cứng ảo trực quan. Hãy thử nghiệm và khám phá sức mạnh của BybyLang!_

---

**Pull requests are very welcome! Thank you for visiting the project!**
