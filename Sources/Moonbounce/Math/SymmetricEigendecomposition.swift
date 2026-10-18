/// The eigenvalues and eigenvectors of a symmetric `size` × `size` matrix,
/// such as an inertia tensor, whose eigenvectors are its principal axes.
///
/// For each `i`, `matrix * eigenvectors[column: i]` equals
/// `eigenvalues[i] * eigenvectors[column: i]`, and the eigenvectors are
/// orthonormal. The pairs are in no particular order.
@frozen
public struct SymmetricEigendecomposition<let size: Int>: Sendable, BitwiseCopyable {
    /// The eigenvalues, one per column of ``eigenvectors``.
    public var eigenvalues: Vector<size>

    /// The eigenvectors, one per column, each of length 1.
    public var eigenvectors: Matrix<size, size>

    /// Decomposes `matrix`, of which only the upper triangle is read: the
    /// lower one is taken to mirror it. `nil` when the rotations have not
    /// converged after 50 sweeps.
    ///
    /// Each sweep applies one Jacobi rotation per element above the
    /// diagonal, which zeroes it, until every such element is below
    /// `Float.leastNormalMagnitude` on average. The rotations are Jolt's
    /// (from Numerical Recipes, paragraph 11.1), with a threshold for the
    /// first sweeps and, from the sixth, elements too small to change the
    /// diagonal set to 0 rather than rotated away. Repeated eigenvalues and
    /// diagonal input need no special case: a diagonal matrix converges at
    /// once, with the identity as its eigenvectors. The method suits small
    /// sizes; its cost grows with the cube of `size` per sweep.
    @inline(always)
    public init?(_ matrix: Matrix<size, size>) {
        var a = matrix
        var eigenvalues = Vector<size> { i in matrix[row: i, column: i] }
        var eigenvectors = Matrix<size, size>.identity
        // The diagonal at the start of the sweep, and what the sweep has
        // added to it so far: accumulated apart, as in Jolt, so rounding in
        // one rotation doesn't carry into the next sweep's thresholds.
        var diagonal = eigenvalues
        var change = Vector<size>.zero

        let converged = unsafe a.withUnsafeMutableElements { a, aRowStride, aColumnStride in
            unsafe eigenvectors.withUnsafeMutableElements { v, vRowStride, vColumnStride in
                @inline(always) func at(_ row: Int, _ column: Int) -> UnsafeMutablePointer<Float> {
                    unsafe a + (row &* aRowStride &+ column &* aColumnStride)
                }
                @inline(always) func vAt(_ row: Int, _ column: Int) -> UnsafeMutablePointer<Float> {
                    unsafe v + (row &* vRowStride &+ column &* vColumnStride)
                }
                // One rotation of the pair x, y by s and tau: x - s (y + x tau)
                // and y + s (x - y tau), with the fused multiply-adds a
                // compiler that contracts Jolt's expressions makes.
                @inline(always) func rotate(_ x: UnsafeMutablePointer<Float>, _ y: UnsafeMutablePointer<Float>, _ s: Float, _ tau: Float) {
                    let g = unsafe x.pointee, h = unsafe y.pointee
                    unsafe x.pointee = g.addingProduct(-s, h.addingProduct(g, tau))
                    unsafe y.pointee = h.addingProduct(s, g.addingProduct(-h, tau))
                }

                for sweep in 0..<50 {
                    var sum: Float = 0
                    for p in 0..<size {
                        for q in (p &+ 1)..<size {
                            sum += unsafe abs(at(p, q).pointee)
                        }
                    }
                    let average = sum / Float(size &* size)
                    // Converged once the average is denormal: Jolt's change
                    // from Numerical Recipes, which waits for exactly 0.
                    if average < .leastNormalMagnitude {
                        return true
                    }
                    // The first four sweeps rotate only the larger elements.
                    // The least normal float rather than 0 keeps a rotation
                    // from dividing by a denormal.
                    let threshold: Float = sweep < 4 ? 0.2 * average : .leastNormalMagnitude

                    for p in 0..<size {
                        for q in (p &+ 1)..<size {
                            let element = unsafe at(p, q)
                            let magnitude = unsafe abs(element.pointee)
                            let g = 100 * magnitude
                            let valueP = eigenvalues[p], valueQ = eigenvalues[q]
                            if sweep > 4 && abs(valueP) + g == abs(valueP) && abs(valueQ) + g == abs(valueQ) {
                                unsafe element.pointee = 0
                            } else if magnitude > threshold {
                                let difference = valueQ - valueP
                                let t: Float
                                if abs(difference) + g == abs(difference) {
                                    t = unsafe element.pointee / difference
                                } else {
                                    // theta is infinite for a tiny element,
                                    // which makes t 0, as it should be.
                                    let theta = unsafe 0.5 * difference / element.pointee
                                    let magnitudeT = 1 / (abs(theta) + Float(1).addingProduct(theta, theta).squareRoot())
                                    t = theta < 0 ? -magnitudeT : magnitudeT
                                }
                                let c = 1 / Float(1).addingProduct(t, t).squareRoot()
                                let s = t * c
                                let tau = s / (1 + c)
                                let h = unsafe t * element.pointee
                                unsafe element.pointee = 0

                                change[p] -= h
                                change[q] += h
                                eigenvalues[p] -= h
                                eigenvalues[q] += h

                                for j in 0..<p {
                                    unsafe rotate(at(j, p), at(j, q), s, tau)
                                }
                                for j in (p &+ 1)..<q {
                                    unsafe rotate(at(p, j), at(j, q), s, tau)
                                }
                                for j in (q &+ 1)..<size {
                                    unsafe rotate(at(p, j), at(q, j), s, tau)
                                }
                                for j in 0..<size {
                                    unsafe rotate(vAt(j, p), vAt(j, q), s, tau)
                                }
                            }
                        }
                    }

                    for i in 0..<size {
                        diagonal[i] += change[i]
                        eigenvalues[i] = diagonal[i]
                        change[i] = 0
                    }
                }
                return false
            }
        }
        if !converged {
            return nil
        }
        self.eigenvalues = eigenvalues
        self.eigenvectors = eigenvectors
    }
}
