import Foundation

public actor MemoryStorage {
    // MARK: - Properties

    /// 캐시는 NSCache로 접근합니다.
    private let storage = NSCache<NSString, StorageObject>()
    private let totalCostLimit: Int
    
    var keys = Set<String>()
    private var cleanTask: Task<Void, Never>? = nil
    
    // MARK: - Lifecycle

    init(totalCostLimit: Int) {
        // 메모리가 사용할 수 있는 공간 상한선 (ImageCache 클래스에서 총 메모리공간의 1/4로 주입하고 있음) 데이터를 아래 private 속성에 주입시킵니다.
        self.totalCostLimit = totalCostLimit
        storage.totalCostLimit = totalCostLimit
        
        NeoLogger.shared.debug("initialized")
        
        Task {
            await setupCleanTask()
        }
    }

    private func setupCleanTask() {
        // Timer 대신 Task로 주기적인 정리 작업 수행
        cleanTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120 * 1_000_000_000)
                
                // 취소 확인
                if Task.isCancelled { break }
                
                // 만료된 항목 제거
                removeExpired()
            }
        }
    }
    
    // MARK: - Functions
    public func removeExpired() {
        for key in keys {
            let nsKey = key as NSString
            guard let object = storage.object(forKey: nsKey) else {
                keys.remove(key)
                continue
            }
            
            if object.isExpired {
                storage.removeObject(forKey: nsKey)
                keys.remove(key)
            }
        }
    }
    
    /// 캐시에 저장
    func store(
        value: Data,
        forKey key: String,
        expiration: StorageExpiration? = nil
    ) {
        let expiration = expiration ?? NeoImageConstants.expiration

        guard !expiration.isExpired else { return }
        
        let object = StorageObject(value as Data , expiration: expiration)
        
        storage.setObject(object, forKey: key as NSString)
        keys.insert(key)
    }

    /// 캐시에서 조회
    func value(forKey key: String, extendingExpiration: ExpirationExtending = .cacheTime) -> Data? {
        guard let object = storage.object(forKey: key as NSString) else {
            return nil
        }
        
        if object.isExpired {
            return nil
        }
        
        object.extendExpiration(extendingExpiration)
        return object.value
    }
    
    /// 캐시에서 제거
    public func remove(forKey key: String) {
        storage.removeObject(forKey: key as NSString)
        keys.remove(key)
    }

    /// Removes all values in this storage.
    public func removeAll() {
        storage.removeAllObjects()
        keys.removeAll()
    }
}

extension MemoryStorage {
    class StorageObject {
        var value: Data
        let expiration: StorageExpiration
        
        private(set) var estimatedExpiration: Date
        
        init(_ value: Data, expiration: StorageExpiration) {
            self.value = value
            self.expiration = expiration
            
            self.estimatedExpiration = expiration.estimatedExpirationSinceNow
        }

        func extendExpiration(_ extendingExpiration: ExpirationExtending = .cacheTime) {
            switch extendingExpiration {
            case .none:
                return
            case .cacheTime:
                self.estimatedExpiration = expiration.estimatedExpirationSinceNow
            case .expirationTime(let expirationTime):
                self.estimatedExpiration = expirationTime.estimatedExpirationSinceNow
            }
        }
        
        var isExpired: Bool {
            return estimatedExpiration.isPast
        }
    }
}
