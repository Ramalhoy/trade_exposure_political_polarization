# Build the reconciliation list: locate each row's PDF page (01/10 PDF) and write CSV + markdown.
import re, csv, subprocess, glob, unicodedata, collections
exec(open('s5_rows.py', encoding='utf8').read())
pdf = glob.glob('/mnt/user-data/uploads/disserta*/yago_ramalho_disserta*.pdf')[0]
npages = int(re.search(r'Pages:\s+(\d+)', subprocess.run(['pdfinfo', pdf], capture_output=True, text=True).stdout).group(1))
def norm(t):
    t = unicodedata.normalize('NFKC', t).lower().replace('ﬁ', 'fi').replace('ﬂ', 'fl')
    return re.sub(r'[^a-z0-9à-ÿ]+', ' ', t)
pages = [norm(subprocess.run(['pdftotext', '-f', str(p), '-l', str(p), pdf, '-'], capture_output=True, text=True).stdout) for p in range(1, npages + 1)]
def clean(snip):
    s = re.sub(r'\\(citeonline|cite|ref|label|emph|textit|textbf)\{[^}]*\}', ' ', snip)
    s = re.sub(r'\$[^$]*\$', ' ', s); s = re.sub(r'\\[a-zA-Z]+', ' ', s); s = s.replace('{,}', ',')
    return norm(s)
miss = []; last = None
for r in rows:
    w = clean(r['snippet']).split(); pg = None
    for k in (8, 6, 5, 4, 3):
        for i in range(0, max(1, len(w) - k + 1)):
            q = ' '.join(w[i:i + k])
            if len(q) < 12: continue
            hits = [p + 1 for p, t in enumerate(pages) if q in t]
            if hits:
                pg = min(hits, key=lambda h: abs(h - last) if last else h); break
        if pg: break
    if pg is None: miss.append(r['tex_line']); pg_s = f"~{last}" if last else "?"
    else: last = pg; pg_s = str(pg)
    r['pdf_page'] = pg_s
def printed(p):
    m = re.match(r'(~?)(\d+)$', p)
    if not m: return p
    n = int(m.group(2))
    return f"{m.group(1)}{n-1}" if n >= 11 else f"front matter (pdf p.{n})"
for i, r in enumerate(rows, 1): r['id'] = i; r['pdf_page'] = printed(r['pdf_page'])
cols = ['id', 'section', 'tex_line', 'pdf_page', 'status', 'old', 'new', 'source', 'snippet']
with open('out/05_reconciliation.csv', 'w', newline='', encoding='utf8') as f:
    w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); [w.writerow({c: r[c] for c in cols}) for r in rows]
c = collections.Counter(r['status'] for r in rows)
print(len(rows), dict(c), 'unlocated:', miss)
