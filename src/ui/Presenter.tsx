import { useEffect, useRef } from 'react'
import { useStore } from '@/state/store'
import { bridge } from '@/editor/bridge'
import { SlideFrame, aspectOf } from './SlideFrame'

/** Fullscreen presentation with speaker notes (N) and a progress hairline. */
export function Presenter() {
  const render = useStore((s) => s.render)
  const active = useStore((s) => s.activeSlide)
  const notesOpen = useStore((s) => s.notesOpen)
  const ref = useRef<HTMLDivElement>(null)
  const count = render?.count ?? 0

  useEffect(() => {
    document.documentElement.requestFullscreen?.().catch(() => {})
    const onKey = (e: KeyboardEvent) => {
      const st = useStore.getState()
      if (['ArrowRight', ' ', 'PageDown', 'j', 'l'].includes(e.key)) { e.preventDefault(); bridge.goToSlide(st.activeSlide + 1, { focus: false }) }
      else if (['ArrowLeft', 'PageUp', 'k', 'h'].includes(e.key)) { e.preventDefault(); bridge.goToSlide(st.activeSlide - 1, { focus: false }) }
      else if (e.key === 'Home') bridge.goToSlide(0, { focus: false })
      else if (e.key === 'End') bridge.goToSlide(count - 1, { focus: false })
      else if (e.key === 'n' || e.key === 'N') st.setNotesOpen(!st.notesOpen)
      else if (e.key === 'Escape') st.setPresenting(false)
    }
    window.addEventListener('keydown', onKey)
    const onFs = () => { if (!document.fullscreenElement) useStore.getState().setPresenting(false) }
    document.addEventListener('fullscreenchange', onFs)
    return () => {
      window.removeEventListener('keydown', onKey)
      document.removeEventListener('fullscreenchange', onFs)
      if (document.fullscreenElement) document.exitFullscreen?.().catch(() => {})
    }
  }, [count])

  if (!render) return null
  const html = render.slides[Math.min(active, count - 1)]
  const notes = render.notes[active] ?? []
  const aspect = aspectOf(render.slides)

  return (
    <div className={`presenter${notesOpen ? ' has-notes' : ''}`} ref={ref} onClick={(e) => { if ((e.target as HTMLElement).closest('.presenter__notes')) return; bridge.goToSlide(active + 1, { focus: false }) }}>
      <div className="presenter__stage" style={{ '--aspect': aspect } as React.CSSProperties}>
        <SlideFrame className="presenter__slide" html={html} css={render.css} />
      </div>
      {notesOpen && (
        <aside className="presenter__notes">
          <h4>노트 · {active + 1} / {count}</h4>
          {notes.length ? notes.map((n, i) => <p key={i}>{n}</p>) : <p className="muted">이 슬라이드에는 노트가 없어요. 마크다운에 <code>&lt;!-- 노트 --&gt;</code>를 쓰면 여기에 보입니다.</p>}
          {render.slides[active + 1] && <div className="presenter__next"><span>다음</span><SlideFrame html={render.slides[active + 1]} css={render.css} /></div>}
        </aside>
      )}
      <div className="presenter__progress"><span style={{ width: `${((active + 1) / Math.max(count, 1)) * 100}%` }} /></div>
    </div>
  )
}
