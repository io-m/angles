import Foundation
import Testing
@testable import Angles

/// Answers `/reframe` from a queue and `/cards` with one stored card, and records every body.
private final class ComposeStubURLProtocol: URLProtocol {
    struct Recorded {
        var path: String
        var body: [String: Any]
        var raw: String
    }

    nonisolated(unsafe) static var replies: [String] = []
    nonisolated(unsafe) static var recorded: [Recorded] = []
    private static let lock = NSLock()

    static func reset(replies: [String]) {
        lock.lock()
        defer { lock.unlock() }
        self.replies = replies
        recorded = []
    }

    static func requests(to path: String) -> [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.filter { $0.path == path }
    }

    private static func take(_ path: String, request: URLRequest) -> String {
        lock.lock()
        defer { lock.unlock() }
        let data = bodyData(of: request) ?? Data()
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        recorded.append(Recorded(path: path, body: object, raw: String(decoding: data, as: UTF8.self)))
        if path == "/reframe", !replies.isEmpty {
            return replies.removeFirst()
        }
        return storedCardJSON
    }

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else {
            return
        }
        let body = Self.take(url.path, request: request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private let usageJSON = #"{"creditsUsed":0,"remaining":599,"granted":600,"resetsAt":null,"warning":"normal","creditCost":1,"plan":"membership"}"#
private let metaJSON = #"{"category":"work","tags":[],"intensity":3,"timeframe":"present","emotions":[],"safety":"none","inputLanguage":"en","skippedStyles":[],"matching":{"category":"work","tags":[],"intensityBand":"mid"}}"#
private let storedCardJSON = #"{"id":"00000000-0000-4000-8000-0000000000c1","thought":"A thought.","category":"work","results":[{"style":"stoic","reframe":"An angle.","isHearted":false}],"spotlightStyle":"stoic","isPublic":true,"createdAt":"2026-10-09T10:00:00.000Z","isOwner":true,"author":{"id":"00000000-0000-4000-8000-0000000000aa","initials":"JM","following":false}}"#

/// What the AI says in a finished cook carries a marker, so a test can prove it never goes back.
private func ready(_ tag: String) -> String {
    #"{"kind":"ready","thought":"THOUGHT-\#(tag)","results":[{"style":"stoic","reframe":"AIMARK-\#(tag)","signature":"result-\#(tag)"}],"meta":\#(metaJSON),"model":"m","signature":"cook-\#(tag)","usage":\#(usageJSON)}"#
}

private func question(_ message: String) -> String {
    #"{"kind":"continue","message":"\#(message)","options":[],"safety":"none","usage":\#(usageJSON)}"#
}

@MainActor
private func makeViewModel(replies: [String]) -> HomeViewModel {
    ComposeStubURLProtocol.reset(replies: replies)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ComposeStubURLProtocol.self]
    let client = APIClient(
        baseURL: URL(string: "https://angles.test"),
        session: URLSession(configuration: configuration)
    )
    return HomeViewModel(
        reframeService: ReframeService(client: client),
        cardsService: CardsService(client: client)
    )
}

@MainActor
private func waitFor(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return condition()
}

@MainActor
private func send(_ viewModel: HomeViewModel, _ text: String) {
    viewModel.compose.composeText = text
    viewModel.compose.sendComposer()
}

private func followUps(_ request: ComposeStubURLProtocol.Recorded) -> [[String: String]] {
    (request.body["followUps"] as? [[String: String]]) ?? []
}

@Suite("Compose thread", .serialized)
@MainActor
struct ComposeThreadTests {
    @Test("answered questions travel with the send, and nothing the AI wrote does")
    func answersTravelButNotTheAIsWords() async {
        let viewModel = makeViewModel(
            replies: [question("What worries you most?"), question("Since when?"), ready("one")]
        )

        send(viewModel, "I’m scared AI will take my job")
        #expect(await waitFor { viewModel.compose.openTurn != nil })
        send(viewModel, "Money")
        #expect(await waitFor { viewModel.compose.turns.count == 2 && viewModel.compose.openTurn != nil })
        send(viewModel, "Since spring")
        #expect(await waitFor { viewModel.compose.isCookReady })

        let last = ComposeStubURLProtocol.requests(to: "/reframe").last
        let sent = last.map(followUps) ?? []
        #expect(sent.count == 2)
        #expect(sent.first?["question"] == "What worries you most?")
        #expect(sent.first?["answer"] == "Money")
        #expect(sent.last?["answer"] == "Since spring")
        #expect(last?.body["text"] as? String == "I’m scared AI will take my job")
        let raw = last?.raw ?? ""
        #expect(!raw.isEmpty)
        #expect(!raw.contains("AIMARK"))
    }

    @Test("a quick reply answers the open question")
    func optionAnswersTheQuestion() async {
        let viewModel = makeViewModel(replies: [
            #"{"kind":"continue","message":"What is it about?","options":["Money","Time"],"safety":"none","usage":\#(usageJSON)}"#,
            ready("one"),
        ])

        send(viewModel, "Work is bad")
        #expect(await waitFor { viewModel.compose.openTurn != nil })
        viewModel.compose.chooseOption("Money")
        #expect(await waitFor { viewModel.compose.isCookReady })

        #expect(viewModel.compose.turns.first?.reply == "Money")
        #expect(viewModel.compose.turns.first?.replyWasChip == true)
    }

    @Test("once angles are showing there is one card and no more writing")
    func noWritingAfterAngles() async {
        let viewModel = makeViewModel(replies: [ready("one")])

        send(viewModel, "A thought")
        #expect(await waitFor { viewModel.compose.isCookReady })

        #expect(!viewModel.compose.isComposerVisible)
        viewModel.compose.composeText = "More"
        #expect(!viewModel.compose.canSubmit)
        viewModel.compose.sendComposer()
        #expect(ComposeStubURLProtocol.requests(to: "/reframe").count == 1)
    }

    @Test("Start new clears the thread")
    func startNewClears() async {
        let viewModel = makeViewModel(replies: [ready("one")])
        send(viewModel, "A thought")
        #expect(await waitFor { viewModel.compose.isCookReady })

        viewModel.compose.resetCompose()

        #expect(viewModel.compose.phase == .composing)
        #expect(viewModel.compose.statement.isEmpty)
        #expect(viewModel.compose.turns.isEmpty)
        #expect(viewModel.compose.isComposerVisible)
    }

    @Test("the card saves with its own signature")
    func savesTheCook() async {
        let viewModel = makeViewModel(replies: [ready("one")])
        send(viewModel, "A thought")
        #expect(await waitFor { viewModel.compose.isCookReady })

        viewModel.compose.composeIsPublic = false
        let saved = await viewModel.compose.saveCook()

        #expect(saved != nil)
        let create = ComposeStubURLProtocol.requests(to: "/cards").last
        #expect(create?.body["signature"] as? String == "cook-one")
        #expect(create?.body["isPublic"] as? Bool == false)
        #expect(viewModel.cards.first?.id == saved?.id)
        #expect(!viewModel.compose.isSaving)
    }

    @Test("a cook's usage lands in the shared balance")
    func usageReachesTheHost() async {
        let viewModel = makeViewModel(replies: [ready("one")])
        send(viewModel, "A thought")
        #expect(await waitFor { viewModel.compose.isCookReady })

        #expect(viewModel.usageSummary?.creditsRemaining == 599)
        #expect(viewModel.compose.hasCreditsForCook)
        #expect(viewModel.compose.usageFeedback == nil)
    }

    @Test("a thought past the server's limit is refused here and the words stay in the field")
    func overLongWritingIsRefusedLocally() async {
        let viewModel = makeViewModel(replies: [ready("one")])
        let long = String(repeating: "a", count: ComposeSession.maxThoughtLength + 1)

        send(viewModel, long)

        #expect(viewModel.compose.composeNote != nil)
        #expect(viewModel.compose.composeText == long)
        #expect(viewModel.compose.phase == .composing)
        #expect(ComposeStubURLProtocol.requests(to: "/reframe").isEmpty)

        // Typing clears the note.
        viewModel.compose.composeText = "short"
        #expect(viewModel.compose.composeNote == nil)
    }
}
