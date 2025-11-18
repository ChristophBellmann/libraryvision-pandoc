#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Basisverzeichnis = Ordner dieser Datei
# ------------------------------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE_DIR"

# ------------------------------------------------------------
# Konfiguration laden
# Standard: ./libraryvision.config
# Alternativ: LIBRARYVISION_CONFIG=/pfad/zur/datei ./make_libraryvision.sh
# ------------------------------------------------------------
CONFIG_FILE="${LIBRARYVISION_CONFIG:-libraryvision.config}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "FEHLER: Konfigurationsdatei '$CONFIG_FILE' nicht gefunden." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Erwartete Variablen:
required_vars=(LIB_INPUT_ROOT LIB_BUILD_ROOT LIB_OVERVIEW_FILENAME LIB_TEMPLATE_FILENAME LIB_OUTPUT_SUFFIX LIB_TITLE_PREFIX LIB_LV_OUTPUT)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var-}" ]]; then
    echo "FEHLER: Variable '$var' ist in '$CONFIG_FILE' nicht gesetzt." >&2
    exit 1
  fi
done

mkdir -p "$LIB_BUILD_ROOT"

# ------------------------------------------------------------
# Hilfsfunktionen
# ------------------------------------------------------------

usage() {
  cat <<EOF
Verwendung: ./make_libraryvision.sh [PROJEKT|--all|--LV]

  PROJEKT   Name eines Unterordners in $LIB_INPUT_ROOT (z.B. Messtechnik-Script)
  --all     alle Projekte unter $LIB_INPUT_ROOT bauen
  --LV      alle existierenden Projekt-PDFs zu einem LV-PDF zusammenfügen
EOF
}

discover_projects() {
  # Gibt eine Liste von Projektnamen aus (Ordner unter LIB_INPUT_ROOT mit overview.md)
  local p
  if [[ ! -d "$LIB_INPUT_ROOT" ]]; then
    return
  fi
  for p in "$LIB_INPUT_ROOT"/*; do
    [[ -d "$p" ]] || continue
    local name
    name="$(basename "$p")"
    if [[ -f "$p/$LIB_OVERVIEW_FILENAME" ]]; then
      echo "$name"
    fi
  done
}

build_project() {
  local project="$1"
  echo
  echo "================== LibraryVision: Projekt '$project' =================="

  local PROJECT_ROOT="$LIB_INPUT_ROOT/$project"

  if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "FEHLER: Projektordner '$PROJECT_ROOT' existiert nicht." >&2
    return 1
  fi

  # Build-Ordner pro Projekt
  local BUILD_DIR="$LIB_BUILD_ROOT/$project"
  mkdir -p "$BUILD_DIR"

  # Eingaben
  local SRC_MD="$PROJECT_ROOT/$LIB_OVERVIEW_FILENAME"
  local TEMPLATE_BASE="$PROJECT_ROOT/$LIB_TEMPLATE_FILENAME"

  # Ausgaben / Zwischenartefakte NUR im Build-Ordner
  local LIB_MD="$BUILD_DIR/${LIB_OVERVIEW_FILENAME%.md}_libraryvision.md"
  local TEMPLATE_LIB="$BUILD_DIR/${LIB_TEMPLATE_FILENAME%.tex}_libraryvision.tex"
  local CSV_OFFSETS="$BUILD_DIR/pdf_offsets.csv"

  local OUTPUT_BASENAME="${project}${LIB_OUTPUT_SUFFIX}"
  local OVERVIEW_PDF_TEMP="$BUILD_DIR/${OUTPUT_BASENAME}_overview.pdf"
  local LIB_PDF_TEMP="$BUILD_DIR/${OUTPUT_BASENAME}_temp.pdf"
  local LIB_PDF_OUT="$BUILD_DIR/${OUTPUT_BASENAME}.pdf"
  local TITLE="${LIB_TITLE_PREFIX}${project}"

  echo "Projektroot:               $PROJECT_ROOT"
  echo "Übersicht (Markdown):      $SRC_MD"
  echo "LibraryVision-Markdown:    $LIB_MD"
  echo "Template (Basis):          $TEMPLATE_BASE"
  echo "Template (LibraryVision):  $TEMPLATE_LIB"
  echo "Build-Ordner:              $BUILD_DIR"
  echo "Ausgabe-PDF:               $LIB_PDF_OUT"
  echo

  if [[ ! -f "$SRC_MD" ]]; then
    echo "FEHLER: Übersicht '$SRC_MD' nicht gefunden." >&2
    return 1
  fi
  if [[ ! -f "$TEMPLATE_BASE" ]]; then
    echo "FEHLER: Basis-Template '$TEMPLATE_BASE' nicht gefunden." >&2
    return 1
  fi

  # --------------------------------------------------------------------
  # Schritt 0: PDF-Liste automatisch aus SRC_MD extrahieren
  # --------------------------------------------------------------------
  echo "== Schritt 0: PDF-Liste aus Übersicht extrahieren =="

  local PDF_LIST=()
  while IFS= read -r pdf; do
    [[ -z "$pdf" ]] && continue
    PDF_LIST+=("$pdf")
  done < <(
    SRC_MD="$SRC_MD" python3 << 'PY'
import os
import re

src_md = os.environ["SRC_MD"]

seen = set()
order = []

with open(src_md, encoding="utf-8") as f:
    for line in f:
        # 1) Markdown-Links: (...irgendwas.pdf#page=...)
        for m in re.findall(r"\((\.?\.?/[^)#]+\.pdf)", line):
            path = m.strip()
            path = path.split("#", 1)[0]
            path = re.sub(r"^\./+", "", path)  # führende ./ entfernen
            if path not in seen:
                seen.add(path)
                order.append(path)

        # 2) LaTeX-\href: \href{./...irgendwas.pdf}{Text}
        for m in re.findall(r"\\href\{(\.?\.?/[^}]+\.pdf)\}", line):
            path = m.strip()
            path = path.split("#", 1)[0]
            path = re.sub(r"^\./+", "", path)
            if path not in seen:
                seen.add(path)
                order.append(path)

for p in order:
    print(p)
PY
  )

  echo "   → Gefundene PDFs: ${#PDF_LIST[@]}"
  printf '      - %s\n' "${PDF_LIST[@]}"
  echo

  # --------------------------------------------------------------------
  # Schritt 0.1: LaTeX-Template mit eingebetteten PDFs generieren
  # --------------------------------------------------------------------
  echo "== Schritt 0.1: LaTeX-Library-Template generieren =="

  local TEMP_BLOCKS_FILE="$BUILD_DIR/temp_libraryvision_blocks.tex.tmp"

  cat <<EOF > "$TEMP_BLOCKS_FILE"
% =========================================================
%  LibraryVision: Eingebettete PDFs mit Back-Link
% =========================================================

\\clearpage
\\pdfbookmark[1]{Anhänge}{libraryvision-attachments}

% Makro für Back-Button auf jeder eingebetteten Seite
\\newcommand{\\BackToOverview}{%
  \\hyperlink{overview}{\\textcolor{MidnightBlue}{\\scriptsize Zurück zur Übersicht}}%
}

EOF

  local pdf_rel
  for pdf_rel in "${PDF_LIST[@]}"; do
    # pdf_rel ist der Pfad relativ zum Projektroot
    local pdf_include="$PROJECT_ROOT/$pdf_rel"

    local filename bookmark_text target_id
    filename="$(basename "$pdf_rel")"
    bookmark_text="${filename%.pdf}"
    target_id="$(echo "$bookmark_text" | tr '[:upper:]' '[:lower:]' | tr '/.' '_' )"

    cat <<EOF >> "$TEMP_BLOCKS_FILE"
% -------- ${bookmark_text} ----------------------
\\clearpage
\\pdfbookmark[1]{${bookmark_text}}{${target_id}}
\\phantomsection
\\hypertarget{${target_id}}{}
\\includepdf[
  pages=-,
  pagecommand={\\thispagestyle{empty}\\BackToOverview}
]{${pdf_include}}

EOF
  done

  sed -e '/\$body\$/r '"$TEMP_BLOCKS_FILE"'' \
      "$TEMPLATE_BASE" > "$TEMPLATE_LIB"

  rm "$TEMP_BLOCKS_FILE"

  echo "   → Ausgabe-Template: $TEMPLATE_LIB"
  echo "   → Enthält ${#PDF_LIST[@]} eingebettete PDFs."
  echo

  # --------------------------------------------------------------------
  # Schritt 1: Übersicht-Only-PDF (ohne Anhänge) bauen
  # --------------------------------------------------------------------
  echo "== Schritt 1: Übersicht-PDF (ohne Anhänge) bauen =="

  pandoc "$SRC_MD" \
    -f markdown+raw_tex \
    --template="$TEMPLATE_BASE" \
    --pdf-engine=xelatex \
    -V title="$TITLE" \
    -o "$OVERVIEW_PDF_TEMP"

  local overview_pages
  overview_pages="$(pdfinfo "$OVERVIEW_PDF_TEMP" | awk '/Pages:/ {print $2}')"
  echo "   Übersicht vorne:                $overview_pages Seiten"
  rm "$OVERVIEW_PDF_TEMP"

  # --------------------------------------------------------------------
  # Schritt 2: Seiten der eingebetteten PDFs zählen + Offsets berechnen
  # --------------------------------------------------------------------
  echo "== Schritt 2: Seiten der eingebetteten PDFs zählen =="

  local sum_pdf_pages=0

  echo "pfad,pages,start_bigpage" > "$CSV_OFFSETS"

  for pdf_rel in "${PDF_LIST[@]}"; do
    local file_path="$PROJECT_ROOT/$pdf_rel"
    if [[ ! -f "$file_path" ]]; then
      echo "   WARNUNG: Datei nicht gefunden: $file_path" >&2
      continue
    fi
    local pages
    pages=$(pdfinfo "$file_path" | awk '/Pages:/ {print $2}')
    printf "   %-80s %3d Seiten\n" "$pdf_rel" "$pages"
    sum_pdf_pages=$(( sum_pdf_pages + pages ))
  done

  echo "   Summe aller eingebetteten PDFs: $sum_pdf_pages Seiten"
  echo "   Übersicht vorne:                $overview_pages Seiten"

  if (( overview_pages <= 0 )); then
    echo "FEHLER: Übersicht hat <= 0 Seiten – stimmt etwas nicht?" >&2
    return 1
  fi

  echo "pfad,pages,start_bigpage" > "$CSV_OFFSETS"
  local current_start=$(( overview_pages + 1 ))

  for pdf_rel in "${PDF_LIST[@]}"; do
    local file_path="$PROJECT_ROOT/$pdf_rel"
    if [[ ! -f "$file_path" ]]; then
      echo "   WARNUNG: Datei nicht gefunden: $file_path (Offset-Eintrag wird übersprungen!)" >&2
      continue
    fi
    local pages
    pages=$(pdfinfo "$file_path" | awk '/Pages:/ {print $2}')
    printf "   %-80s %3d Seiten (Start im Dokument: %d)\n" "$pdf_rel" "$pages" "$current_start"
    echo "$pdf_rel,$pages,$current_start" >> "$CSV_OFFSETS"
    current_start=$(( current_start + pages ))
  done

  echo "   CSV geschrieben: $CSV_OFFSETS"
  echo

  # --------------------------------------------------------------------
  # Schritt 3: LIB_MD aus SRC_MD erzeugen, Links auf interne Seiten umbiegen
  # --------------------------------------------------------------------
  echo "== Schritt 3: $LIB_MD erzeugen (Links umbiegen) =="

SRC_MD="$SRC_MD" LIB_MD="$LIB_MD" CSV_OFFSETS="$CSV_OFFSETS" python3 << 'PY'
import csv
import os
import re

src_md = os.environ["SRC_MD"]
lib_md = os.environ["LIB_MD"]
csv_path = os.environ["CSV_OFFSETS"]

def norm_path(p: str) -> str:
  p = p.strip().replace("\\", "/")
  p = re.sub(r"^\./+", "", p)
  return p

# Offsets aus CSV einlesen: normierter Pfad -> Startseite im Dokument
offsets = {}
with open(csv_path, newline="", encoding="utf-8") as f:
  reader = csv.DictReader(f)
  for row in reader:
      raw_path = row["pfad"]
      start = int(row["start_bigpage"])
      offsets[norm_path(raw_path)] = start

md_total = md_pdf = md_rewritten = 0
href_total = href_pdf = href_rewritten = 0

def rewrite_md_link(match):
  global md_total, md_pdf, md_rewritten
  md_total += 1

  text = match.group("text")
  pdf  = match.group("pdf")
  page = match.group("page")
  page_num = int(page) if page is not None else 1

  norm = norm_path(pdf)

  if norm in offsets:
      md_pdf += 1
      target = offsets[norm] + page_num - 1
      md_rewritten += 1
      # Markdown-Link -> \hyperlink
      return r"\hyperlink{page.%d}{%s}" % (target, text)
  else:
      return match.group(0)

def rewrite_href(match):
  global href_total, href_pdf, href_rewritten
  href_total += 1

  pdf  = match.group("pdf")
  page = match.group("page")
  text = match.group("text")
  page_num = int(page) if page is not None else 1

  norm = norm_path(pdf)

  if norm in offsets:
      href_pdf += 1
      target = offsets[norm] + page_num - 1
      href_rewritten += 1
      # \href -> \hyperlink
      return r"\hyperlink{page.%d}{%s}" % (target, text)
  else:
      return match.group(0)

# Markdown-Links: [Text](pfad/datei.pdf#page=N)
md_pattern = re.compile(
  r"""\[(?P<text>[^\]]+)]\(      # [Text](
      (?P<pdf>[^)#]+\.pdf)       # Pfad bis .pdf, kein ) oder #
      (?:\#page=(?P<page>\d+))?  # optional #page=N
      \)                         # )
  """,
  re.VERBOSE,
)

# LaTeX-\href: \href{pfad/datei.pdf#page=N}{Text}
href_pattern = re.compile(
  r"""\\href\{                   # \href{
       (?P<pdf>[^}#]+\.pdf)      # Pfad bis .pdf, kein } oder #
       (?:\#page=(?P<page>\d+))? # optional #page=N
     \}\{                        # }{
       (?P<text>[^}]*)           # Linktext
     \}                          # }
  """,
  re.VERBOSE,
)

with open(src_md, encoding="utf-8") as fin, \
   open(lib_md, "w", encoding="utf-8") as fout:
  for line in fin:
      line = md_pattern.sub(rewrite_md_link, line)
      line = href_pattern.sub(rewrite_href, line)
      fout.write(line)

print("LibraryVision – Link-Rewrite Zusammenfassung:")
print(f"  Markdown-Links gesamt:        {md_total}")
print(f"    davon .pdf (in Offsets):    {md_pdf}")
print(f"    erfolgreich ersetzt:        {md_rewritten}")
print(f"  LaTeX-\\href-Links gesamt:    {href_total}")
print(f"    davon .pdf (in Offsets):    {href_pdf}")
print(f"    erfolgreich ersetzt:        {href_rewritten}")
PY

  echo
  echo "   Fertig: $LIB_MD"
  echo

  # --------------------------------------------------------------------
  # Schritt 4: Finale LibraryVision-PDF mit aktualisierten Links bauen
  # --------------------------------------------------------------------
  echo "== Schritt 4: Finale LibraryVision-PDF bauen =="

  pandoc "$LIB_MD" \
    -f markdown+raw_tex \
    --template="$TEMPLATE_LIB" \
    --pdf-engine=xelatex \
    -V title="$TITLE" \
    -o "$LIB_PDF_TEMP"

  mv "$LIB_PDF_TEMP" "$LIB_PDF_OUT"

  echo
  echo "LibraryVision – Projekt '$project' fertig:"
  echo "  - Übersicht (Markdown, umgeschriebene Links): $LIB_MD"
  echo "  - Template (LibraryVision):                   $TEMPLATE_LIB"
  echo "  - Offsets (CSV):                              $CSV_OFFSETS"
  echo "  - LibraryVision-PDF:                          $LIB_PDF_OUT"
  echo

  # Optionales Aufräumen, gesteuert über LIB_KEEP_INTERMEDIATE
  if [[ "${LIB_KEEP_INTERMEDIATE:-true}" != "true" ]]; then
    echo "Bereinige Zwischenartefakte im Build-Ordner..."
    rm -f "$LIB_MD" "$TEMPLATE_LIB" "$CSV_OFFSETS"
  fi
}

build_LV() {
  echo "== LibraryVision – LV-PDF aus allen Projekt-PDFs bauen =="

  local projects
  mapfile -t projects < <(discover_projects)

  if (( ${#projects[@]} == 0 )); then
    echo "Keine Projekte gefunden." >&2
    return 1
  fi

  local pdfs=()
  local project
  for project in "${projects[@]}"; do
    local OUTPUT_BASENAME="${project}${LIB_OUTPUT_SUFFIX}"
    local pdf_path="$LIB_BUILD_ROOT/$project/${OUTPUT_BASENAME}.pdf"
    if [[ -f "$pdf_path" ]]; then
      pdfs+=("$pdf_path")
    else
      echo "WARNUNG: Projekt-PDF fehlt (erst bauen?): $pdf_path" >&2
    fi
  done

  if (( ${#pdfs[@]} == 0 )); then
    echo "Keine Projekt-PDFs zum Zusammenfügen gefunden." >&2
    return 1
  fi

  local LV_pdf="$LIB_BUILD_ROOT/${LIB_LV_OUTPUT}.pdf"

  echo "Füge folgende PDFs zusammen:"
  printf '  - %s\n' "${pdfs[@]}"
  echo "→ Ausgabe: $LV_pdf"

  # einfache Zusammenführung (keine neuen internen Links)
  pdfunite "${pdfs[@]}" "$LV_pdf"

  echo "LV-PDF fertig: $LV_pdf"
}

# ------------------------------------------------------------
# Argumente auswerten
# ------------------------------------------------------------
arg="${1-}"

case "$arg" in
  --all)
    mapfile -t projects < <(discover_projects)
    if (( ${#projects[@]} == 0 )); then
      echo "Keine Projekte in '$LIB_INPUT_ROOT' gefunden." >&2
      exit 1
    fi
    for p in "${projects[@]}"; do
      build_project "$p"
    done
    ;;
  --LV)
    build_LV
    ;;
  "" )
    mapfile -t projects < <(discover_projects)
    if (( ${#projects[@]} == 0 )); then
      echo "Keine Projekte gefunden." >&2
      exit 1
    elif (( ${#projects[@]} == 1 )); then
      build_project "${projects[0]}"
    else
      echo "Mehrere Projekte gefunden:"
      printf '  - %s\n' "${projects[@]}"
      echo
      echo "Bitte eines angeben, z.B.:"
      echo "  ./make_libraryvision.sh Messtechnik-Script"
      echo "oder alle bauen:"
      echo "  ./make_libraryvision.sh --all"
      exit 1
    fi
    ;;
  -*)
    usage
    exit 1
    ;;
  *)
    build_project "$arg"
    ;;
esac

