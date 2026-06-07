#!/usr/bin/env python3
"""Generate the validation charts embedded in the top-level README.

Reads docs/mgen_metrics.json (real native-Windows Bakta run on M. genitalium)
and writes docs/img/*.png. Pure matplotlib.
"""
import json, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "img")
os.makedirs(IMG, exist_ok=True)
M = json.load(open(os.path.join(HERE, "mgen_metrics.json")))

NAVY, BLUE, TEAL, GREEN, GREY, AMBER = "#1b2a4a", "#2f6db5", "#1aa6a6", "#16a34a", "#8895a7", "#e0a82e"
plt.rcParams.update({"font.size": 11, "axes.edgecolor": "#cfd6e0",
                     "axes.grid": True, "grid.color": "#eef1f5",
                     "figure.facecolor": "white", "axes.facecolor": "white"})

g = M["genome"]; f = M["features"]; c = M["cds_annotation"]

# --- 1. headline cards -------------------------------------------------------
fig, ax = plt.subplots(figsize=(9.2, 3.0))
ax.axis("off")
rna_total = f["tRNA"] + f["tmRNA"] + f["rRNA"] + f["ncRNA"]
cards = [
    (f"{g['length_bp']/1000:.0f} kb", "genome", "1 circular contig"),
    (f"{f['CDS']:,}", "protein CDS", f"{c['with_pfam_domain']} with Pfam"),
    (f"{rna_total}", "RNA features", f"{f['tRNA']} tRNA / {f['rRNA']} rRNA / {f['tmRNA']} tmRNA"),
    (f"{M['runtime_seconds_wall']}s", "wall time", f"{M['threads']} threads, native"),
]
for i, (v, k, sub) in enumerate(cards):
    x = 0.02 + i * 0.245
    ax.add_patch(Rectangle((x, 0.12), 0.225, 0.76, transform=ax.transAxes,
                           facecolor="#f0f4f9", edgecolor="#d3dde8", zorder=1))
    ax.text(x + 0.1125, 0.66, v, transform=ax.transAxes, ha="center", fontsize=22,
            color=NAVY, fontweight="bold")
    ax.text(x + 0.1125, 0.43, k, transform=ax.transAxes, ha="center", fontsize=11.5, color=BLUE)
    ax.text(x + 0.1125, 0.26, sub, transform=ax.transAxes, ha="center", fontsize=8, color=GREY)
ax.set_title(f"Native-Windows Bakta: full annotation of {M['organism']}  -  every feature, no --skip",
             fontweight="bold", color=NAVY, fontsize=11.5, y=1.0)
fig.tight_layout()
fig.savefig(os.path.join(IMG, "headline.png"), dpi=150, bbox_inches="tight")
plt.close(fig)

# --- 2. feature breakdown (horizontal bars) ----------------------------------
order = ["CDS", "tRNA", "rRNA", "ncRNA", "tmRNA", "oriC", "CRISPR array", "ncRNA region"]
labels = [k for k in order]
vals = [f[k] for k in order]
colors = [NAVY, BLUE, TEAL, GREEN, "#3f86c9", AMBER, GREY, GREY]
fig, ax = plt.subplots(figsize=(8.4, 3.6))
bars = ax.barh(labels[::-1], vals[::-1], color=colors[::-1], height=0.62, zorder=3)
ax.set_xscale("symlog")
ax.set_xlim(0, max(vals) * 1.6)
for b, v in zip(bars, vals[::-1]):
    ax.text(b.get_width(), b.get_y() + b.get_height()/2, f"  {v}",
            va="center", fontsize=10, color=NAVY, fontweight="bold")
ax.set_title("Features annotated by the bundled tool stack (M. genitalium, light DB)",
             fontweight="bold", color=NAVY, fontsize=11)
ax.set_xlabel("count (log scale)")
fig.text(0.5, -0.02,
         "tRNA->tRNAscan-SE+Infernal   rRNA/ncRNA->cmscan   tmRNA->Aragorn   "
         "CRISPR->PilerCR   CDS->Pyrodigal+Diamond+pyHMMER+AMRFinderPlus   oriC->BLAST+",
         ha="center", fontsize=8, color=GREY)
fig.tight_layout()
fig.savefig(os.path.join(IMG, "features.png"), dpi=150, bbox_inches="tight")
plt.close(fig)

# --- 3. CDS functional annotation coverage -----------------------------------
fig, ax = plt.subplots(figsize=(7.6, 3.0))
total = c["total_cds"]; pfam = c["with_pfam_domain"]; hyp = c["hypothetical"]
named = total - hyp
seg = [("functionally annotated", named, GREEN),
       ("Pfam domain hit", pfam, TEAL),
       ("hypothetical", hyp, GREY)]
y = 0
for label, val, col in seg:
    ax.barh([label], [val], color=col, height=0.6, zorder=3)
    ax.text(val, y, f"  {val}", va="center", fontsize=10, color=NAVY, fontweight="bold")
    y += 1
ax.set_xlim(0, total * 1.12)
ax.set_title(f"CDS annotation: {total} proteins predicted (Pyrodigal) + characterised",
             fontweight="bold", color=NAVY, fontsize=11)
ax.set_xlabel("protein CDS")
ax.invert_yaxis()
fig.tight_layout()
fig.savefig(os.path.join(IMG, "cds.png"), dpi=150, bbox_inches="tight")
plt.close(fig)

print("wrote:", ", ".join(sorted(os.listdir(IMG))))
