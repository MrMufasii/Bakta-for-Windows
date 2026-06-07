# Porting notes — Bakta's tool stack on native Windows

Everything was compiled with **MinGW-w64** (winlibs GCC 16.1.0) and **statically
linked** so the shipped `.exe`s depend only on Windows system DLLs (KERNEL32, the UCRT
`api-ms-win-crt-*`, WS2_32). Bakta itself (Python) runs unmodified — its hardest
dependencies, `pyrodigal` and `pyhmmer`, publish Windows wheels.

A recurring gotcha across **all** the C/C++ tools: **MinGW GCC's modern output is
ASLR-sensitive** for these codebases. They crash on launch standalone but run fine under
a debugger (which disables ASLR) — the classic heisenbug. The fix everywhere is to link
with `-Wl,--disable-dynamicbase -Wl,--disable-high-entropy-va`.

## AMRFinderPlus (NCBI `amr`, C++) — the largest port

No upstream Windows binary. Patched `common.hpp` / `common.cpp` / `seq.hpp` /
`amrfinder.cpp`:

- `#undef stderr` — NCBI uses `stderr` as a **struct member** name; it's a macro on
  Windows. The 3 real `fileno(stderr)` sites are in `_MSC_VER`-guarded code → widen
  those guards to `_MSC_VER || _WIN32`.
- `realpath`→`_fullpath` (normalise `\`→`/`); `getProgramDirName`→`GetModuleFileNameA`;
  `lstat`/`mkdir`/`S_ISLNK`/`S_ISSOCK`/`SIGPIPE` macros; `<execinfo.h>` shim.
- **`cmd.exe` quoting** for `system()`: `cmd /c` strips the outer quote pair, so wrap the
  whole command in one extra pair; convert `/`→`\`; `/dev/null`→`NUL`; `shellQuote`/
  `-outfmt` use `"` not `'`; append `.exe`; `which()` splits PATH on `;`.
- **Symlinks must be copies, not junctions** — AMRFinderPlus recursively deletes its
  temp dir, and a directory junction is followed *into the real database and deletes it*.
- DB version floor (`dataVer_min`) lowered to accept the light DB's bundled
  `amrfinderplus-db`. The `latest` symlink in the DB is made a real directory copy.

## HMMER 3.4 `hmmsearch` (C) — needed by AMRFinderPlus

Easel needs `<syslog.h>` + `<sys/mman.h>` shims and `getuid`/`geteuid`/`getgid`/
`getegid`/`getppid`/`vsyslog` stubs (`#ifdef _WIN32`). `esl_buffer.c`: guard the
`_POSIX_VERSION` blocks with `&& !defined(_WIN32)` and add a Windows `fstat` that sets
only `st_size` (MinGW's `struct stat` has no `st_blksize`) → small files take the stable
slurp path. Force-include a prelude with `ctime_r`/`localtime_r`/`gmtime_r`. Strip the
daemon/socket objects (`hmmd*`) from `src/Makefile`.

## Infernal 1.1.5 `cmscan` / `cmsearch` (C) — rRNA + ncRNA

Same Easel shims as HMMER. Build only the libraries of the bundled HMMER (the daemon
*program* `hmmpgmd` uses `sigaction`/`SIGALRM` and isn't needed). Two Windows-specific
bugs were the interesting part:

1. **Pressed-CM read.** `cm_file.c` opened the pressed `*.i1m` in **text** mode and then
   read the **binary** p7 HMM filter from that handle → `cm_Pipeline() failed ... bad
   file format for HMM filter`. Fixed to open binary on Windows.
2. **CRLF output.** `cmscan`/`cmsearch` wrote CRLF (Windows text-mode `fopen`). This was
   invisible to Bakta (Python uses universal newlines) but **silently broke
   tRNAscan-SE**: its Perl structure-parser left `\r` in the secondary-structure string,
   so every tRNA came back `Undet` with anticodon `NNN` (bounds and scores were fine).
   Fixed by forcing LF: `_set_fmode(_O_BINARY)` + `_setmode` on stdout/stderr at the top
   of `main()`.

## tRNAscan-SE 2.0.12 (Perl + squid-era C) — tRNA

A Perl wrapper around Infernal `cmsearch` plus four legacy C scanners. Default `-B`
(bacterial) mode actually runs Infernal for both passes, but startup still checks that
all four C binaries exist.

- **C binaries** (`eufindtRNA`, `trnascan-1.4`, `covels-SE`, `coves-SE`): K&R/C89 code;
  GCC 16 defaults to C23 (where `()` means `(void)` and implicit-int/-func are errors), so
  compile with `-std=gnu89 -fcommon -fpermissive -Wno-implicit-function-declaration
  -Wno-implicit-int -Wno-int-conversion`.
- **Perl Windows-portability** (it shells out via `cmd.exe` under Strawberry Perl):
  - upstream bug — `CM.pm::set_bin` appends `.exe` to cmsearch/covels/coves but **forgets
    `cmscan_bin`**; added it.
  - replace `<bin> -h | grep`, `` `cat file` ``, `` `date` `` (cmd `date` *prompts* and
    hangs!), `system("rm -f ...")`, `system("cat a >> b")`, and `/dev/null` with portable
    Perl (`unlink`/`glob`, `scalar(localtime)`, slurp, `NUL`).
  - **self-locating**: `use FindBin`, a `{base}`-relative conf, and Configuration seeding
    so it works from any install path with no substitution.
- **Runtime**: a bundled **Strawberry Perl** (`perl\`) + a tiny **`tRNAscan-SE.exe`**
  launcher in C (Bakta calls the tool via `CreateProcess`, which resolves only `.exe` on
  PATH, not `.cmd`/`.bat`; the launcher spawns `perl.exe <script> <args>`).

## Aragorn 1.2.41 (tmRNA) & PilerCR 1.06 (CRISPR)

Small fixes: widen `_MSC_VER`-only guards to also cover `_WIN32` (so MinGW takes the
Windows path), add a tiny stdio prelude; static build. Both validated.

## diamond & BLAST+

Upstream ships Windows binaries — bundled as-is. BLAST+ is trimmed to the executables
Bakta/AMRFinderPlus actually use (`blastn`, `blastp`, `blastx`, `tblastn`, `makeblastdb`)
plus its DLLs.

## Validation

Full `bakta` run (no `--skip`) on *M. genitalium* G37 on Windows 11: 991 CDS (316 with
Pfam), 36 tRNA, 3 rRNA, 2 ncRNA, 1 tmRNA, 1 oriC, circular plot, all 11 output formats,
~63 s, zero warnings/errors. See [`../docs`](../docs).
