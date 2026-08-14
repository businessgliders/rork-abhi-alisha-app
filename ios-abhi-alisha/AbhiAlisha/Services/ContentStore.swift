import Foundation
import Observation

/// Offline-first store for everything beyond the schedule: hero photographs, the gallery
/// and its categories, resort photographs, the couple's questions, their story, the two
/// families, and their letter to their guests.
///
/// Disk cache renders first, then a quiet background refresh replaces it. A failed
/// refresh never removes what is already on screen.
@Observable
final class ContentStore {
    private(set) var heroPhotos: [GalleryPhoto] = []
    private(set) var resortPhotos: [GalleryPhoto] = []
    private(set) var galleryPhotos: [GalleryPhoto] = []
    private(set) var galleryCategories: [GalleryCategory] = []
    private(set) var faqs: [Faq] = []
    private(set) var familyMembers: [FamilyMember] = []
    private(set) var storyChapters: [StoryChapter] = []
    private(set) var contentItems: [WeddingContentItem] = []
    private(set) var loveLetter: LoveLetter?

    private let api: WeddingAPI
    private let galleryCache = JSONDiskCache(filename: "gallery-photos.json")
    private let categoryCache = JSONDiskCache(filename: "gallery-categories.json")
    private let faqCache = JSONDiskCache(filename: "faqs.json")
    private let familyCache = JSONDiskCache(filename: "family-members.json")
    private let storyCache = JSONDiskCache(filename: "story-timeline.json")
    private let contentCache = JSONDiskCache(filename: "wedding-content.json")
    private let letterCache = JSONDiskCache(filename: "love-letter.json")

    private var didRefresh = false
    private var isRefreshing = false

    init(api: WeddingAPI = .shared) {
        self.api = api
        loadCached()
    }

    private func loadCached() {
        if let photos = galleryCache.load(GalleryPhoto.self) {
            apply(gallery: photos)
        }
        if let categories = categoryCache.load(GalleryCategory.self) {
            galleryCategories = GalleryCategory.active(from: categories)
        }
        if let cachedFaqs = faqCache.load(Faq.self) {
            faqs = cachedFaqs
        }
        if let members = familyCache.load(FamilyMember.self) {
            familyMembers = FamilyMember.active(from: members)
        }
        if let chapters = storyCache.load(StoryChapter.self) {
            storyChapters = StoryChapter.timeline(from: chapters)
        }
        if let items = contentCache.load(WeddingContentItem.self) {
            contentItems = WeddingContentItem.active(from: items)
        }
        if let letters = letterCache.load(LoveLetter.self) {
            loveLetter = LoveLetter.firstActive(from: letters)
        }
    }

    /// Refreshes once per launch, quietly.
    func refreshIfNeeded() async {
        guard !didRefresh, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await loadGallery()
        await loadGalleryCategories()
        await loadFaqs()
        await loadFamily()
        await loadStory()
        await loadContentItems()
        await loadLoveLetter()

        didRefresh = true
    }

    private func apply(gallery photos: [GalleryPhoto]) {
        let sequence = GalleryPhoto.heroSequence(from: photos)
        if !sequence.isEmpty { heroPhotos = sequence }
        resortPhotos = GalleryPhoto.resortSequence(from: photos)
        galleryPhotos = GalleryPhoto.gallerySequence(from: photos)
    }

    private func loadGallery() async {
        do {
            let result = try await api.fetch(GalleryPhoto.self, entity: "GalleryPhoto")
            guard !result.items.isEmpty else { return }
            galleryCache.save(result.raw)
            apply(gallery: result.items)
        } catch {
            print("[ContentStore] gallery refresh failed")
        }
    }

    private func loadGalleryCategories() async {
        do {
            let result = try await api.fetch(GalleryCategory.self, entity: "GalleryCategory")
            let categories = GalleryCategory.active(from: result.items)
            guard !categories.isEmpty else { return }
            categoryCache.save(result.raw)
            galleryCategories = categories
        } catch {
            print("[ContentStore] gallery categories refresh failed")
        }
    }

    private func loadFaqs() async {
        do {
            let result = try await api.fetch(Faq.self, entity: "Faq")
            guard !result.items.isEmpty else { return }
            faqCache.save(result.raw)
            faqs = result.items
        } catch {
            print("[ContentStore] questions refresh failed")
        }
    }

    private func loadFamily() async {
        do {
            let result = try await api.fetch(FamilyMember.self, entity: "FamilyMember")
            let members = FamilyMember.active(from: result.items)
            guard !members.isEmpty else { return }
            familyCache.save(result.raw)
            familyMembers = members
        } catch {
            print("[ContentStore] family refresh failed")
        }
    }

    private func loadStory() async {
        do {
            let result = try await api.fetch(StoryChapter.self, entity: "StoryTimeline")
            let chapters = StoryChapter.timeline(from: result.items)
            guard !chapters.isEmpty else { return }
            storyCache.save(result.raw)
            storyChapters = chapters
        } catch {
            print("[ContentStore] story refresh failed")
        }
    }

    private func loadContentItems() async {
        do {
            let result = try await api.fetch(WeddingContentItem.self, entity: "WeddingContent")
            let items = WeddingContentItem.active(from: result.items)
            guard !items.isEmpty else { return }
            contentCache.save(result.raw)
            contentItems = items
        } catch {
            print("[ContentStore] content refresh failed")
        }
    }

    private func loadLoveLetter() async {
        do {
            let result = try await api.fetch(LoveLetter.self, entity: "LoveLetter")
            guard let letter = LoveLetter.firstActive(from: result.items) else { return }
            letterCache.save(result.raw)
            loveLetter = letter
        } catch {
            print("[ContentStore] letter refresh failed")
        }
    }

    // MARK: - Derived

    func faqs(in section: FaqSection) -> [Faq] {
        Faq.group(faqs, section: section)
    }

    /// Sections that actually have content, in the order they should be read.
    func populatedSections(_ order: [FaqSection]) -> [FaqSection] {
        order.filter { !faqs(in: $0).isEmpty }
    }

    /// Every answered question the couple has published, in reading order.
    func allSectionsInReadingOrder() -> [FaqSection] {
        populatedSections([.important, .payment, .transfer, .cancellation, .resort, .general])
    }

    /// The resort map the couple published on their schedule page.
    var resortMap: WeddingContentItem? {
        contentItems.first { $0.key == "resort_map" && $0.url != nil }
    }

    /// Gallery photographs for one category slug, or all of them when no slug is given.
    func galleryPhotos(in slug: String?) -> [GalleryPhoto] {
        guard let slug else { return galleryPhotos }
        return galleryPhotos.filter { ($0.category ?? "").lowercased() == slug.lowercased() }
    }

    /// Only the categories that actually hold something.
    var populatedGalleryCategories: [GalleryCategory] {
        galleryCategories.filter { category in
            guard let slug = category.slug else { return false }
            return !galleryPhotos(in: slug).isEmpty
        }
    }
}
