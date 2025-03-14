import Testing
import UIKit
import NeoImage

@Suite("NeoImage Download Cancellation Tests")
struct NeoImageCancellationTests {
    
    @Test("그리드 스크롤 시 다운로드 취소 테스트")
    func testDownloadCancellationOnScroll() async throws {
        // 테스트 컨텍스트 생성
        let context = await GridScrollTestContext()
        
        ImageCache.shared.clearCache()
        // 초기 이미지 로드 시작
        await context.loadInitialImages()
        
        // 스크롤 시뮬레이션
        await context.simulateScrolling()
        
        // 취소된 이미지 다운로드 검증
        let cancellationStats = await context.getCancellationStats()
        
        print("""
        ======== 다운로드 취소 테스트 결과 ========
        시작된 다운로드: \(cancellationStats.totalStarted)
        완료된 다운로드: \(cancellationStats.totalCompleted)
        취소된 다운로드: \(cancellationStats.totalCancelled)
        취소율: \(String(format: "%.1f", cancellationStats.cancellationRate * 100))%
        =======================================
        """)
        
        // 실제로 일부 다운로드가 취소되었는지 확인
        #expect(cancellationStats.totalCancelled > 0, "스크롤 시 일부 다운로드가 취소되어야 합니다")
        
        // 스크롤 후 새로 보이는 이미지는 로드되었는지 확인
        #expect(await context.areVisibleImagesLoaded(), "스크롤 후 화면에 보이는 이미지가 모두 로드되어야 합니다")
        
        // 정리
        await context.cleanUp()
    }
    
    @Test("이미지뷰 재사용 시 취소 및 새 다운로드 테스트")
    func testCancellationAndRestartOnReuse() async throws {
        // 테스트 컨텍스트 생성
        let context = await GridScrollTestContext()
        
        // 셀 재사용 시뮬레이션
        await context.simulateCellReuse()
        
        // 재사용 통계 가져오기
        let reuseStats = await context.getReuseStats()
        
        print("""
        ======== 재사용 취소 테스트 결과 ========
        기존 URL 다운로드 취소: \(reuseStats.cancellationCount)
        새 URL 다운로드 성공: \(reuseStats.successfulReloads)
        =====================================
        """)
        
        // 이전 작업이 취소되고 새 작업이 시작되었는지 확인
        #expect(reuseStats.cancellationCount > 0, "셀 재사용 시 이전 다운로드가 취소되어야 합니다")
        #expect(reuseStats.successfulReloads > 0, "셀 재사용 시 새 이미지가 로드되어야 합니다")
        
        // 정리
        await context.cleanUp()
    }
    
    @Test("cancelOnDisappear 옵션 테스트")
    func testCancelOnDisappearOption() async throws {
        // 테스트 컨텍스트 생성
        let context = await GridScrollTestContext()
        
        // cancelOnDisappear 옵션 활성화 테스트
        await context.testWithCancelOnDisappear(enabled: true)
        let statsWithOption = await context.getCancellationStats()
        
        // 옵션 비활성화 테스트를 위한 초기화
        await context.resetStats()
        
        // cancelOnDisappear 옵션 비활성화 테스트
        await context.testWithCancelOnDisappear(enabled: false)
        let statsWithoutOption = await context.getCancellationStats()
        
        print("""
        ======== cancelOnDisappear 옵션 테스트 결과 ========
        [옵션 활성화]
        취소된 다운로드: \(statsWithOption.totalCancelled)
        취소율: \(String(format: "%.1f", statsWithOption.cancellationRate * 100))%
        
        [옵션 비활성화]
        취소된 다운로드: \(statsWithoutOption.totalCancelled)
        취소율: \(String(format: "%.1f", statsWithoutOption.cancellationRate * 100))%
        ===============================================
        """)
        
        // cancelOnDisappear 옵션이 있을 때 취소가 더 많이 발생해야 함
        #expect(statsWithOption.totalCancelled > statsWithoutOption.totalCancelled,
              "cancelOnDisappear 옵션이 활성화되면 더 많은 다운로드가 취소되어야 합니다")
        
        // 정리
        await context.cleanUp()
    }
}

/// 그리드 스크롤 테스트를 위한 컨텍스트 클래스
@MainActor
class GridScrollTestContext {
    // 테스트용 이미지 URL 목록 - 고해상도 이미지로 다운로드에 충분한 시간이 걸리도록 함
    let testImageURLs: [URL] = (1...100).map {
        URL(string: "https://picsum.photos/id/\($0)/1200/1200")!
    }
    
    // 테스트 환경 속성
    private var testWindow: UIWindow!
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, URL>!
    private var downloadTracker = DownloadTracker()
    
    // 현재 화면에 보이는 셀 인덱스
    private var visibleItemIndexes: [Int] = []
    
    // 테스트 설정
    private let cellSize = CGSize(width: 120, height: 120)
    private let gridColumns = 3
    private let initialItemCount = 30
    private var downloadOptions = NeoImageOptions()
    
    init() {
        setupTestEnvironment()
    }
    
    /// 테스트 환경 설정
    private func setupTestEnvironment() {
        // 테스트 윈도우 생성
        testWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        testWindow.makeKeyAndVisible()
        
        // 컬렉션 뷰 레이아웃 설정
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = cellSize
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        // 컬렉션 뷰 생성
        collectionView = UICollectionView(frame: testWindow.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .white
        collectionView.register(ImageCollectionViewCell.self, forCellWithReuseIdentifier: "ImageCell")
        testWindow.addSubview(collectionView)
        
        // 데이터 소스 설정
        setupDataSource()
    }
    
    /// 컬렉션 뷰 데이터 소스 설정
    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Int, URL>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, url in
            guard let self = self else { return UICollectionViewCell() }
            
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "ImageCell",
                for: indexPath
            ) as! ImageCollectionViewCell
            
            // 모든 비동기 작업을 Task 내에서 수행
            Task {
                // 이미지 로드 시작 기록
                await self.downloadTracker.startedDownload(for: url)
                
                // 비동기 이미지 로드 호출
                await cell.loadImage(with: url, options: self.downloadOptions) { [weak self] result in
                    guard let self = self else { return }
                    
                    switch result {
                    case .success:
                        Task {
                            print("completedDownload")
                            await self.downloadTracker.completedDownload(for: url)
                        }
                    case .failure:
                        Task {
                            await self.downloadTracker.cancelledDownload(for: url)
                        }
                    }
                }
            }
            
            return cell
        }
        
        // 초기 데이터 로드
        var snapshot = NSDiffableDataSourceSnapshot<Int, URL>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(testImageURLs.prefix(initialItemCount)), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    /// 초기 이미지 로드
    func loadInitialImages() async {
        // 초기 화면에 보이는 셀 인덱스 저장
        visibleItemIndexes = collectionView.indexPathsForVisibleItems.map { $0.item }
        
        // 약간의 지연을 주어 다운로드가 시작되도록 함
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.5초
    }
    
    /// 스크롤 시뮬레이션
    func simulateScrolling() async {
        // 컬렉션 뷰 중간 지점으로 스크롤
        let middleIndex = initialItemCount / 2
        let indexPath = IndexPath(item: middleIndex, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        
        // 스크롤 적용을 위한 지연
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1초
        
        // 마지막 부분으로 스크롤
        let lastIndex = initialItemCount - 1
        let lastIndexPath = IndexPath(item: lastIndex, section: 0)
        collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
        
        // 작업이 취소되고 새 작업이 시작될 시간 부여
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1초
        
        // 현재 화면에 보이는 셀 인덱스 업데이트
        visibleItemIndexes = collectionView.indexPathsForVisibleItems.map { $0.item }
    }
    
    /// 셀 재사용 시뮬레이션 (URL 교체)
    func simulateCellReuse() async {
        // 초기 데이터 로드
        var snapshot = NSDiffableDataSourceSnapshot<Int, URL>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(testImageURLs.prefix(15)), toSection: 0)
        await dataSource.apply(snapshot, animatingDifferences: false)
        
        // 다운로드 시작 대기
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초
        
        // 화면에 보이는 셀의 URL을 다른 URL로 교체
        let visibleCells = collectionView.indexPathsForVisibleItems
        
        for indexPath in visibleCells {
            // 기존 URL 기록
            let originalURL = testImageURLs[indexPath.item]
            await downloadTracker.markForReuse(originalURL)
            
            // 새 스냅샷 생성
            var newSnapshot = dataSource.snapshot()
            
            // 새 URL (원본과 다른 URL)
            let newIndex = indexPath.item + 50
            let newURL = testImageURLs[min(newIndex, 99)]
            
            // 아이템 교체
            newSnapshot.deleteItems([originalURL])
            newSnapshot.appendItems([newURL], toSection: 0)
            
            // 적용
            await dataSource.apply(newSnapshot, animatingDifferences: false)
        }
        
        // 처리 대기
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1초
    }
    
    /// 취소 통계 가져오기
    func getCancellationStats() async -> (totalStarted: Int, totalCompleted: Int, totalCancelled: Int, cancellationRate: Double) {
        let stats = await downloadTracker.getDownloadStats()
        let cancellationRate = stats.totalStarted > 0 ? Double(stats.totalCancelled) / Double(stats.totalStarted) : 0
        return (stats.totalStarted, stats.totalCompleted, stats.totalCancelled, cancellationRate)
    }
    
    /// 재사용 통계 가져오기
    func getReuseStats() async -> (cancellationCount: Int, successfulReloads: Int) {
        return await downloadTracker.getReuseStats()
    }
    
    /// 현재 화면에 보이는 이미지가 모두 로드되었는지 확인
    func areVisibleImagesLoaded() async -> Bool {
        let visibleURLs = visibleItemIndexes.map { testImageURLs[min($0, testImageURLs.count - 1)] }
        return await downloadTracker.areURLsLoaded(visibleURLs)
    }
    
    /// 통계 초기화
    func resetStats() async {
        await downloadTracker.resetStats()
    }
    
    /// cancelOnDisappear 옵션으로 테스트
    func testWithCancelOnDisappear(enabled: Bool) async {
        // 옵션 설정
        downloadOptions = NeoImageOptions()
        downloadOptions.cancelOnDisappear = enabled
        
        // 초기 이미지 로드
        await loadInitialImages()
        
        // 스크롤 시뮬레이션
        await simulateScrolling()
    }
    
    /// 테스트 환경 정리
    func cleanUp() {
        collectionView.removeFromSuperview()
        testWindow.isHidden = true
        testWindow = nil
        collectionView = nil
        dataSource = nil
    }
}

/// 다운로드 추적기
actor DownloadTracker {
    private var startedDownloads: Set<URL> = []
    private var completedDownloads: Set<URL> = []
    private var cancelledDownloads: Set<URL> = []
    private var reusedURLs: Set<URL> = []
    private var reuseCancellations: Int = 0
    private var reuseSuccessfulLoads: Int = 0
    
    func startedDownload(for url: URL) {
        startedDownloads.insert(url)
    }
    
    func completedDownload(for url: URL) {
        completedDownloads.insert(url)
        
        if reusedURLs.contains(url) {
            reuseSuccessfulLoads += 1
        }
    }
    
    func cancelledDownload(for url: URL) {
        cancelledDownloads.insert(url)
        
        if reusedURLs.contains(url) {
            reuseCancellations += 1
        }
    }
    
    func markForReuse(_ url: URL) {
        reusedURLs.insert(url)
    }
    
    func getDownloadStats() -> (totalStarted: Int, totalCompleted: Int, totalCancelled: Int) {
        return (startedDownloads.count, completedDownloads.count, cancelledDownloads.count)
    }
    
    func getReuseStats() -> (cancellationCount: Int, successfulReloads: Int) {
        return (reuseCancellations, reuseSuccessfulLoads)
    }
    
    func areURLsLoaded(_ urls: [URL]) -> Bool {
        return urls.allSatisfy { completedDownloads.contains($0) }
    }
    
    func resetStats() {
        startedDownloads.removeAll()
        completedDownloads.removeAll()
        cancelledDownloads.removeAll()
        reusedURLs.removeAll()
        reuseCancellations = 0
        reuseSuccessfulLoads = 0
    }
}

/// 이미지 컬렉션 뷰 셀
class ImageCollectionViewCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private var task: DownloadTask?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupImageView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupImageView() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.lightGray.withAlphaComponent(0.3)
        
        contentView.addSubview(imageView)
        imageView.frame = contentView.bounds
    }
    
    func loadImage(with url: URL?, options: NeoImageOptions, completion: @Sendable @escaping (Result<ImageLoadingResult, Error>) -> Void) async {
        // 이전 다운로드 작업 취소
        if let currentTask = objc_getAssociatedObject(imageView, NeoImageConstants.associatedKey) as? DownloadTask {
            print("cancelled1")
            await currentTask.cancel()
        }
        
        imageView.neo.setImage(
            with: url,
            placeholder: nil,
            completion: completion
        )
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        print("prepareForReuse")
        // 다운로드 작업 취소 - 비동기 호출이지만 prepareForReuse는 동기적이어야 함
        if let task = objc_getAssociatedObject(imageView, NeoImageConstants.associatedKey) as? DownloadTask {
            Task {
                print("cancelled2")
                await task.cancel()
            }
        }
    }
}
