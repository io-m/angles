import Foundation
import Observation
import Testing
@testable import Angles

/// Serves `/feed` and `/cards` from whatever the running test last set.
private final class HomeStubURLProtocol: URLProtocol {
    struct Route {
        var feed: [[String: Any]] = []
        var arrivals: [[String: Any]] = []
        var library: [[String: Any]] = []
        /// When set, `/cards` answers only after the test signals it.
        var libraryGate: DispatchSemaphore?
    }

    nonisolated(unsafe) static var route = Route()
    nonisolated(unsafe) static var servedArrivals = false
    private static let lock = NSLock()

    static func update(_ body: (inout Route) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&route)
    }

    private static func snapshot() -> Route {
        lock.lock()
        defer { lock.unlock() }
        return route
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else {
            return
        }
        let route = Self.snapshot()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let cards: [[String: Any]]
        var gate: DispatchSemaphore?
        switch url.path {
        case "/feed" where query.contains { $0.name == "after" }:
            cards = route.arrivals
            Self.lock.lock()
            Self.servedArrivals = true
            Self.lock.unlock()
        case "/feed":
            cards = route.feed
        case "/cards":
            cards = route.library
            gate = route.libraryGate
        default:
            cards = []
        }
        let body = try! JSONSerialization.data(withJSONObject: ["cards": cards])
        let respond = { [self] in
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if let gate {
            DispatchQueue.global().async {
                gate.wait()
                respond()
            }
        } else {
            respond()
        }
    }

    static func didServeArrivals() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return servedArrivals
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        route = Route()
        servedArrivals = false
    }
}

private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private let ownerID = UUID(uuidString: "00000000-0000-4000-8000-0000000000aa")!
private let strangerID = UUID(uuidString: "00000000-0000-4000-8000-0000000000bb")!

private func cardJSON(
    _ id: UUID,
    day: Int,
    isOwner: Bool,
    isPublic: Bool = true,
    moderationHidden: Bool = false,
    spotlight: String = "stoic"
) -> [String: Any] {
    var json: [String: Any] = [
        "id": id.uuidString.lowercased(),
        "thought": "A thought.",
        "category": "work",
        "results": ["stoic", "hopeful", "witty", "tough"].map { style in
            ["style": style, "reframe": "An angle.", "isHearted": false]
        },
        "spotlightStyle": spotlight,
        "isPublic": isPublic,
        "createdAt": String(format: "2026-10-%02dT10:00:00.000Z", day),
        "isOwner": isOwner,
        "author": [
            "id": (isOwner ? ownerID : strangerID).uuidString.lowercased(),
            "initials": isOwner ? "JM" : "AL",
            "following": false,
        ],
    ]
    if moderationHidden {
        json["moderationHidden"] = true
    }
    return json
}

@MainActor
private func makeViewModel() -> HomeViewModel {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HomeStubURLProtocol.self]
    let client = APIClient(baseURL: URL(string: "https://angles.test"), session: URLSession(configuration: configuration))
    return HomeViewModel(cardsService: CardsService(client: client))
}

@Suite("Home owner visibility", .serialized)
@MainActor
struct HomeOwnerVisibilityTests {
    let newer = UUID()
    let mine = UUID()
    let older = UUID()

    init() {
        HomeStubURLProtocol.reset()
    }

    private func feed() -> [[String: Any]] {
        [
            cardJSON(newer, day: 5, isOwner: false),
            cardJSON(mine, day: 3, isOwner: true),
            cardJSON(older, day: 1, isOwner: false),
        ]
    }

    private func library(isPublic: Bool, hidden: Bool = false) -> [[String: Any]] {
        [cardJSON(mine, day: 3, isOwner: true, isPublic: isPublic, moderationHidden: hidden)]
    }

    private func loaded() async -> HomeViewModel {
        HomeStubURLProtocol.update {
            $0.feed = feed()
            $0.library = library(isPublic: true)
        }
        let viewModel = makeViewModel()
        await viewModel.loadFeedIfNeeded()
        await viewModel.loadLibrary()
        return viewModel
    }

    @Test("operator hide, pull, operator publish, pull: the card is back once, without a restart")
    func hideThenPublishSequence() async {
        let viewModel = await loaded()
        #expect(viewModel.homeCards(for: .all).map(\.id) == [newer, mine, older])

        HomeStubURLProtocol.update { $0.library = library(isPublic: false, hidden: true) }
        await viewModel.refreshFeed(.all)
        #expect(viewModel.homeCards(for: .all).map(\.id) == [newer, older])
        #expect(viewModel.feedBoard.record(mine) == nil)
        #expect(viewModel.feedBoard.anchors[mine] == nil)
        let profileCard = viewModel.cards.first { $0.id == mine }
        #expect(profileCard?.moderationNoticeText == HomeCard.moderationHiddenMessage)
        #expect(profileCard?.allowsOwnerVisibilityChange == false)

        await viewModel.refreshFeed(.all)
        #expect(viewModel.homeCards(for: .all).map(\.id) == [newer, older])

        HomeStubURLProtocol.update { $0.library = library(isPublic: true) }
        await viewModel.refreshFeed(.all)
        #expect(viewModel.homeCards(for: .all).map(\.id) == [newer, mine, older])
        #expect(viewModel.feedBoard.anchors[mine] != nil)
        #expect(viewModel.cards.first { $0.id == mine }?.moderationNoticeText == nil)

        let settled = viewModel.homeCards(for: .all)
        await viewModel.refreshFeed(.all)
        #expect(viewModel.homeCards(for: .all) == settled)
        #expect(viewModel.homeCards(for: .all).filter { $0.id == mine }.count == 1)
    }

    @Test("a pull with nothing new leaves Home records and the library untouched")
    func noChangePullIsANoOp() async {
        let viewModel = await loaded()
        let home = viewModel.homeCards(for: .all)
        let records = viewModel.feedBoard.records

        let libraryChanged = ChangeFlag()
        withObservationTracking {
            _ = viewModel.cards
        } onChange: {
            libraryChanged.set()
        }
        await viewModel.refreshFeed(.all)

        #expect(viewModel.homeCards(for: .all) == home)
        #expect(viewModel.feedBoard.records == records)
        #expect(!libraryChanged.isSet)
    }

    @Test("arrivals and a visibility change land together, not before the library read")
    func pullCommitsOnce() async throws {
        let viewModel = await loaded()
        let arrival = UUID()
        let gate = DispatchSemaphore(value: 0)
        HomeStubURLProtocol.update {
            $0.arrivals = [cardJSON(arrival, day: 7, isOwner: false)]
            $0.library = library(isPublic: false, hidden: true)
            $0.libraryGate = gate
        }

        let pull = Task { await viewModel.refreshFeed(.all) }
        for _ in 0 ..< 200 where !HomeStubURLProtocol.didServeArrivals() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(HomeStubURLProtocol.didServeArrivals())
        try await Task.sleep(for: .milliseconds(150))
        #expect(viewModel.homeCards(for: .all).map(\.id) == [newer, mine, older])

        gate.signal()
        await pull.value
        #expect(viewModel.homeCards(for: .all).map(\.id) == [arrival, newer, older])
    }
}
