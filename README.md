# compile_flagz

A Zig library for generating `compile_flags.txt` files to improve C/C++ IDE integration in projects that use Zig as their build system.

## Overview

`compile_flagz` enables better C/C++ development experience in projects that use Zig's build system by automatically generating `compile_flags.txt` files. This allows C/C++ language servers (like clangd) to understand your project's include paths, providing better code completion, error detection, and navigation when working on C/C++ code within Zig-built projects.

## Use Cases

- **C/C++ projects using Zig build**: Building traditional C/C++ applications or libraries with `build.zig` instead of Make/CMake
- **Mixed C/C++/Zig codebases**: Projects where you're writing both C/C++ and Zig code
- **C/C++ libraries with Zig tooling**: Leveraging Zig's excellent cross-compilation and dependency management for C/C++ development

## Installation

Add `compile_flagz` to your project:

```bash
zig fetch --save git+https://github.com/deevus/compile_flagz
```

This will automatically add the dependency to your `build.zig.zon` file.

## Usage

In your `build.zig`:

```zig
const compile_flagz = @import("compile_flagz");

pub fn build(b: *std.Build) void {
    // Your existing build configuration...
    
    // Create compile flags generator
    var cflags = compile_flagz.addCompileFlags(b);
    
    // Add include paths
    cflags.addIncludePath(b.path("include"));
    cflags.addIncludePath(dependency.builder.path("include"));
    
    // Create the build step
    const cflags_step = b.step("compile-flags", "Generate compile_flags.txt for C/C++ IDE support");
    cflags_step.dependOn(&cflags.step);
}
```

Generate the file:

```bash
zig build compile-flags
```

This creates a `compile_flags.txt` file with your include paths formatted for C/C++ language servers.

## Example

See the `example/` directory for a complete working project that demonstrates usage with SDL dependency.

## Building

Build the library:

```bash
zig build
```

## Documentation

Generate API documentation:

```bash
zig build docs
```

The generated documentation will be available in `zig-out/docs/`.

## Requirements

- Zig 0.14.1 or later

## License

MIT License - see [LICENSE](LICENSE) file for details.
