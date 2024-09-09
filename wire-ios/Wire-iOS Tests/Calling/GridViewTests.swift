//
// Wire
// Copyright (C) 2024 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import WireTestingPackage
import XCTest

@testable import Wire

class OrientableViewMock: OrientableView {
    func layoutForOrientation() {}
    func layout(forInterfaceOrientation interfaceOrientation: UIInterfaceOrientation, deviceOrientation: UIDeviceOrientation) {}
}

class GridViewDelegateMock: GridViewDelegate {

    var page: Int = 0

    func gridView(_ gridView: GridView, didChangePageTo page: Int) {
        self.page = page
    }
}

final class GridViewTests: XCTestCase {

    // MARK: - Properties

    private var snapshotHelper: SnapshotHelper!
    private var sut: GridView!
    private var gridViewDelegateMock: GridViewDelegateMock!
    private var tiles = [OrientableView]()

    let frame = CGRect(origin: CGPoint(x: 0, y: 0), size: XCTestCase.DeviceSizeIPhone5)

    lazy var views: [OrientableView] = colors.map {
        let view = OrientableViewMock(frame: frame)
        view.backgroundColor = $0
        return view
    }

    let colors: [UIColor] = [
        .red,
        .blue,
        .cyan,
        .brown,
        .orange,
        .green,
        .yellow,
        .magenta,
        .purple,
        .systemPink,
        .systemTeal,
        .gray
    ]

    // MARK: - setUp

    override func setUp() {
        super.setUp()
        snapshotHelper = .init()
        gridViewDelegateMock = GridViewDelegateMock()
    }

    // MARK: - tearDown

    override func tearDown() {
        snapshotHelper = nil
        sut = nil
        gridViewDelegateMock = nil
        tiles.removeAll()
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func setupSut(maxItemsPerPage: Int = 8) {
        sut = GridView(maxItemsPerPage: maxItemsPerPage)
        sut.frame = frame
        sut.dataSource = self
    }

    private func testGrid(
        withAmount amount: Int,
        maxItemsPerPage: Int = 8,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        // Given
        tiles = Array(views.prefix(amount))
        setupSut(maxItemsPerPage: maxItemsPerPage)
        sut.reloadData()

        // Then
        snapshotHelper.verify(
            matching: sut,
            file: file,
            testName: testName,
            line: line
        )
    }

    // MARK: - Snapshot Tests

    func testOneView() {
        testGrid(withAmount: 1)
    }

    func testTwoViews() {
        testGrid(withAmount: 2)
    }

    func testThreeViews() {
        testGrid(withAmount: 3)
    }

    func testFourViews() {
        testGrid(withAmount: 4)
    }

    func testSixViews() {
        testGrid(withAmount: 6)
    }

    func testEightViews() {
        testGrid(withAmount: 8)
    }

    func testEightViews_WithMaxItemsPerPage_Of_Four() {
        testGrid(withAmount: 8, maxItemsPerPage: 4)
    }

    // MARK: - Unit Tests

    func testThatItUpdatesDelegate_When_ThePageChanges() {
        // GIVEN
        setupSut()
        sut.gridViewDelegate = gridViewDelegateMock
        let scrollView = UIScrollView(frame: frame)
        scrollView.contentOffset = CGPoint(x: 0, y: frame.size.height)

        // WHEN
        sut.scrollViewDidEndDecelerating(scrollView)

        // THEN
        XCTAssertEqual(gridViewDelegateMock.page, 1)
    }
}

extension GridViewTests: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tiles.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GridCell.reuseIdentifier, for: indexPath) as? GridCell else {
            return UICollectionViewCell()
        }

        cell.add(streamView: tiles[indexPath.row])
        return cell
    }

}
