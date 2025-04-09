# Kingfisher_With_SwiftConcurrency
Swift의 최신 동시성 모델(structured concurrency)을 활용한 현대적인 이미지 캐싱 및 로딩 라이브러리입니다. 
Kingfisher를 분석하여 핵심 기능을 가져오면서도 Swift의 async/await, actor 모델을 적용하여 간결하고 안전한 코드를 제공하고자 했습니다.

## 주요 기능
✅ Swift 동시성 모델(async/await, actor) 지원
✅ 메모리 및 디스크 캐싱
✅ 우선순위 기반 이미지 캐싱 전략
✅ UIKit과 SwiftUI 지원
✅ 진행 상황 및 완료 콜백
✅ 이미지 다운로드 취소 지원

## 설치 방법
#### Swift Package Manager
```swift
dependencies: [
    .package(url: "https://github.com/yourusername/NeoImage.git", from: "1.0.0")
]
```

## 사용 방법
UIKit에서 사용
```swift
// 이미지 로드
imageView.neo.setImage(with:"https://example.com/image.jpg")

// 우선순위 이미지로 로드
imageView.neo.setImage(with: "https://example.com/image.jpg", isPriority: true)
```

## 우선순위 캐시 전략
NeoImage는 자주 접근하는 이미지를 효율적으로 로드하기 위한 우선순위 캐싱 전략을 제공합니다. 이 전략은 특히 사용자가 자주 방문하는 화면의 이미지를 빠르게 로딩해야 하는 상황에서 유용합니다.

### 작동 방식

1. 우선순위 이미지 표시: isPriority 플래그를 true로 설정하여 특정 이미지를 우선순위 이미지로 지정합니다.
2. 프리로딩: 앱 시작 시 우선순위 이미지를 디스크 캐시에서 메모리 캐시로 자동 프리로드합니다.
3. 메모리 관리: 메모리 부족 상황에서도 우선순위 이미지는 메모리에 유지됩니다.

swift// 이미지에 우선순위 부여
ImageCache.shared.store(data, for: "priority_" + hashedKey)

// 앱 시작 시 우선순위 이미지 프리로드
func preloadPriorityToMemory() async {
    // 'priority_' 접두사가 있는 모든 이미지 파일 찾기
    let prefixedFiles = fileURLs.filter { $0.lastPathComponent.hasPrefix("priority_") }
    
    // 메모리에 프리로드
    for fileURL in prefixedFiles {
        if let data = try? Data(contentsOf: fileURL) {
            await ImageCache.shared.memoryStorage.store(value: data, for: hashedKey)
        }
    }
}
### 성능 이점
우선순위 캐싱 전략은 주요 화면의 이미지 로딩 시간을 최대 88.89% 단축시킬 수 있습니다. 테스트 결과, 자주 방문하는 화면에서의 이미지 로드 시간이 평균 0.018초에서 0.002초로 감소했습니다.


## Swift 구조적 동시성 도입을 위한 변경 사항
Kingfisher에서 NeoImage로의 마이그레이션 과정에서 다음과 같은 주요 변경이 이루어졌습니다:

1. 클래스를 actor로 변경
메모리와 디스크 캐시 관리를 위한 클래스는 actor로 변환되어 스레드 안전성을 보장합니다:
```swift
// Kingfisher 방식: 클래스 + 락 메커니즘
class MemoryStorage<T: DataTransformable>: @unchecked Sendable{
    private let storage = NSCache<NSString, StorageObject<T>>()
    private let lock = NSLock()
    
    func store(value: T, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        // 저장 로직...
    }
}

// NeoImage 방식: actor
public actor MemoryStorage<T: DataTransformable> {
    private let storage = NSCache<NSString, StorageObject<T>>()
    
    func store(value: T, for key: String) {
        // 저장 로직 (락 필요 없음)...
    }
}
```

2. 비동기 API 재설계
콜백 기반 API를 async/await 패턴으로 변환했습니다:
```swift
// Kingfisher 방식: 콜백 기반
func retrieveImage(
    with key: String,
    completionHandler: ((Result<T, Error>) -> Void)? = nil
) {
    // 비동기 작업 후 콜백 호출
    // ...
    completionHandler?(.success(image))
}

// NeoImage 방식: async/await
func retrieveImage(with key: String) async throws -> T {
    // 비동기 작업 수행
    // ...
    return image
}
```

## Kingfisher에서 구조적 동시성을 도입하지 않은 이유
Kingfisher가 Swift의 최신 동시성 모델을 완전히 도입하지 않은 데에는 몇 가지 타당한 이유가 있었습니다.

1. 작업 순서 보장의 차이
Kingfisher는 파일 시스템 작업과 같이 순서가 중요한 작업에 직렬 DispatchQueue를 사용합니다. actor는 상호 배제(mutual exclusion)를 보장하지만, 항상 FIFO(First-In-First-Out) 방식으로 작업을 처리하지는 않습니다.
예를 들어, 다음과 같은 이미지 작업 시퀀스에서:

이미지 A 저장
이미지 A 업데이트
이미지 A 읽기

actor를 사용할 경우 우선순위와 재진입성(reentrancy)으로 인해 항상 1-2-3 순서로 실행된다고 보장할 수 없습니다. 반면 직렬 DispatchQueue는 이 순서를 엄격히 유지합니다.

2. 성능 고려사항
async/await 패턴은 컨텍스트 전환 오버헤드를 발생시킵니다. 메모리에 캐싱된 이미지에 접근하는 것과 같은 간단한 동기 작업의 경우, async/await를 사용하면 오히려 소요 시간이 증가할 수 있습니다.
테스트 결과, 메모리 캐시에서 이미지를 로드하는 데 다음과 같은 성능 차이가 관찰되었습니다:

async/await 사용 시: 약 0.034초
콜백 방식 사용 시: 약 0.003초

3. Objective-C 상호 운용성
URLSessionDelegate와 같은 Objective-C 기반 API는 Swift의 비동기 모델과 완전히 호환되지 않습니다. 이러한 API를 사용하는 코드는 별도의 변환 작업 없이 구조적 동시성으로 마이그레이션하기 어렵습니다.
