# Unlimited OCR

> OCR any number of scanned PDFs and images into Open Brain — no page caps, no per-page fees, resumable across runs.

## What It Does

Turns a folder of scanned documents — contracts, invoices, medical records, decades of paper you photographed once and never read again — into searchable thoughts in your Open Brain. It runs OCR locally, so there is no page limit and no per-page bill, and it checkpoints every page so a 50,000-page archive can be imported over as many sessions as you like.

## Why "Unlimited"

Hosted OCR APIs meter you by the page, which is exactly the wrong shape for a personal archive: the whole point is to dump everything in at once. This recipe inverts the cost curve by trying the cheapest method that can work on each page:

| Tier | Method | Cost | When it fires |
| ---- | ------ | ---- | ------------- |
| 1 | Embedded PDF text layer | Free, instant | The page already has real text — true for most "scans" produced by modern scanners and every digital PDF |
| 2 | Local Tesseract OCR | Free, unmetered | The page has no text layer |
| 3 | Vision-model OCR | Paid, hard-capped | *Optional.* Only pages Tesseract read badly, and never more than `--max-vision-pages` of them |

Tiers 1 and 2 have no ceiling — that is the "unlimited" part. Tier 3 is off by default, and when you turn it on it can only spend what you explicitly allow.

> [!NOTE]
> Embeddings are still billed per thought by OpenRouter, as with every OB1 import recipe. `text-embedding-3-small` costs roughly $0.02 per million tokens, so a 10,000-page archive lands in the low single-digit dollars. Run with `--no-embed` if you want zero API spend and plan to backfill vectors later.

## Prerequisites

- Working Open Brain setup ([guide](../../docs/01-getting-started.md))
- Python 3.10+
- **Tesseract OCR** and **Poppler** (`pdftoppm`) on your PATH:
  - macOS: `brew install tesseract poppler`
  - Ubuntu/Debian: `sudo apt install tesseract-ocr poppler-utils`
  - Windows: [Tesseract installer](https://github.com/UB-Mannheim/tesseract/wiki) + [Poppler for Windows](https://github.com/oschwartz10612/poppler-windows/releases)
  - Non-English documents also need the language pack, e.g. `sudo apt install tesseract-ocr-deu`
- OpenRouter API key (for embeddings, and for the optional vision fallback)

> [!TIP]
> Skip the binaries entirely with `--text-layer-only`. You will import every already-digital page and silently skip the true scans — a fast way to see what is in the pile before installing anything.

If you also want your agent to route heavy non-PDF formats (spreadsheets, decks, archives) into Open Brain, pair this with [Heavy File Ingestion](../../skills/heavy-file-ingestion/README.md).

## Credential Tracker

Copy this block into a text editor and fill it in as you go.

```text
UNLIMITED OCR -- CREDENTIAL TRACKER
--------------------------------------

FROM YOUR OPEN BRAIN SETUP
  Project URL:           ____________
  Service role key:      ____________
  OpenRouter API key:    ____________

GENERATED DURING SETUP
  Document folder path:  ____________
  Tesseract language(s): ____________  (default: eng)

--------------------------------------
```

## Steps

1. Install Tesseract, Poppler, and the Python dependencies
2. Add your Supabase and OpenRouter credentials to `.env`
3. Survey the pile with `--dry-run` to see how much is already digital
4. Import — a small slice first, then the whole archive
5. Rescue the badly-read pages with the capped vision fallback

Each step is detailed below.

---

![Step 1](https://img.shields.io/badge/Step_1-Install_the_OCR_Tools-6A1B9A?style=for-the-badge)

**1. Install the system binaries:**

```bash
# macOS
brew install tesseract poppler

# Ubuntu/Debian
sudo apt install tesseract-ocr poppler-utils
```

**2. Confirm both are visible:**

```bash
tesseract --version
pdftoppm -v
```

**3. Install the Python dependencies:**

```bash
cd recipes/unlimited-ocr
pip install -r requirements.txt
```

✅ **Done when:** both commands print a version number and `pip install` finishes without errors.

---

![Step 2](https://img.shields.io/badge/Step_2-Add_Your_Credentials-6A1B9A?style=for-the-badge)

Create a `.env` file in this folder:

```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
OPENROUTER_API_KEY=your-openrouter-key
```

> [!WARNING]
> `.env` is gitignored by this repo, but double-check `git status` before committing. Never paste real keys into a README, a script, or an issue.

✅ **Done when:** `.env` exists in `recipes/unlimited-ocr/` and does not appear in `git status`.

---

![Step 3](https://img.shields.io/badge/Step_3-Survey_the_Pile-6A1B9A?style=for-the-badge)

Before importing anything, find out how much of your archive is already digital:

```bash
python ocr-import.py ~/Documents/scans --dry-run
```

You will get a per-file breakdown and a total:

```text
Files:            412
Pages to process: 8,930
  From text layer (free):  6,104
  Needing OCR (free/local): 2,826
```

✅ **Done when:** the page counts look roughly like the archive you pointed at. If "Needing OCR" is 0, everything already has a text layer and you can run with `--text-layer-only`.

---

![Step 4](https://img.shields.io/badge/Step_4-Import-6A1B9A?style=for-the-badge)

Start with a small slice to check the output quality:

```bash
python ocr-import.py ~/Documents/scans --limit 5 --verbose
```

Inspect a few thoughts in Supabase, then run the whole archive:

```bash
python ocr-import.py ~/Documents/scans
```

**Useful flags:**

| Flag | What it does |
| ---- | ------------ |
| `--lang eng+deu` | OCR in multiple languages |
| `--group-pages 3` | Combine 3 pages into one thought — better for prose, worse for forms |
| `--workers 8` | OCR more pages in parallel (match your CPU cores) |
| `--dpi 400` | Higher rasterization detail for small or faint print |
| `--psm 6` | Treat pages as a single uniform block — helps on receipts and tables |
| `--source-label medical-records` | Stamp a custom `metadata.source` so you can filter this batch later |
| `--reprocess` | Ignore the checkpoint and re-import everything |

> [!IMPORTANT]
> The run is interruptible. Ctrl+C at any point and rerun the same command — completed pages are recorded in `ocr-sync-log.json` and skipped. Editing a source file changes its hash, which re-imports that file only.

✅ **Done when:** the summary reports inserted thoughts and `ocr-sync-log.json` exists in this folder.

---

![Step 5](https://img.shields.io/badge/Step_5-Rescue_the_Bad_Pages-6A1B9A?style=for-the-badge)

Tesseract struggles with handwriting, faxes, and heavy skew. Those pages are flagged automatically — low mean confidence, low alphanumeric ratio, or almost no text. To send only those pages to a vision model:

```bash
python ocr-import.py ~/Documents/scans --vision-fallback --max-vision-pages 50
```

The cap is a hard stop, not a suggestion. Once it is reached the run continues on Tesseract output alone and tells you so, which is what keeps an "unlimited" import from turning into an unlimited invoice.

✅ **Done when:** the summary shows a non-zero `Vision model:` count no larger than your cap.

---

## Expected Outcome

Every imported page becomes a thought whose content is prefixed with the document name and page range:

```text
2019-lease-agreement — page 4

TENANT IMPROVEMENTS. Landlord shall provide an allowance of $45.00 per
rentable square foot toward the cost of Tenant's initial improvements...
```

The metadata records how the text was obtained, so you can audit quality later:

```json
{
  "source": "ocr",
  "type": "reference",
  "document": "2019-lease-agreement.pdf",
  "path": "leases/2019-lease-agreement.pdf",
  "pages": [4],
  "ocr_methods": ["tesseract"],
  "ocr_confidence": 91.4,
  "file_hash": "3f9a1c7e2b8d0456",
  "imported_at": "2026-07-29T14:02:11+00:00"
}
```

Verify in the Supabase SQL editor:

```sql
select metadata->>'document' as document,
       count(*) as thoughts,
       round(avg((metadata->>'ocr_confidence')::numeric), 1) as avg_confidence
from thoughts
where metadata->>'source' = 'ocr'
group by 1
order by thoughts desc
limit 20;
```

Then ask your AI client something only the paper knows — *"what was the tenant improvement allowance in the 2019 lease?"* — and it should answer from the scan.

To find pages worth re-running with `--vision-fallback`:

```sql
select metadata->>'document' as document, metadata->'pages' as pages,
       (metadata->>'ocr_confidence')::numeric as confidence
from thoughts
where metadata->>'source' = 'ocr'
  and (metadata->>'ocr_confidence')::numeric < 75
order by confidence
limit 50;
```

## Troubleshooting

**Issue: `Error: missing required binaries: tesseract, pdftoppm`**
Solution: The binaries are not installed or not on your PATH. Install them per the Prerequisites, then confirm with `tesseract --version` and `pdftoppm -v` in the *same* shell you run the script from. On Windows, add the install directories to PATH and restart your terminal. To proceed without OCR for now, use `--text-layer-only`.

**Issue: `Error: Tesseract language data missing: deu`**
Solution: Language packs install separately from the engine. `sudo apt install tesseract-ocr-deu` on Ubuntu, `brew install tesseract-lang` on macOS. Run `tesseract --list-langs` to see what you have.

**Issue: OCR output is garbled — random punctuation, wrong letters, nonsense words.**
Solution: Usually resolution or layout. Try `--dpi 400` for small print, `--psm 6` for receipts and dense tables, or `--psm 4` for multi-column pages. If the source is a photo rather than a scan, straighten and crop it first — Tesseract is sensitive to skew. For pages that stay bad, `--vision-fallback` handles them.

**Issue: The import is very slow.**
Solution: Rasterizing at 300 DPI is the expensive part. Raise `--workers` to match your CPU cores, and lower `--dpi 200` for clean modern typed documents. Check the dry-run breakdown first — if most pages come from the text layer, the run should be fast, and a slow run means most of your archive is genuinely image-only.

**Issue: Nothing was inserted, and the summary shows pages read but zero thoughts.**
Solution: Pages under `--min-page-chars` (default 40) are dropped as blank. Run with `--verbose` to see the character count per page. If real pages are being dropped, lower the threshold; if every page reads near-zero characters, OCR is failing — check the language setting and try `--dpi 400`.

**Issue: `Skipped page(s) [7]: possible AWS access key`**
Solution: Working as intended. Scanned onboarding sheets and screenshots often carry live credentials, and the scanner refuses to embed them. Rotate the exposed credential. If the match is a false positive, rerun that file with `--no-secret-scan`.

**Issue: Rerunning skips files you want re-imported.**
Solution: Completed files are recorded in `ocr-sync-log.json`. Pass `--reprocess` to ignore it, or delete the entry for a single file. Note that duplicate content is also caught at the database level by `content_fingerprint`, so re-imports do not create duplicate thoughts.
