# Unlimited OCR

> OCR an unlimited number of scanned PDFs into Open Brain for about 16 cents per thousand pages.

## What It Does

Turns a folder of scanned documents — contracts, invoices, medical records, decades of paper you photographed once and never read again — into searchable thoughts in your Open Brain. There is no page cap and no per-page OCR licence. Every page is checkpointed, so a 100,000-page archive can be imported across as many interrupted sessions as you like.

## Why "Unlimited"

Hosted OCR APIs meter you by the page, which is exactly the wrong shape for a personal archive: the whole point is to dump everything in at once. This recipe reads each page with the cheapest method that can actually do the job:

| Tier | Method | Cost | When it fires |
| ---- | ------ | ---- | ------------- |
| 1 | Embedded PDF text layer | Free, instant | The page already has real text — true for most "scans" produced by modern scanners and every digital PDF |
| 2 | Vision-model OCR | ~$0.16 per 1,000 pages | The page is genuinely an image. **This is the default.** |
| 2-alt | Local Tesseract OCR | Free, unmetered, offline | Same job, zero API spend, in exchange for a local install and lower accuracy |

Tier 2 is the part that changed the math. The cheapest image-capable model on OpenRouter is currently `qwen/qwen3.7-flash` at **$0.03 per million input tokens and $0.13 per million output**. A 300 DPI page is roughly 2,000 image tokens in and 800 tokens out, which works out to about **$0.00016 per page**:

| Archive size | Vision OCR cost |
| ------------ | --------------- |
| 1,000 pages | ~$0.16 |
| 10,000 pages | ~$1.64 |
| 100,000 pages | ~$16.40 |

At those prices a per-page budget is not worth defending, so there isn't one by default. `--max-vision-pages` exists if you want a hard ceiling, but it is off unless you ask for it.

> [!NOTE]
> Prices come from OpenRouter's public model API, read in July 2026, and they move. `--dry-run` prints an estimate for the model you selected before you spend anything. Embeddings are billed separately and are far cheaper than the OCR — roughly a cent per thousand pages with `text-embedding-3-small`.

### Choosing an engine

```bash
--ocr-engine vision      # default: cheap vision model, no local OCR install
--ocr-engine tesseract   # local only, free and offline, no API key at all
--ocr-engine hybrid      # Tesseract first, vision only for pages it read badly
```

Pick `vision` unless you have a reason not to — it is more accurate than Tesseract on handwriting, faxes, skew, tables, and multi-column layouts, and it reads most languages without installing a language pack. Pick `tesseract` when the documents are sensitive enough that they should not leave the machine, or when you want zero API spend. Pick `hybrid` for very large archives of clean typed text, where Tesseract handles the bulk for free and only the ugly pages cost anything.

> [!CAUTION]
> `vision` and `hybrid` send page images to OpenRouter, which routes them to a third-party model provider — for the default model, a Chinese one. Do not use them for material you are contractually or legally barred from sending offshore. `--ocr-engine tesseract` keeps every page on your own machine.

## Prerequisites

- Working Open Brain setup ([guide](../../docs/01-getting-started.md))
- Python 3.10+
- **Poppler** (`pdftoppm`), which rasterizes PDF pages for any OCR engine:
  - macOS: `brew install poppler`
  - Ubuntu/Debian: `sudo apt install poppler-utils`
  - Windows: [Poppler for Windows](https://github.com/oschwartz10612/poppler-windows/releases)
- OpenRouter API key — for embeddings, and for the default vision engine
- **Tesseract**, *only* for `--ocr-engine tesseract` or `hybrid`:
  - macOS: `brew install tesseract` · Ubuntu: `sudo apt install tesseract-ocr`
  - Non-English documents also need a language pack, e.g. `sudo apt install tesseract-ocr-deu`

> [!TIP]
> `--text-layer-only` needs no binaries at all. It imports every already-digital page and skips the true scans — a fast way to see what is in the pile before installing anything.

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
  OCR engine:            ____________  (default: vision)
  Vision model:          ____________  (default: qwen/qwen3.7-flash)

--------------------------------------
```

## Steps

1. Install Poppler and the Python dependencies
2. Add your Supabase and OpenRouter credentials to `.env`
3. Survey the pile with `--dry-run` — page counts and a cost estimate
4. Import — a small slice first, then the whole archive
5. Tune the engine if the output quality or the cost is not what you want

Each step is detailed below.

---

![Step 1](https://img.shields.io/badge/Step_1-Install_the_Tools-6A1B9A?style=for-the-badge)

**1. Install Poppler:**

```bash
# macOS
brew install poppler

# Ubuntu/Debian
sudo apt install poppler-utils
```

**2. Confirm it is visible:**

```bash
pdftoppm -v
```

**3. Install the Python dependencies:**

```bash
cd recipes/unlimited-ocr
pip install -r requirements.txt
```

✅ **Done when:** `pdftoppm -v` prints a version and `pip install` finishes without errors. You do *not* need Tesseract unless you plan to use `--ocr-engine tesseract` or `hybrid`.

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

Before importing anything, find out how much of your archive is already digital and what the rest will cost:

```bash
python ocr-import.py ~/Documents/scans --dry-run
```

```text
Files:            412
Pages to process: 8,930
  From text layer (free):  6,104
  Vision OCR:              2,826  (~$0.46 at qwen/qwen3.7-flash)
```

✅ **Done when:** the page counts look roughly like the archive you pointed at, and the estimate is one you are happy to spend. If "From text layer" is close to the total, most of your pile is already digital — run with `--text-layer-only` and spend nothing.

---

![Step 4](https://img.shields.io/badge/Step_4-Import-6A1B9A?style=for-the-badge)

Start with a small slice to check output quality:

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
| `--ocr-engine tesseract` | Keep every page on your machine; no API spend |
| `--vision-model qwen/qwen3-vl-32b-instruct` | Trade a little cost for a document-specialist model |
| `--max-vision-pages 500` | Put a hard ceiling on paid pages (default: unlimited) |
| `--group-pages 3` | Combine 3 pages into one thought — better for prose, worse for forms |
| `--workers 8` | Process more pages in parallel (match your CPU cores) |
| `--dpi 400` | Higher rasterization detail for small or faint print |
| `--lang eng+deu` | Tesseract language(s) — `tesseract`/`hybrid` engines only |
| `--source-label medical-records` | Stamp a custom `metadata.source` so you can filter this batch later |
| `--reprocess` | Ignore the checkpoint and re-import everything |

> [!IMPORTANT]
> The run is interruptible. Ctrl+C at any point and rerun the same command — completed pages are recorded in `ocr-sync-log.json` and skipped, so you never pay to OCR the same page twice. Editing a source file changes its hash, which re-imports that file only.

✅ **Done when:** the summary reports inserted thoughts and `ocr-sync-log.json` exists in this folder.

---

![Step 5](https://img.shields.io/badge/Step_5-Tune-6A1B9A?style=for-the-badge)

**If quality is the problem**, move up the model ladder. Prices are USD per million tokens, from OpenRouter in July 2026:

| Model | In / Out | Notes |
| ----- | -------- | ----- |
| `qwen/qwen3.7-flash` | $0.030 / $0.130 | Default. Cheapest image-capable model available |
| `qwen/qwen3.5-flash-02-23` | $0.065 / $0.260 | Slightly older, sometimes steadier on dense layouts |
| `qwen/qwen3-vl-32b-instruct` | $0.104 / $0.416 | Vision-specialist family, tuned for document work |
| `z-ai/glm-4.6v` | $0.300 / $0.900 | Different lineage — worth trying when Qwen struggles on a specific document class |
| `google/gemini-2.5-flash-lite` | $0.100 / $0.400 | Non-Chinese option if routing matters to you |

**If cost is the problem** at very large scale, switch to `--ocr-engine hybrid`. Tesseract reads the clean pages for free and only pages it botches — measured by mean confidence, alphanumeric ratio, and character count — reach the API.

✅ **Done when:** a spot check of the worst documents in your archive reads correctly, at a per-page cost you are happy with.

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
  "ocr_methods": ["vision"],
  "ocr_confidence": 100.0,
  "file_hash": "3f9a1c7e2b8d0456",
  "imported_at": "2026-07-29T14:02:11+00:00"
}
```

Verify in the Supabase SQL editor:

```sql
select metadata->>'document' as document,
       count(*) as thoughts,
       metadata->'ocr_methods' as methods
from thoughts
where metadata->>'source' = 'ocr'
group by 1, 3
order by thoughts desc
limit 20;
```

Then ask your AI client something only the paper knows — *"what was the tenant improvement allowance in the 2019 lease?"* — and it should answer from the scan.

To find pages worth re-running on a better model (Tesseract-read pages only; vision pages do not report a confidence score):

```sql
select metadata->>'document' as document, metadata->'pages' as pages,
       (metadata->>'ocr_confidence')::numeric as confidence
from thoughts
where metadata->>'source' = 'ocr'
  and metadata->'ocr_methods' ? 'tesseract'
  and (metadata->>'ocr_confidence')::numeric < 75
order by confidence
limit 50;
```

## Troubleshooting

**Issue: `Error: missing required binaries: pdftoppm`**
Solution: Poppler is not installed or not on your PATH. Install it per the Prerequisites, then confirm with `pdftoppm -v` in the *same* shell you run the script from. On Windows, add the install directory to PATH and restart your terminal. To proceed without it for now, use `--text-layer-only`.

**Issue: `Error: --ocr-engine vision requires OPENROUTER_API_KEY`**
Solution: The default engine calls OpenRouter. Either add the key to `.env`, or run fully locally with `--ocr-engine tesseract` (which needs Tesseract installed, but no key and no network).

**Issue: The vision model returns nothing, or the run reports `vision-failed` pages.**
Solution: Usually the model id or your account credit. Confirm the id still exists at [openrouter.ai/models](https://openrouter.ai/models) — model ids are retired regularly — and that the model accepts image input. Check your credit balance. Then retry; failed pages are not checkpointed, so a rerun picks them up.

**Issue: OCR output is garbled — random punctuation, wrong letters, nonsense words.**
Solution: On `--ocr-engine tesseract` this is usually resolution or layout: try `--dpi 400` for small print, `--psm 6` for receipts and dense tables, `--psm 4` for multi-column pages. The faster fix is `--ocr-engine vision`, which handles skew, columns, and handwriting far better. If the vision output is also poor, try a model further up the ladder in Step 5.

**Issue: The bill was higher than the dry-run estimate.**
Solution: The estimate assumes ~2,000 image tokens per page, which is typical for a 300 DPI letter page of text. Dense pages, larger paper, and `--dpi 400` all push it up. Lower `--dpi 200` for clean typed documents, and set `--max-vision-pages` to make the ceiling enforceable rather than estimated.

**Issue: The import is very slow.**
Solution: Raise `--workers` to match your CPU cores — on `vision` the bottleneck is API round-trips, so higher worker counts help more than they do locally. Lower `--dpi 200` to cut rasterizing time and image tokens together. If the dry run showed most pages coming from the text layer, a slow run means your archive is genuinely image-heavy.

**Issue: Nothing was inserted, and the summary shows pages read but zero thoughts.**
Solution: Pages under `--min-page-chars` (default 40) are dropped as blank. Run with `--verbose` to see the character count per page. If real pages are being dropped, lower the threshold; if every page reads near-zero characters, OCR is failing — check the engine, the model id, and try `--dpi 400`.

**Issue: `Skipped page(s) [7]: possible AWS access key`**
Solution: Working as intended. Scanned onboarding sheets and screenshots often carry live credentials, and the scanner refuses to embed them. Rotate the exposed credential. If the match is a false positive, rerun that file with `--no-secret-scan`.

**Issue: Rerunning skips files you want re-imported.**
Solution: Completed files are recorded in `ocr-sync-log.json`. Pass `--reprocess` to ignore it, or delete the entry for a single file. Duplicate content is also caught at the database level by `content_fingerprint`, so re-imports do not create duplicate thoughts.
