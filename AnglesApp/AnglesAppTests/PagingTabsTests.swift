import CoreGraphics
import Testing
@testable import Angles

struct PagingTabsTests {
    @Test func restingOnTheFirstPage() {
        #expect(PagingTrack.pageIndex(contentMinX: 0, pageWidth: 390, pageCount: 2) == 0)
        #expect(PagingTrack.nearestPage(0, pageCount: 2) == 0)
    }

    @Test func halfwayFollowsTheFinger() {
        let index = PagingTrack.pageIndex(contentMinX: -195, pageWidth: 390, pageCount: 2)
        #expect(abs(index - 0.5) < 0.000_001)
        #expect(PagingTrack.nearestPage(index, pageCount: 2) == 1)
    }

    @Test func aFullPageLandsOnTheNextTab() {
        #expect(PagingTrack.pageIndex(contentMinX: -390, pageWidth: 390, pageCount: 2) == 1)
        #expect(PagingTrack.nearestPage(1, pageCount: 2) == 1)
    }

    @Test func rubberBandStaysOnTheRow() {
        #expect(PagingTrack.pageIndex(contentMinX: 40, pageWidth: 390, pageCount: 2) == 0)
        #expect(PagingTrack.pageIndex(contentMinX: -900, pageWidth: 390, pageCount: 2) == 1)
    }

    @Test func missingWidthStaysPut() {
        #expect(PagingTrack.pageIndex(contentMinX: -100, pageWidth: 0, pageCount: 2) == 0)
        #expect(PagingTrack.pageIndex(contentMinX: -100, pageWidth: 390, pageCount: 1) == 0)
        #expect(PagingTrack.nearestPage(3, pageCount: 0) == 0)
        #expect(PagingTrack.nearestPage(-1, pageCount: 2) == 0)
        #expect(PagingTrack.nearestPage(4.2, pageCount: 2) == 1)
    }

    @Test func justBeforeHalfwayKeepsTheCurrentTab() {
        #expect(PagingTrack.nearestPage(0.49, pageCount: 2) == 0)
    }

    @Test func aPinnedTapIgnoresAStaleFirstPage() {
        let track = PagingTrackModel()
        var settled: [Int] = []
        track.activate(1)
        #expect(track.activeIndex == 1)
        track.note(contentMinX: 0, pageWidth: 390, pageCount: 2) { settled.append($0) }
        #expect(track.activeIndex == 1)
        #expect(settled.isEmpty)
    }

    @Test func landingOnThePinnedPageClearsThePinAndMaySettle() {
        let track = PagingTrackModel()
        var settled: [Int] = []
        track.activate(1)
        track.note(contentMinX: -390, pageWidth: 390, pageCount: 2) { settled.append($0) }
        #expect(track.activeIndex == 1)
        #expect(settled == [1])
    }

    @Test func resetToTheSecondPageDoesNotSettleBackToZero() {
        let track = PagingTrackModel()
        var settled: [Int] = []
        track.reset(to: 1)
        #expect(track.activeIndex == 1)
        track.note(contentMinX: 0, pageWidth: 390, pageCount: 2) { settled.append($0) }
        #expect(track.activeIndex == 1)
        #expect(settled.isEmpty)
    }
}
