import SwiftUI
import Testing
@testable import Angles

@MainActor
@Suite("Style tab pager state")
struct StyleTabPagerStateTests {
    private let tabs = Array(HomeFeedTab.allCases)

    @Test("starts settled on its first tab")
    func startsSettled() {
        let state = StyleTabPagerState<HomeFeedTab>(initialTab: .all)
        #expect(state.snapshot == StyleTabPagerSnapshot(fromIndex: 0, toIndex: 0, pageProgress: 0))
        #expect(state.requestedTab == .all)
        #expect(state.expansion(at: 0) == 1)
        #expect(state.expansion(at: 1) == 0)
    }

    @Test("a pick with no animation settles at once")
    func unanimatedPickSettles() {
        let state = StyleTabPagerState<HomeFeedTab>(initialTab: .all)
        let serial = state.requestSerial
        state.requestPage(tabs[3], animation: nil)
        #expect(state.requestedTab == tabs[3])
        #expect(state.requestSerial != serial)
        #expect(state.snapshot == StyleTabPagerSnapshot(fromIndex: 3, toIndex: 3, pageProgress: 0))
    }

    @Test("an animated pick targets the new tab, fading or already settled")
    func animatedPickTargets() {
        let state = StyleTabPagerState<HomeFeedTab>(initialTab: .all)
        state.requestPage(tabs[2])
        #expect(state.requestedTab == tabs[2])
        #expect(state.snapshot.toIndex == 2)
        // With no screen to render, the fade may complete at once; either way the old and
        // new tab together always account for the whole chip.
        #expect(state.expansion(at: 0) + state.expansion(at: 2) == 1)
    }

    @Test("a quick second pick wins, never stranding the first")
    func secondPickWins() {
        let state = StyleTabPagerState<HomeFeedTab>(initialTab: .all)
        state.requestPage(tabs[2])
        state.requestPage(tabs[4])
        #expect(state.requestedTab == tabs[4])
        #expect(state.snapshot.toIndex == 4)
        state.requestPage(tabs[1], animation: nil)
        #expect(state.snapshot == StyleTabPagerSnapshot(fromIndex: 1, toIndex: 1, pageProgress: 0))
    }

    @Test("picking the page already showing does not start a fade")
    func samePageDoesNotFade() {
        let state = StyleTabPagerState<HomeFeedTab>(initialTab: .all)
        state.requestPage(.all)
        #expect(state.snapshot == StyleTabPagerSnapshot(fromIndex: 0, toIndex: 0, pageProgress: 0))
    }

    @Test("expansion is zero for an index that does not exist")
    func outOfRangeExpansion() {
        let state = StyleTabPagerState<HomeFeedTab>(initialTab: .all)
        #expect(state.expansion(at: -1) == 0)
        #expect(state.expansion(at: 99) == 0)
    }
}
