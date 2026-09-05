import Testing
import Foundation
@testable import The_SESH_

@Suite struct SeshMediaPolicyTests {
    @Test func boundedImageSizesHaveDistinctCacheIdentities() throws {
        let url = try #require(URL(string: "https://example.invalid/photo.jpg"))
        #expect(SeshReliabilityPolicy.imagePixels(.nan) == 600)
        #expect(SeshReliabilityPolicy.imagePixels(.infinity) == 600)
        #expect(SeshReliabilityPolicy.imagePixels(30) == 64)
        #expect(SeshReliabilityPolicy.imagePixels(9000) == 2048)
        #expect(SeshReliabilityPolicy.imagePixels(200.1) == 201)
        #expect(SeshReliabilityPolicy.imageKey(url, pixels: 64) != SeshReliabilityPolicy.imageKey(url, pixels: 600))
    }

    @Test func imageHTTPContractRejectsEmptyOversizeOrNonImageData() {
        #expect(SeshReliabilityPolicy.acceptsHTTPImage(status: 200, mime: "image/jpeg", bytes: 100))
        #expect(!SeshReliabilityPolicy.acceptsHTTPImage(status: 404, mime: "image/jpeg", bytes: 100))
        #expect(!SeshReliabilityPolicy.acceptsHTTPImage(status: 200, mime: "text/html", bytes: 100))
        #expect(!SeshReliabilityPolicy.acceptsHTTPImage(status: 200, mime: "image/jpeg", bytes: 0))
        #expect(!SeshReliabilityPolicy.acceptsHTTPImage(status: 200, mime: "image/jpeg", bytes: SeshReliabilityPolicy.maxImageBytes + 1))
    }

    @Test func realtimeDecodingIsBoundedAndIgnoresUnknownFrames() {
        #expect(SeshRealtimeFramePolicy.eventType(in: Data(#"{"type":"changed"}"#.utf8)) == "changed")
        #expect(SeshRealtimeFramePolicy.eventType(in: Data(#"{"type":"pong"}"#.utf8)) == "pong")
        #expect(SeshRealtimeFramePolicy.eventType(in: Data(#"{"type":"unrecognized"}"#.utf8)) == nil)
        #expect(SeshRealtimeFramePolicy.eventType(in: Data(#"{"type":12}"#.utf8)) == nil)
        #expect(SeshRealtimeFramePolicy.eventType(in: Data(repeating: 32, count: SeshRealtimeFramePolicy.maximumBytes + 1)) == nil)
        #expect(SeshRealtimeFramePolicy.eventType(in: Data()) == nil)
    }
}
