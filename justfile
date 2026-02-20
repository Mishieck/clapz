test-mod:
    zig build test    

run-examples: run-simple-example run-main-example

run-simple-example:
    zig build run-simple-example -- build
    zig build run-simple-example -- build ./src/main.ext
    zig build run-simple-example -- run ./src/main.ext
    zig build run-simple-example -- --help
    zig build run-simple-example -- -h

run-main-example:
    zig build run-main-example -- build
    zig build run-main-example -- build exe
    zig build run-main-example -- run ./src/main.zig
    zig build run-main-example -- test ./src/main.zig
    zig build run-main-example -- --version
    zig build run-main-example -- -v
    zig build run-main-example -- --help
    zig build run-main-example -- -h
    
