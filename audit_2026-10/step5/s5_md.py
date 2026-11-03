import csv, collections
rows = list(csv.DictReader(open('out/05_reconciliation.csv', encoding='utf8')))
esc = lambda t: t.replace('|', '\\|').replace('\n', ' ')
out = []
secs = []
for r in rows:
    if r['section'] not in secs: secs.append(r['section'])
for s in secs:
    rr = [r for r in rows if r['section'] == s]
    c = collections.Counter(r['status'] for r in rr)
    out.append(f"\n### {s}  ({', '.join(f'{k} {v}' for k, v in sorted(c.items()))})\n")
    out.append("| # | tex | p. | Status | Old | New | Source |\n|---|---|---|---|---|---|---|")
    for r in rr:
        out.append(f"| {r['id']} | {r['tex_line']} | {r['pdf_page']} | **{r['status']}** | {esc(r['old'])} | {esc(r['new'])} | {esc(r['source'])} |")
open('out/05_table.md', 'w', encoding='utf8').write('\n'.join(out) + '\n')
print(collections.Counter(r['status'] for r in rows))
