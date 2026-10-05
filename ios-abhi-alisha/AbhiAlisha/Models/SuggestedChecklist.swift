import Foundation

/// A starter list for the couple's checklist, in the order it should read.
nonisolated enum SuggestedChecklist {
    static let beforeYouFly = "Before you fly"
    static let weekOf = "Week of"
    static let dayOf = "Day of"

    static let drafts: [ChecklistDraft] = [
        (beforeYouFly, "Confirm final guest count with AVA's wedding coordinator"),
        (beforeYouFly, "Send the seating chart to the resort"),
        (beforeYouFly, "Share shot lists with the photographer and videographer"),
        (beforeYouFly, "Confirm DJ and dhol timings for the Sangeet and Jaggo"),
        (beforeYouFly, "Pack outfits, jewellery and accessories by event"),
        (weekOf, "Welcome bags delivered to guest rooms"),
        (weekOf, "Confirm the Granthi and setup for the Anand Karaj"),
        (weekOf, "Confirm the Pandit and mandap for the Hindu ceremony"),
        (weekOf, "Milni garlands ready"),
        (weekOf, "Haldi supplies and towels ready"),
        (weekOf, "Choora and kaleere ready"),
        (weekOf, "Send shuttle times to guests"),
        (dayOf, "Rings and ceremony items with a trusted person"),
        (dayOf, "Emergency kit: safety pins, fashion tape, stain remover"),
        (dayOf, "Vendor tips in labelled envelopes")
    ].map { category, title in
        ChecklistDraft(title: title, notes: nil, category: category, dueDate: nil)
    }
}
