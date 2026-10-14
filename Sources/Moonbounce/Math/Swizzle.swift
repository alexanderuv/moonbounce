/// A vector lane, for building swizzles such as `v.swizzled(.y, .x, .w, .z)`.
///
/// A swizzle with constant lanes folds into a single shuffle after inlining.
/// It is meant for setup code and tests: in arithmetic-heavy code, LLVM can
/// split the work around a lane-by-lane shuffle into 2-lane pieces, so hot
/// paths use the fixed shuffles of `_MoonbounceShims` instead.
@frozen
public enum Lane: Int, Sendable, CaseIterable {
    case x = 0
    case y = 1
    case z = 2
    case w = 3
}
