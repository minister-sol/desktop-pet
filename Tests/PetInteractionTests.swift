// PetInteractionTests.swift
// Verifies the distance threshold used to distinguish clicks from drags.

import XCTest
@testable import DesktopPet

final class PetInteractionTests: XCTestCase {
    func testMovementBelowFourPointsIsClick() {
        XCTAssertFalse(PetInteraction.isDrag(deltaX: 3, deltaY: 2))
    }

    func testMovementAtFourPointsIsDrag() {
        XCTAssertTrue(PetInteraction.isDrag(deltaX: 4, deltaY: 0))
    }

    func testDiagonalMovementUsesDistance() {
        XCTAssertTrue(PetInteraction.isDrag(deltaX: 3, deltaY: 3))
        XCTAssertTrue(PetInteraction.isDrag(deltaX: -4, deltaY: 0))
    }
}
