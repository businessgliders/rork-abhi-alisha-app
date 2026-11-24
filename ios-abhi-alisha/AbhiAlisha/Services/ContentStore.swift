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

    private let galleryCache = JSONDiskCache(filename: "gallery-photos.json")
    private let categoryCache = JSONDiskCache(filename: "gallery-categories.json")
    private let faqCache = JSONDiskCache(filename: "faqs.json")
    private let familyCache = JSONDiskCache(filename: "family-members.json")
    private let storyCache = JSONDiskCache(filename: "story-timeline.json")
    private let contentCache = JSONDiskCache(filename: "wedding-content.json")
    private let letterCache = JSONDiskCache(filename: "love-letter.json")

    private var didRefresh = false
    private var isRefreshing = false

    init() {
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

    /// Refreshes once per launch, quietly, from the open wedding's content sections.
    func refreshIfNeeded() async {
        guard !didRefresh, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let weddingID = ActiveWedding.id
        do {
            let content = try await MilniAPI.shared.content(weddingID: weddingID)
            guard weddingID == ActiveWedding.id else { return }
            let isSample = ActiveWedding.snapshot.isSampleWedding

            let photos = MilniDecode.list(GalleryPhoto.self, from: content.gallery)
            if !photos.isEmpty || !isSample {
                galleryCache.save(content.gallery)
                apply(gallery: photos)
            }
            let categories = GalleryCategory.active(from: MilniDecode.list(GalleryCategory.self, from: content.categories))
            if !categories.isEmpty || !isSample {
                categoryCache.save(content.categories)
                galleryCategories = categories
            }
            let questions = MilniDecode.list(Faq.self, from: content.faqs)
            if !questions.isEmpty || !isSample {
                faqCache.save(content.faqs)
                faqs = questions
            }
            let members = FamilyMember.active(from: MilniDecode.list(FamilyMember.self, from: content.family))
            if !members.isEmpty || !isSample {
                familyCache.save(content.family)
                familyMembers = members
            }
            let chapters = StoryChapter.timeline(from: MilniDecode.list(StoryChapter.self, from: content.story))
            if !chapters.isEmpty || !isSample {
                storyCache.save(content.story)
                storyChapters = chapters
            }
            let items = WeddingContentItem.active(from: MilniDecode.list(WeddingContentItem.self, from: content.items))
            if !items.isEmpty || !isSample {
                contentCache.save(content.items)
                contentItems = items
            }
            if let letterData = content.letter,
               let letter = LoveLetter.firstActive(from: MilniDecode.list(LoveLetter.self, from: letterData)) {
                letterCache.save(letterData)
                loveLetter = letter
            } else if !isSample {
                letterCache.clear()
                loveLetter = nil
            }
            didRefresh = true
        } catch {
            print("[ContentStore] content refresh failed")
        }
    }

    private func apply(gallery photos: [GalleryPhoto]) {
        heroPhotos = GalleryPhoto.heroSequence(from: photos)
        resortPhotos = GalleryPhoto.resortSequence(from: photos)
        galleryPhotos = GalleryPhoto.gallerySequence(from: photos)
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
