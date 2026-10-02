import Foundation
import StoreKit
import Testing
@testable import Angles

struct SafetyContractTests {
    private let usage = #"{"creditsUsed":0,"remaining":599,"granted":600,"resetsAt":null,"warning":"normal","creditCost":1}"#

    private func decode(_ json: String) throws -> ReframeResponse {
        try JSONDecoder().decode(ReframeResponse.self, from: Data(json.utf8))
    }

    @Test func unknownSafetyLabelIsTreatedAsSelfHarm() throws {
        for raw in ["suicide", "crisis", "self-harm", "SELF_HARM", "something_new"] {
            let flag = try JSONDecoder().decode(SafetyFlag.self, from: Data("\"\(raw)\"".utf8))
            #expect(flag == .selfHarm, "\(raw)")
            #expect(flag.needsCare)
        }
        let none = try JSONDecoder().decode(SafetyFlag.self, from: Data(#""none""#.utf8))
        #expect(none == .none)
        #expect(!none.needsCare)
    }

    @Test func crisisContinueCarriesTheServersResourceLine() throws {
        let response = try decode(
            #"{"kind":"continue","message":"Please reach a real person.","options":[],"safety":"self_harm","crisisResource":"In the US, call or text 988 any time, or call 911 in an emergency.","usage":\#(usage)}"#
        )
        guard case .continueTurn(_, let options, let safety, let crisisResource, _) = response else {
            Issue.record("Expected a continue turn")
            return
        }
        #expect(options.isEmpty)
        #expect(safety == .selfHarm)
        #expect(crisisResource?.contains("988") == true)
    }

    @Test func ordinaryContinueHasNoResourceLine() throws {
        let response = try decode(
            #"{"kind":"continue","message":"What part stings?","options":["The pause"],"safety":"none","usage":\#(usage)}"#
        )
        guard case .continueTurn(_, _, let safety, let crisisResource, _) = response else {
            Issue.record("Expected a continue turn")
            return
        }
        #expect(safety == .none)
        #expect(crisisResource == nil)
    }

    @Test func fallbackCrisisLineNamesNoNumber() {
        #expect(SafetyFlag.unknownRegionCrisisLine.rangeOfCharacter(from: .decimalDigits) == nil)
    }

    @Test func deviceRegionIsTwoLetterUppercaseOrNothing() {
        #expect(ReframeService.deviceRegion(Locale(identifier: "en_US")) == "US")
        #expect(ReframeService.deviceRegion(Locale(identifier: "hr_HR")) == "HR")
        #expect(ReframeService.deviceRegion(Locale(identifier: "es_419")) == nil)
        #expect(ReframeService.deviceRegion(Locale(identifier: "en")) == nil)
    }

    @Test func requestSendsRegionOnlyWhenKnown() throws {
        let withRegion = ReframeRequest(text: "t", followUps: [], region: "DK")
        let without = ReframeRequest(text: "t", followUps: [], region: nil)
        let encodedWith = String(decoding: try JSONEncoder().encode(withRegion), as: UTF8.self)
        let encodedWithout = String(decoding: try JSONEncoder().encode(without), as: UTF8.self)
        #expect(encodedWith.contains(#""region":"DK""#))
        #expect(!encodedWithout.contains("region"))
        #expect(!encodedWith.contains("model"))
        #expect(!encodedWith.contains("styles"))
    }

    @Test func recookEchoesTheSignedCookAndThePreviousAnswer() throws {
        let metaJSON = #"{"category":"work","tags":["interview"],"intensity":3,"timeframe":"past","emotions":["anxious"],"distortions":["mind_reading"],"safety":"none","inputLanguage":"en","skippedStyles":[],"matching":{"category":"work","tags":["interview"],"intensityBand":"mid"}}"#
        let meta = try JSONDecoder().decode(ReframeMeta.self, from: Data(metaJSON.utf8))
        let body = RecookRequestBody(
            recook: RecookRequest(
                style: .toughLove,
                cook: RecookSource(thought: "I froze.", thoughtOriginal: nil, meta: meta, model: "gpt-4.1-mini", signature: "c"),
                previous: RecookPrevious(reframe: "It passed.", signature: "r")
            ),
            region: "HR"
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        let recook = object?["recook"] as? [String: Any]
        let cook = recook?["cook"] as? [String: Any]
        #expect(object?["region"] as? String == "HR")
        #expect(object?["text"] == nil)
        #expect(recook?["style"] as? String == "tough_love")
        #expect(cook?["thought"] as? String == "I froze.")
        #expect(cook?["thoughtOriginal"] == nil)
        #expect(cook?["model"] as? String == "gpt-4.1-mini")
        #expect(cook?["signature"] as? String == "c")
        #expect((cook?["meta"] as? [String: Any])?["distortions"] as? [String] == ["mind_reading"])
        #expect((recook?["previous"] as? [String: Any])?["signature"] as? String == "r")
    }

    @Test func readyCarriesTheModelTheServerRoutedTo() throws {
        let meta = #"{"category":"work","tags":[],"intensity":3,"timeframe":"past","emotions":[],"safety":"none","inputLanguage":"en","skippedStyles":[],"matching":{"category":"work","tags":[],"intensityBand":"mid"}}"#
        let response = try decode(
            #"{"kind":"ready","thought":"I froze.","results":[{"style":"stoic","reframe":"It passed.","signature":"r"}],"meta":\#(meta),"model":"gpt-4.1-mini","signature":"c","usage":\#(usage)}"#
        )
        guard case .ready(_, _, let results, _, let model, let signature, _) = response else {
            Issue.record("Expected a ready cook")
            return
        }
        #expect(model == "gpt-4.1-mini")
        #expect(signature == "c")
        #expect(results.count == 1)
    }

    @Test func bothSignedVersionsOfAnAnswerEchoOnSaveAndRecook() throws {
        let json = #"{"style":"stoic","reframe":"It passed.","reframeOriginal":"Prošlo je.","signature":"r"}"#
        let signed = try JSONDecoder().decode(SignedReframeResult.self, from: Data(json.utf8))
        #expect(signed.result.reframeOriginal == "Prošlo je.")
        let echoed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(signed)) as? [String: Any]
        #expect(echoed?["reframeOriginal"] as? String == "Prošlo je.")
        #expect(echoed?["signature"] as? String == "r")

        let english = try JSONDecoder().decode(
            SignedReframeResult.self,
            from: Data(#"{"style":"stoic","reframe":"It passed.","signature":"r"}"#.utf8)
        )
        let englishEcho = String(decoding: try JSONEncoder().encode(english), as: UTF8.self)
        #expect(!englishEcho.contains("reframeOriginal"))

        let previous = RecookPrevious(reframe: "It passed.", reframeOriginal: "Prošlo je.", signature: "r")
        let encodedPrevious = String(decoding: try JSONEncoder().encode(previous), as: UTF8.self)
        #expect(encodedPrevious.contains(#""reframeOriginal":"Prošlo je.""#))
    }

    @Test func storedAnswerCarriesTheAuthorsOwnLanguage() throws {
        let json = #"{"style":"stoic","reframe":"It passed.","reframeOriginal":"Prošlo je.","isFavorite":false}"#
        let stored = try JSONDecoder().decode(StoredReframeResult.self, from: Data(json.utf8))
        #expect(stored.result == ReframeResult(style: .stoic, reframe: "It passed.", reframeOriginal: "Prošlo je."))
    }

    @Test func signedDistortionsEchoUnchangedEvenWhenUnknown() throws {
        let json = #"{"category":"work","tags":[],"intensity":3,"timeframe":"past","emotions":[],"distortions":["mind_reading","a_future_trap"],"safety":"none","inputLanguage":"en","skippedStyles":[],"matching":{"category":"work","tags":[],"intensityBand":"mid"}}"#
        let meta = try JSONDecoder().decode(ReframeMeta.self, from: Data(json.utf8))
        #expect(meta.distortions == ["mind_reading", "a_future_trap"])
        let echoed = String(decoding: try JSONEncoder().encode(meta), as: UTF8.self)
        #expect(echoed.contains(#""distortions":["mind_reading","a_future_trap"]"#))
    }
}

struct ReplayContractTests {
    @Test func replayKeyIsThirtyTwoBytesOfUnpaddedBase64URL() {
        let key = ReframeAttempt.newReplayKey()
        #expect(key.count == 43)
        #expect(key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })

        var base64 = key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += "="
        #expect(Data(base64Encoded: base64)?.count == 32)
    }

    @Test func everyAttemptGetsItsOwnPair() {
        let first = ReframeAttempt()
        let second = ReframeAttempt()
        #expect(first.id != second.id)
        #expect(first.replayKey != second.replayKey)
    }
}

struct GraceOnlyAccessTests {
    @Test func onlySubscribedAndGraceUnlock() {
        #expect(StoreKitManager.statusUnlocks(.subscribed))
        #expect(StoreKitManager.statusUnlocks(.inGracePeriod))
        #expect(!StoreKitManager.statusUnlocks(.inBillingRetryPeriod))
        #expect(!StoreKitManager.statusUnlocks(.expired))
        #expect(!StoreKitManager.statusUnlocks(.revoked))
    }

    @Test func aFailedReadKeepsAnUnlockOnlyOverALapsedReceipt() {
        #expect(StoreKitManager.keepsUnlockAfterEmptyRead(
            statusReadFailed: true, isUnlocked: true, holdsLapsedReceipt: true
        ))
        #expect(!StoreKitManager.keepsUnlockAfterEmptyRead(
            statusReadFailed: false, isUnlocked: true, holdsLapsedReceipt: true
        ))
        #expect(!StoreKitManager.keepsUnlockAfterEmptyRead(
            statusReadFailed: true, isUnlocked: false, holdsLapsedReceipt: true
        ))
        #expect(!StoreKitManager.keepsUnlockAfterEmptyRead(
            statusReadFailed: true, isUnlocked: true, holdsLapsedReceipt: false
        ))
    }
}
