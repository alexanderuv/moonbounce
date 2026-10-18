// The precision of world positions, chosen by the `DoublePrecision` package
// trait. Positions and the transforms that place objects use these names, so
// one build setting moves a whole simulation to double precision. Directions,
// rotations, velocities and shapes stay `Float` either way.
//
// Enable the trait in a client's manifest:
//
//     .package(url: "...", from: "...", traits: ["DoublePrecision"])
//
// or for a local build with `swift build --traits DoublePrecision`.

#if DoublePrecision
/// A world coordinate: `Double` with the `DoublePrecision` trait.
public typealias Real = Double

/// A world position: ``DoubleVector3`` with the `DoublePrecision` trait.
public typealias RealVector3 = DoubleVector3

/// A transform that places an object in the world: ``DoubleMatrix4x4`` with
/// the `DoublePrecision` trait.
public typealias RealMatrix4x4 = DoubleMatrix4x4
#else
/// A world coordinate: `Float`, or `Double` with the `DoublePrecision` trait.
public typealias Real = Float

/// A world position: ``Vector3``, or ``DoubleVector3`` with the
/// `DoublePrecision` trait.
public typealias RealVector3 = Vector3

/// A transform that places an object in the world: ``Matrix4x4``, or
/// ``DoubleMatrix4x4`` with the `DoublePrecision` trait.
public typealias RealMatrix4x4 = Matrix4x4
#endif
