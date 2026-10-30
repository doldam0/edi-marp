/**
 * Everything the user can do, as data. The command palette, the top bar and
 * the keyboard shortcuts are all views over this one list.
 */
import { useStore } from './store'
import { bridge } from '@/editor/bridge'
import { insertSlide, deleteSlide, duplicateSlide, moveSlide, setGlobalDirective, toggleSlideClass, setSlideDirective } from '@/core/transforms'
import { THEMES } from '@/themes'
import { buildStandaloneHtml, printToPdf } from '@/core/export'
import { downloadBlob, openMarkdownFile, saveMarkdownFile } from '@/core/storage'

export interface Command {
  id: string
  title: string
  section: 'slide' | 'deck' | 'insert' | 'view' | 'file'
  hint?: string
  /** display string, e.g. "⌘⇧D" */
  shortcut?: string
  keywords?: string
  run(): unknown
}

const S = useStore.getState

const SNIPPETS: Record<string, { title: string; body: string; hint: string }> = {
  image: { title: '이미지', hint: '![bg right](...) 형식', body: '![bg right:40%](https://picsum.photos/800/600)\n' },
  columns: { title: '2단 레이아웃', hint: 'flex 컨테이너', body: '<div style="display:flex;gap:2em">\n<div style="flex:1">\n\n왼쪽\n\n</div>\n<div style="flex:1">\n\n오른쪽\n\n</div>\n</div>\n' },
  code: { title: '코드 블록', hint: '```lang', body: '```ts\n\n```\n' },
  math: { title: '수식', hint: 'KaTeX', body: '$$\n\n$$\n' },
  table: { title: '표', hint: '3×2', body: '| 항목 | 값 |\n| --- | --- |\n|  |  |\n' },
  note: { title: '발표자 노트', hint: 'HTML 주석', body: '<!-- 발표자 노트 -->\n' },
  bgcolor: { title: '배경 이미지', hint: '![bg](...)', body: '![bg brightness:.6](https://picsum.photos/1280/720)\n' },
}

export function buildCommands(): Command[] {
  const { doc, activeSlide, panels, previewMode, scheme, file, render } = S()
  const slide = doc.slides[activeSlide]
  const title = file.name.replace(/\.md$/i, '')

  const cmds: Command[] = [
    { id: 'slide.new', title: '아래에 새 슬라이드', section: 'slide', shortcut: '⌘⏎', keywords: 'insert add new slide', run: () => bridge.transform((d) => insertSlide(d, S().activeSlide), { scrollTo: slideEndOffset() + 6 }) },
    { id: 'slide.dup', title: '슬라이드 복제', section: 'slide', shortcut: '⌘⇧D', keywords: 'duplicate copy', run: () => bridge.transform((d) => duplicateSlide(d, S().activeSlide)) },
    { id: 'slide.delete', title: '슬라이드 삭제', section: 'slide', shortcut: '⌘⇧⌫', keywords: 'delete remove', run: () => bridge.transform((d) => deleteSlide(d, S().activeSlide)) },
    { id: 'slide.up', title: '슬라이드 위로 이동', section: 'slide', shortcut: '⌘⇧↑', keywords: 'move up reorder', run: () => moveActive(-1) },
    { id: 'slide.down', title: '슬라이드 아래로 이동', section: 'slide', shortcut: '⌘⇧↓', keywords: 'move down reorder', run: () => moveActive(1) },
    { id: 'slide.lead', title: `이 슬라이드: lead ${has('lead') ? '해제' : '적용'}`, section: 'slide', keywords: 'class lead title center', run: () => bridge.transform((d) => toggleSlideClass(d, S().activeSlide, 'lead')) },
    { id: 'slide.invert', title: `이 슬라이드: invert ${has('invert') ? '해제' : '적용'}`, section: 'slide', keywords: 'class invert dark', run: () => bridge.transform((d) => toggleSlideClass(d, S().activeSlide, 'invert')) },
    { id: 'slide.paginate', title: `이 슬라이드: 페이지 번호 ${slide?.effective.paginate === 'false' ? '보이기' : '숨기기'}`, section: 'slide', keywords: 'paginate number', run: () => bridge.transform((d) => setSlideDirective(d, S().activeSlide, 'paginate', d.slides[S().activeSlide]?.effective.paginate === 'false' ? null : 'false')) },

    ...THEMES.map<Command>((t) => ({
      id: `deck.theme.${t.name}`, title: `테마: ${t.label}`, hint: t.description, section: 'deck', keywords: `theme ${t.name}`,
      run: () => bridge.transform((d) => setGlobalDirective(d, 'theme', t.name)),
    })),
    { id: 'deck.paginate', title: `덱 전체: 페이지 번호 ${doc.globals.paginate === 'true' ? '끄기' : '켜기'}`, section: 'deck', keywords: 'paginate numbers global', run: () => bridge.transform((d) => setGlobalDirective(d, 'paginate', d.globals.paginate === 'true' ? null : 'true')) },
    { id: 'deck.size169', title: '슬라이드 크기: 16:9', section: 'deck', keywords: 'size aspect', run: () => bridge.transform((d) => setGlobalDirective(d, 'size', null)) },
    { id: 'deck.size43', title: '슬라이드 크기: 4:3', section: 'deck', keywords: 'size aspect', run: () => bridge.transform((d) => setGlobalDirective(d, 'size', '4:3')) },
    { id: 'deck.header', title: '덱 전체: 헤더 설정…', section: 'deck', keywords: 'header', run: () => prompt('헤더 텍스트', doc.globals.header ?? '').then((v) => v !== null && bridge.transform((d) => setGlobalDirective(d, 'header', v || null))) },
    { id: 'deck.footer', title: '덱 전체: 푸터 설정…', section: 'deck', keywords: 'footer', run: () => prompt('푸터 텍스트', doc.globals.footer ?? '').then((v) => v !== null && bridge.transform((d) => setGlobalDirective(d, 'footer', v || null))) },

    ...Object.entries(SNIPPETS).map<Command>(([k, s]) => ({
      id: `insert.${k}`, title: `삽입: ${s.title}`, hint: s.hint, section: 'insert', keywords: `insert snippet ${k}`,
      run: () => bridge.insertAtCursor(s.body),
    })),

    { id: 'view.palette', title: '커맨드 팔레트', section: 'view', shortcut: '⌘K', run: () => S().setPaletteOpen(true) },
    { id: 'view.rail', title: `${panels.rail ? '숨기기' : '보이기'}: 슬라이드 레일`, section: 'view', shortcut: '⌘1', keywords: 'rail thumbnails sidebar', run: () => S().togglePanel('rail') },
    { id: 'view.editor', title: `${panels.editor ? '숨기기' : '보이기'}: 에디터`, section: 'view', shortcut: '⌘2', keywords: 'editor code', run: () => S().togglePanel('editor') },
    { id: 'view.preview', title: `${panels.preview ? '숨기기' : '보이기'}: 미리보기`, section: 'view', shortcut: '⌘3', keywords: 'preview', run: () => S().togglePanel('preview') },
    { id: 'view.mode', title: `미리보기: ${previewMode === 'focus' ? '그리드' : '포커스'} 모드`, section: 'view', shortcut: '⌘G', keywords: 'grid focus overview', run: () => S().setPreviewMode(previewMode === 'focus' ? 'grid' : 'focus') },
    { id: 'view.present', title: '발표 시작', section: 'view', shortcut: '⌘⇧P', keywords: 'present fullscreen', run: () => S().setPresenting(true) },
    { id: 'view.scheme', title: `${scheme === 'dark' ? '라이트' : '다크'} 모드로`, section: 'view', keywords: 'theme dark light color scheme', run: () => S().setScheme(scheme === 'dark' ? 'light' : 'dark') },
    { id: 'view.zen', title: '집중 모드 (에디터만)', section: 'view', keywords: 'zen focus writing', run: () => S().setPanels({ rail: false, editor: true, preview: false }) },
    { id: 'view.all', title: '모든 패널 보이기', section: 'view', keywords: 'reset layout', run: () => S().setPanels({ rail: true, editor: true, preview: true }) },

    { id: 'file.open', title: '열기…', section: 'file', shortcut: '⌘O', keywords: 'open load', run: openFile },
    { id: 'file.save', title: '저장', section: 'file', shortcut: '⌘S', keywords: 'save write', run: () => saveFile(false) },
    { id: 'file.saveAs', title: '다른 이름으로 저장…', section: 'file', shortcut: '⌘⇧S', keywords: 'save as', run: () => saveFile(true) },
    { id: 'file.rename', title: '파일 이름 바꾸기…', section: 'file', keywords: 'rename title', run: () => prompt('파일 이름', file.name).then((v) => v && S().setFile({ name: v.endsWith('.md') ? v : `${v}.md`, handle: null })) },
    { id: 'file.exportHtml', title: '내보내기: HTML', section: 'file', shortcut: '⌘⇧E', hint: '단독 실행 HTML, F로 발표', keywords: 'export html', run: () => render && downloadBlob(`${title}.html`, new Blob([buildStandaloneHtml(render, title)], { type: 'text/html' })) },
    { id: 'file.exportPdf', title: '내보내기: PDF', section: 'file', hint: '인쇄 대화상자 → PDF로 저장', keywords: 'export pdf print', run: () => render && printToPdf(render, title) },
    { id: 'file.exportMd', title: '내보내기: Markdown 다운로드', section: 'file', keywords: 'export markdown download', run: () => downloadBlob(file.name, new Blob([S().source], { type: 'text/markdown' })) },
    { id: 'file.new', title: '새 문서', section: 'file', hint: '현재 내용을 비웁니다', keywords: 'new clear', run: () => { if (!S().file.dirty || confirm('저장하지 않은 변경이 있습니다. 비울까요?')) { bridge.applyEdits([{ from: 0, to: S().source.length, insert: '---\nmarp: true\ntheme: default\n---\n\n# \n' }]); S().setFile({ name: 'untitled.md', handle: null, dirty: false }) } } },
  ]

  if (doc.slides.length > 1) {
    cmds.push(...doc.slides.map<Command>((s) => ({
      id: `goto.${s.index}`, title: `이동: ${s.index + 1}. ${s.title || '(제목 없음)'}`, section: 'slide', keywords: `goto go to slide ${s.index + 1}`,
      run: () => bridge.goToSlide(s.index),
    })))
  }
  return cmds

  function has(cls: string) { return (slide?.effective.class ?? '').split(/\s+/).includes(cls) }
  function slideEndOffset() { const s = S().doc.slides[S().activeSlide]; return S().doc.offsets[Math.min(s.range.to, S().doc.lines.length)] }
  function moveActive(delta: number) {
    const i = S().activeSlide, j = i + delta
    if (j < 0 || j >= S().doc.slides.length) return
    bridge.transform((d) => moveSlide(d, i, j))
    requestAnimationFrame(() => bridge.goToSlide(j, { focus: false }))
  }
}

async function prompt(label: string, initial = ''): Promise<string | null> {
  return window.prompt(label, initial)
}

export async function openFile() {
  const r = await openMarkdownFile()
  if (!r) return
  const { setSource, setFile } = S()
  bridge.applyEdits([{ from: 0, to: S().source.length, insert: r.source }])
  setSource(r.source)
  setFile({ name: r.name, handle: r.handle, dirty: false, savedAt: Date.now() })
  bridge.goToLine(0)
}

export async function saveFile(saveAs: boolean) {
  const { source, file, setFile } = S()
  const r = await saveMarkdownFile(source, file.name, file.handle, { saveAs })
  if (r) setFile({ name: r.name, handle: r.handle, dirty: false, savedAt: Date.now() })
}

/** Keyboard shortcuts → command ids. `mod` = ⌘ on mac / Ctrl elsewhere. */
export const SHORTCUTS: Array<{ key: string; mod?: boolean; shift?: boolean; id: string }> = [
  { key: 'k', mod: true, id: 'view.palette' },
  { key: 'Enter', mod: true, id: 'slide.new' },
  { key: 'd', mod: true, shift: true, id: 'slide.dup' },
  { key: 'Backspace', mod: true, shift: true, id: 'slide.delete' },
  { key: 'ArrowUp', mod: true, shift: true, id: 'slide.up' },
  { key: 'ArrowDown', mod: true, shift: true, id: 'slide.down' },
  { key: '1', mod: true, id: 'view.rail' },
  { key: '2', mod: true, id: 'view.editor' },
  { key: '3', mod: true, id: 'view.preview' },
  { key: 'g', mod: true, id: 'view.mode' },
  { key: 'p', mod: true, shift: true, id: 'view.present' },
  { key: 'o', mod: true, id: 'file.open' },
  { key: 's', mod: true, id: 'file.save' },
  { key: 's', mod: true, shift: true, id: 'file.saveAs' },
  { key: 'e', mod: true, shift: true, id: 'file.exportHtml' },
]
