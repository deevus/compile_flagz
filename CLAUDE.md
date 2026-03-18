# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

compile_flagz is a Zig library that generates `compile_flags.txt` files for C/C++ language server integration (clangd) in projects using Zig as their build system. It works as a custom Zig build step.

## Build Commands

```bash
zig build              # Build the library
zig build docs         # Generate API docs to zig-out/docs/
```

There are no tests in this project currently. The `example/` directory contains a separate project demonstrating usage with an SDL dependency.

## Tooling

- **Zig 0.15.2**, **ZLS 0.15.0** — managed via `mise.toml`
- No CI/CD configured
- No external dependencies

## Architecture

This is a small, single-file library:

- **`src/CompileFlags.zig`** — The entire library implementation. A struct that implements a custom Zig `Build.Step`. Collects `LazyPath` include paths and writes them as `-I<path>` lines to `compile_flags.txt` in the build root.
- **`build.zig`** — Exposes `addCompileFlags(b)` as the public API entry point for consumers. Also sets up the library artifact and docs generation.

The consumer API is: `addCompileFlags(b)` returns a `*CompileFlags`, call `.addIncludePath()` on it, then hook `cflags.step` into a build step.

## Zig Style Conventions (from .rules)

- **Imports go at the bottom of the file**, not the top
- **Naming:** Types are `TitleCase`; callables returning types are `TitleCase`; other callables are `camelCase`; variables/fields/constants are `snake_case`
- **Doc comments** on all public methods (don't repeat the signature). No doc comments on private methods unless complex
- **No section comments** (e.g., `// Imports`, `// Types`)
- Minimal inline comments — only for complex/non-obvious logic
- Composition over inheritance; explicit memory management with allocators; error unions over panics for recoverable errors
