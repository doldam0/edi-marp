import { useEffect, useRef } from 'react'
import { EditorView } from '@codemirror/view'
import { createEditorState } from '@/editor/setup'
import { bridge } from '@/editor/bridge'
import { useStore } from '@/state/store'

export function Editor() {
  const hostRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const { source, setSource, setCursorLine, cursorLine } = useStore.getState()
    const view = new EditorView({
      state: createEditorState(source, { onChange: setSource, onCursor: setCursorLine }),
      parent: hostRef.current!,
    })
    bridge.attach(view)
    // restore the cursor the store remembers (e.g. after the panel was hidden)
    if (cursorLine > 0) bridge.goToLine(cursorLine, { focus: false })
    return () => { bridge.detach(view); view.destroy() }
  }, [])

  return <div ref={hostRef} className="editor" />
}
