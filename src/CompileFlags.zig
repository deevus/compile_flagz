//! CompileFlags provides a build step for generating compile_flags.txt files.
//! This is useful for C/C++ development in projects that use Zig as their build system,
//! enabling C/C++ language servers (like clangd) to understand include paths and
//! providing better IDE integration and code completion for C/C++ code in Zig-built projects.

const CompileFlags = @This();

pub const base_id: Step.Id = .custom;

pub const Compiler = enum {
    zigcc,
    zigcxx,
    clang,
    clangxx,
    gcc,
    gxx,

    fn getProgramArgs(self: Compiler) []const []const u8 {
        return switch (self) {
            .zigcxx => comptime &[_][]const u8{
                "zig",
                "c++",

                "-E",
                "-x",
                "c++",
                "-",
                "-v",
            },
            .zigcc => comptime &[_][]const u8{
                "zig",
                "cc",

                "-E",
                "-x",
                "c",
                "-",
                "-v",
            },
            .clang => comptime &[_][]const u8{
                "clang",

                "-E",
                "-x",
                "c",
                "-",
                "-v",
            },
            .clangxx => comptime &[_][]const u8{
                "clang++",

                "-E",
                "-x",
                "c++",
                "-",
                "-v",
            },
            .gcc => comptime &[_][]const u8{
                "gcc",

                "-E",
                "-x",
                "c",
                "-",
                "-v",
            },
            .gxx => comptime &[_][]const u8{
                "g++",

                "-E",
                "-x",
                "c++",
                "-",
                "-v",
            },
        };
    }
};

pub const LanguageVariant = enum {
    cxx11,
    cxx14,
    cxx17,
    cxx20,
    cxx23,
};

b: *Build,
step: Step,
selected_compiler: Compiler,
language_variant: []const u8,
warnings: []const []const u8,
custom: ?[]const []const u8,
is_verbose_output_enabled: bool,

include_paths: ArrayList(LazyPath) = .empty,

pub const Config = struct {
    enable_verbose_output: ?bool = false,
    language_variant: LanguageVariant = .cxx23,
    warnings: struct {
        all: bool = false,
        errors: bool = false,
        extra: bool = false,
    },
    compiler: Compiler = .zigcxx,
    paths: []const LazyPath = &.{},
    custom: ?[]const []const u8 = &.{},
};

/// Add an include path that will be written to the compile_flags.txt file.
///
/// Example:
///
/// cflags.addIncludePath(b.path("include"))
/// cflags.addIncludePath(DEP_GTEST.path("include"))
pub fn addIncludePath(self: *CompileFlags, path: LazyPath) void {
    path.addStepDependencies(&self.step);
    self.include_paths.append(self.b.allocator, path) catch @panic("OOM");
}

fn buildWarnings(self: *CompileFlags, args: Config) void {
    const b = self.b;

    var warnings = std.ArrayList([]const u8).empty;
    defer warnings.deinit(b.allocator);

    if (args.warnings.all) {
        warnings.append(b.allocator, "-Wall") catch @panic("OOM");
    }

    if (args.warnings.errors) {
        warnings.append(b.allocator, "-Werror") catch @panic("OOM");
    }

    if (args.warnings.extra) {
        warnings.append(b.allocator, "-Wextra") catch @panic("OOM");
    }

    self.warnings = warnings.toOwnedSlice(b.allocator) catch @panic("failed to move slice");

    // if (args.warnings.all and args.warnings.errors) {
    //     self.warnings = &[_][]const u8{ "-Wall", "-Werror" };
    // }
}

/// Initialize a new CompileFlags build step.
pub fn init(b: *Build, args: Config) *CompileFlags {
    const self = b.allocator.create(CompileFlags) catch @panic("OOM");

    self.* = .{
        .b = b,
        .selected_compiler = args.compiler,
        .language_variant = switch (args.language_variant) {
            .cxx11 => "c++11",
            .cxx14 => "c++14",
            .cxx17 => "c++17",
            .cxx20 => "c++20",
            .cxx23 => "c++23",
        },
        .warnings = &[_][]const u8{},
        .custom = null,
        .is_verbose_output_enabled = args.enable_verbose_output orelse false,
        .step = .init(.{
            .id = base_id,
            .name = "generate-compile-flags",
            .makeFn = &makeFn,
            .owner = b,
        }),
    };

    self.buildWarnings(args);

    for (args.paths) |path| {
        self.addIncludePath(path);
    }

    if (args.custom) |custom_flags| {
        self.custom = custom_flags;
    }

    return self;
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

    // NOTE: strategy pattern, form compiler args
    const program = selected_compiler.getProgramArgs();

    var code: u8 = undefined;
    const process = try runAllowFail(
        b,
        program,
        &code,
        .pipe,
    );

    if (self.is_verbose_output_enabled) {
        std.debug.print("{s}", .{process});
    }

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

    try w.print("-std={s}\n", .{self.language_variant});

    for (self.warnings) |value| {
        try w.print("{s}\n", .{value});
    }

    for (self.include_paths.items) |lazy_path| {
        const path = lazy_path.getPath3(b, step);
        try w.print("-I{s}\n", .{try path.toString(allocator)});
    }

    if (self.custom) |custom_flags| {
        for (custom_flags) |flag| {
            try w.print("{s}\n", .{flag});
        }
    }

    try w.flush();
}

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
