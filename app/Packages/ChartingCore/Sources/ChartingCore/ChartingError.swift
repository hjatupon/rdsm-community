/// Errors thrown by the ChartingCore library.
public enum ChartingError: Error, Sendable {
    case metalUnavailable
    case bufferAllocationFailed(length: Int)
    case shaderCompilationFailed(String)
}
