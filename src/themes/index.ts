import paper from './paper.css?raw'
import noir from './noir.css?raw'

export interface ThemeInfo {
  name: string
  label: string
  description: string
  /** custom CSS – undefined for Marp built-ins */
  css?: string
}

export const THEMES: ThemeInfo[] = [
  { name: 'default', label: 'Default', description: 'Marp 기본 테마. 흰 배경, GitHub 느낌' },
  { name: 'gaia', label: 'Gaia', description: '따뜻한 베이지 톤, 큼직한 타이포' },
  { name: 'uncommon', label: 'Uncommon', description: '미니멀 흑백, 넉넉한 여백' },
  { name: 'paper', label: 'Paper', description: '세리프, 종이 질감의 에디토리얼 테마', css: paper },
  { name: 'noir', label: 'Noir', description: '블랙 + 라임 악센트, 개발자 발표용', css: noir },
]

export const CUSTOM_THEME_CSS = THEMES.flatMap((t) => (t.css ? [t.css] : []))
