pub fn build(_: *std.Build) void {}

pub fn addCompileFlags(b: *Build) CompileFlags {
    return .init(b);
}

const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;

const CompileFlags = @import("src/CompileFlags.zig");
