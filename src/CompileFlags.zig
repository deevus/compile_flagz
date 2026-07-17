//! CompileFlags provides a build step for generating compile_flags.txt files.
//! This is useful for C/C++ development in projects that use Zig as their build system,
//! enabling C/C++ language servers (like clangd) to understand include paths and
//! providing better IDE integration and code completion for C/C++ code in Zig-built projects.
const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const Step = Build.Step;
const TopLevelStep = Build.TopLevelStep;
const Io = std.Io;

const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayListUnmanaged;
const Dir = std.Io.Dir;
const File = std.Io.File;

const CompileFlags = @This();

pub const base_id: Step.Id = .custom;

pub const Compilers = enum {
    zigcc,
    zigcxx,
    clang,
    clangxx,
    gcc,
    gxx,
};

b: *Build,
step: Step,
selected_compiler: Compilers,

include_paths: ArrayList(LazyPath) = .empty,

/// Initialize a new CompileFlags build step.
pub fn init(b: *Build) *CompileFlags {
    const self = b.allocator.create(CompileFlags) catch @panic("OOM");
    self.* = .{
        .b = b,
        .selected_compiler = Compilers.zigcxx,
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
///
/// Example:
///
/// cflags.addIncludePath(b.path("include"))
/// cflags.addIncludePath(DEP_GTEST.path("include"))
pub fn addIncludePath(self: *CompileFlags, path: LazyPath) void {
    path.addStepDependencies(&self.step);
    self.include_paths.append(self.b.allocator, path) catch unreachable;
}

/// Add include paths obtained from compiler pre-processor paths
///
/// Example:
///
/// cflags.addSelectedCompilerIncludePaths(.zig)
pub fn addCompilerIncludePaths(self: *CompileFlags, compiler: Compilers) void {
    self.selected_compiler = compiler;
}

const RunError = error{
    ReadFailure,
    ExitCodeFailure,
    ProcessTerminated,
    ExecNotSupported,
} || std.process.SpawnError;

// NOTE: It's a pain in the ass to get stderr using std.Build.runAllowFail
// so this is a fork primarily using stderr
fn runAllowFail(
    b: *Build,
    argv: []const []const u8,
    out_code: *u8,
    stderr_behavior: std.process.SpawnOptions.StdIo,
) RunError![]u8 {
    std.debug.assert(argv.len != 0);

    if (!std.process.can_spawn)
        return error.ExecNotSupported;

    const graph = b.graph;
    const io = graph.io;

    const max_output_size = 400 * 1024;
    try Step.handleVerbose2(b, .inherit, &graph.environ_map, argv);

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .environ_map = &graph.environ_map,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = stderr_behavior,
    });

    // swap out stdout -> stderr
    var stderr_reader = child.stderr.?.readerStreaming(io, &.{});
    const stderr = stderr_reader.interface.allocRemaining(b.allocator, .limited(max_output_size)) catch {
        return error.ReadFailure;
    };
    errdefer b.allocator.free(stderr);

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| {
            if (code != 0) {
                out_code.* = @as(u8, @truncate(code));
                return error.ExitCodeFailure;
            }
            return stderr;
        },
        .signal, .stopped => |sig| {
            out_code.* = @as(u8, @truncate(@intFromEnum(sig)));
            return error.ProcessTerminated;
        },
        .unknown => |code| {
            out_code.* = @as(u8, @truncate(code));
            return error.ProcessTerminated;
        },
    }
}

fn getCompilerIncludePaths(self: *CompileFlags) !void {
    const b = self.b;
    const selected_compiler = self.selected_compiler;

    const program_args = &[_][]const u8{
        "-E",
        "-x",
        "c++",
        "-",
        "-v",
    };

    // NOTE: strategy pattern, form compiler args
    const program = switch (selected_compiler) {
        .zigcxx => comptime &[_][]const u8{ "zig", "c++" } ++ program_args,
        .zigcc => comptime &[_][]const u8{ "zig", "cc" } ++ program_args,
        .clang => comptime &[_][]const u8{"clang"} ++ program_args,
        .clangxx => comptime &[_][]const u8{"clang++"} ++ program_args,
        .gcc => comptime &[_][]const u8{"gcc"} ++ program_args,
        .gxx => comptime &[_][]const u8{"g++"} ++ program_args,
    };

    var code: u8 = undefined;
    const process = try runAllowFail(
        b,
        program,
        &code,
        .pipe,
    );

    std.debug.print("{s}", .{process});

    var process_result = std.mem.splitScalar(
        u8,
        process,
        '\n',
    );

    var start_capture = false;

    while (process_result.next()) |line| {
        if (std.mem.startsWith(u8, line, "#include <...> search starts here:")) {
            start_capture = true;
            continue;
        }

        if (std.mem.startsWith(u8, line, "End of search list.")) {
            break;
        }

        if (start_capture) {
            self.addIncludePath(.{ .cwd_relative = std.mem.trim(u8, line, " ") });
        }
    }
}

fn makeFn(step: *Step, _: Step.MakeOptions) anyerror!void {
    const self: *CompileFlags = @fieldParentPtr("step", step);
    const b = self.b;
    const allocator = b.allocator;

    var init_io = Io.Threaded.init_single_threaded;
    defer init_io.deinit();
    const io = init_io.io();

    try getCompilerIncludePaths(self);

    var out_dir = try std.Io.Dir.openDirAbsolute(
        io,
        b.build_root.path.?,
        .{},
    );
    defer out_dir.close(io);

    var buffer: [1024]u8 = undefined;

    var out_file = try out_dir.createFile(io, "compile_flags.txt", .{});
    defer out_file.close(io);
    var writer = out_file.writer(io, &buffer);
    var w = &writer.interface;

    for (self.include_paths.items) |lazy_path| {
        const path = lazy_path.getPath3(b, step);
        try w.print("-I{s}\n", .{try path.toString(allocator)});
    }
    try w.flush();
}



