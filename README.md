# BybyLang

BybyLang là một ngôn ngữ lập trình do Byby phát triển, cho phép điều khiển 
phần cứng ảo (APU, BUS, RAM, Pins) hoặc sinh ra mã Nim thực thi trực tiếp. 
BybyLang hỗ trợ chế độ **AOT compilation**, cho phép bạn biên dịch code 
BybyLang ra file thực thi (<em>executable</em>) nhanh chóng.

## Tính năng chính

- Hỗ trợ 3 chế độ:
  - **Low**: thao tác trực tiếp phần cứng ảo
  - **Mid**: tương tác code trung gian
  - **High**: code kiểu Python/Objective-C
- Mô phỏng RAM, BUS, Pins
- Lệnh hardware-level: `apu tran`, `apu mem`, `bit send`, `mem push`, 
`tran pulse`
- Biên dịch ra Nim và build thành executable tự động

## Cài đặt

1. Cài Nim (phiên bản khuyến nghị: 2.2.x):
   ```bash
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

2. Clone repository BybyLang:
   ```
git clone https://github.com/username/bybylang.git
cd bybylang
```

3. Chạy trực tiếp hoặc build AOT:
   ```bash
nim c -r bybylang.nim
```

## Cách sử dụng

1. Chạy trực tiếp file BybyLang:
   ```
./bybylang main.bybylang
```

2. Biên dịch ra Nim code và executable:
   ```
./bybylang main.bybylang --aot=output
```
   `[--aot=output]` sẽ tạo:
     - `output.nim` (mã Nim sinh ra từ BybyLang)
     - `output` (executable Nim được build tự động với `-d:release`)

3. Tuỳ chọn thêm:
   - `--ignore-errors`: bỏ qua lỗi RAM/Pins
   - `--quiet`: không in log chi tiết

## Cú pháp cơ bản

### Mode

- `mode is 1` # 1: Low, 2: Mid, 3: High

### Function

- `function sayHello`
    ```
print "Hello, Byby!"
```

- Gọi hàm:
  ```bash
sayHello
```

### Hardware commands

- Ghi RAM:
  ```bash
apu mem write RAM0 with 5
```
- Đọc RAM:
  ```
apu mem read RAM0 with 0
```
- Truyền dữ liệu qua APU:
  ```
apu tran print with "hello world"
```
- Điều khiển pin:
  ```
tran pulse pin 3 width 2ns
apu pin 5 set high
```
- Bus operations:
  ```
bit send 101010
bit recv
mem map "RAM0"
mem push "RAM1" with 10
```

### Print

- `print "Hello World"`

## Gợi ý viết code

- Luôn khai báo `mode is <level>` ở đầu file
- Sử dụng `function` để định nghĩa hàm
- Lệnh phần cứng (`apu`, `bit`, `mem`, `tran`) chỉ chạy khi chế độ Low
- File BybyLang nên có đuôi `.bybylang` để dễ nhận diện

## Build Nim executable thủ công (tùy chọn)

```bash
nim c -d:release output.nim
./output
```

## Ví dụ file BybyLang (`main.bybylang`)

```bash
mode is 1
function sayHello
    print "Hello World"

apu mem write RAM0 with 5
apu tran print with "hello world"
tran pulse pin 3 width 2ns
sayHello
```

Sử dụng BybyLang giúp bạn khám phá và điều khiển phần cứng ảo một cách 
trực quan. Hãy thử nghiệm và khám phá sức mạnh của BybyLang!
