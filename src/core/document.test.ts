import { describe, it, expect } from 'vitest'
import { parseDocument, slideAtLine } from './document'
import { applyEdits } from './edits'
import { setGlobalDirective, setSlideDirective, insertSlide, deleteSlide, moveSlide, toggleSlideClass, duplicateSlide } from './transforms'

const SRC = `---
marp: true
theme: gaia
---

# One

text

---

<!-- _class: lead -->

# Two

\`\`\`md
---
not a separator
\`\`\`

---

<!-- paginate: true -->
# Three
`

describe('parseDocument', () => {
  const doc = parseDocument(SRC)
  it('reads frontmatter', () => {
    expect(doc.frontmatter?.data).toEqual({ marp: 'true', theme: 'gaia' })
    expect(doc.globals.theme).toBe('gaia')
  })
  it('splits slides, ignoring fenced hr', () => {
    expect(doc.slides.map((s) => s.title)).toEqual(['One', 'Two', 'Three'])
  })
  it('tracks directives', () => {
    expect(doc.slides[1].effective).toEqual({ class: 'lead' })
    expect(doc.slides[2].effective).toEqual({ paginate: 'true' })
  })
  it('maps lines to slides', () => {
    expect(slideAtLine(doc, 0)).toBe(0)
    expect(slideAtLine(doc, 5)).toBe(0)
    expect(slideAtLine(doc, 12)).toBe(1)
    expect(slideAtLine(doc, doc.lines.length - 1)).toBe(2)
  })
  it('treats setext underline as heading, not break', () => {
    const d = parseDocument('Title\n---\n\nbody\n\n---\n\nnext')
    expect(d.slides).toHaveLength(2)
  })
})

describe('transforms', () => {
  const doc = parseDocument(SRC)
  const run = (edits: ReturnType<typeof setGlobalDirective>) => parseDocument(applyEdits(SRC, edits))

  it('sets and removes global directives', () => {
    expect(run(setGlobalDirective(doc, 'theme', 'default')).globals.theme).toBe('default')
    expect(run(setGlobalDirective(doc, 'paginate', 'true')).globals.paginate).toBe('true')
    expect(run(setGlobalDirective(doc, 'theme', null)).globals.theme).toBeUndefined()
  })
  it('creates frontmatter when missing', () => {
    const d = parseDocument('# Hi')
    const next = parseDocument(applyEdits('# Hi', setGlobalDirective(d, 'theme', 'gaia')))
    expect(next.frontmatter?.data).toEqual({ marp: 'true', theme: 'gaia' })
    expect(next.slides[0].title).toBe('Hi')
  })
  it('sets and clears slide directives', () => {
    const a = run(setSlideDirective(doc, 0, 'backgroundColor', '#000'))
    expect(a.slides[0].effective.backgroundColor).toBe('#000')
    expect(a.slides[1].effective.backgroundColor).toBeUndefined()
    const b = parseDocument(applyEdits(a.source, setSlideDirective(a, 0, 'backgroundColor', null)))
    expect(b.source).toBe(SRC)
  })
  it('toggles classes', () => {
    const a = run(toggleSlideClass(doc, 1, 'invert'))
    expect(a.slides[1].effective.class).toBe('lead invert')
    const b = parseDocument(applyEdits(a.source, toggleSlideClass(a, 1, 'lead')))
    expect(b.slides[1].effective.class).toBe('invert')
    const c = parseDocument(applyEdits(b.source, toggleSlideClass(b, 1, 'invert')))
    expect(c.slides[1].effective.class).toBeUndefined()
  })
  it('inserts, duplicates, deletes and moves', () => {
    const ins = run(insertSlide(doc, 0, '# New\n'))
    expect(ins.slides.map((s) => s.title)).toEqual(['One', 'New', 'Two', 'Three'])
    const dup = run(duplicateSlide(doc, 2))
    expect(dup.slides.map((s) => s.title)).toEqual(['One', 'Two', 'Three', 'Three'])
    const del = run(deleteSlide(doc, 1))
    expect(del.slides.map((s) => s.title)).toEqual(['One', 'Three'])
    const delLast = run(deleteSlide(doc, 2))
    expect(delLast.slides.map((s) => s.title)).toEqual(['One', 'Two'])
    const mv = run(moveSlide(doc, 2, 0))
    expect(mv.slides.map((s) => s.title)).toEqual(['Three', 'One', 'Two'])
    expect(mv.frontmatter?.data.theme).toBe('gaia')
  })
})
