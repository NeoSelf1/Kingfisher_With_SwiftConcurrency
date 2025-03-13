import SwiftUI
import UIKit

/// NeoImage 바인딩을 위한 ObservableObject
@MainActor
class NeoImageBinder: ObservableObject {
    init() {}
    
    // 다운로드 작업 정보
    var downloadTask: DownloadTask?
    private var loading = false
    
    // 로딩 상태 정보
    var loadingOrSucceeded: Bool {
        return loading || loadedImage != nil
    }
    
    // 이미지 로딩 상태와 결과
    @Published var loaded = false
    @Published var animating = false
    @Published var loadedImage: UIImage? = nil
    @Published var progress: Progress = .init()
    
    func markLoading() {
        loading = true
    }
    
    func markLoaded() {
        loaded = true
    }
    
    // 이미지 로딩 시작
    func start(url: URL?, options: NeoImageOptions?) async {
        guard let url = url else {
            loading = false
            markLoaded()
            return
        }
        
        loading = true
        progress = .init()
        
        do {
            let result = try await ImageDownloader.default.downloadImage(with: url, options: options)
            
            await MainActor.run {
                loadedImage = result.image
                loading = false
                markLoaded()
            }
        } catch {
            await MainActor.run {
                loadedImage = nil
                loading = false
                markLoaded()
            }
        }
    }
    
    // 로딩 취소
    func cancel() async {
        await downloadTask?.cancel()
        downloadTask = nil
        loading = false
    }
}

/// SwiftUI에서 사용 가능한 비동기 이미지 로딩 View
public struct NeoImage: View {
    // 이미지 소스
    private let source: Source
    // 이미지 로딩 바인더
    @StateObject private var binder = NeoImageBinder()
    
    // 옵션 및 콜백
    private var placeholder: AnyView?
    private var options: NeoImageOptions
    private var onSuccess: ((ImageLoadingResult) -> Void)?
    private var onFailure: ((Error) -> Void)?
    private var contentMode: SwiftUI.ContentMode
    
    /// 이미지 소스를 나타내는 열거형
    public enum Source {
        case url(URL?)
        case urlString(String?)
    }
    
    // MARK: - Initializers
    
    /// URL로 초기화
    public init(url: URL?) {
        self.source = .url(url)
        self.options = .default
        self.contentMode = .fill
    }
    
    /// URL 문자열로 초기화
    public init(urlString: String?) {
        self.source = .urlString(urlString)
        self.options = .default
        self.contentMode = .fill
    }
    
    // MARK: - View 구현
    
    public var body: some View {
        ZStack {
            // 이미지가 로드된 경우 표시
            if let image = binder.loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
            }
            // 로딩 중이거나 로드되지 않은 경우 플레이스홀더 표시
            else if !binder.loaded || binder.loadedImage == nil {
                if let placeholder = placeholder {
                    placeholder
                }
            }
        }
        .clipped() // 이미지가 경계를 넘지 않도록 클리핑
        .onAppear {
            // 뷰가 나타날 때 이미지 로딩 시작
            startLoading()
        }
        .onDisappear {
            // 옵션에 따라 뷰가 사라질 때 로딩 취소
            if options.cancelOnDisappear {
                Task { await binder.cancel() }
            }
        }
    }
    
    private func startLoading() {
        // 이미 로딩 중이거나 성공한 경우 스킵
        if binder.loadingOrSucceeded {
            return
        }
        
        let url: URL? = {
            switch source {
            case .url(let url):
                return url
            case .urlString(let string):
                if let string = string {
                    return URL(string: string)
                }
                return nil
            }
        }()
        
        // 비동기 로딩 시작
        Task {
            await binder.start(url: url, options: options)
            
            // 결과 처리
            if let image = binder.loadedImage, let url = url {
                // 이미지 변환이 필요한 경우
                if options.transition != .none {
                    binder.animating = true
                    withAnimation(Animation.linear(duration: transitionDuration(for: options.transition))) {
                        binder.animating = false
                    }
                }
                
                // 성공 콜백 호출
                let result = ImageLoadingResult(image: image, url: url, originalData: Data())
                onSuccess?(result)
            } else if url != nil {
                // 실패 콜백 호출
                onFailure?(NeoImageError.responseError(reason: .invalidImageData))
            }
        }
    }
    
    private func transitionDuration(for transition: ImageTransition) -> TimeInterval {
        switch transition {
        case .none:
            return 0
        case .fade(let duration):
            return duration
        case .flip(let duration):
            return duration
        }
    }
    
    // MARK: - 모디파이어
    
    /// 플레이스홀더 이미지 설정
    public func placeholder<Content: View>(_ content: @escaping () -> Content) -> NeoImage {
        var result = self
        result.placeholder = AnyView(content())
        return result
    }
    
    /// 옵션 설정
    public func options(_ options: NeoImageOptions) -> NeoImage {
        var result = self
        result.options = options
        return result
    }
    
    /// 이미지 로딩 성공 시 호출될 콜백
    public func onSuccess(_ action: @escaping (ImageLoadingResult) -> Void) -> NeoImage {
        var result = self
        result.onSuccess = action
        return result
    }
    
    /// 이미지 로딩 실패 시 호출될 콜백
    public func onFailure(_ action: @escaping (Error) -> Void) -> NeoImage {
        var result = self
        result.onFailure = action
        return result
    }
    
    /// 페이드 트랜지션 설정
    public func fade(duration: TimeInterval = 0.3) -> NeoImage {
        var result = self
        result.options = NeoImageOptions(
            transition: .fade(duration),
            cacheExpiration: result.options.cacheExpiration
        )
        return result
    }
    
    /// 콘텐츠 모드 설정 (fill/fit)
    public func contentMode(_ contentMode: SwiftUI.ContentMode) -> NeoImage {
        var result = self
        result.contentMode = contentMode
        return result
    }
    
    /// 뷰가 사라질 때 다운로드 취소 여부 설정
    public func cancelOnDisappear(_ cancel: Bool) -> NeoImage {
        var result = self
        var newOptions = result.options
        newOptions.cancelOnDisappear = cancel
        result.options = newOptions
        return result
    }
}

// MARK: - View Extensions for NeoImage

/// NeoImage 생성을 위한 편의 확장
public extension View {
    /// URL로부터 NeoImage를 생성하는 모디파이어
    func neoImage(url: URL?, placeholder: AnyView? = nil, options: NeoImageOptions = .default) -> some View {
        let neoImage = NeoImage(url: url)
            .options(options)
        
        if let placeholder = placeholder {
            return neoImage.placeholder { placeholder }
        }
        
        return neoImage
    }
    
    /// URL 문자열로부터 NeoImage를 생성하는 모디파이어
    func neoImage(urlString: String?, placeholder: AnyView? = nil, options: NeoImageOptions = .default) -> some View {
        let neoImage = NeoImage(urlString: urlString)
            .options(options)
        
        if let placeholder = placeholder {
            return neoImage.placeholder { placeholder }
        }
        
        return neoImage
    }
}
