# LibraryVision – PDF Library Builder

LibraryVision ist ein generisches System zum automatisierten Erstellen einer
zusammenhängenden, klickbaren Gesamt-PDF („Library Document“) aus:

- einer Markdown-Übersicht  
- mehreren externen PDF-Dateien in `./input/`  
- Pandoc + XeLaTeX  
- automatischer Link-Umschreibung  
- und PDF-Einbettung inklusive „Zurück zur Übersicht“-Link.

Das Projekt ist **allgemein gehalten**, universell einsetzbar für technische
Dokumentationen, Unterlagensammlungen, Projekte, Archive oder beliebige
PDF-Strukturen.

---

## Benutzung

```
./libravision.sh Projektname
```

Projektname ist der Ordner in `./input/`

---

## Features

- Automatische Erkennung aller PDF-Referenzen in der Übersicht
- Verarbeitung beliebiger Unterordner in `./input/`
- Erzeugung eines Library-Templates mit eingebetteten PDFs
- Interne Hyperlinks auf exakte Seitenpositionen
- Übersicht ohne sichtbare Seitennummern (optional)
- Einbettung mit „Back-to-Overview“-Button
- Konfiguration über `libraryvision.config`
- Komplett CLI-basiert

---

## Beispielhafte Ordnerstruktur

```
.
├── input/
│   ├── kapitel1/
│   │   ├── dokument1.pdf
│   │   └── anhang.pdf
│   ├── kapitel2/
│   │   └── protokoll.pdf
│   └── weitere_datei.pdf
├── overview.md
├── overview_template.tex
├── libraryvision.config
├── libraryvision.sh
└── build/
```

---

## Übersicht: `overview.md`

Links auf PDFs sehen so aus:

```markdown
[Dokument A](./input/kapitel1/dokument1.pdf#page=2)
[Anhang](input/kapitel1/anhang.pdf)
```

`libraryvision.sh` erkennt diese automatisch,
normiert die Pfade, zählt die Seiten und berechnet interne Bigfile-Seiten.

---

## Konfiguration (`libraryvision.config`)

Beispiel:

```bash
# Übersicht (Markdown)
SRC_MD="overview.md"

# Ausgabe der link-umschriebenen Version
LIB_MD="overview_libraryvision.md"

# Templates
TEMPLATE_BASE="overview_template.tex"
TEMPLATE_LIB="overview_template_libraryvision.tex"

# Build-Verzeichnis
BUILD_DIR="build"

# Finales PDF
OUTPUT_BASENAME="LibraryVision_Document"

# Titel für Pandoc
TITLE="LibraryVision"
```

---

## Installation von Abhängigkeiten

```bash
sudo apt install pandoc texlive-xetex texlive-latex-extra fonts-texgyre poppler-utils
```

---

## Ausführen

```bash
./libraryvision.sh
```

oder mit externer Konfigurationsdatei:

```bash
LIBRARYVISION_CONFIG=andere.config ./libraryvision.sh
```

Ergebnis:

- `overview_libraryvision.md`
- `LibraryVision_Document.pdf`

---

## Pipeline (Kurzüberblick)

1. **Pfade extrahieren** aus `overview.md`
2. **Library-Template erzeugen** mit `\includepdf`-Blöcken
3. **Übersicht-PDF ohne Anhänge generieren** → liefert Startseiten-Offset
4. **PDF-Seiten zählen** (`pdfinfo`)
5. **Link-Umschreibung** → `\hyperlink{page.N}{Text}`
6. **Finale LibraryVision-PDF bauen**

---

## Zweck

LibraryVision dient dazu, große PDF-Sammlungen elegant in einem einzigen,
voll verlinkten PDF-Dokument darzustellen – ohne manuelle Pflege.

Ideal für:

- technische Dokumentationen  
- Projektdokumente  
- Sammlungen vieler PDFs  
- interne Wissensarchive  
- alles, was eine saubere, klickbare „PDF-Library“ braucht.  

