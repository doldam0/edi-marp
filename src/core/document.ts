/**
 * Marp document model.
 *
 * The markdown source is the single source of truth. This module turns it into
 * a cheap, immutable description of slides, line ranges and directives so that
 * the editor, the preview and the command system can all reason about the
 * same thing without ever touching the DOM or the renderer.
 */

export interface Range {
  /** first line (0-based, inclusive) */
  from: number
  /** last line (0-based, exclusive) */
  to: number
}

export interface DirectiveEntry {
  key: string
  value: string
  /** `_key` (spot directive, this slide only) vs `key` (inherited onwards) */
  spot: boolean
  /** line of the comment that holds this directive */
  line: number
}

export interface Slide {
  index: number
  /** lines of the slide body, separators excluded */
  range: Range
  /** directives declared inside this slide's HTML comments */
  declared: DirectiveEntry[]
  /** directives in effect for this slide after inheritance */
  effective: Record<string, string>
  /** first non-empty, non-directive line – used as a title */
  title: string
}

export interface Frontmatter {
  range: Range
  data: Record<string, string>
}

export interface MarpDocument {
  source: string
  lines: string[]
  /** char offset of every line start, plus a trailing entry for EOF */
  offsets: number[]
  frontmatter: Frontmatter | null
  slides: Slide[]
  /** global directives (frontmatter + non-underscore comment directives) */
  globals: Record<string, string>
}

/** Keys that Marp treats as global (deck-wide) directives. */
export const GLOBAL_DIRECTIVES = new Set([
  'marp', 'theme', 'style', 'headingDivider', 'size', 'lang', 'math', 'title', 'author', 'description', 'keywords', 'url', 'image',
])

/** Keys Marp treats as local (slide) directives. */
export const LOCAL_DIRECTIVES = [
  'paginate', 'header', 'footer', 'class', 'backgroundColor', 'backgroundImage', 'backgroundPosition',
  'backgroundRepeat', 'backgroundSize', 'color',
] as const

const HR = /^ {0,3}([-*_])(?: *\1){2,} *$/
const FENCE = /^ {0,3}(`{3,}|~{3,})/
const COMMENT_SINGLE = /<!--([\s\S]*?)-->/g

export function parseDocument(source: string): MarpDocument {
  const lines = source.split('\n')
  const offsets: number[] = new Array(lines.length + 1)
  let acc = 0
  for (let i = 0; i < lines.length; i++) {
    offsets[i] = acc
    acc += lines[i].length + 1
  }
  offsets[lines.length] = acc - 1 < 0 ? 0 : source.length

  const frontmatter = parseFrontmatter(lines)
  const bodyStart = frontmatter ? frontmatter.range.to : 0

  // Split into slide ranges on thematic breaks that are outside code fences.
  const ranges: Range[] = []
  let start = bodyStart
  let fence: string | null = null
  for (let i = bodyStart; i < lines.length; i++) {
    const line = lines[i]
    const f = FENCE.exec(line)
    if (f) {
      const mark = f[1]
      if (!fence) fence = mark
      else if (mark[0] === fence[0] && mark.length >= fence.length) fence = null
      continue
    }
    if (!fence && HR.test(line) && !isSetextUnderline(lines, i, start)) {
      ranges.push({ from: start, to: i })
      start = i + 1
    }
  }
  ranges.push({ from: start, to: lines.length })

  const globals: Record<string, string> = { ...(frontmatter?.data ?? {}) }
  const inherited: Record<string, string> = {}
  for (const [k, v] of Object.entries(globals)) if (!GLOBAL_DIRECTIVES.has(k)) inherited[k] = v

  const slides: Slide[] = ranges.map((range, index) => {
    const declared = collectDirectives(lines, range)
    const spot: Record<string, string> = {}
    for (const d of declared) {
      if (GLOBAL_DIRECTIVES.has(d.key)) { globals[d.key] = d.value; continue }
      if (d.spot) spot[d.key] = d.value
      else inherited[d.key] = d.value
    }
    const effective = { ...inherited, ...spot }
    return { index, range, declared, effective, title: findTitle(lines, range) }
  })

  return { source, lines, offsets, frontmatter, slides, globals }
}

function isSetextUnderline(lines: string[], i: number, start: number): boolean {
  // `---` directly under a paragraph line is a setext H2, not a slide break –
  // unless the paragraph line is blank. Marp follows CommonMark here.
  if (i === start) return false
  const prev = lines[i - 1].trim()
  if (!prev) return false
  // lines that cannot be a paragraph: headings, quotes, lists, tables, html, fences
  if (/^(#{1,6}(\s|$)|>|[-*+]\s|\d+[.)]\s|\||<|```|~~~)/.test(prev)) return false
  if (/-->$/.test(prev)) return false
  return true
}

function parseFrontmatter(lines: string[]): Frontmatter | null {
  if (lines[0]?.trim() !== '---') return null
  for (let i = 1; i < lines.length; i++) {
    const t = lines[i].trim()
    if (t === '---' || t === '...') {
      const data: Record<string, string> = {}
      for (let j = 1; j < i; j++) {
        const kv = parseKeyValue(lines[j])
        if (kv) data[kv.key] = kv.value
      }
      return { range: { from: 0, to: i + 1 }, data }
    }
  }
  return null
}

function parseKeyValue(line: string): { key: string; value: string } | null {
  const m = /^\s*([A-Za-z_][\w-]*)\s*:\s*(.*?)\s*$/.exec(line)
  if (!m) return null
  let value = m[2]
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1)
  return { key: m[1], value }
}

function collectDirectives(lines: string[], range: Range): DirectiveEntry[] {
  const out: DirectiveEntry[] = []
  const text = lines.slice(range.from, range.to).join('\n')
  let m: RegExpExecArray | null
  COMMENT_SINGLE.lastIndex = 0
  while ((m = COMMENT_SINGLE.exec(text))) {
    const line = range.from + text.slice(0, m.index).split('\n').length - 1
    for (const raw of m[1].split('\n')) {
      const kv = parseKeyValue(raw)
      if (!kv) continue
      const spot = kv.key.startsWith('_')
      out.push({ key: spot ? kv.key.slice(1) : kv.key, value: kv.value, spot, line })
    }
  }
  return out
}

function findTitle(lines: string[], range: Range): string {
  for (let i = range.from; i < range.to; i++) {
    const t = lines[i].trim()
    if (!t || t.startsWith('<!--') || t.startsWith('![')) continue
    return t.replace(/^#+\s*/, '').replace(/[*_`~]/g, '').slice(0, 80)
  }
  return ''
}

/** Index of the slide containing `line`, clamped to a valid slide. */
export function slideAtLine(doc: MarpDocument, line: number): number {
  for (const s of doc.slides) if (line < s.range.to) return s.index
  // separator lines belong to the following slide; trailing lines to the last
  for (const s of doc.slides) if (line >= s.range.from && line <= s.range.to) return s.index
  return doc.slides.length - 1
}

export function slideAtOffset(doc: MarpDocument, offset: number): number {
  return slideAtLine(doc, lineAtOffset(doc, offset))
}

export function lineAtOffset(doc: MarpDocument, offset: number): number {
  let lo = 0, hi = doc.lines.length - 1
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1
    if (doc.offsets[mid] <= offset) lo = mid
    else hi = mid - 1
  }
  return lo
}

export function slideText(doc: MarpDocument, index: number): string {
  const s = doc.slides[index]
  return doc.lines.slice(s.range.from, s.range.to).join('\n')
}

/** Rough word count that treats CJK characters as words. */
export function wordCount(text: string): number {
  const stripped = text.replace(/<!--[\s\S]*?-->/g, '').replace(/^---$/gm, '')
  const latin = stripped.match(/[A-Za-z0-9_'’-]+/g)?.length ?? 0
  const cjk = stripped.match(/[぀-ヿ㐀-鿿가-힯]/g)?.length ?? 0
  return latin + cjk
}
