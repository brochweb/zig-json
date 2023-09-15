# zig-json

`zig-json` is a zig program with an optimized JSON parsing implementation. It only parses to a `JsonValue` enum, not to a Zig struct, but it ends up being around twice as fast as `std.json.Parser` on some benchmarks.


This is a research project, it is not tested for production, but only provided as an example zig program to optimize. Suggestions for improving reliability, speed or memory usage are welcome.

For more information, read [my blog post](https://www.brochweb.com/blog/post/optimizing-a-json-parser-in-zig/).

## Benchmarks

Each command was run several times, with the best time taken. The zsh `time` utility with a `$TIMEFMT` that shows memory was used for benchmarking.

|           file           | json implementation | max memory (KB) | time (secs) |
| :----------------------: | :-----------------: | :-------------: | :---------: |
| tests/ascii_strings.json |      zig-json       |     100096      |    0.033    |
| tests/ascii_strings.json |      std.json       |      87232      |    0.152    |
|    tests/numbers.json    |      zig-json       |      94064      |    0.058    |
|    tests/numbers.json    |      std.json       |     220432      |    0.091    |
|    tests/random.json     |      zig-json       |     206512      |    0.154    |
|    tests/random.json     |      std.json       |     380240      |    0.300    |
|     tests/food.json      |      zig-json       |      1424       |    0.003    |
|     tests/food.json      |      std.json       |      1536       |    0.003    |
|    tests/geojson.json    |      zig-json       |      51104      |    0.031    |
|    tests/geojson.json    |      std.json       |      78944      |    0.038    |


A [Broch Web Solutions](https://www.brochweb.com/) project
