import { useEffect, useState } from 'react'
import { useStore } from '@/state/store'
import { wordCount } from '@/core/document'

export function StatusBar({ renderMode }: { renderMode: string }) {
  const doc = useStore((s) => s.doc)
  const active = useStore((s) => s.activeSlide)
  const line = useStore((s) => s.cursorLine)
  const file = useStore((s) => s.file)
  const error = useStore((s) => s.renderError)
  const [, tick] = useState(0)
  useEffect(() => { const t = setInterval(() => tick((n) => n + 1), 10000); return () => clearInterval(t) }, [])

  const words = wordCount(doc.source)
  const saved = file.savedAt ? `${relative(file.savedAt)} 저장됨` : file.dirty ? '초안은 브라우저에 자동 저장' : ''

  return (
    <footer className="statusbar">
      <span>슬라이드 <b>{active + 1}</b> / {doc.slides.length}</span>
      <span className="sep" />
      <span>줄 {line + 1}</span>
      <span className="sep" />
      <span>{words.toLocaleString()} 단어</span>
      {error && <><span className="sep" /><span className="statusbar__error" title={error}>렌더 오류</span></>}
      <span className="grow" />
      <span className="muted">{saved}</span>
      <span className="sep" />
      <span className="muted">{doc.globals.theme ?? 'default'} · {doc.globals.size ?? '16:9'} · {renderMode}</span>
    </footer>
  )
}

function relative(t: number): string {
  const s = Math.round((Date.now() - t) / 1000)
  if (s < 5) return '방금'
  if (s < 60) return `${s}초 전`
  if (s < 3600) return `${Math.round(s / 60)}분 전`
  return `${Math.round(s / 3600)}시간 전`
}
