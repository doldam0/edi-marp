import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { useStore } from '@/state/store'
import { bridge } from '@/editor/bridge'
import { SlideFrame, aspectOf } from './SlideFrame'
import { Inspector } from './Inspector'

export function Preview() {
  const mode = useStore((s) => s.previewMode)
  return (
    <section className="preview">
      {mode === 'focus' ? <FocusView /> : <GridView />}
      <Inspector />
    </section>
  )
}

/** Fits a 16:9 (or whatever) box inside the container: returns the width to use. */
function useFit(ref: React.RefObject<HTMLElement>, aspect: number, pad = 48): number {
  const [w, setW] = useState(0)
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const ro = new ResizeObserver(([e]) => {
      const cw = e.contentRect.width - pad, ch = e.contentRect.height - pad
      setW(Math.max(0, Math.min(cw, ch * aspect)))
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [ref, aspect, pad])
  return w
}

function FocusView() {
  const render = useStore((s) => s.render)
  const error = useStore((s) => s.renderError)
  const active = useStore((s) => s.activeSlide)
  const count = render?.count ?? 0
  const ref = useRef<HTMLDivElement>(null)
  const aspect = aspectOf(render?.slides ?? [])
  const width = useFit(ref, aspect)
  const html = render?.slides[Math.min(active, count - 1)]

  const go = (d: number) => bridge.goToSlide(active + d, { focus: false })

  return (
    <div className="focus" ref={ref}>
      {html && render ? (
        <SlideFrame key="focus" className="focus__slide" style={{ width }} html={html} css={render.css} onLineClick={(l) => bridge.goToLine(l)} />
      ) : (
        <div className="focus__empty">{error ?? '렌더링 중…'}</div>
      )}
      <div className="focus__nav">
        <button onClick={() => go(-1)} disabled={active <= 0} aria-label="이전"><ChevronLeft size={16} /></button>
        <span>{count ? active + 1 : 0} <em>/</em> {count}</span>
        <button onClick={() => go(1)} disabled={active >= count - 1} aria-label="다음"><ChevronRight size={16} /></button>
      </div>
      {error && html && <div className="focus__error">{error}</div>}
    </div>
  )
}

function GridView() {
  const render = useStore((s) => s.render)
  const active = useStore((s) => s.activeSlide)
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    ref.current?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }, [active])
  if (!render) return <div className="focus__empty">렌더링 중…</div>
  return (
    <div className="grid" ref={ref} style={{ '--aspect': aspectOf(render.slides) } as React.CSSProperties}>
      <div className="grid__inner">
      {render.slides.map((html, i) => (
        <div key={i} data-index={i} className={`grid__item${i === active ? ' is-active' : ''}`} onDoubleClick={() => { useStore.getState().setPreviewMode('focus'); bridge.goToSlide(i) }}>
          <SlideFrame html={html} css={render.css} onClick={() => bridge.goToSlide(i, { focus: false })} />
          <span className="grid__num">{i + 1}</span>
        </div>
      ))}
      </div>
    </div>
  )
}
