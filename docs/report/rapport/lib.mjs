// Building blocks for the report: French typography, paragraphs with inline
// **bold** and `code`, tables, figures (screenshots and diagrams), code blocks.
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  AlignmentType, BorderStyle, HeadingLevel, ImageRun, Paragraph, ShadingType,
  Table, TableCell, TableRow, TextRun, VerticalAlign, WidthType,
} from 'docx';

export const C = {
  ink: '1D2340', muted: '4A5670', line: 'DDE5EA', page: 'F4F8FA',
  primary: '3157E8', primarySoft: 'EEF2FD', progress: 'FFC845', progressSoft: 'FFF4D6',
};
export const FONT = 'Arial';
export const MONO = 'Consolas';
// A4, 2 cm margins: 17 cm of text, in twentieths of a point and in pixels (96 dpi).
export const TEXT_DXA = 9638;
const TEXT_PX = 642;

// French typography: a no-break space before : ; ? ! % € and inside « ».
export const fr = (s) => s
  .replace(/ ([:;?!%€»])/g, ' $1')
  .replace(/« /g, '« ');

// Inline markup: **bold**, `code`.
export function runs(text, base = {}) {
  return text.split(/(\*\*[^*]+\*\*|`[^`]+`)/).filter(Boolean).map((part) => {
    if (part.startsWith('**')) return new TextRun({ ...base, text: fr(part.slice(2, -2)), bold: true });
    if (part.startsWith('`')) {
      return new TextRun({ ...base, text: part.slice(1, -1), font: MONO, size: (base.size ?? 21) - 2, color: C.ink });
    }
    return new TextRun({ ...base, text: fr(part) });
  });
}

export const P = (text, opts = {}) => new Paragraph({
  children: runs(text, opts.run),
  spacing: { after: 120, line: 288 },
  alignment: opts.align ?? AlignmentType.JUSTIFIED,
  ...opts.para,
});

export const H1 = (text) => new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: true, children: [new TextRun(fr(text))] });
export const H2 = (text) => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(fr(text))] });
export const H3 = (text) => new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(fr(text))] });

export const bullets = (items) => items.map((t) => new Paragraph({
  children: runs(t),
  numbering: { reference: 'bullets', level: 0 },
  spacing: { after: 60, line: 276 },
}));

// A highlighted note: a soft background and a primary rule on its left.
export const note = (text) => new Paragraph({
  children: runs(text),
  shading: { type: ShadingType.CLEAR, fill: C.primarySoft, color: 'auto' },
  border: { left: { style: BorderStyle.SINGLE, size: 18, color: C.primary, space: 8 } },
  spacing: { before: 120, after: 200, line: 288 },
  indent: { left: 160, right: 160 },
});

export const code = (lines) => lines.map((l, i) => new Paragraph({
  children: [new TextRun({ text: l === '' ? ' ' : l, font: MONO, size: 17, color: C.ink })],
  shading: { type: ShadingType.CLEAR, fill: C.page, color: 'auto' },
  spacing: { before: i === 0 ? 120 : 0, after: i === lines.length - 1 ? 200 : 0, line: 240 },
  indent: { left: 160, right: 160 },
  keepLines: true,
  keepNext: i < lines.length - 1,
}));

const cellBorders = {
  top: { style: BorderStyle.SINGLE, size: 4, color: C.line },
  bottom: { style: BorderStyle.SINGLE, size: 4, color: C.line },
  left: { style: BorderStyle.SINGLE, size: 4, color: C.line },
  right: { style: BorderStyle.SINGLE, size: 4, color: C.line },
};

// widths: relative weights, scaled to the text width.
export function table(headers, rows, weights) {
  const w = weights ?? headers.map(() => 1);
  const sum = w.reduce((a, b) => a + b, 0);
  const cols = w.map((x) => Math.floor((x / sum) * TEXT_DXA));
  cols[cols.length - 1] += TEXT_DXA - cols.reduce((a, b) => a + b, 0);
  const cell = (text, i, head) => new TableCell({
    width: { size: cols[i], type: WidthType.DXA },
    borders: cellBorders,
    shading: head ? { type: ShadingType.CLEAR, fill: C.primarySoft, color: 'auto' } : undefined,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    verticalAlign: VerticalAlign.CENTER,
    children: [new Paragraph({
      children: runs(String(text), { size: 18, bold: head || undefined, color: C.ink }),
      spacing: { after: 0, line: 252 },
    })],
  });
  return new Table({
    width: { size: TEXT_DXA, type: WidthType.DXA },
    columnWidths: cols,
    rows: [
      new TableRow({ tableHeader: true, cantSplit: true, children: headers.map((h, i) => cell(h, i, true)) }),
      ...rows.map((r) => new TableRow({ cantSplit: true, children: r.map((t, i) => cell(t, i, false)) })),
    ],
  });
}

export const spacer = (after = 120) => new Paragraph({ children: [], spacing: { after } });

// Images ------------------------------------------------------------------

const work = mkdtempSync(join(tmpdir(), 'motu-rapport-'));
let n = 0;
const size = (file) => execFileSync('magick', ['identify', '-format', '%w %h', file]).toString().split(' ').map(Number);

// A phone screenshot, cut to a phone's height (from `top` px of the original),
// framed with a thin line and compressed: the report shows screens, not scrolls.
function phone(file, { top = 0, height = 2250 } = {}) {
  const [w, h] = size(file);
  const out = join(work, `s${n++}.jpg`);
  const ch = Math.min(height, h - top);
  execFileSync('magick', [file, '-crop', `${w}x${ch}+0+${top}`, '+repage', '-resize', '720x',
    '-bordercolor', '#C9D3DA', '-border', '3', '-quality', '86', out]);
  return out;
}

function wide(file) {
  const out = join(work, `w${n++}.jpg`);
  execFileSync('magick', [file, '-resize', '1600x', '-bordercolor', '#C9D3DA', '-border', '3', '-quality', '86', out]);
  return out;
}

let figure = 0;
const caption = (text) => new Paragraph({
  children: [
    new TextRun({ text: `Figure ${++figure}. `, bold: true, size: 16, color: C.muted }),
    ...runs(text, { size: 16, color: C.muted }),
  ],
  alignment: AlignmentType.CENTER,
  spacing: { before: 60, after: 160, line: 240 },
});

const image = (file, widthPx, ratio, type = 'jpg') => new ImageRun({
  type, data: readFileSync(file),
  transformation: { width: Math.round(widthPx), height: Math.round(widthPx * ratio) },
});

const noBorders = {
  top: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
  bottom: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
  left: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
  right: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
  insideHorizontal: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
  insideVertical: { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' },
};

// Screenshots three to a row: [[file, caption, crop?], …], files in docs/screenshots.
export function screens(dir, items, perRow = 3) {
  const colDxa = Math.floor(TEXT_DXA / perRow);
  const imgPx = perRow === 3 ? 165 : 230;
  const rows = [];
  for (let i = 0; i < items.length; i += perRow) {
    const cells = items.slice(i, i + perRow).map(([f, text, crop]) => {
      const out = phone(join(dir, `${f}.png`), crop);
      const [w, h] = size(out);
      return new TableCell({
        width: { size: colDxa, type: WidthType.DXA },
        borders: noBorders,
        verticalAlign: VerticalAlign.TOP,
        margins: { left: 60, right: 60 },
        children: [
          new Paragraph({ children: [image(out, imgPx, h / w)], alignment: AlignmentType.CENTER, spacing: { after: 0 } }),
          caption(text),
        ],
      });
    });
    while (cells.length < perRow) {
      cells.push(new TableCell({ width: { size: colDxa, type: WidthType.DXA }, borders: noBorders, children: [new Paragraph('')] }));
    }
    rows.push(new TableRow({ cantSplit: true, children: cells }));
  }
  return new Table({ width: { size: colDxa * perRow, type: WidthType.DXA }, columnWidths: Array(perRow).fill(colDxa), borders: noBorders, rows });
}

// One wide image (a landscape screenshot or a diagram), at most maxCm high.
export function wideFigure(file, text, { maxCm = 21, widthFrac = 1, diagram = false, numbered = true } = {}) {
  const out = diagram ? file : wide(file);
  const [w, h] = size(out);
  let px = TEXT_PX * widthFrac;
  const maxPx = (maxCm / 2.54) * 96;
  if (px * (h / w) > maxPx) px = maxPx / (h / w);
  return [
    new Paragraph({ children: [image(out, px, h / w, diagram ? 'png' : 'jpg')], alignment: AlignmentType.CENTER, spacing: { before: 120, after: 0 }, keepNext: numbered }),
    ...(numbered ? [caption(text)] : []),
  ];
}
