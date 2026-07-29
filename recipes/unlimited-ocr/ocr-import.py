#!/usr/bin/env python3
"""
ocr-import.py — OCR any volume of scanned PDFs and images into Open Brain.

Runs a local-first OCR pipeline with no page caps and no per-page fees:

  1. Embedded text layer  (free, instant)   — most "scanned" PDFs already have one
  2. Local Tesseract OCR  (free, unmetered) — for pages with no text layer
  3. Vision-model OCR     (paid, capped)    — optional, only for pages Tesseract
                                              read badly, never more than
                                              --max-vision-pages of them

Every page is checkpointed, so a 50,000-page run can be interrupted and resumed
without redoing work or double-inserting thoughts.

Usage:
  python ocr-import.py /path/to/documents --dry-run
  python ocr-import.py /path/to/documents
  python ocr-import.py /path/to/scan.pdf --lang eng+deu --verbose
  python ocr-import.py /path/to/documents --vision-fallback --max-vision-pages 50
"""

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

try:
    import requests
except ImportError:
    print("Missing dependency: requests")
    print("Run: pip install -r requirements.txt")
    sys.exit(1)

try:
    from pypdf import PdfReader
except ImportError:
    print("Missing dependency: pypdf")
    print("Run: pip install -r requirements.txt")
    sys.exit(1)


# ── Config ───────────────────────────────────────────────────────────────────

PDF_EXTS = {".pdf"}
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".webp", ".gif"}

# A page whose embedded text layer has at least this many characters is treated
# as already-digital — no rasterizing, no OCR, no cost.
TEXT_LAYER_MIN_CHARS = 120

# Pages with fewer characters than this after OCR are dropped as blank/noise.
MIN_PAGE_CHARS = 40

# Tesseract mean word confidence (0-100) below which a page is considered
# badly read and becomes a candidate for vision-model escalation.
DEFAULT_CONFIDENCE_THRESHOLD = 70.0

# Rasterization resolution. 300 DPI is the Tesseract sweet spot; 400+ costs
# time and memory for little accuracy gain on typical office scans.
DEFAULT_DPI = 300

EMBEDDING_MODEL = "openai/text-embedding-3-small"
DEFAULT_VISION_MODEL = "google/gemini-2.0-flash-001"

MAX_RETRIES = 3
RETRY_BACKOFF = 2  # seconds, doubles each retry

SYNC_LOG_FILE = "ocr-sync-log.json"

VISION_PROMPT = (
    "Transcribe all text visible in this scanned page image. "
    "Return the text only — no commentary, no markdown fences, no description "
    "of the layout. Preserve reading order, paragraph breaks, and table rows "
    "as plain lines. If the page is blank, return nothing."
)

# Secret patterns — scanned invoices, contracts, and screenshots regularly
# contain credentials. Anything matching is skipped rather than embedded.
SECRET_PATTERNS = [
    ("OpenAI/OpenRouter API key", re.compile(r'sk-(?:or-v1-|proj-|live-)?[a-zA-Z0-9]{20,}')),
    ("JWT token", re.compile(r'eyJ[a-zA-Z0-9_-]{20,}\.[a-zA-Z0-9_-]{20,}')),
    ("GitHub token", re.compile(r'gh[ps]_[a-zA-Z0-9]{36,}')),
    ("AWS access key", re.compile(r'AKIA[0-9A-Z]{16}')),
    ("Supabase key", re.compile(r'sbp_[a-zA-Z0-9]{20,}')),
    ("Private key block", re.compile(r'-----BEGIN [A-Z ]+ PRIVATE KEY-----')),
    ("Generic secret assignment", re.compile(
        r'(?:password|secret|token|api_key|apikey|access_token|auth_token)'
        r'\s*[=:]\s*["\']?[a-zA-Z0-9_\-/.]{16,}',
        re.IGNORECASE,
    )),
]


def scan_for_secrets(text: str) -> str | None:
    """Return the label of the first secret pattern found, or None if clean."""
    for label, pattern in SECRET_PATTERNS:
        if pattern.search(text):
            return label
    return None


# ── Vision budget ────────────────────────────────────────────────────────────

class VisionBudget:
    """Hard cap on paid vision-OCR pages, safe to share across OCR threads.

    Pages are claimed before the API call, so the cap holds even when several
    worker threads hit low-confidence pages at the same moment.
    """

    def __init__(self, cap: int):
        self.cap = cap
        self.used = 0
        self._lock = threading.Lock()
        self._warned = False

    def claim(self) -> bool:
        """Reserve one vision page. Returns False when the budget is spent."""
        with self._lock:
            if self.used >= self.cap:
                if not self._warned:
                    self._warned = True
                    print(f"  Vision budget of {self.cap} page(s) spent — remaining "
                          f"low-confidence pages keep their Tesseract text. "
                          f"Raise it with --max-vision-pages.", flush=True)
                return False
            self.used += 1
            return True

    def release(self):
        """Return an unused claim (the call failed before spending anything)."""
        with self._lock:
            self.used = max(0, self.used - 1)


# ── Text cleanup ─────────────────────────────────────────────────────────────

_HYPHEN_BREAK_RE = re.compile(r'(\w)-\n(\w)')
_MULTI_BLANK_RE = re.compile(r'\n{3,}')
_TRAILING_SPACE_RE = re.compile(r'[ \t]+\n')
# Runs of OCR garbage: isolated punctuation-only lines like "| | ." or "~~~"
_JUNK_LINE_RE = re.compile(r'^[\s|_~`\^\-\.,:;\'"]{0,}$')


def clean_ocr_text(text: str) -> str:
    """Repair the artifacts OCR and PDF text layers reliably produce."""
    if not text:
        return ""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("­", "")           # soft hyphen
    text = text.replace("ﬁ", "fi").replace("ﬂ", "fl")
    text = _HYPHEN_BREAK_RE.sub(r'\1\2', text)  # rejoin words split across lines
    lines = [ln.rstrip() for ln in text.split("\n")]
    lines = [ln for ln in lines if not _JUNK_LINE_RE.match(ln) or ln == ""]
    text = "\n".join(lines)
    text = _TRAILING_SPACE_RE.sub("\n", text)
    text = _MULTI_BLANK_RE.sub("\n\n", text)
    return text.strip()


def alpha_ratio(text: str) -> float:
    """Fraction of characters that are letters or digits.

    A page of Tesseract noise scores well under 0.5 even when its reported
    confidence looks acceptable, so this is a second quality signal.
    """
    if not text:
        return 0.0
    useful = sum(1 for c in text if c.isalnum())
    return useful / len(text)


# ── Tooling checks ───────────────────────────────────────────────────────────

def have_binary(name: str) -> bool:
    return shutil.which(name) is not None


def tesseract_languages() -> set:
    try:
        out = subprocess.run(
            ["tesseract", "--list-langs"],
            capture_output=True, text=True, timeout=30,
        )
        lines = (out.stdout or "").splitlines()[1:]
        return {ln.strip() for ln in lines if ln.strip()}
    except (subprocess.SubprocessError, OSError):
        return set()


# ── PDF handling ─────────────────────────────────────────────────────────────

def pdf_page_texts(path: Path) -> list[str]:
    """Return the embedded text layer for each page (empty string if none)."""
    try:
        reader = PdfReader(str(path))
    except Exception as e:
        print(f"  Could not open PDF: {e}", flush=True)
        return []

    texts = []
    for page in reader.pages:
        try:
            texts.append(page.extract_text() or "")
        except Exception:
            texts.append("")
    return texts


def rasterize_page(pdf_path: Path, page_no: int, out_dir: Path, dpi: int) -> Path | None:
    """Render one PDF page to PNG with pdftoppm. Returns the image path."""
    prefix = out_dir / f"page-{page_no}"
    try:
        subprocess.run(
            [
                "pdftoppm", "-png", "-r", str(dpi),
                "-f", str(page_no), "-l", str(page_no),
                str(pdf_path), str(prefix),
            ],
            capture_output=True, timeout=300, check=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"  Rasterize failed (page {page_no}): "
              f"{e.stderr.decode(errors='replace').strip()[:200]}", flush=True)
        return None
    except (subprocess.SubprocessError, OSError) as e:
        print(f"  Rasterize failed (page {page_no}): {e}", flush=True)
        return None

    matches = sorted(out_dir.glob(f"page-{page_no}*.png"))
    return matches[0] if matches else None


# ── Tesseract OCR ────────────────────────────────────────────────────────────

def ocr_image(image_path: Path, lang: str, psm: int) -> tuple[str, float]:
    """OCR an image with Tesseract. Returns (text, mean_confidence_0_to_100)."""
    base_cmd = ["tesseract", str(image_path), "stdout", "-l", lang, "--psm", str(psm)]

    # TSV output carries per-word confidence, which is what makes the
    # vision-fallback decision cheap and automatic.
    try:
        proc = subprocess.run(
            base_cmd + ["tsv"], capture_output=True, text=True, timeout=600,
        )
    except (subprocess.SubprocessError, OSError) as e:
        print(f"  Tesseract failed on {image_path.name}: {e}", flush=True)
        return "", 0.0

    if proc.returncode != 0:
        print(f"  Tesseract error on {image_path.name}: "
              f"{proc.stderr.strip()[:200]}", flush=True)
        return "", 0.0

    words, confs = [], []
    current_line = None
    lines: list[list[str]] = []

    for row in proc.stdout.splitlines()[1:]:
        cols = row.split("\t")
        if len(cols) < 12:
            continue
        text = cols[11].strip()
        if not text:
            continue
        try:
            conf = float(cols[10])
        except ValueError:
            continue
        if conf < 0:
            continue
        line_key = tuple(cols[2:7])  # page/block/par/line identifiers
        if line_key != current_line:
            lines.append([])
            current_line = line_key
        lines[-1].append(text)
        words.append(text)
        confs.append(conf)

    text = "\n".join(" ".join(line) for line in lines if line)
    mean_conf = sum(confs) / len(confs) if confs else 0.0
    return text, mean_conf


# ── Vision fallback ──────────────────────────────────────────────────────────

def vision_ocr(image_path: Path, api_key: str, model: str) -> str:
    """Transcribe a page image with a vision model via OpenRouter."""
    try:
        b64 = base64.b64encode(image_path.read_bytes()).decode()
    except OSError as e:
        print(f"  Could not read image for vision OCR: {e}", flush=True)
        return ""

    payload = {
        "model": model,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": VISION_PROMPT},
                {"type": "image_url",
                 "image_url": {"url": f"data:image/png;base64,{b64}"}},
            ],
        }],
        "temperature": 0,
    }

    for attempt in range(MAX_RETRIES):
        try:
            resp = requests.post(
                "https://openrouter.ai/api/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
                timeout=120,
            )
            resp.raise_for_status()
            return resp.json()["choices"][0]["message"]["content"] or ""
        except (requests.RequestException, KeyError, IndexError) as e:
            status = getattr(getattr(e, 'response', None), 'status_code', None)
            if attempt < MAX_RETRIES - 1 and status in (None, 429, 500, 502, 503, 504):
                wait = RETRY_BACKOFF * (2 ** attempt)
                print(f"  Vision retry in {wait}s ({e})", flush=True)
                time.sleep(wait)
                continue
            print(f"  Vision OCR failed: {e}", flush=True)
            return ""
    return ""


# ── Embeddings ───────────────────────────────────────────────────────────────

def generate_embedding(text: str, api_key: str) -> list[float] | None:
    """Generate an embedding via OpenRouter."""
    for attempt in range(MAX_RETRIES):
        try:
            resp = requests.post(
                "https://openrouter.ai/api/v1/embeddings",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={"model": EMBEDDING_MODEL, "input": text[:8000]},
                timeout=30,
            )
            resp.raise_for_status()
            return resp.json()["data"][0]["embedding"]
        except (requests.RequestException, KeyError, IndexError) as e:
            status = getattr(getattr(e, 'response', None), 'status_code', None)
            if attempt < MAX_RETRIES - 1:
                wait = RETRY_BACKOFF * (2 ** attempt)
                if status == 429:
                    print(f"  Rate limited by OpenRouter. Retrying in {wait}s "
                          f"(attempt {attempt + 1}/{MAX_RETRIES})", flush=True)
                time.sleep(wait)
                continue
            print(f"  Embedding failed: {e}", flush=True)
            return None
    return None


# ── Supabase ─────────────────────────────────────────────────────────────────

def insert_thought(content: str, embedding: list[float] | None, metadata: dict,
                   supabase_url: str, supabase_key: str,
                   created_at: str | None = None,
                   fingerprint: str | None = None) -> str:
    """Insert a thought. Returns 'inserted', 'duplicate', or 'failed'."""
    payload = {"content": content, "metadata": metadata}
    if embedding:
        payload["embedding"] = embedding
    if created_at:
        payload["created_at"] = created_at
    if fingerprint:
        payload["content_fingerprint"] = fingerprint

    headers = {
        "apikey": supabase_key,
        "Authorization": f"Bearer {supabase_key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    if fingerprint:
        headers["Prefer"] = "return=minimal,resolution=merge-duplicates"

    for attempt in range(MAX_RETRIES):
        try:
            resp = requests.post(
                f"{supabase_url}/rest/v1/thoughts",
                headers=headers, json=payload, timeout=20,
            )
            resp.raise_for_status()
            return "inserted"
        except requests.RequestException as e:
            status = getattr(getattr(e, 'response', None), 'status_code', None)
            if status == 409:
                return "duplicate"
            if attempt < MAX_RETRIES - 1 and status in (None, 429, 500, 502, 503, 504):
                time.sleep(RETRY_BACKOFF * (2 ** attempt))
                continue
            print(f"  Insert failed: {e}", flush=True)
            return "failed"
    return "failed"


# ── Sync log ─────────────────────────────────────────────────────────────────

def load_sync_log(recipe_dir: Path) -> dict:
    log_path = recipe_dir / SYNC_LOG_FILE
    if log_path.exists():
        try:
            return json.loads(log_path.read_text())
        except (OSError, json.JSONDecodeError):
            print(f"Warning: could not read {SYNC_LOG_FILE}, starting fresh",
                  file=sys.stderr)
    return {"last_run": "", "files": {}}


def save_sync_log(recipe_dir: Path, log: dict):
    log_path = recipe_dir / SYNC_LOG_FILE
    tmp = log_path.with_suffix(".tmp")
    tmp.write_text(json.dumps(log, indent=2))
    tmp.replace(log_path)


def file_hash(path: Path) -> str:
    """SHA-256 of file bytes, streamed so a 2GB scan doesn't land in memory."""
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()[:16]


def content_fingerprint(text: str) -> str:
    """SHA-256 fingerprint of normalized content for DB-level dedup."""
    normalized = re.sub(r'\s+', ' ', text.strip().lower())
    return hashlib.sha256(normalized.encode()).hexdigest()


# ── Page extraction ──────────────────────────────────────────────────────────

def extract_pdf_page(pdf_path: Path, page_no: int, layer_text: str, work_dir: Path,
                     args, openrouter_key: str, vision_budget: "VisionBudget") -> dict:
    """Extract one PDF page. Returns {page, text, method, confidence}."""
    layer_text = clean_ocr_text(layer_text)
    if len(layer_text) >= args.text_layer_min_chars:
        return {"page": page_no, "text": layer_text,
                "method": "text-layer", "confidence": 100.0}

    if args.text_layer_only:
        return {"page": page_no, "text": layer_text,
                "method": "text-layer", "confidence": 100.0}

    page_dir = work_dir / f"p{page_no}"
    page_dir.mkdir(parents=True, exist_ok=True)
    image_path = rasterize_page(pdf_path, page_no, page_dir, args.dpi)
    if not image_path:
        return {"page": page_no, "text": layer_text,
                "method": "rasterize-failed", "confidence": 0.0}

    try:
        text, conf = ocr_image(image_path, args.lang, args.psm)
        text = clean_ocr_text(text)
        method = "tesseract"

        needs_help = (conf < args.confidence_threshold
                      or alpha_ratio(text) < 0.5
                      or len(text) < args.min_page_chars)

        if needs_help and args.vision_fallback and openrouter_key and vision_budget.claim():
            v_text = clean_ocr_text(vision_ocr(image_path, openrouter_key,
                                               args.vision_model))
            if v_text:
                if len(v_text) > len(text):
                    text, method, conf = v_text, "vision", 100.0
            else:
                vision_budget.release()

        return {"page": page_no, "text": text, "method": method, "confidence": conf}
    finally:
        shutil.rmtree(page_dir, ignore_errors=True)


def extract_image_file(path: Path, args, openrouter_key: str,
                       vision_budget: "VisionBudget") -> dict:
    """Extract text from a standalone image file."""
    text, conf = ocr_image(path, args.lang, args.psm)
    text = clean_ocr_text(text)
    method = "tesseract"

    needs_help = (conf < args.confidence_threshold
                  or alpha_ratio(text) < 0.5
                  or len(text) < args.min_page_chars)

    if needs_help and args.vision_fallback and openrouter_key and vision_budget.claim():
        v_text = clean_ocr_text(vision_ocr(path, openrouter_key, args.vision_model))
        if v_text:
            if len(v_text) > len(text):
                text, method, conf = v_text, "vision", 100.0
        else:
            vision_budget.release()

    return {"page": 1, "text": text, "method": method, "confidence": conf}


# ── File discovery ───────────────────────────────────────────────────────────

def iter_documents(root: Path, include_images: bool):
    """Yield document paths under root (or root itself if it is a file)."""
    exts = set(PDF_EXTS)
    if include_images:
        exts |= IMAGE_EXTS

    if root.is_file():
        if root.suffix.lower() in exts:
            yield root
        return

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]
        for name in sorted(filenames):
            if name.startswith('.'):
                continue
            path = Path(dirpath) / name
            if path.suffix.lower() in exts:
                yield path


def group_pages(pages: list[dict], group_size: int) -> list[dict]:
    """Combine consecutive pages into thought-sized chunks."""
    if group_size <= 1:
        return [{"pages": [p["page"]], "text": p["text"],
                 "methods": [p["method"]], "confidence": p["confidence"]}
                for p in pages]

    grouped = []
    for i in range(0, len(pages), group_size):
        block = pages[i:i + group_size]
        confs = [p["confidence"] for p in block]
        grouped.append({
            "pages": [p["page"] for p in block],
            "text": "\n\n".join(p["text"] for p in block).strip(),
            "methods": [p["method"] for p in block],
            "confidence": sum(confs) / len(confs) if confs else 0.0,
        })
    return grouped


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    sys.stdout.reconfigure(line_buffering=True)

    parser = argparse.ArgumentParser(
        description="OCR scanned PDFs and images into Open Brain as searchable thoughts.",
    )
    parser.add_argument("path", help="File or directory of PDFs/images to import")
    parser.add_argument("--dry-run", action="store_true",
                        help="Report page counts and OCR workload without inserting")
    parser.add_argument("--limit", type=int, default=0,
                        help="Process only the first N files (0 = all)")
    parser.add_argument("--max-pages-per-file", type=int, default=0,
                        help="Cap pages read per file (0 = unlimited, the default)")
    parser.add_argument("--lang", type=str, default="eng",
                        help="Tesseract language(s), e.g. 'eng' or 'eng+deu'")
    parser.add_argument("--dpi", type=int, default=DEFAULT_DPI,
                        help=f"Rasterization DPI (default: {DEFAULT_DPI})")
    parser.add_argument("--psm", type=int, default=3,
                        help="Tesseract page segmentation mode (default: 3, auto)")
    parser.add_argument("--workers", type=int, default=4,
                        help="Pages OCRed in parallel per file (default: 4)")
    parser.add_argument("--group-pages", type=int, default=1,
                        help="Pages combined into one thought (default: 1)")
    parser.add_argument("--min-page-chars", type=int, default=MIN_PAGE_CHARS,
                        help=f"Drop pages with fewer characters (default: {MIN_PAGE_CHARS})")
    parser.add_argument("--text-layer-min-chars", type=int, default=TEXT_LAYER_MIN_CHARS,
                        help="Characters of embedded text that count as already-digital")
    parser.add_argument("--text-layer-only", action="store_true",
                        help="Never rasterize or OCR — import embedded text layers only")
    parser.add_argument("--no-images", action="store_true",
                        help="Skip standalone image files, import PDFs only")
    parser.add_argument("--vision-fallback", action="store_true",
                        help="Escalate badly-read pages to a vision model (costs money)")
    parser.add_argument("--max-vision-pages", type=int, default=25,
                        help="Hard cap on vision-model pages per run (default: 25)")
    parser.add_argument("--vision-model", type=str, default=DEFAULT_VISION_MODEL,
                        help=f"OpenRouter vision model (default: {DEFAULT_VISION_MODEL})")
    parser.add_argument("--confidence-threshold", type=float,
                        default=DEFAULT_CONFIDENCE_THRESHOLD,
                        help="Tesseract confidence below which a page is 'badly read'")
    parser.add_argument("--no-embed", action="store_true",
                        help="Insert thoughts without embeddings")
    parser.add_argument("--no-secret-scan", action="store_true",
                        help="Disable secret detection (not recommended)")
    parser.add_argument("--reprocess", action="store_true",
                        help="Ignore the sync log and re-import everything")
    parser.add_argument("--source-label", type=str, default="ocr",
                        help="Value stamped in metadata.source (default: 'ocr')")
    parser.add_argument("--verbose", action="store_true", help="Show per-page detail")
    args = parser.parse_args()

    root = Path(args.path).expanduser().resolve()
    if not root.exists():
        print(f"Error: path not found: {root}", file=sys.stderr)
        sys.exit(1)

    # Load env vars
    env_file = Path(__file__).parent / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, _, value = line.partition('=')
                os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))

    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    supabase_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    openrouter_key = os.environ.get("OPENROUTER_API_KEY", "")

    if not args.dry_run:
        if not supabase_url or not supabase_key:
            print("Error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required",
                  file=sys.stderr)
            print("Set them in .env or as environment variables", file=sys.stderr)
            sys.exit(1)
        if not openrouter_key and not args.no_embed:
            print("Error: OPENROUTER_API_KEY required for embeddings", file=sys.stderr)
            print("Or pass --no-embed to skip embedding generation", file=sys.stderr)
            sys.exit(1)
    if args.vision_fallback and not openrouter_key:
        print("Error: --vision-fallback requires OPENROUTER_API_KEY", file=sys.stderr)
        sys.exit(1)

    # ── Preflight ────────────────────────────────────────────────────────────

    need_ocr_tools = not args.text_layer_only
    if need_ocr_tools:
        missing = [b for b in ("tesseract", "pdftoppm") if not have_binary(b)]
        if missing:
            print(f"Error: missing required binaries: {', '.join(missing)}",
                  file=sys.stderr)
            print("  macOS:  brew install tesseract poppler", file=sys.stderr)
            print("  Ubuntu: sudo apt install tesseract-ocr poppler-utils",
                  file=sys.stderr)
            print("  Or run with --text-layer-only to skip OCR entirely.",
                  file=sys.stderr)
            sys.exit(1)

        installed = tesseract_languages()
        wanted = set(args.lang.split("+"))
        absent = wanted - installed if installed else set()
        if absent:
            print(f"Error: Tesseract language data missing: {', '.join(sorted(absent))}",
                  file=sys.stderr)
            print(f"  Installed: {', '.join(sorted(installed)) or '(none detected)'}",
                  file=sys.stderr)
            print("  Ubuntu: sudo apt install tesseract-ocr-<lang>", file=sys.stderr)
            sys.exit(1)

    if not args.dry_run:
        print("Preflight check...", flush=True)
        try:
            resp = requests.get(
                f"{supabase_url}/rest/v1/thoughts?limit=1",
                headers={"apikey": supabase_key,
                         "Authorization": f"Bearer {supabase_key}"},
                timeout=10,
            )
            if resp.status_code == 404:
                print("Error: 'thoughts' table not found at this Supabase URL.",
                      file=sys.stderr)
                sys.exit(1)
            resp.raise_for_status()
        except requests.RequestException as e:
            print(f"Error: could not reach Supabase: {e}", file=sys.stderr)
            sys.exit(1)

        if not args.no_embed and generate_embedding("preflight check", openrouter_key) is None:
            print("Error: embedding preflight failed. Check OPENROUTER_API_KEY "
                  "and that your account has credit.", file=sys.stderr)
            sys.exit(1)

        print("  Supabase and OpenRouter connections verified.\n", flush=True)

    # ── Discover files ───────────────────────────────────────────────────────

    recipe_dir = Path(__file__).parent
    sync_log = load_sync_log(recipe_dir) if not args.reprocess else {"last_run": "", "files": {}}

    documents = list(iter_documents(root, include_images=not args.no_images))
    if args.limit and args.limit > 0:
        documents = documents[:args.limit]

    print(f"Source:   {root}")
    print(f"Mode:     {'DRY RUN' if args.dry_run else 'LIVE IMPORT'}")
    print(f"Found:    {len(documents)} document(s)\n")

    if not documents:
        print("Nothing to do. Check the path and file extensions.")
        return

    vision_budget = VisionBudget(args.max_vision_pages if args.vision_fallback else 0)
    stats = {
        "files": 0, "files_skipped": 0, "pages": 0, "pages_skipped": 0,
        "text_layer": 0, "tesseract": 0, "vision": 0, "failed_pages": 0,
        "inserted": 0, "duplicates": 0, "failed": 0, "secrets": 0,
    }

    for doc in documents:
        rel = doc.relative_to(root) if root.is_dir() else doc.name
        try:
            f_hash = file_hash(doc)
        except OSError as e:
            print(f"Skipping {rel}: {e}")
            stats["files_skipped"] += 1
            continue

        record = sync_log["files"].get(str(rel), {})
        done_pages = set(record.get("pages_done", [])) if record.get("hash") == f_hash else set()
        if record.get("hash") == f_hash and record.get("complete"):
            stats["files_skipped"] += 1
            if args.verbose:
                print(f"Skipping {rel} (already imported)")
            continue

        is_pdf = doc.suffix.lower() in PDF_EXTS
        layer_texts = pdf_page_texts(doc) if is_pdf else [""]
        total_pages = len(layer_texts) if is_pdf else 1
        if total_pages == 0:
            print(f"Skipping {rel}: no readable pages")
            stats["files_skipped"] += 1
            continue

        page_numbers = list(range(1, total_pages + 1))
        if args.max_pages_per_file > 0:
            page_numbers = page_numbers[:args.max_pages_per_file]
        todo = [p for p in page_numbers if p not in done_pages]

        resumed = len(page_numbers) - len(todo)
        print(f"{rel}  ({total_pages} page(s)"
              + (f", {resumed} already done" if resumed else "") + ")")

        if args.dry_run:
            needs_ocr = sum(
                1 for p in todo
                if len(clean_ocr_text(layer_texts[p - 1] if is_pdf else "")) < args.text_layer_min_chars
            )
            stats["files"] += 1
            stats["pages"] += len(todo)
            stats["text_layer"] += len(todo) - needs_ocr
            stats["tesseract"] += needs_ocr
            print(f"  Would read {len(todo) - needs_ocr} page(s) from the text layer, "
                  f"OCR {needs_ocr} page(s)")
            continue

        if not todo:
            record.update({"hash": f_hash, "complete": True})
            sync_log["files"][str(rel)] = record
            save_sync_log(recipe_dir, sync_log)
            continue

        # ── OCR pages (parallel: subprocess work releases the GIL) ───────────
        with tempfile.TemporaryDirectory(prefix="ob1-ocr-") as tmp:
            work_dir = Path(tmp)
            if is_pdf:
                def run_page(p):
                    return extract_pdf_page(doc, p, layer_texts[p - 1], work_dir,
                                            args, openrouter_key, vision_budget)

                workers = max(1, args.workers)
                with ThreadPoolExecutor(max_workers=workers) as pool:
                    pages = list(pool.map(run_page, todo))
            else:
                pages = [extract_image_file(doc, args, openrouter_key, vision_budget)]

        pages.sort(key=lambda p: p["page"])

        for p in pages:
            if p["method"] == "text-layer":
                stats["text_layer"] += 1
            elif p["method"] == "vision":
                stats["vision"] += 1
            elif p["method"] == "tesseract":
                stats["tesseract"] += 1
            else:
                stats["failed_pages"] += 1
            if args.verbose:
                print(f"  p{p['page']}: {p['method']} "
                      f"conf={p['confidence']:.0f} chars={len(p['text'])}")

        usable = [p for p in pages if len(p["text"]) >= args.min_page_chars]
        stats["pages_skipped"] += len(pages) - len(usable)
        stats["pages"] += len(pages)

        # ── Insert as thoughts ───────────────────────────────────────────────
        mtime = datetime.fromtimestamp(doc.stat().st_mtime, tz=timezone.utc)
        pages_committed = set(done_pages)

        for block in group_pages(usable, args.group_pages):
            text = block["text"]
            if not text:
                continue

            if not args.no_secret_scan:
                found = scan_for_secrets(text)
                if found:
                    stats["secrets"] += 1
                    print(f"  Skipped page(s) {block['pages']}: possible {found}")
                    pages_committed.update(block["pages"])
                    continue

            page_label = (f"page {block['pages'][0]}" if len(block["pages"]) == 1
                          else f"pages {block['pages'][0]}-{block['pages'][-1]}")
            content = f"{doc.stem} — {page_label}\n\n{text}"

            embedding = None
            if not args.no_embed:
                embedding = generate_embedding(content, openrouter_key)
                if embedding is None:
                    stats["failed"] += 1
                    continue

            metadata = {
                "source": args.source_label,
                "type": "reference",
                "document": doc.name,
                "path": str(rel),
                "pages": block["pages"],
                "ocr_methods": sorted(set(block["methods"])),
                "ocr_confidence": round(block["confidence"], 1),
                "file_hash": f_hash,
                "imported_at": datetime.now(tz=timezone.utc).isoformat(),
            }

            result = insert_thought(
                content, embedding, metadata, supabase_url, supabase_key,
                created_at=mtime.isoformat(),
                fingerprint=content_fingerprint(content),
            )
            if result == "inserted":
                stats["inserted"] += 1
            elif result == "duplicate":
                stats["duplicates"] += 1
            else:
                stats["failed"] += 1
                continue

            pages_committed.update(block["pages"])

        # Pages that yielded nothing usable are still done — don't re-OCR them.
        pages_committed.update(p["page"] for p in pages
                               if p["method"] != "rasterize-failed")

        sync_log["files"][str(rel)] = {
            "hash": f_hash,
            "pages_done": sorted(pages_committed),
            "total_pages": total_pages,
            "complete": len(pages_committed) >= len(page_numbers),
            "last_run": datetime.now(tz=timezone.utc).isoformat(),
        }
        sync_log["last_run"] = datetime.now(tz=timezone.utc).isoformat()
        save_sync_log(recipe_dir, sync_log)
        stats["files"] += 1

    # ── Summary ──────────────────────────────────────────────────────────────

    print()
    print("─" * 60)
    if args.dry_run:
        print(f"Files:            {stats['files']}")
        print(f"Pages to process: {stats['pages']}")
        print(f"  From text layer (free):  {stats['text_layer']}")
        print(f"  Needing OCR (free/local): {stats['tesseract']}")
        print("\nRun again without --dry-run to import.")
        return

    print(f"Files processed:  {stats['files']} ({stats['files_skipped']} skipped)")
    print(f"Pages read:       {stats['pages']}")
    print(f"  Text layer:     {stats['text_layer']}")
    print(f"  Tesseract:      {stats['tesseract']}")
    print(f"  Vision model:   {stats['vision']} (cap: {vision_budget.cap})")
    if stats["failed_pages"]:
        print(f"  Failed:         {stats['failed_pages']}")
    print(f"Thoughts inserted: {stats['inserted']}")
    if stats["duplicates"]:
        print(f"  Duplicates skipped: {stats['duplicates']}")
    if stats["secrets"]:
        print(f"  Skipped for possible secrets: {stats['secrets']}")
    if stats["failed"]:
        print(f"  Failed inserts: {stats['failed']}")
    print(f"\nResume state saved to {SYNC_LOG_FILE}")


if __name__ == "__main__":
    main()
