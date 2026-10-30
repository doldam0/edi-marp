import { useEffect, useMemo, useRef, useState } from 'react'
import { useStore } from '@/state/store'
import { createRenderer } from '@/render/renderer'
import { saveDraft } from '@/core/storage'
import { buildCommands, SHORTCUTS } from '@/state/commands'
import { TopBar } from './TopBar'
import { SlideRail } from './SlideRail'
import { Editor } from './Editor'
import { Preview } from './Preview'
import { StatusBar } from './StatusBar'
import { CommandPalette } from './CommandPalette'
import { Presenter } from './Presenter'

const isMac = /Mac|iPhone|iPad/.test(navigator.platform)

export function App() {
  const panels = useStore((s) => s.panels)
  const presenting = useStore((s) => s.presenting)
  const scheme = useStore((s) => s.scheme)
  const renderer = useMemo(createRenderer, [])
  const [split, setSplit] = useState(() => Number(localStorage.getItem('edi:split')) || 0.48)

  // --- render pipeline: source → (debounced) → worker → store
  useEffect(() => {
    let timer = 0
    const kick = (source: string) => {
      clearTimeout(timer)
      timer = window.setTimeout(async () => {
        try {
          const r = await renderer.render(source)
          if (useStore.getState().source === source) useStore.getState().setRender(r)
        } catch (e) {
          useStore.getState().setRender(useStore.getState().render, (e as Error).message)
        }
      }, 40)
    }
    kick(useStore.getState().source)
    return useStore.subscribe((s, prev) => { if (s.source !== prev.source) kick(s.source) })
  }, [renderer])

  // --- autosave draft
  useEffect(() => {
    let timer = 0
    return useStore.subscribe((s, prev) => {
      if (s.source === prev.source && s.file.name === prev.file.name) return
      clearTimeout(timer)
      timer = window.setTimeout(() => saveDraft({ source: s.source, name: s.file.name }), 400)
    })
  }, [])

  // --- shortcuts (capture phase so CodeMirror's own bindings don't win)
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const mod = isMac ? e.metaKey : e.ctrlKey
      if (!mod) return
      const hit = SHORTCUTS.find((s) => s.key.toLowerCase() === e.key.toLowerCase() && !!s.mod === mod && !!s.shift === e.shiftKey)
      if (!hit) return
      e.preventDefault()
      e.stopPropagation()
      if (useStore.getState().presenting && hit.id !== 'view.present') return
      void buildCommands().find((c) => c.id === hit.id)?.run()
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [])

  useEffect(() => { document.documentElement.dataset.theme = scheme }, [scheme])
  useEffect(() => {
    const onUnload = (e: BeforeUnloadEvent) => { if (useStore.getState().file.handle && useStore.getState().file.dirty) e.preventDefault() }
    window.addEventListener('beforeunload', onUnload)
    return () => window.removeEventListener('beforeunload', onUnload)
  }, [])

  // --- resizable split
  const workRef = useRef<HTMLDivElement>(null)
  const onDrag = (e: React.PointerEvent) => {
    const el = workRef.current!
    const rect = el.getBoundingClientRect()
    const railW = el.querySelector('.rail')?.getBoundingClientRect().width ?? 0
    const move = (ev: PointerEvent) => {
      const r = (ev.clientX - rect.left - railW) / (rect.width - railW)
      setSplit(Math.min(0.8, Math.max(0.2, r)))
    }
    const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); localStorage.setItem('edi:split', String(split)) }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
    e.preventDefault()
  }

  const both = panels.editor && panels.preview
  return (
    <div className="app">
      <TopBar />
      <div className="work" ref={workRef} style={{ '--split': split } as React.CSSProperties}>
        {panels.rail && <SlideRail />}
        {panels.editor && <div className="pane pane--editor"><Editor /></div>}
        {both && <div className="splitter" onPointerDown={onDrag} />}
        {panels.preview && <div className="pane pane--preview"><Preview /></div>}
      </div>
      <StatusBar renderMode={renderer.mode} />
      <CommandPalette />
      {presenting && <Presenter />}
    </div>
  )
}
