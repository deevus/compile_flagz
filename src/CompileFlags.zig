//! CompileFlags provides a build step for generating compile_flags.txt files.
//! This is useful for C/C++ development in projects that use Zig as their build system,
//! enabling C/C++ language servers (like clangd) to understand include paths and
//! providing better IDE integration and code completion for C/C++ code in Zig-built projects.

const CompileFlags = @This();

pub const base_id: Step.Id = .custom;

b: *Build,
step: Step,

include_paths: ArrayList(LazyPath) = .empty,

/// Initialize a new CompileFlags build step.
pub fn init(b: *Build) *CompileFlags {
    const self = b.allocator.create(CompileFlags) catch @panic("OOM");
    self.* = .{
        .b = b,
        .step = .init(.{
            .id = base_id,
            .name = "generate-compile-flags",
            .makeFn = &makeFn,
            .owner = b,
        }),
    };

    return self;
}

/// Add an include path that will be written to the compile_flags.txt file.
pub fn addIncludePath(self: *CompileFlags, path: LazyPath) void {
    path.addStepDependencies(&self.step);
    self.include_paths.append(self.b.allocator, path) catch unreachable;
}

fn makeFn(step: *Step, _: Step.MakeOptions) anyerror!void {
    const self: *CompileFlags = @fieldParentPtr("step", step);
    const b = self.b;
    const allocator = b.allocator;

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
