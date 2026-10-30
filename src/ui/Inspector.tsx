import { Hash, Paintbrush, Type } from 'lucide-react'
import { useStore, selectActive } from '@/state/store'
import { bridge } from '@/editor/bridge'
import { setSlideDirective, toggleSlideClass } from '@/core/transforms'

/**
 * Floating directive bar for the active slide. Each control writes a spot
 * directive (`_key`) into the markdown – nothing is stored outside the file.
 */
export function Inspector() {
  const slide = useStore(selectActive)
  const index = useStore((s) => s.activeSlide)
  if (!slide) return null
  const classes = (slide.effective.class ?? '').split(/\s+/).filter(Boolean)
  const paginated = slide.effective.paginate === 'true'
  const bg = slide.effective.backgroundColor
  const color = slide.effective.color

  const toggleClass = (c: string) => bridge.transform((d) => toggleSlideClass(d, index, c))
  const set = (key: string, value: string | null) => bridge.transform((d) => setSlideDirective(d, index, key, value))

  return (
    <div className="inspector" role="toolbar" aria-label="슬라이드 디렉티브">
      <span className="inspector__label">#{index + 1}</span>
      <div className="inspector__group">
        <button className={`chip${classes.includes('lead') ? ' is-on' : ''}`} onClick={() => toggleClass('lead')} title="_class: lead">lead</button>
        <button className={`chip${classes.includes('invert') ? ' is-on' : ''}`} onClick={() => toggleClass('invert')} title="_class: invert">invert</button>
      </div>
      <div className="inspector__group">
        <button className={`chip${paginated ? ' is-on' : ''}`} onClick={() => set('paginate', slide.declared.some((d) => d.key === 'paginate' && d.spot) ? null : paginated ? 'false' : 'true')} title="_paginate">
          <Hash size={12} /> 번호
        </button>
        <label className={`chip chip--color${bg ? ' is-on' : ''}`} title="_backgroundColor">
          <Paintbrush size={12} /> 배경
          <input type="color" value={toHex(bg) ?? '#ffffff'} onChange={(e) => set('backgroundColor', e.target.value)} />
          {bg && <span className="chip__swatch" style={{ background: bg }} onClick={(e) => { e.preventDefault(); set('backgroundColor', null) }} title="제거" />}
        </label>
        <label className={`chip chip--color${color ? ' is-on' : ''}`} title="_color">
          <Type size={12} /> 글자
          <input type="color" value={toHex(color) ?? '#000000'} onChange={(e) => set('color', e.target.value)} />
          {color && <span className="chip__swatch" style={{ background: color }} onClick={(e) => { e.preventDefault(); set('color', null) }} title="제거" />}
        </label>
      </div>
      {slide.declared.filter((d) => !['class', 'paginate', 'backgroundColor', 'color'].includes(d.key)).map((d) => (
        <span key={d.key + d.line} className="chip chip--static" title={`line ${d.line + 1}`} onClick={() => bridge.goToLine(d.line)}>
          {d.spot ? '_' : ''}{d.key}: {d.value}
        </span>
      ))}
    </div>
  )
}

function toHex(v?: string): string | undefined {
  if (!v) return undefined
  if (/^#[0-9a-f]{6}$/i.test(v)) return v
  if (/^#[0-9a-f]{3}$/i.test(v)) return '#' + [...v.slice(1)].map((c) => c + c).join('')
  return undefined
}
