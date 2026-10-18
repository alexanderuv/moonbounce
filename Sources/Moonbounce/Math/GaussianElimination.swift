/// Gauss-Jordan elimination with full pivoting, which solves `A · X = B`
/// for any ``MatrixProtocol`` matrices: fixed (``Matrix``, ``Vector``) or
/// sized at run time (``DynamicMatrix``).
public enum GaussianElimination {
    /// Solves `a · x = b` in place: on success `b` holds `x`, and `a` is
    /// left as the identity. Returns `false` when `a` is singular.
    ///
    /// `a` is n × n and `b` is n × m, so one call solves for m right-hand
    /// sides at once; with `b` the identity it computes `a`'s inverse.
    ///
    /// Each step takes as its pivot the element of largest magnitude among
    /// the rows and columns not yet pivoted on, which keeps the elimination
    /// stable without any scaling of the input. A pivot whose magnitude is
    /// below `tolerance`, or a remaining block that is all NaN, means `a` is
    /// singular, and `a` and `b` are left partly reduced.
    ///
    /// Bookkeeping takes five bytes per column of stack. Beyond 256
    /// columns it is a heap allocation instead.
    @inline(always)
    public static func solve<A: MatrixProtocol, B: MatrixProtocol>(
        _ a: inout A, _ b: inout B, tolerance: Float = 1.0e-16
    ) -> Bool {
        let n = a.columnCount
        let m = b.columnCount
        precondition(a.rowCount == n && b.rowCount == n, "a must be square and b must have as many rows")
        if n == 0 {
            return true
        }

        return unsafe a.withUnsafeMutableElements { a, aRowStride, aColumnStride in
            unsafe b.withUnsafeMutableElements { b, bRowStride, bColumnStride in
                // Per row: its elimination factor in the current step, and
                // whether it has been pivoted on, in one allocation so the
                // whole solve inlines. The flags are `Bool`, not `Float`: on
                // x86-64 a float compare for equality also branches on the
                // unordered case.
                withUnsafeTemporaryAllocation(
                    byteCount: n &* (MemoryLayout<Float>.stride &+ MemoryLayout<Bool>.stride),
                    alignment: MemoryLayout<Float>.alignment
                ) { scratch in
                    let factors = unsafe scratch.baseAddress!.bindMemory(to: Float.self, capacity: n)
                    let pivoted = unsafe (scratch.baseAddress! + n &* MemoryLayout<Float>.stride)
                        .bindMemory(to: Bool.self, capacity: n)
                    unsafe pivoted.initialize(repeating: false, count: n)
                    @inline(always) func at(_ row: Int, _ column: Int) -> UnsafeMutablePointer<Float> {
                        unsafe a + (row &* aRowStride &+ column &* aColumnStride)
                    }
                    @inline(always) func bAt(_ row: Int, _ column: Int) -> UnsafeMutablePointer<Float> {
                        unsafe b + (row &* bRowStride &+ column &* bColumnStride)
                    }

                    for _ in 0..<n {
                        // The last of the largest remaining elements, row by
                        // row. Rows and columns pivoted on are skipped
                        // together, because each pivot is swapped onto the
                        // diagonal. A NaN element is never picked.
                        var pivotRow = -1, pivotColumn = -1
                        var largest: Float = 0
                        for row in 0..<n where unsafe !pivoted[row] {
                            for column in 0..<n where unsafe !pivoted[column] {
                                let element = unsafe abs(at(row, column).pointee)
                                if element >= largest {
                                    largest = element
                                    pivotRow = row
                                    pivotColumn = column
                                }
                            }
                        }
                        if pivotColumn < 0 {
                            return false
                        }
                        unsafe pivoted[pivotColumn] = true

                        // Move the pivot onto the diagonal.
                        if pivotRow != pivotColumn {
                            for j in 0..<n {
                                unsafe swap(&at(pivotRow, j).pointee, &at(pivotColumn, j).pointee)
                            }
                            for j in 0..<m {
                                unsafe swap(&bAt(pivotRow, j).pointee, &bAt(pivotColumn, j).pointee)
                            }
                        }

                        let diagonal = unsafe at(pivotColumn, pivotColumn).pointee
                        if abs(diagonal) < tolerance {
                            return false
                        }

                        // Scale the pivot row so the pivot is 1.
                        for j in 0..<n {
                            unsafe at(pivotColumn, j).pointee /= diagonal
                        }
                        for j in 0..<m {
                            unsafe bAt(pivotColumn, j).pointee /= diagonal
                        }
                        unsafe at(pivotColumn, pivotColumn).pointee = 1

                        // Clear the pivot column from every other row: each
                        // row subtracts the pivot row times its element in
                        // the pivot column, with one fused multiply-add per
                        // element. Column by column, so the inner loop runs
                        // down a column, which is contiguous in a ``Matrix``.
                        // The pivot row takes part with a factor of 0 and
                        // gets its value back after, to stay exact. In the
                        // pivot column itself the pivot is 1, so each other
                        // row's finite element `x` becomes `x + 1 · -x`, exactly 0.
                        for row in 0..<n {
                            unsafe factors[row] = -at(row, pivotColumn).pointee
                        }
                        unsafe factors[pivotColumn] = 0
                        for column in 0..<n {
                            let pivotElement = unsafe at(pivotColumn, column).pointee
                            for row in 0..<n {
                                unsafe at(row, column).pointee.addProduct(pivotElement, factors[row])
                            }
                            unsafe at(pivotColumn, column).pointee = pivotElement
                        }
                        for column in 0..<m {
                            let pivotElement = unsafe bAt(pivotColumn, column).pointee
                            for row in 0..<n {
                                unsafe bAt(row, column).pointee.addProduct(pivotElement, factors[row])
                            }
                            unsafe bAt(pivotColumn, column).pointee = pivotElement
                        }
                    }
                    return true
                }
            }
        }
    }
}
