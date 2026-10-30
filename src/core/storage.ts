/** Draft persistence (localStorage) and file I/O (File System Access API with download fallback). */

const DRAFT_KEY = 'edi:draft'

export interface Draft { source: string; name: string; at: number }

export function loadDraft(): Draft | null {
  try {
    const raw = localStorage.getItem(DRAFT_KEY)
    return raw ? (JSON.parse(raw) as Draft) : null
  } catch {
    return null
  }
}

export function saveDraft(d: Omit<Draft, 'at'>) {
  try {
    localStorage.setItem(DRAFT_KEY, JSON.stringify({ ...d, at: Date.now() }))
  } catch { /* quota – ignore */ }
}

export const hasFileSystemAccess = typeof window !== 'undefined' && 'showOpenFilePicker' in window

const MD_TYPES = [{ description: 'Markdown', accept: { 'text/markdown': ['.md', '.markdown'] } }]

export async function openMarkdownFile(): Promise<{ name: string; source: string; handle: FileSystemFileHandle | null } | null> {
  if (hasFileSystemAccess) {
    try {
      const [handle] = await (window as any).showOpenFilePicker({ types: MD_TYPES, multiple: false })
      const file = await handle.getFile()
      return { name: file.name, source: await file.text(), handle }
    } catch (e) {
      if ((e as DOMException).name === 'AbortError') return null
      throw e
    }
  }
  return new Promise((resolve) => {
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = '.md,.markdown,text/markdown'
    input.onchange = async () => {
      const file = input.files?.[0]
      if (!file) return resolve(null)
      resolve({ name: file.name, source: await file.text(), handle: null })
    }
    input.click()
  })
}

export async function saveMarkdownFile(
  source: string,
  name: string,
  handle: FileSystemFileHandle | null,
  { saveAs = false } = {},
): Promise<{ name: string; handle: FileSystemFileHandle | null } | null> {
  if (hasFileSystemAccess) {
    try {
      let h = handle
      if (!h || saveAs) h = await (window as any).showSaveFilePicker({ suggestedName: name, types: MD_TYPES })
      const writable = await h!.createWritable()
      await writable.write(source)
      await writable.close()
      return { name: h!.name, handle: h }
    } catch (e) {
      if ((e as DOMException).name === 'AbortError') return null
      throw e
    }
  }
  downloadBlob(name, new Blob([source], { type: 'text/markdown' }))
  return { name, handle: null }
}

export function downloadBlob(name: string, blob: Blob) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = name
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
