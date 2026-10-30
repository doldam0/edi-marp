import { createMarp, renderWith } from './marp'

const marp = createMarp()

self.onmessage = (ev: MessageEvent<{ id: number; source: string }>) => {
  const { id, source } = ev.data
  try {
    const result = renderWith(marp, source)
    self.postMessage({ id, ok: true, result })
  } catch (error) {
    self.postMessage({ id, ok: false, error: String((error as Error)?.message ?? error) })
  }
}

self.postMessage({ id: -1, ok: true, ready: true })
