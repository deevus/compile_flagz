//! CompileFlags provides a build step for generating compile_flags.txt files.
//! This is useful for C/C++ development in projects that use Zig as their build system,
//! enabling C/C++ language servers (like clangd) to understand include paths and
//! providing better IDE integration and code completion for C/C++ code in Zig-built projects.

const CompileFlags = @This();

arena: ArenaAllocator,
b: *Build,
step: Step,

include_paths: ArrayList(LazyPath) = .empty,

/// Initialize a new CompileFlags build step.
pub fn init(b: *Build) CompileFlags {
    const step = Step.init(.{
        .name = "compile-flags",
        .owner = b,
        .makeFn = makeFn,
        .id = .custom,
    });

    return .{
        .arena = ArenaAllocator.init(b.allocator),
        .b = b,
        .step = step,
    };
}

/// Add an include path that will be written to the compile_flags.txt file.
pub fn addIncludePath(self: *CompileFlags, path: LazyPath) void {
    self.include_paths.append(self.arena.allocator(), path) catch unreachable;
}

/// This is not necessary but it's there if you want to clean up after yourself
pub fn deinit(self: *CompileFlags) void {
    self.arena.deinit();
}

fn makeFn(step: *Step, _: Step.MakeOptions) anyerror!void {
    const self: *CompileFlags = @fieldParentPtr("step", step);
    const b = self.b;
    const allocator = self.arena.allocator();

    var out_dir = try std.fs.openDirAbsolute(b.build_root.path.?, .{});
    defer out_dir.close();

    var out_file = try out_dir.createFile("compile_flags.txt", .{});
    defer out_file.close();
    var writer = out_file.writer().any();

    for (self.include_paths.items) |lazy_path| {
        const path = lazy_path.getPath3(b, step);
        try writer.print("-I{s}\n", .{try path.toString(allocator)});
    }
}

const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayListUnmanaged;
const Dir = std.fs.Dir;
const File = std.fs.File;

const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const Step = Build.Step;
const TopLevelStep = Build.TopLevelStep;
