Bakta for Windows
=================

A native-Windows build of Bakta (bacterial genome annotation) with its whole tool
stack ported - no WSL, no Docker, no Cygwin.

GETTING STARTED
---------------
1. Get the database (one time, ~1.5 GB download):
   - Open "Bakta for Windows (app)" and click "Download light DB...", OR
   - In the "Bakta Command Prompt":
        bakta_db download --type light --output C:\bakta-db
   This produces a folder named "db-light".

2. Annotate a genome:
   - In the app: pick the genome FASTA, an output folder, and the db-light folder,
     then click "Run annotation".
   - Or on the command line:
        bakta --db C:\bakta-db\db-light -o out --threads 8 genome.fasta

OUTPUT
------
GFF3, GenBank (.gbff), EMBL, FASTA (.faa/.ffn/.fna), TSV, JSON, a text summary,
and a circular genome plot (.png/.svg).

WHAT'S BUNDLED
--------------
- Ported native .exe tools: AMRFinderPlus, HMMER (hmmsearch), Infernal
  (cmscan/cmsearch), tRNAscan-SE (+ Strawberry Perl), Aragorn, PilerCR,
  diamond, BLAST+.
- A private embedded Python with Bakta and all its packages.
Nothing else needs to be installed.

NOTES
-----
- The database is NOT included in the program folder; it lives wherever you
  downloaded it and is selected per run.
- First run may be slightly slower (Windows SmartScreen / AV scanning the new exes).

Project: https://github.com/MrMufasii/Bakta-for-Windows
Upstream Bakta: https://github.com/oschwengers/bakta  (please cite the Bakta paper)
License: GPL-3.0 (same as Bakta).
