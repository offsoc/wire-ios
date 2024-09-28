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

import SnapshotTesting
import XCTest

@testable import WireAPI
@testable import WireAPISupport

/// A helper object to make snapshotting API requests easier.

struct APIServiceSnapshotHelper<API> {

    enum Failure: Error {
        case noRequestGenerated
    }

    private let httpRequestHelper = HTTPRequestSnapshotHelper()
    private let buildAPI: (MockAPIServiceProtocol, APIVersion) -> API

    init(buildAPI: @escaping (MockAPIServiceProtocol, APIVersion) -> API) {
        self.buildAPI = buildAPI
    }

    /// Snapshot test the request generated by the given block for
    /// all api versions.
    ///
    /// This will generate one snapshot reference for each version.
    ///
    /// - Parameters:
    ///   - apiService: A mock api service. Use this to mock http responses that may be needed
    ///     during the `when` block. A new client is invoked for each api version.
    ///   - block: Some code that should invoke a method of the given api to generate a request.
    ///   - file: The file invoking the test.
    ///   - function: The method invoking the test.
    ///   - line: The line invoking the test.

    func verifyRequestForAllAPIVersions(
        apiService: (() throws -> MockAPIServiceProtocol)? = nil,
        when block: (API) async throws -> Void,
        file: StaticString = #file,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        try await verifyRequest(
            for: APIVersion.allCases,
            apiService: apiService,
            when: block,
            file: file,
            function: function,
            line: line
        )
    }

    /// Snapshot test the request generated by the given block for
    /// the given api versions.
    ///
    /// This will generate one snapshot reference for each version.
    ///
    /// - Parameters:
    ///   - apiVersions: A sequence of api versions to test.
    ///   - apiService: A mock api service. Use this to mock http responses that may be needed
    ///     during the `when` block. A new client is invoked for each api version.
    ///   - block: Some code that should invoke a method of the given api to generate a request.
    ///   - file: The file invoking the test.
    ///   - function: The method invoking the test.
    ///   - line: The line invoking the test.

    func verifyRequest(
        for apiVersions: any Sequence<APIVersion>,
        apiService: (() throws -> MockAPIServiceProtocol)? = nil,
        when block: (API) async throws -> Void,
        file: StaticString = #file,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        for apiVersion in apiVersions {
            try await verifyRequest(
                apiVersion: apiVersion,
                apiService: apiService?() ?? .withResponses([]),
                when: block,
                file: file,
                function: function,
                line: line
            )
        }
    }

    /// Snapshot test the request generated by the given block for a
    /// specific api version.
    ///
    /// Note: this is run on the main thread as a workaround of a crash in
    /// the SnapshotTesting framework when snapshotting in async environments.
    /// See https://github.com/pointfreeco/swift-snapshot-testing/issues/822
    ///
    /// - Parameters:
    ///   - apiVersion: API version to test.
    ///   - apiService: A mock api service. Use this to mock http responses that may be needed
    ///     during the `when` block.
    ///   - block: Some code that should invoke a method of the given api to generate a request.
    ///   - file: The file invoking the test.
    ///   - function: The method invoking the test.
    ///   - line: The line invoking the test.

    private func verifyRequest(
        apiVersion: APIVersion,
        apiService: MockAPIServiceProtocol,
        when block: (API) async throws -> Void,
        file: StaticString = #file,
        function: String = #function,
        line: UInt = #line
    ) async throws {
        let sut = buildAPI(apiService, apiVersion)
        try? await block(sut)

        let receivedRequests = apiService.executeRequestRequiringAccessToken_Invocations.map(\.request)

        guard !receivedRequests.isEmpty else {
            XCTFail("no requests to snapshot", file: file, line: line)
            return
        }

        for (index, request) in receivedRequests.enumerated() {
            let name = "request-\(index)-v\(apiVersion.rawValue)"

            await httpRequestHelper.verifyRequest(
                request: request,
                resourceName: name,
                file: file,
                function: function,
                line: line
            )
        }
    }

}
