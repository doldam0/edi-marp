import Testing
import Foundation
@testable import EdiCore

private let sample = """
---
marp: true
theme: noir
paginate: true
---

<!-- _class: lead -->

# One

Hello

---

## Two

```md
---
not a separator
```

---

<!-- _backgroundColor: #123 -->
<!-- color: red -->

Three
---
still three (setext)

"""

@Suite struct DeckParsing {
    @Test func frontmatterAndGlobals() {
        let deck = Deck(parsing: sample)
        #expect(deck.frontmatter == 0..<5)
        #expect(deck.globals["theme"] == "noir")
        #expect(deck.frontmatterValues["paginate"] == "true")
        #expect(deck.theme == "noir")
    }

    @Test func slidesIgnoreFencedRulesAndSetext() {
        let deck = Deck(parsing: sample)
        #expect(deck.slideCount == 3)
        #expect(deck.slides[0].title == "One")
        #expect(deck.slides[1].title == "Two")
        #expect(deck.slides[2].title == "Three")
    }

    @Test func directivesAndInheritance() {
        let deck = Deck(parsing: sample)
        let s0 = deck.slides[0], s2 = deck.slides[2]
        #expect(s0.declared("class", spot: true)?.value == "lead")
        #expect(s0.effective["paginate"] == "true")
        #expect(s0.classes == ["lead"])
        #expect(s2.effective["backgroundColor"] == "#123")
        #expect(s2.effective["color"] == "red")
        #expect(deck.slides[1].effective["class"] == nil)
    }

    @Test func lineMapping() {
        let deck = Deck(parsing: sample)
        let line = deck.lines.firstIndex(of: "Hello")!
        #expect(deck.slideIndex(atLine: line) == 0)
        #expect(deck.lineIndex(atOffset: deck.offset(ofLine: line) + 2) == line)
        #expect(deck.slideIndex(atOffset: deck.lineOffsets.last!) == 2)
        #expect(deck.lineOffsets.last == (sample as NSString).length)
    }

    @Test func emptyAndMinimal() {
        let empty = Deck(parsing: "")
        #expect(empty.slideCount == 1)
        #expect(empty.slides[0].isBlank)
        let one = Deck(parsing: "# A")
        #expect(one.slides[0].title == "A")
        #expect(one.slides[0].trimmedRange == NSRange(location: 0, length: 3))
    }

    @Test func wordCountIsCJKAware() {
        #expect(Deck(parsing: "hello world 안녕 세상").wordCount == 6)
    }
}

@Suite struct TransformTests {
    private func roundTrip(_ src: String, _ edits: (Deck) -> [Edit]) -> String {
        let deck = Deck(parsing: src)
        return edits(deck).apply(to: src)
    }

    @Test func globalDirectiveSetAndClear() {
        var s = roundTrip(sample) { Transforms.setGlobalDirective($0, key: "theme", value: "paper") }
        #expect(s.contains("theme: paper"))
        #expect(!s.contains("theme: noir"))
        s = roundTrip(s) { Transforms.setGlobalDirective($0, key: "size", value: "4:3") }
        #expect(s.contains("size: 4:3\n---"))
        s = roundTrip(s) { Transforms.setGlobalDirective($0, key: "size", value: nil) }
        #expect(!s.contains("size:"))
        let noFm = roundTrip("# Hi") { Transforms.setGlobalDirective($0, key: "theme", value: "gaia") }
        #expect(noFm == "---\nmarp: true\ntheme: gaia\n---\n\n# Hi")
    }

    @Test func slideDirectiveRoundTrip() {
        let src = "# A\n\ntext\n\n---\n\n# B\n"
        let with = roundTrip(src) { Transforms.setSlideDirective($0, slide: 1, key: "backgroundColor", value: "#fff") }
        #expect(with == "# A\n\ntext\n\n---\n\n<!-- _backgroundColor: #fff -->\n\n# B\n")
        let changed = roundTrip(with) { Transforms.setSlideDirective($0, slide: 1, key: "backgroundColor", value: "#000") }
        #expect(changed.contains("<!-- _backgroundColor: #000 -->"))
        let cleared = roundTrip(changed) { Transforms.setSlideDirective($0, slide: 1, key: "backgroundColor", value: nil) }
        #expect(cleared == src)
    }

    @Test func classToggle() {
        let src = "# A\n"
        let lead = roundTrip(src) { Transforms.toggleClass($0, slide: 0, name: "lead") }
        #expect(lead == "<!-- _class: lead -->\n\n# A\n")
        let both = roundTrip(lead) { Transforms.toggleClass($0, slide: 0, name: "invert") }
        #expect(both == "<!-- _class: lead invert -->\n\n# A\n")
        let back = roundTrip(roundTrip(both) { Transforms.toggleClass($0, slide: 0, name: "lead") }) {
            Transforms.toggleClass($0, slide: 0, name: "invert")
        }
        #expect(back == src)
    }

    @Test func insertDuplicateDelete() {
        let src = "# A\n\n---\n\n# B\n"
        let inserted = roundTrip(src) { Transforms.insertSlide($0, at: 1, body: "# New") }
        #expect(inserted == "# A\n\n---\n\n# New\n\n---\n\n# B\n")
        let appended = roundTrip(src) { Transforms.insertSlide($0, at: 2) }
        #expect(appended == "# A\n\n---\n\n# B\n\n---\n\n# \n")
        let prepended = roundTrip(src) { Transforms.insertSlide($0, at: 0, body: "# Z") }
        #expect(prepended == "# Z\n\n---\n\n# A\n\n---\n\n# B\n")
        let dup = roundTrip(src) { Transforms.duplicateSlide($0, 1) }
        #expect(dup == "# A\n\n---\n\n# B\n\n---\n\n# B\n")
        #expect(Deck(parsing: dup).slideCount == 3)
        #expect(roundTrip(dup) { Transforms.deleteSlide($0, 2) } == src)
        #expect(roundTrip(dup) { Transforms.deleteSlide($0, 0) } == "# B\n\n---\n\n# B\n")
        #expect(roundTrip("# Only\n") { Transforms.deleteSlide($0, 0) } == "")
        let fromEmpty = roundTrip("") { Transforms.insertSlide($0, at: 1, body: "# First") }
        #expect(fromEmpty == "# First\n")
    }

    @Test func moveSlide() {
        let src = "# A\n\n---\n\n# B\n\n---\n\n# C\n"
        #expect(roundTrip(src) { Transforms.moveSlide($0, from: 0, to: 2) } == "# B\n\n---\n\n# C\n\n---\n\n# A\n")
        #expect(roundTrip(src) { Transforms.moveSlide($0, from: 2, to: 0) } == "# C\n\n---\n\n# A\n\n---\n\n# B\n")
        #expect(Transforms.moveSlide(Deck(parsing: src), from: 1, to: 1).isEmpty)
    }

    @Test func insertAfterSlideWithSpotDirectiveKeepsIt() {
        let src = "<!-- _class: lead -->\n\n# A\n"
        let out = roundTrip(src) { Transforms.insertSlide($0, at: 1) }
        #expect(out == "<!-- _class: lead -->\n\n# A\n\n---\n\n# \n")
        #expect(Deck(parsing: out).slides[1].classes.isEmpty)
    }
}
