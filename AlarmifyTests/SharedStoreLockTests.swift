import XCTest
import os
@testable import Alarmify

/// App Group の共有ストアの書き換えを直列化するロックのテスト。
/// flock は同じプロセス内でも open し直した記述子どうしで待ち合うため、2 つのスレッドで重ねて取り合って順序を確かめる
final class SharedStoreLockTests: XCTestCase {
    func testWithLockRunsOverlappingCallersOneAtATime() {
        let lock = SharedStoreLock(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "SharedStoreLockTests.\(UUID().uuidString).lock")
        )
        let order = OSAllocatedUnfairLock(initialState: [String]())
        let firstEntered = expectation(description: "first entered the lock")
        let secondFinished = expectation(description: "second finished")
        let workers = DispatchQueue(label: "SharedStoreLockTests", attributes: .concurrent)

        workers.async {
            lock.withLock {
                order.withLock { $0.append("first-begin") }
                firstEntered.fulfill()
                Thread.sleep(forTimeInterval: 0.3)
                order.withLock { $0.append("first-end") }
            }
        }
        wait(for: [firstEntered], timeout: 2)
        workers.async {
            lock.withLock {
                order.withLock { $0.append("second") }
            }
            secondFinished.fulfill()
        }
        wait(for: [secondFinished], timeout: 2)

        XCTAssertEqual(order.withLock { $0 }, ["first-begin", "first-end", "second"])
    }

    func testWithLockWithoutAFileRunsTheBodyDirectly() {
        XCTAssertEqual(SharedStoreLock(fileURL: nil).withLock { 42 }, 42)
    }
}
