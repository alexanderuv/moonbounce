import Moonbounce

// Temporary x86-64 experiments for #22, measured side by side on Windows.
// Not for merging. `branchFreeSearch` and `rowElimination` are constants at
// every call, so each benchmark compiles one variant.
enum GaussianEliminationVariants {
    @inline(always)
    static func solve<A: MatrixProtocol, B: MatrixProtocol>(
        _ a: inout A, _ b: inout B, branchFreeSearch: Bool, rowElimination: Bool, tolerance: Float = 1.0e-16
    ) -> Bool {
        let n = a.columnCount
        let m = b.columnCount
        if n == 0 {
            return true
        }
        return unsafe a.withUnsafeMutableElements { a, aRowStride, aColumnStride in
            unsafe b.withUnsafeMutableElements { b, bRowStride, bColumnStride in
                withUnsafeTemporaryAllocation(of: Bool.self, capacity: n) { pivoted in
                    withUnsafeTemporaryAllocation(of: Float.self, capacity: n) { factors in
                        unsafe pivoted.initialize(repeating: false)
                        @inline(always) func at(_ row: Int, _ column: Int) -> UnsafeMutablePointer<Float> {
                            unsafe a + (row &* aRowStride &+ column &* aColumnStride)
                        }
                        @inline(always) func bAt(_ row: Int, _ column: Int) -> UnsafeMutablePointer<Float> {
                            unsafe b + (row &* bRowStride &+ column &* bColumnStride)
                        }

                        for _ in 0..<n {
                            var pivotRow = -1, pivotColumn = -1
                            var largest: Float = 0
                            if branchFreeSearch {
                                // Used columns multiply to NaN, which no
                                // comparison picks; updates are selects.
                                for column in 0..<n {
                                    unsafe factors[column] = pivoted[column] ? .nan : 1
                                }
                                for row in 0..<n where unsafe !pivoted[row] {
                                    for column in 0..<n {
                                        let element = unsafe abs(at(row, column).pointee) * factors[column]
                                        let isLarger = element >= largest
                                        largest = isLarger ? element : largest
                                        pivotRow = isLarger ? row : pivotRow
                                        pivotColumn = isLarger ? column : pivotColumn
                                    }
                                }
                            } else {
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
                            }
                            if pivotColumn < 0 {
                                return false
                            }
                            unsafe pivoted[pivotColumn] = true

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
                            for j in 0..<n {
                                unsafe at(pivotColumn, j).pointee /= diagonal
                            }
                            for j in 0..<m {
                                unsafe bAt(pivotColumn, j).pointee /= diagonal
                            }
                            unsafe at(pivotColumn, pivotColumn).pointee = 1

                            if rowElimination {
                                // Jolt's order: row by row.
                                for row in 0..<n where row != pivotColumn {
                                    let factor = unsafe -at(row, pivotColumn).pointee
                                    for j in 0..<n {
                                        unsafe at(row, j).pointee.addProduct(at(pivotColumn, j).pointee, factor)
                                    }
                                    for j in 0..<m {
                                        unsafe bAt(row, j).pointee.addProduct(bAt(pivotColumn, j).pointee, factor)
                                    }
                                }
                            } else {
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
                        }
                        return true
                    }
                }
            }
        }
    }
}
