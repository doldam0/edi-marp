import { useEffect, useMemo, useRef, useState } from 'react'
import { Search, CornerDownLeft } from 'lucide-react'
import { useStore } from '@/state/store'
import { buildCommands, type Command } from '@/state/commands'

const SECTION_LABEL: Record<Command['section'], string> = { slide: '슬라이드', deck: '덱', insert: '삽입', view: '보기', file: '파일' }

/** Lightweight fuzzy scorer: prefix > word start > subsequence. */
function score(q: string, c: Command): number {
  if (!q) return 1
  const hay = `${c.title} ${c.keywords ?? ''} ${c.hint ?? ''}`.toLowerCase()
  const needle = q.toLowerCase()
  if (hay.includes(needle)) return 100 - hay.indexOf(needle) * 0.1 + (c.title.toLowerCase().startsWith(needle) ? 50 : 0)
  let i = 0, run = 0, best = 0
  for (const ch of hay) {
    if (ch === needle[i]) { i++; run++; best += run } else run = 0
    if (i === needle.length) return best
  }
  return 0
}

export function CommandPalette() {
  const open = useStore((s) => s.paletteOpen)
  const close = () => useStore.getState().setPaletteOpen(false)
  const [q, setQ] = useState('')
  const [sel, setSel] = useState(0)
  const inputRef = useRef<HTMLInputElement>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const commands = useMemo(() => (open ? buildCommands().filter((c) => c.id !== 'view.palette') : []), [open])

  const results = useMemo(() => {
    const scored = commands.map((c) => ({ c, s: score(q, c) })).filter((x) => x.s > 0)
    if (q) scored.sort((a, b) => b.s - a.s)
    return scored.map((x) => x.c)
  }, [commands, q])

  useEffect(() => { if (open) { setQ(''); setSel(0); requestAnimationFrame(() => inputRef.current?.focus()) } }, [open])
  useEffect(() => { setSel(0) }, [q])
  useEffect(() => {
    listRef.current?.querySelector<HTMLElement>(`[data-i="${sel}"]`)?.scrollIntoView({ block: 'nearest' })
  }, [sel])

  if (!open) return null

  const run = (c: Command) => { close(); void c.run() }
  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); setSel((s) => Math.min(s + 1, results.length - 1)) }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setSel((s) => Math.max(s - 1, 0)) }
    else if (e.key === 'Enter') { e.preventDefault(); if (results[sel]) run(results[sel]) }
    else if (e.key === 'Escape') { e.preventDefault(); close() }
  }

  let lastSection: string | null = null
  return (
    <div className="palette__backdrop" onMouseDown={close}>
      <div className="palette" role="dialog" aria-label="커맨드 팔레트" onMouseDown={(e) => e.stopPropagation()}>
        <div className="palette__input">
          <Search size={16} />
          <input ref={inputRef} value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={onKey} placeholder="무엇을 할까요? (테마, 이동, 삽입, 내보내기…)" spellCheck={false} />
          <kbd>esc</kbd>
        </div>
        <div className="palette__list" ref={listRef}>
          {results.length === 0 && <div className="palette__empty">일치하는 명령이 없어요</div>}
          {results.map((c, i) => {
            const header = !q && c.section !== lastSection ? SECTION_LABEL[c.section] : null
            lastSection = c.section
            return (
              <div key={c.id}>
                {header && <div className="palette__section">{header}</div>}
                <button data-i={i} className={`palette__item${i === sel ? ' is-selected' : ''}`} onMouseEnter={() => setSel(i)} onClick={() => run(c)}>
                  <span className="palette__title">{c.title}</span>
                  {c.hint && <span className="palette__hint">{c.hint}</span>}
                  {c.shortcut ? <kbd>{c.shortcut}</kbd> : i === sel ? <CornerDownLeft size={12} className="palette__enter" /> : null}
                </button>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
