/**
 * Every structural operation on a deck is a pure function from a parsed
 * document to a list of edits. The UI never mutates text directly.
 */
import { type MarpDocument, type Range, GLOBAL_DIRECTIVES } from './document'
import type { Edit } from './edits'

const lineStart = (doc: MarpDocument, line: number) => doc.offsets[Math.min(line, doc.lines.length)]
const lineEnd = (doc: MarpDocument, line: number) => lineStart(doc, line) + (doc.lines[line]?.length ?? 0)

/** Char range covering lines [from, to) including the trailing newline of the last line. */
function blockRange(doc: MarpDocument, range: Range): { from: number; to: number } {
  const from = lineStart(doc, range.from)
  const to = range.to >= doc.lines.length ? doc.source.length : lineStart(doc, range.to)
  return { from, to }
}

function replaceLine(doc: MarpDocument, line: number, text: string): Edit {
  return { from: lineStart(doc, line), to: lineEnd(doc, line), insert: text }
}

function deleteLine(doc: MarpDocument, line: number, { collapseBlank = false } = {}): Edit {
  const from = lineStart(doc, line)
  let last = line
  // drop a blank line that only existed to separate this line from the next block
  if (collapseBlank && doc.lines[line + 1]?.trim() === '' && (line === 0 || doc.lines[line - 1]?.trim() === '')) last = line + 1
  const to = last + 1 < doc.lines.length ? lineStart(doc, last + 1) : lineEnd(doc, last)
  // when deleting the last line, also eat the preceding newline
  if (last + 1 >= doc.lines.length && from > 0) return { from: from - 1, to, insert: '' }
  return { from, to, insert: '' }
}

/** Set (or remove with `null`) a key in the YAML frontmatter, creating one when needed. */
export function setGlobalDirective(doc: MarpDocument, key: string, value: string | null): Edit[] {
  const fm = doc.frontmatter
  if (!fm) {
    if (value === null) return []
    const body = key === 'marp' ? `marp: ${value}` : `marp: true\n${key}: ${value}`
    return [{ from: 0, to: 0, insert: `---\n${body}\n---\n\n` }]
  }
  for (let i = fm.range.from + 1; i < fm.range.to - 1; i++) {
    const m = /^\s*([A-Za-z_][\w-]*)\s*:/.exec(doc.lines[i])
    if (m && m[1] === key) {
      return value === null ? [deleteLine(doc, i)] : [replaceLine(doc, i, `${key}: ${value}`)]
    }
  }
  if (value === null) return []
  const closing = lineStart(doc, fm.range.to - 1)
  return [{ from: closing, to: closing, insert: `${key}: ${value}\n` }]
}

/**
 * Set (or remove) a directive on one slide. By default this uses a spot
 * directive (`_key`) so that it never leaks to the following slides.
 */
export function setSlideDirective(
  doc: MarpDocument,
  index: number,
  key: string,
  value: string | null,
  { spot = true }: { spot?: boolean } = {},
): Edit[] {
  const slide = doc.slides[index]
  if (!slide) return []
  const existing = slide.declared.find((d) => d.key === key && d.spot === spot)
  if (existing) {
    const line = doc.lines[existing.line]
    const re = new RegExp(`(<!--\\s*)(_?)${key}\\s*:\\s*([^\\n]*?)(\\s*-->)`)
    const m = re.exec(line)
    if (m && m[0] === line.trim()) {
      // single-directive comment: rewrite or drop the whole line
      return value === null ? [deleteLine(doc, existing.line, { collapseBlank: true })] : [replaceLine(doc, existing.line, line.replace(re, `$1$2${key}: ${value}$4`))]
    }
    // multi-directive comment – swap just this pair
    const pairRe = new RegExp(`(_?)${key}\\s*:\\s*[^\\n]*?(?=\\s*(?:\\n|-->|$))`)
    const text = value === null ? '' : `$1${key}: ${value}`
    return [replaceLine(doc, existing.line, line.replace(pairRe, text))]
  }
  if (value === null) return []
  const prefix = spot ? '_' : ''
  // insert right after leading blank lines of the slide
  let at = slide.range.from
  while (at < slide.range.to && doc.lines[at].trim() === '') at++
  const pos = lineStart(doc, at)
  const needsGap = at < slide.range.to && doc.lines[at].trim() !== ''
  return [{ from: pos, to: pos, insert: `<!-- ${prefix}${key}: ${value} -->\n${needsGap ? '\n' : ''}` }]
}

/** Insert a new slide after `index` (or at the very start with -1). */
export function insertSlide(doc: MarpDocument, index: number, body = '# \n'): Edit[] {
  if (doc.slides.length === 0 || index < 0) {
    const at = doc.frontmatter ? lineStart(doc, doc.frontmatter.range.to) : 0
    return [{ from: at, to: at, insert: `${body}\n---\n\n` }]
  }
  const slide = doc.slides[Math.min(index, doc.slides.length - 1)]
  const { to } = blockRange(doc, slide.range)
  // guarantee exactly one blank line before the new separator
  let trailing = 0
  while (trailing < 2 && doc.source[to - 1 - trailing] === '\n') trailing++
  const lead = to === 0 ? '' : '\n'.repeat(2 - trailing)
  const tail = to === doc.source.length ? '' : '\n'
  return [{ from: to, to, insert: `${lead}---\n\n${body}${tail}` }]
}

export function deleteSlide(doc: MarpDocument, index: number): Edit[] {
  const slide = doc.slides[index]
  if (!slide || doc.slides.length === 1) return []
  // delete body plus the separator line adjoining it
  const { from, to } = blockRange(doc, slide.range)
  if (index < doc.slides.length - 1) {
    const sepEnd = lineStart(doc, doc.slides[index + 1].range.from)
    return [{ from, to: sepEnd, insert: '' }]
  }
  const prevSep = lineStart(doc, slide.range.from - 1)
  return [{ from: prevSep, to, insert: '' }]
}

export function duplicateSlide(doc: MarpDocument, index: number): Edit[] {
  const slide = doc.slides[index]
  if (!slide) return []
  const text = doc.lines.slice(slide.range.from, slide.range.to).join('\n')
  return insertSlide(doc, index, text.replace(/\n+$/, '') + '\n')
}

export function moveSlide(doc: MarpDocument, from: number, to: number): Edit[] {
  if (from === to || !doc.slides[from] || !doc.slides[to]) return []
  const bodies = doc.slides.map((s) => doc.lines.slice(s.range.from, s.range.to).join('\n'))
  const [moved] = bodies.splice(from, 1)
  bodies.splice(to, 0, moved)
  const first = doc.slides[0].range
  const last = doc.slides[doc.slides.length - 1].range
  const start = lineStart(doc, first.from)
  const end = last.to >= doc.lines.length ? doc.source.length : lineEnd(doc, last.to - 1)
  const normalized = bodies.map((b) => b.replace(/^\n+/, '').replace(/\n+$/, ''))
  return [{ from: start, to: end, insert: normalized.join('\n\n---\n\n') + '\n' }]
}

/** Toggle a class token (e.g. `lead`, `invert`) in the slide's `_class` directive. */
export function toggleSlideClass(doc: MarpDocument, index: number, cls: string): Edit[] {
  const slide = doc.slides[index]
  if (!slide) return []
  const current = slide.declared.find((d) => d.key === 'class' && d.spot)?.value ?? ''
  const set = new Set(current.split(/\s+/).filter(Boolean))
  if (set.has(cls)) set.delete(cls)
  else set.add(cls)
  const next = [...set].join(' ')
  return setSlideDirective(doc, index, 'class', next.length ? next : null)
}

export function isGlobal(key: string): boolean {
  return GLOBAL_DIRECTIVES.has(key)
}
