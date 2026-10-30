import { useEffect, useRef, useState } from 'react'
import { PanelLeft, Code2, Eye, LayoutGrid, Play, Command, Download, ChevronDown, Sun, Moon } from 'lucide-react'
import { useStore } from '@/state/store'
import { buildCommands } from '@/state/commands'
import { THEMES } from '@/themes'
import { bridge } from '@/editor/bridge'
import { setGlobalDirective } from '@/core/transforms'

export function TopBar() {
  const file = useStore((s) => s.file)
  const panels = useStore((s) => s.panels)
  const mode = useStore((s) => s.previewMode)
  const scheme = useStore((s) => s.scheme)
  const theme = useStore((s) => s.doc.globals.theme ?? 'default')
  const st = useStore.getState
  const run = (id: string) => buildCommands().find((c) => c.id === id)?.run()

  return (
    <header className="topbar">
      <div className="topbar__left">
        <span className="brand"><span className="brand__mark" />edi</span>
        <button className="filename" onClick={() => run('file.rename')} title="이름 바꾸기">
          {file.name}{file.dirty && <span className="filename__dirty" title="저장되지 않음" />}
        </button>
      </div>
      <div className="topbar__right">
        <Menu
          label={<><span className="muted">theme</span> {THEMES.find((t) => t.name === theme)?.label ?? theme}</>}
          items={THEMES.map((t) => ({ key: t.name, label: t.label, hint: t.description, active: t.name === theme, onSelect: () => bridge.transform((d) => setGlobalDirective(d, 'theme', t.name)) }))}
        />
        <div className="seg">
          <button className={panels.rail ? 'is-on' : ''} onClick={() => st().togglePanel('rail')} title="슬라이드 레일 ⌘1"><PanelLeft size={15} /></button>
          <button className={panels.editor ? 'is-on' : ''} onClick={() => st().togglePanel('editor')} title="에디터 ⌘2"><Code2 size={15} /></button>
          <button className={panels.preview ? 'is-on' : ''} onClick={() => st().togglePanel('preview')} title="미리보기 ⌘3"><Eye size={15} /></button>
          <button className={mode === 'grid' ? 'is-on' : ''} onClick={() => st().setPreviewMode(mode === 'grid' ? 'focus' : 'grid')} title="그리드 보기 ⌘G"><LayoutGrid size={15} /></button>
        </div>
        <button className="icon" onClick={() => st().setScheme(scheme === 'dark' ? 'light' : 'dark')} title="라이트/다크">{scheme === 'dark' ? <Sun size={15} /> : <Moon size={15} />}</button>
        <Menu
          icon={<Download size={15} />}
          label="내보내기"
          items={[
            { key: 'html', label: 'HTML', hint: '단독 실행, F 키로 발표', onSelect: () => run('file.exportHtml') },
            { key: 'pdf', label: 'PDF', hint: '인쇄 → PDF로 저장', onSelect: () => run('file.exportPdf') },
            { key: 'md', label: 'Markdown', hint: '.md 다운로드', onSelect: () => run('file.exportMd') },
          ]}
        />
        <button className="btn btn--primary" onClick={() => st().setPresenting(true)} title="발표 ⌘⇧P"><Play size={14} /> 발표</button>
        <button className="btn btn--kbd" onClick={() => st().setPaletteOpen(true)} title="커맨드 팔레트"><Command size={13} /> K</button>
      </div>
    </header>
  )
}

interface MenuItem { key: string; label: string; hint?: string; active?: boolean; onSelect(): void }

function Menu({ label, icon, items }: { label: React.ReactNode; icon?: React.ReactNode; items: MenuItem[] }) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setOpen(false) }
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false) }
    window.addEventListener('mousedown', onDown)
    window.addEventListener('keydown', onKey)
    return () => { window.removeEventListener('mousedown', onDown); window.removeEventListener('keydown', onKey) }
  }, [open])
  return (
    <div className="menu" ref={ref}>
      <button className={`btn${open ? ' is-on' : ''}`} onClick={() => setOpen((o) => !o)}>{icon}{label}<ChevronDown size={12} className="muted" /></button>
      {open && (
        <div className="menu__pop">
          {items.map((it) => (
            <button key={it.key} className={`menu__item${it.active ? ' is-active' : ''}`} onClick={() => { setOpen(false); it.onSelect() }}>
              <span>{it.label}</span>{it.hint && <small>{it.hint}</small>}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
