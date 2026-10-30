# edi · marp

브라우저에서 돌아가는 [Marp](https://marp.app) 슬라이드 에디터.
마크다운이 유일한 진실이고, 나머지는 전부 그 위의 뷰다.

```bash
npm install
npm run dev      # http://localhost:5173
npm test         # core 단위 테스트
npm run build    # dist/
```

## 쓰는 법

| 단축키 | 동작 |
| --- | --- |
| `⌘ K` | 커맨드 팔레트 — 모든 기능이 여기 있다 |
| `⌘ ⏎` | 현재 슬라이드 아래에 새 슬라이드 |
| `⌘ ⇧ D` / `⌘ ⇧ ⌫` | 슬라이드 복제 / 삭제 |
| `⌘ ⇧ ↑` / `↓` | 슬라이드 순서 이동 |
| `⌘ 1` `⌘ 2` `⌘ 3` | 레일 / 에디터 / 미리보기 토글 |
| `⌘ G` | 미리보기 포커스 ↔ 그리드 |
| `⌘ ⇧ P` | 발표 모드 (`N` 발표자 노트, `Esc` 종료) |
| `⌘ O` / `⌘ S` / `⌘ ⇧ S` | 열기 / 저장 / 다른 이름으로 |
| `⌘ ⇧ E` | 단독 실행 HTML 내보내기 |

- 커서가 있는 슬라이드가 항상 미리보기에 보인다. 미리보기 요소를 클릭하면 그 줄로 에디터가 점프한다.
- 미리보기 아래 인스펙터의 칩(`lead`, `invert`, 번호, 배경, 글자)은 해당 슬라이드에 `<!-- _key: value -->` 주석을 쓰거나 지운다.
- 레일에서 썸네일을 드래그하면 슬라이드 순서가 바뀐다.
- 초안은 브라우저에 자동 저장된다. 파일 저장은 File System Access API를 쓰고, 지원하지 않는 브라우저에서는 다운로드로 대체한다.
- 테마: Marp 기본 `default` · `gaia` · `uncommon` 에 더해 이 에디터만의 `paper`, `noir`.

## 구조

```
src/
  core/        순수 모듈. DOM도 React도 모른다.
    document.ts    마크다운 → 슬라이드 범위 / 디렉티브 / 제목
    transforms.ts  모든 구조 변경은 (doc) => Edit[] 순수 함수
    edits.ts       Edit[] 를 문자열에 적용 (테스트/헤드리스용)
    export.ts      단독 HTML, 인쇄→PDF
    storage.ts     초안 자동 저장, 파일 열기/저장
  render/      Marp 렌더링. Web Worker 우선, 메인 스레드 폴백, 최신 요청만 처리
  editor/      CodeMirror 6 설정 + 에디터 브리지 (Edit[] 를 트랜잭션으로 디스패치)
  state/       zustand 스토어, 커맨드 레지스트리 (팔레트·툴바·단축키가 공유)
  ui/          React 컴포넌트. 슬라이드는 Shadow DOM 안에서 렌더되어 앱 CSS와 격리
  themes/      커스텀 Marp 테마 CSS
```

핵심 아이디어 세 가지.

1. **텍스트가 진실.** GUI는 상태를 따로 갖지 않는다. 인스펙터 토글, 테마 변경, 슬라이드 이동은 전부 `core/transforms.ts` 의 순수 함수가 돌려주는 `Edit[]` 로 환원되고, 브리지가 그것을 CodeMirror 트랜잭션으로 보낸다. 그래서 되돌리기(⌘Z)가 모든 조작에 자연스럽게 통한다.
2. **소스 라인 매핑.** markdown-it 플러그인이 블록 요소에 `data-line` 을 찍는다. 미리보기 클릭 → 에디터 점프가 여기서 나온다.
3. **격리된 렌더.** Marp 는 워커에서 돌고, 결과 SVG 는 Shadow DOM 에 들어간다. 모든 썸네일이 하나의 constructed stylesheet 를 공유하므로 슬라이드가 많아져도 CSS 파싱은 한 번이다.
