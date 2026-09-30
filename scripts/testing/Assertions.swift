// Minimal XCTest-compatible assertions for Command Line Tools installations
// without XCTest. The actual test methods are shared with the XCTest target.
import Foundation

class XCTestCase {}
struct XCTSkip: Error { let reason: String; init(_ reason: String) { self.reason = reason } }
struct AssertionError: Error {}
var assertionFailures = 0
func XCTFail(_ message: String = "Assertion failed", file: StaticString = #filePath, line: UInt = #line) {
    assertionFailures += 1
    print("FAIL \(file):\(line): \(message)")
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(), b = try rhs(); if a != b { XCTFail("\(a) != \(b)", file: file, line: line) } }
    catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertNotEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { if try lhs() == rhs() { XCTFail("Values unexpectedly equal", file: file, line: line) } }
    catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { XCTFail("Expected true", file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { XCTFail("Expected false", file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() != nil { XCTFail("Expected nil", file: file, line: line) } } catch { XCTFail("\(error)", file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); XCTFail("Expected a thrown error", file: file, line: line) } catch {}
}
func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value = try expression() else { XCTFail("Expected non-nil", file: file, line: line); throw AssertionError() }
    return value
}
