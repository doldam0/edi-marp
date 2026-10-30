/**
 * Latest-wins asynchronous renderer. Prefers a Web Worker so typing never
 * contends with Marp; transparently falls back to the main thread.
 */
import type { RenderResult } from './marp'

export interface Renderer {
  render(source: string): Promise<RenderResult>
  readonly mode: 'worker' | 'main'
}

type Pending = { resolve: (r: RenderResult) => void; reject: (e: Error) => void }

export function createRenderer(): Renderer {
  let mode: 'worker' | 'main' = 'worker'
  let worker: Worker | null = null
  let mainMarp: Promise<typeof import('./marp')> | null = null
  const pending = new Map<number, Pending>()
  let seq = 0

  const useMain = () => {
    mode = 'main'
    worker?.terminate()
    worker = null
    mainMarp ??= import('./marp')
    for (const [, p] of pending) p.reject(new Error('worker unavailable'))
    pending.clear()
  }

  try {
    worker = new Worker(new URL('./worker.ts', import.meta.url), { type: 'module' })
    worker.onmessage = (ev) => {
      const { id, ok, result, error } = ev.data
      const p = pending.get(id)
      if (!p) return
      pending.delete(id)
      if (ok) p.resolve(result)
      else p.reject(new Error(error))
    }
    worker.onerror = () => useMain()
  } catch {
    useMain()
  }

  let marpInstance: ReturnType<typeof import('./marp').createMarp> | null = null

  async function renderMain(source: string): Promise<RenderResult> {
    const m = await (mainMarp ??= import('./marp'))
    marpInstance ??= m.createMarp()
    return m.renderWith(marpInstance, source)
  }

  // coalescing: keep only the newest request while one is in flight
  let inflight: Promise<RenderResult> | null = null
  let queued: { source: string; resolvers: Pending[] } | null = null

  const run = (source: string): Promise<RenderResult> => {
    if (mode === 'main' || !worker) return renderMain(source)
    return new Promise<RenderResult>((resolve, reject) => {
      const id = ++seq
      pending.set(id, { resolve, reject })
      worker!.postMessage({ id, source })
    }).catch(async (err) => {
      if (mode === 'main') return renderMain(source)
      throw err
    })
  }

  const pump = async () => {
    while (queued) {
      const job = queued
      queued = null
      inflight = run(job.source)
      try {
        const r = await inflight
        job.resolvers.forEach((p) => p.resolve(r))
      } catch (e) {
        job.resolvers.forEach((p) => p.reject(e as Error))
      }
    }
    inflight = null
  }

  return {
    get mode() { return mode },
    render(source) {
      return new Promise<RenderResult>((resolve, reject) => {
        if (queued) {
          queued.source = source
          queued.resolvers.push({ resolve, reject })
        } else {
          queued = { source, resolvers: [{ resolve, reject }] }
          if (!inflight) void pump()
        }
      })
    },
  }
}
