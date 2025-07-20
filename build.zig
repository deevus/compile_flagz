pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/CompileFlags.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addStaticLibrary(.{
        .name = "compile_flagz",
        .root_module = mod,
    });

    b.installArtifact(lib);

    const docs = buildDocs(b, lib);
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(docs.step);
    docs.step.dependOn(&lib.step);
}

fn buildDocs(
    b: *Build,
    lib: *Step.Compile,
) struct {
    step: *Step,
} {
    const install = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    return .{
        .step = &install.step,
    };
}

/// Create a new CompileFlags build step for generating compile_flags.txt files.
/// This is the main entry point for using the compile_flagz library.
/// The returned CompileFlags instance can be used to add include paths and
/// generate a compile_flags.txt file for C/C++ language server integration
/// when developing C/C++ code in projects that use Zig as their build system.
pub fn addCompileFlags(b: *Build) CompileFlags {
    return .init(b);
}

const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const Step = Build.Step;

const CompileFlags = @import("src/CompileFlags.zig");
