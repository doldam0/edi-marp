import { useEffect, useRef, useState } from 'react'
import { Plus, Copy, Trash2 } from 'lucide-react'
import { useStore } from '@/state/store'
import { bridge } from '@/editor/bridge'
import { SlideFrame, aspectOf } from './SlideFrame'
import { deleteSlide, duplicateSlide, insertSlide, moveSlide } from '@/core/transforms'

export function SlideRail() {
  const doc = useStore((s) => s.doc)
  const render = useStore((s) => s.render)
  const active = useStore((s) => s.activeSlide)
  const listRef = useRef<HTMLDivElement>(null)
  const [drag, setDrag] = useState<{ from: number; over: number | null }>({ from: -1, over: null })

  useEffect(() => {
    const el = listRef.current?.querySelector<HTMLElement>(`[data-index="${active}"]`)
    el?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }, [active])

  const count = Math.max(doc.slides.length, render?.count ?? 0)

  return (
    <aside className="rail" style={{ '--aspect': aspectOf(render?.slides ?? []) } as React.CSSProperties}>
      <div className="rail__list" ref={listRef}>
        {Array.from({ length: count }, (_, i) => {
          const html = render?.slides[i]
          const slide = doc.slides[i]
          const isActive = i === active
          const dragging = drag.from === i
          const over = drag.over === i && drag.from !== i
          return (
            <div
              key={i}
              data-index={i}
              className={`rail__item${isActive ? ' is-active' : ''}${dragging ? ' is-dragging' : ''}${over ? (drag.from < i ? ' is-over-after' : ' is-over-before') : ''}`}
              draggable
              onDragStart={(e) => { setDrag({ from: i, over: null }); e.dataTransfer.effectAllowed = 'move' }}
              onDragOver={(e) => { e.preventDefault(); if (drag.over !== i) setDrag((d) => ({ ...d, over: i })) }}
              onDrop={(e) => { e.preventDefault(); if (drag.from >= 0 && drag.from !== i) { bridge.transform((d) => moveSlide(d, drag.from, i)); requestAnimationFrame(() => bridge.goToSlide(i, { focus: false })) } setDrag({ from: -1, over: null }) }}
              onDragEnd={() => setDrag({ from: -1, over: null })}
              onClick={() => bridge.goToSlide(i, { focus: false })}
            >
              <span className="rail__num">{i + 1}</span>
              <div className="rail__thumb">
                {html && render ? <SlideFrame html={html} css={render.css} /> : <div className="rail__skeleton" />}
              </div>
              <div className="rail__actions" onClick={(e) => e.stopPropagation()}>
                <button title="복제" onClick={() => bridge.transform((d) => duplicateSlide(d, i))}><Copy size={12} /></button>
                <button title="삭제" disabled={count <= 1} onClick={() => bridge.transform((d) => deleteSlide(d, i))}><Trash2 size={12} /></button>
              </div>
              <span className="rail__title">{slide?.title}</span>
            </div>
          )
        })}
        <button className="rail__add" onClick={() => { bridge.transform((d) => insertSlide(d, d.slides.length - 1)); requestAnimationFrame(() => bridge.goToSlide(useStore.getState().doc.slides.length - 1)) }}>
          <Plus size={14} /> 새 슬라이드
        </button>
      </div>
    </aside>
  )
}
