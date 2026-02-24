test file:
    zig test src/{{file}}.zig

test-mod:
    zig build test    

run-examples: run-simple-example run-main-example

run-simple-example:
    zig build simple-example -- build
    zig build simple-example -- build ./src/main.ext
    zig build simple-example -- run ./src/main.ext
    zig build simple-example -- --help
    zig build simple-example -- -h

run-main-example:
    zig build main-example -- build
    zig build main-example -- build exe
    zig build main-example -- run ./src/main.zig
    zig build main-example -- test ./src/main.zig
    zig build main-example -- test --filter=documentation ./src/main.zig
    zig build main-example -- test -f=argument ./src/main.zig
    zig build main-example -- --help
    zig build main-example -- -h
    zig build main-example -- --version
    zig build main-example -- -v
    
