#!/usr/bin/env bash
# db2 위키(wiki/)를 Quartz content/로 동기화한다.
# 발행 제외 규칙을 결정적으로 적용한다 (배포자 에이전트가 매번 이 스크립트를 돌린다).
# 원본 wiki/는 읽기만 한다 — 절대 수정하지 않는다.
set -euo pipefail

WIKI="/c/project/obsodian/db2/wiki"
CONTENT="/c/project/obsodian/quartz-site/content"

# wiki/ 기준 상대경로. 발행에서 제외할 파일.
#  - 생존 인물 비판 사례(명예훼손 노출) / 내부 파일(템플릿·작업로그=원본 파일명 노출)
EXCLUDE_FILES=(
  "사례/조현아.md"
  "사례/윤석열과 김건희.md"
  "_template.md"
  "log.md"
)

# 위 제외 페이지를 가리키는 [[위키링크]]를 본문에서 정리할 대상 이름(확장자·폴더 없이)
EXCLUDE_NAMES=("조현아" "윤석열과 김건희")

echo "→ content/ 비우고 wiki/ 복사"
rm -rf "$CONTENT"
mkdir -p "$CONTENT"
cp -r "$WIKI/." "$CONTENT/"

echo "→ 제외 파일 제거"
for f in "${EXCLUDE_FILES[@]}"; do
  rm -f "$CONTENT/$f" && echo "   - $f"
done

echo "→ 비공개 '원본 색인' 섹션을 발행본 index.md에서 제거 (원본은 웹에 안 나감)"
if [ -f "$CONTENT/index.md" ]; then
  perl -i -ne 'print unless /\[\[원본 색인\]\]/ or /^##\s*원본\s*\(비공개\)/' "$CONTENT/index.md"
fi

echo "→ 제외 페이지로 향하는 깨진 위키링크 정리"
for name in "${EXCLUDE_NAMES[@]}"; do
  export SCRUB_NAME="$name"   # perl 자식 프로세스가 상속받도록 export
  while IFS= read -r file; do
    # "· [[name]](설명)" / "[[name]](설명) ·" / 단독 "[[name]](설명)" 세 경우를 제거
    perl -i -pe '
      BEGIN { $n = quotemeta($ENV{SCRUB_NAME}); }
      s/\s*·\s*\[\[$n\]\](\([^)]*\))?//g;
      s/\[\[$n\]\](\([^)]*\))?\s*·\s*//g;
      s/\[\[$n\]\](\([^)]*\))?//g;
    ' "$file"
    echo "   ~ $(basename "$file") 에서 [[$name]] 제거"
  done < <(grep -rl "\[\[$name\]\]" "$CONTENT" 2>/dev/null || true)
done
unset SCRUB_NAME

echo "→ 링크 제거로 생긴 dangling 구분자(·) 정리"
find "$CONTENT" -name '*.md' -print0 | while IFS= read -r -d '' f; do
  perl -0777 -i -pe '
    s/[ \t]*·[ \t]*\n[ \t]*\n/\n/g;      # 줄 끝 "·" + 빈 연속줄  →  다음 줄과 합침
    s/[ \t]*·[ \t]*\n([ \t]*-[ \t])/\n$1/g; # 줄 끝 "·" 다음이 새 목록 항목
    s/[ \t]*·[ \t]*$//mg;                 # 줄 끝에 홀로 남은 "·"
  ' "$f"
done

PAGES=$(find "$CONTENT" -name '*.md' | wc -l)
echo "✓ sync 완료: content/ 에 $PAGES 페이지"
