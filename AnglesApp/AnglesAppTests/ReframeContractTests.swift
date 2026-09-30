import Foundation
import StoreKit
import Testing
@testable import Angles

struct SafetyContractTests {
    private let usage = #"{"creditsUsed":0,"remaining":599,"granted":600,"resetsAt":null,"warning":"normal","allowedModels":["mistral-small-latest"],"creditCost":1}"#

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
        let withRegion = ReframeRequest(text: "t", followUps: [], styles: nil, model: nil, region: "DK")
        let without = ReframeRequest(text: "t", followUps: [], styles: nil, model: nil, region: nil)
        let encodedWith = String(decoding: try JSONEncoder().encode(withRegion), as: UTF8.self)
        let encodedWithout = String(decoding: try JSONEncoder().encode(without), as: UTF8.self)
        #expect(encodedWith.contains(#""region":"DK""#))
        #expect(!encodedWithout.contains("region"))
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
