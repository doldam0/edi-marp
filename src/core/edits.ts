/**
 * Text edits expressed as character ranges so they can be fed straight into
 * CodeMirror transactions (preserving undo history and cursor positions) or
 * applied to a plain string for tests and headless use.
 */
export interface Edit {
  from: number
  to: number
  insert: string
}

export function applyEdits(source: string, edits: Edit[]): string {
  const sorted = [...edits].sort((a, b) => a.from - b.from)
  let out = ''
  let cursor = 0
  for (const e of sorted) {
    if (e.from < cursor) throw new Error('overlapping edits')
    out += source.slice(cursor, e.from) + e.insert
    cursor = e.to
  }
  return out + source.slice(cursor)
}
