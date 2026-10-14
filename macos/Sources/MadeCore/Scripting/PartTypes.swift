import Foundation
import simd

/// Source location and message for a script diagnostic, mapped back to the original `.part.ts` or `.part.js` file.
public struct PartDiagnostic: Sendable, Codable, Equatable, CustomStringConvertible {
    public let file: String
    public let line: Int
    public let column: Int
    public let message: String

    public init(file: String, line: Int, column: Int, message: String) {
        self.file = file
        self.line = max(1, line)
        self.column = max(1, column)
        self.message = message
    }

    public var description: String {
        "\(file):\(line):\(column): \(message)"
    }
}

/// Classification of failures raised while loading or evaluating a part script.
public enum PartRuntimeErrorCode: String, Sendable, Codable, Equatable, CaseIterable {
    case syntaxError = "syntax-error"
    case scriptError = "script-error"
    case moduleNotFound = "module-not-found"
    case accessDenied = "access-denied"
    case invalidExport = "invalid-export"
    case validationFailed = "validation-failed"
    case executionLimitExceeded = "execution-limit-exceeded"
    case kernelFailed = "kernel-failed"
    case cancelled = "cancelled"
}

/// Structured error returned by `PartRuntime`.
public struct PartRuntimeError: Error, Sendable, Codable, Equatable, CustomStringConvertible {
    public let code: PartRuntimeErrorCode
    public let diagnostic: PartDiagnostic
    public let kernelError: KernelError?
    public let loadedFiles: [String]

    public init(
        code: PartRuntimeErrorCode,
        diagnostic: PartDiagnostic,
        kernelError: KernelError? = nil,
        loadedFiles: [String] = []
    ) {
        self.code = code
        self.diagnostic = diagnostic
        self.kernelError = kernelError
        self.loadedFiles = loadedFiles
    }

    public var description: String {
        diagnostic.description
    }

    public func withLoadedFiles(_ files: [String]) -> PartRuntimeError {
        guard loadedFiles.isEmpty && !files.isEmpty else { return self }
        return PartRuntimeError(
            code: code,
            diagnostic: diagnostic,
            kernelError: kernelError,
            loadedFiles: files
        )
    }
}

/// Named parameter declared by a part script through `param(...)` or `defineParams(...)`.
public struct PartParameterSpec: Sendable, Codable, Equatable {
    public let name: String
    public let defaultValue: Double
    public let value: Double
    public let min: Double?
    public let max: Double?
    public let step: Double?
    public let unit: String?
    public let label: String?

    public init(
        name: String,
        defaultValue: Double,
        value: Double,
        min: Double? = nil,
        max: Double? = nil,
        step: Double? = nil,
        unit: String? = nil,
        label: String? = nil
    ) {
        self.name = name
        self.defaultValue = defaultValue
        self.value = value
        self.min = min
        self.max = max
        self.step = step
        self.unit = unit
        self.label = label
    }
}

/// Axis-aligned bounding box expected by a part file's `export const expected` block.
public struct PartExpectedBounds: Sendable, Codable, Equatable {
    public let min: SIMD3<Float>
    public let max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }
}

/// Optional intent specification exported as `export const expected` in a `.part.ts` or `.part.js` file (#428).
public struct PartExpected: Sendable, Codable, Equatable {
    public let volume: Double?
    public let area: Double?
    public let bounds: PartExpectedBounds?
    public let tolerance: Double?

    public init(
        volume: Double? = nil,
        area: Double? = nil,
        bounds: PartExpectedBounds? = nil,
        tolerance: Double? = nil
    ) {
        self.volume = volume
        self.area = area
        self.bounds = bounds
        self.tolerance = tolerance
    }
}

/// The shape tree, `expected` block, and parameter table produced by running a part script in JavaScriptCore before kernel evaluation.
public struct PartScriptEvaluation: Sendable, Codable, Equatable {
    public let jobId: JobId
    public let solidId: SolidId
    public let shape: ShapeNode
    public let expected: PartExpected?
    public let parameters: [PartParameterSpec]
    public let evaluatedOnMainThread: Bool
    public let loadedFiles: [String]

    public init(
        jobId: JobId,
        solidId: SolidId,
        shape: ShapeNode,
        expected: PartExpected? = nil,
        parameters: [PartParameterSpec] = [],
        evaluatedOnMainThread: Bool = false,
        loadedFiles: [String] = []
    ) {
        self.jobId = jobId
        self.solidId = solidId
        self.shape = shape
        self.expected = expected
        self.parameters = parameters
        self.evaluatedOnMainThread = evaluatedOnMainThread
        self.loadedFiles = loadedFiles
    }
}

/// Full output of evaluating a `.part.ts` or `.part.js` script through JavaScriptCore and `KernelClient`.
public struct PartEvaluationOutput: Sendable {
    public let jobId: JobId
    public let solidId: SolidId
    public let shape: ShapeNode
    public let payload: MeshPayload
    public let expected: PartExpected?
    public let parameters: [PartParameterSpec]
    public let evaluatedOnMainThread: Bool
    public let loadedFiles: [String]

    public init(
        jobId: JobId,
        solidId: SolidId,
        shape: ShapeNode,
        payload: MeshPayload,
        expected: PartExpected? = nil,
        parameters: [PartParameterSpec] = [],
        evaluatedOnMainThread: Bool = false,
        loadedFiles: [String] = []
    ) {
        self.jobId = jobId
        self.solidId = solidId
        self.shape = shape
        self.payload = payload
        self.expected = expected
        self.parameters = parameters
        self.evaluatedOnMainThread = evaluatedOnMainThread
        self.loadedFiles = loadedFiles
    }
}

/// Typed result wrapper for `PartRuntime` evaluations, keyed by `JobId` (invariant 7).
public enum PartRuntimeResult<T: Sendable>: Sendable {
    case success(jobId: JobId, value: T)
    case failure(jobId: JobId, error: PartRuntimeError)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var jobId: JobId {
        switch self {
        case .success(let id, _): return id
        case .failure(let id, _): return id
        }
    }

    public var value: T? {
        if case .success(_, let v) = self { return v }
        return nil
    }

    public var error: PartRuntimeError? {
        if case .failure(_, let e) = self { return e }
        return nil
    }
}
