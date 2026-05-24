import Foundation
import SQLite3

final class SQLiteStatement {
    private unowned let connection: SQLiteConnection
    private var statement: OpaquePointer?

    init(connection: SQLiteConnection, statement: OpaquePointer?) {
        self.connection = connection
        self.statement = statement
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ value: String?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, SQLiteStatement.transient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw SQLiteStorageError.bindFailed(connection.lastErrorMessage) }
    }

    func bind(_ value: Int, at index: Int32) throws {
        let result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        guard result == SQLITE_OK else { throw SQLiteStorageError.bindFailed(connection.lastErrorMessage) }
    }

    func bind(_ value: Int64, at index: Int32) throws {
        let result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        guard result == SQLITE_OK else { throw SQLiteStorageError.bindFailed(connection.lastErrorMessage) }
    }

    func bind(_ value: Double?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_double(statement, index, value)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw SQLiteStorageError.bindFailed(connection.lastErrorMessage) }
    }

    func bind(_ value: Double, at index: Int32) throws {
        let result = sqlite3_bind_double(statement, index, value)
        guard result == SQLITE_OK else { throw SQLiteStorageError.bindFailed(connection.lastErrorMessage) }
    }

    func bind(_ value: Data?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), SQLiteStatement.transient)
            }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw SQLiteStorageError.bindFailed(connection.lastErrorMessage) }
    }

    func step() throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw SQLiteStorageError.stepFailed(connection.lastErrorMessage)
        }
    }

    func finish() throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw SQLiteStorageError.stepFailed(connection.lastErrorMessage)
        }
    }

    func reset() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    func columnString(_ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    func columnInt(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    func columnInt64(_ index: Int32) -> Int64 {
        Int64(sqlite3_column_int64(statement, index))
    }

    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    func columnIsNull(_ index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    func columnData(_ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: length)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
