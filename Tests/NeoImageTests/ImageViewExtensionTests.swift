import XCTest
@testable import NeoImage

class ImageViewExtensionTests: XCTestCase {
    var imageView: UIImageView!
    
    override func setUp() {
        super.setUp()
        
    }
    
    override func tearDown() {
        imageView = nil
        super.tearDown()
    }
    
    func testImageDownloadForImageView() async throws {
        let exp = expectation(description: #function)
        imageView = await UIImageView()
        
        for url in imageURLs {
            do {
                let result = try await imageView.neo.setImage(
                    with: url,
                    options: NeoImageOptions(
                        processor: nil,
                        transition: .fade(0.3),
                        cacheExpiration: .seconds(60)
                    )
                )
                
                XCTAssertNotNil(result.image)
                //                XCTAssertNotNil(imageView.image)
                XCTAssertEqual(result.url, url)
                
                exp.fulfill()
            } catch {
                XCTFail("Image download failed with error: \(error)")
                exp.fulfill()
            }
        }
        
        await fulfillment(of: [exp], timeout: 5.0)
        
    }
    
//    func testImageDownloadCancelForImageView() async throws {
//        let exp = expectation(description: #function)
//        let url = URL(string: "https://example.com/image.jpg")!
//        
//        // Create mock data
//        let bundle = Bundle(for: ImageViewExtensionTests.self)
//        guard let testImagePath = bundle.path(forResource: "test_image", ofType: "jpg"),
//              let testImageData = try? Data(contentsOf: URL(fileURLWithPath: testImagePath)) else {
//            XCTFail("Could not load test image")
//            return
//        }
//        
//        // Setup URL session mock with delay
//        URLProtocolMock.mockResponses[url] = (testImageData, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
//        URLProtocolMock.responseDelay = 1.0 // Add delay to ensure we can cancel
//        let config = URLSessionConfiguration.ephemeral
//        config.protocolClasses = [URLProtocolMock.self]
//        
//        Task {
//            let downloadTask = imageView.neo.setImage(
//                with: url,
//                completion: { result in
//                    switch result {
//                    case .success:
//                        XCTFail("Task should have been cancelled")
//                    case .failure(let error):
//                        if let neoError = error as? NeoImageError,
//                           case .requestError(let reason) = neoError,
//                           case .taskCancelled = reason {
//                            // Successfully identified cancellation error
//                        } else {
//                            XCTFail("Expected task cancelled error, got \(error)")
//                        }
//                    }
//                    exp.fulfill()
//                }
//            )
//            
//            // Cancel the task after a short delay
//            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
//            await downloadTask?.cancel()
//        }
//        
//        await fulfillment(of: [exp], timeout: 5.0)
//    }
    
    func testSettingNilURL() async throws {
        let exp = expectation(description: #function)
        let url: URL? = nil
        
        
        do {
            _ = try await imageView.neo.setImage(with: url)
            XCTFail("Setting nil URL should throw an error")
            exp.fulfill()
        } catch {
            XCTFail("Expected invalid data error, got \(error)")
            exp.fulfill()
        }
        
        await fulfillment(of: [exp], timeout: 5.0)
    }
    
//    func testImageDownloadCompletionHandler() async throws {
//        let exp = expectation(description: #function)
//        let url = URL(string: "https://example.com/image.jpg")!
//        
//        
//        _ = imageView.neo.setImage(with: url) { result in
//            switch result {
//            case .success(let loadingResult):
//                XCTAssertNotNil(loadingResult.image)
//                XCTAssertEqual(loadingResult.url, url)
//                XCTAssertNotNil(self.imageView.image)
//            case .failure(let error):
//                XCTFail("Image download failed with error: \(error)")
//            }
//            exp.fulfill()
//        }
//        
//        await fulfillment(of: [exp], timeout: 5.0)
//    }
    
    func testSettingImageWhileKeepingCurrentOne() async throws {
        let exp = expectation(description: #function)
        let url = URL(string: "https://example.com/image.jpg")!
        
        // Create mock data and placeholder image
        let bundle = Bundle(for: ImageViewExtensionTests.self)
        guard let testImagePath = bundle.path(forResource: "test_image", ofType: "jpg"),
              let testImageData = try? Data(contentsOf: URL(fileURLWithPath: testImagePath)),
              let placeholderImage = UIImage(data: testImageData) else {
            XCTFail("Could not load test image")
            return
        }
        
        // Setup URL session mock
        //        URLProtocolMock.mockResponses[url] = (testImageData, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        //        let config = URLSessionConfiguration.ephemeral
        //        config.protocolClasses = [URLProtocolMock.self]
        
        // Set placeholder image
        //        imageView.image = placeholderImage
        
        
        do {
            let result = try await imageView.neo.setImage(
                with: url,
                placeholder: placeholderImage
            )
            
            XCTAssertNotNil(result.image)
            //                XCTAssertNotNil(imageView.image)
            // Check that the image was replaced
            //                XCTAssertNotEqual(imageView.image, placeholderImage)
            
            exp.fulfill()
        } catch {
            XCTFail("Image download failed with error: \(error)")
            exp.fulfill()
            
        }
        
        await fulfillment(of: [exp], timeout: 5.0)
    }
    
    let imageURLs: [URL] = [
        URL(string: "https://picsum.photos/id/1/1200/1200")!,
        URL(string: "https://picsum.photos/id/2/1200/1200")!,
        URL(string: "https://picsum.photos/id/3/1200/1200")!,
        URL(string: "https://picsum.photos/id/4/1200/1200")!,
        URL(string: "https://picsum.photos/id/5/1200/1200")!,
        URL(string: "https://picsum.photos/id/6/1200/1200")!,
        URL(string: "https://picsum.photos/id/7/1200/1200")!,
        URL(string: "https://picsum.photos/id/8/1200/1200")!,
        URL(string: "https://picsum.photos/id/9/1200/1200")!,
        URL(string: "https://picsum.photos/id/10/1200/1200")!,
        URL(string: "https://picsum.photos/id/11/1200/1200")!,
        URL(string: "https://picsum.photos/id/12/1200/1200")!,
        URL(string: "https://picsum.photos/id/13/1200/1200")!,
        URL(string: "https://picsum.photos/id/14/1200/1200")!,
        URL(string: "https://picsum.photos/id/15/1200/1200")!,
        URL(string: "https://picsum.photos/id/16/1200/1200")!,
        URL(string: "https://picsum.photos/id/17/1200/1200")!,
        URL(string: "https://picsum.photos/id/18/1200/1200")!,
        URL(string: "https://picsum.photos/id/19/1200/1200")!,
        URL(string: "https://picsum.photos/id/20/1200/1200")!,
        URL(string: "https://picsum.photos/id/21/1200/1200")!,
        URL(string: "https://picsum.photos/id/22/1200/1200")!,
        URL(string: "https://picsum.photos/id/23/1200/1200")!,
        URL(string: "https://picsum.photos/id/24/1200/1200")!,
        URL(string: "https://picsum.photos/id/25/1200/1200")!,
        URL(string: "https://picsum.photos/id/26/1200/1200")!,
        URL(string: "https://picsum.photos/id/27/1200/1200")!,
        URL(string: "https://picsum.photos/id/28/1200/1200")!,
        URL(string: "https://picsum.photos/id/29/1200/1200")!,
        URL(string: "https://picsum.photos/id/30/1200/1200")!,
        URL(string: "https://picsum.photos/id/31/1200/1200")!,
        URL(string: "https://picsum.photos/id/32/1200/1200")!,
        URL(string: "https://picsum.photos/id/33/1200/1200")!,
        URL(string: "https://picsum.photos/id/34/1200/1200")!,
        URL(string: "https://picsum.photos/id/35/1200/1200")!,
        URL(string: "https://picsum.photos/id/36/1200/1200")!
    ]
}

// Mock URLProtocol for testing
//class URLProtocolMock: URLProtocol {
//    
//    static var mockResponses: [URL: (Data, URLResponse?)] = [:]
//    static var responseDelay: TimeInterval = 0
//    
//    override class func canInit(with request: URLRequest) -> Bool {
//        return true
//    }
//    
//    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
//        return request
//    }
//    
//    override func startLoading() {
//        guard let url = request.url,
//              let (data, response) = URLProtocolMock.mockResponses[url] else {
//            client?.urlProtocol(self, didFailWithError: NSError(domain: "test", code: -1, userInfo: nil))
//            return
//        }
//        
//        // Simulate network delay if needed
//        if URLProtocolMock.responseDelay > 0 {
//            DispatchQueue.global().asyncAfter(deadline: .now() + URLProtocolMock.responseDelay) {
//                if let response = response {
//                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
//                }
//                self.client?.urlProtocol(self, didLoad: data)
//                self.client?.urlProtocolDidFinishLoading(self)
//            }
//        } else {
//            if let response = response {
//                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
//            }
//            client?.urlProtocol(self, didLoad: data)
//            client?.urlProtocolDidFinishLoading(self)
//        }
//    }
//    
//    override func stopLoading() {
//        // No-op
//    }
//}


