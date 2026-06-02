"""
Scraper for the Mongratis collection on Pokengine
(https://pokengine.org/collections/107s7x9x/Mongratis).

Mongratis is a community-curated Fakemon dex explicitly licensed for
free use both on and off Pokengine in non-commercial fan games, with
attribution. See:
  https://pokengine.org/collections/107s7x9x/Mongratis

What this script does, on run:
  1. Fetches the 3 collection listing pages and harvests
     (dex_id, uid, name, primary_type_id, sprite_url) for all 219 mons.
  2. For each mon, fetches its detail page to extract:
        - both types (primary + secondary)
        - category / species name (e.g. "Gecko Mon")
        - height + weight (raw "metric / imperial" strings)
        - flavor text (dex entry)
        - direct evolution target (uid → resolved to dex_id)
        - artist credits (every unique "by <Name>" attribution)
  3. Downloads each sprite to:
        assets/gachamon/generation_<N>/<id4>_<name>.webp
     where <N> matches the runtime's gachamonGeneration() bucket so the
     app's sprite resolver finds them without any further config.
  4. Writes gachadex.json with 219 entries containing all the fields
     above. After the first pass, walks the evolution map backwards to
     fill `preEvolution` on every mon that's the target of someone
     else's `evolution` list.
        Rarity defaults to 'common' for everything — edit by hand if
        you want a tiered draw distribution.
  5. Writes mongratis_credits.md with every unique artist name,
     alphabetically. Paste into README.md (or wherever you keep
     attributions).

Idempotency: sprite files that already exist on disk are NOT
re-downloaded. gachadex.json IS overwritten every run.

Requirements:
  pip install requests beautifulsoup4

Run from the public project root:
  python scrape_mongratis.py             # full 219-entry scrape
  python scrape_mongratis.py --limit 3   # smoke-test on the first 3 mons

Total runtime: ~5-10 minutes on first full run (one request per mon
detail page plus one image download each, with a polite 0.3-0.5 s
delay between calls to avoid hammering pokengine.org).
"""

import json
import re
import sys
import time
from pathlib import Path

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("This script needs `requests` and `beautifulsoup4`. Install with:")
    print("  pip install requests beautifulsoup4")
    sys.exit(1)


# ── Paths and constants ──────────────────────────────────────────────────────

ROOT = Path(__file__).parent
GACHAMON_ASSETS = ROOT / "assets" / "gachamon"
GACHADEX_PATH = ROOT / "gachadex.json"
CREDITS_PATH = ROOT / "mongratis_credits.md"

COLLECTION_URL = "https://pokengine.org/collections/107s7x9x/Mongratis"

# Pokengine 403s on bot user agents; spoof a plain desktop Chrome.
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    )
}

# Mirrors the gachamonGeneration() logic in
# lib/services/gachamon_game_service.dart so sprites land in the same
# folders the runtime resolver looks at.
GENERATION_CUTOFFS = [
    (151, 1), (251, 2), (386, 3), (493, 4), (649, 5),
    (721, 6), (809, 7), (905, 8), (1025, 9),
]


def generation_for(dex_id: int) -> int:
    for cutoff, gen in GENERATION_CUTOFFS:
        if dex_id <= cutoff:
            return gen
    return 10


# Type number → name mapping, populated on-the-fly as detail pages are
# parsed. Printed at end so you can sanity-check.
TYPE_MAP: dict[int, str] = {}


# ── HTTP helpers ─────────────────────────────────────────────────────────────

def fetch_text(url: str) -> str:
    """GET a URL with a browser UA. Brief sleep so we're not hammering."""
    resp = requests.get(url, headers=HEADERS, timeout=20)
    resp.raise_for_status()
    time.sleep(0.4)
    return resp.text


def fetch_binary(url: str, dest: Path) -> bool:
    """Download to dest. Returns True on success, False on any failure.
    Skips if dest already exists and is non-empty."""
    if dest.exists() and dest.stat().st_size > 0:
        return True
    try:
        r = requests.get(url, headers=HEADERS, timeout=20)
        r.raise_for_status()
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(r.content)
        time.sleep(0.3)
        return True
    except Exception as exc:
        print(f"    [warn] download failed ({url}): {exc}")
        return False


# ── Listing-page parser ──────────────────────────────────────────────────────

LISTING_RE = re.compile(
    r"data-id='(?P<id>\d+)' data-uid='(?P<uid>[a-z0-9]+)' "
    r"class='dex-block type-(?P<type>\d+)'[^>]*>"
    r"<span><span class='id'>\d+</span>(?P<name>[^<]+)</span>"
    r"<a[^>]*><img[^>]*data-src='(?P<sprite>[^']+)'"
)


def parse_listing(html: str):
    """Yield dicts {dex_id, uid, name, primary_type_n, sprite_url}."""
    for m in LISTING_RE.finditer(html):
        yield {
            "dex_id": int(m["id"]),
            "uid": m["uid"],
            "name": m["name"].strip(),
            "primary_type_n": int(m["type"]),
            "sprite_url": m["sprite"],
        }


# ── Detail-page parser ───────────────────────────────────────────────────────

# Type chips for the mon's own typing have the `martop-8` modifier on
# top of the standard `type type-N` classes. Type chips elsewhere on
# the page (effectiveness tables, etc.) lack `martop-8`, so this lets
# us isolate just the two we care about.
TYPE_CHIP_RE = re.compile(
    r"<p class='type type-(\d+) martop-8'>([^<]+)</p>"
)

# Artist credits appear as " by <a [...] target='blank'>Name</a>"
# attached to phrases like "Concept and design by Feyrah" or
# "front sprite by Such-And-Such". A single mon can have multiple
# credits if the work was split.
CREDIT_RE = re.compile(
    r"by <a [^>]*target='blank'[^>]*>([^<]+)</a>"
)

# Category / species name. Pokengine renders this as
# "<b class='bold'>Gecko</b> Mon" — we capture the bold word.
CATEGORY_RE = re.compile(r"<b class='bold'>([^<]+)</b>\s*Mon")

# Height + weight rendered as
# "<b class='height'>Height</b><small>0.30 m / 1'00&quot;</small>".
HEIGHT_RE = re.compile(r"<b class='height'>Height</b><small>([^<]+)</small>")
WEIGHT_RE = re.compile(r"<b class='weight'>Weight</b><small>([^<]+)</small>")

# Flavor (dex entry) lives inside the "Flavor" light-container.
FLAVOR_RE = re.compile(
    r"<div class='light-container-title'><div>Flavor</div></div>"
    r"<div class='light-container'>(.*?)</div>",
    re.DOTALL,
)

# The evolution chain is rendered as a sequence of mon icons separated
# by arrow spans, e.g.
#   <a href='/mons/AAA/Geckrow?...'><img ...icons/AAA.webp...>
#   <span class='arrow'>...data-mon='Goanopy'>Lv. 16</span>
#       <a href='/mons/BBB/Goanopy?...'>...
#   <span class='arrow'>...data-mon='Varanitor'>Lv. 34</span>
#       <a href='/mons/CCC/Varanitor?...'>...
#
# Every mon's detail page renders the FULL chain. To find the
# direct-next evolution of the current mon, we collect the icon links
# in chain order, find which one is the current uid, and read the
# arrow at the same index (arrow[i] sits BETWEEN icon[i] and
# icon[i+1], so arrow[my_index] is the one I evolve via).
CHAIN_ICON_RE = re.compile(
    r"<a href='/mons/([a-z0-9]+)/[A-Za-z0-9]+\?collection=[^']+'><img[^>]+/icons/"
)
CHAIN_ARROW_RE = re.compile(
    r"<span class='arrow'>.*?<a href='/mons/([a-z0-9]+)/[^']+'",
    re.DOTALL,
)

# Strip remaining HTML markup from extracted text content (mostly <br>).
TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")
HTML_ENTITIES = {
    "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"',
    "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
}


def _clean_text(s: str) -> str:
    """Strip HTML tags, decode common entities, collapse whitespace."""
    s = TAG_RE.sub(" ", s)
    for k, v in HTML_ENTITIES.items():
        s = s.replace(k, v)
    return WS_RE.sub(" ", s).strip()


def _imperial_only(value: str) -> str:
    """Strip the metric half from a Pokengine 'metric / imperial' string.

    Height arrives as e.g. "0.30 m / 1'00\\"" → returns `1'00"`.
    Weight arrives as e.g. "5.00 kg / 11 lbs" → returns `11 lbs`.
    Strings without a slash are returned unchanged (defensive — covers
    any entry where only one unit was filled in).
    """
    if " / " in value:
        return value.split(" / ", 1)[1].strip()
    return value.strip()


def parse_detail(html: str, current_uid: str):
    """Extract all per-mon metadata from a detail page.

    Returns a dict with: type1, type2, artists (list), category, height,
    weight, dex_entry, evolution_uid (or None).
    """
    result = {
        "type1": None, "type2": None, "artists": [],
        "category": None, "height": None, "weight": None,
        "dex_entry": None, "evolution_uid": None,
    }

    # Types
    type_names = []
    for m in TYPE_CHIP_RE.finditer(html):
        type_n = int(m.group(1))
        type_name = m.group(2).strip()
        TYPE_MAP[type_n] = type_name
        type_names.append(type_name)
    if type_names:
        result["type1"] = type_names[0]
        if len(type_names) > 1:
            result["type2"] = type_names[1]

    # Credits (dedupe, preserve order)
    seen = set()
    for m in CREDIT_RE.finditer(html):
        name = m.group(1).strip()
        if name and name not in seen:
            result["artists"].append(name)
            seen.add(name)

    # Category / species
    m = CATEGORY_RE.search(html)
    if m:
        result["category"] = f"{m.group(1).strip()} Mon"

    # Height + weight — page renders "metric / imperial"; keep imperial
    # only to match the gachadex card's `H: 4'7"  W: 264.6 lbs` format.
    m = HEIGHT_RE.search(html)
    if m:
        result["height"] = _imperial_only(_clean_text(m.group(1)))
    m = WEIGHT_RE.search(html)
    if m:
        result["weight"] = _imperial_only(_clean_text(m.group(1)))

    # Dex entry (flavor text)
    m = FLAVOR_RE.search(html)
    if m:
        text = _clean_text(m.group(1))
        if text:
            result["dex_entry"] = text

    # Evolution chain
    icons = CHAIN_ICON_RE.findall(html)
    arrows = CHAIN_ARROW_RE.findall(html)
    try:
        my_pos = icons.index(current_uid)
        if my_pos < len(arrows):
            result["evolution_uid"] = arrows[my_pos]
    except ValueError:
        # Current mon not in chain → single-stage, no evolution.
        pass

    return result


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    # CLI: --limit N stops after the first N mons. Handy for smoke-testing
    # the parsing logic without committing to the full 219-mon scrape.
    limit = None
    for i, arg in enumerate(sys.argv[1:], 1):
        if arg == "--limit" and i < len(sys.argv) - 1:
            try:
                limit = int(sys.argv[i + 1])
            except ValueError:
                print(f"--limit needs an integer (got {sys.argv[i + 1]!r})")
                sys.exit(2)

    GACHAMON_ASSETS.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("Mongratis scraper" + (f"  (limit={limit})" if limit else ""))
    print("=" * 60)
    print(f"Output: {GACHADEX_PATH}")
    print(f"Sprites: {GACHAMON_ASSETS}/generation_*/")
    print(f"Credits: {CREDITS_PATH}")
    print()

    # Step 1: fetch all 3 listing pages
    print("Fetching listing pages...")
    listings = []
    for page in (1, 2, 3):
        url = COLLECTION_URL if page == 1 else f"{COLLECTION_URL}?page={page}"
        print(f"  page {page} ... ", end="", flush=True)
        html = fetch_text(url)
        page_entries = list(parse_listing(html))
        print(f"{len(page_entries)} entries")
        listings.extend(page_entries)

    if limit:
        listings = listings[:limit]
        print(f"\n--limit {limit} → processing first {len(listings)} only.\n")
    else:
        print(f"\nTotal: {len(listings)} mons.\n")

    # uid → dex_id, for resolving evolution targets to their dex IDs
    # (Gachamon's uniqueKey is the integer id rendered as a string).
    uid_to_id = {item["uid"]: item["dex_id"] for item in listings}

    # Step 2: for each mon, fetch detail page and download sprite
    print("Fetching detail pages + downloading sprites...")
    all_artists: set[str] = set()
    entries = []  # list of (dict, evolution_uid_or_None)
    for i, item in enumerate(listings, 1):
        dex_id = item["dex_id"]
        name = item["name"]
        uid = item["uid"]
        print(f"  [{i:3d}/{len(listings)}] #{dex_id:03d} {name}")

        detail_url = f"https://pokengine.org/mons/{uid}/{name}?collection=107s7x9x"
        try:
            detail_html = fetch_text(detail_url)
            detail = parse_detail(detail_html, uid)
        except Exception as exc:
            print(f"    [warn] detail fetch failed: {exc}")
            detail = {
                "type1": None, "type2": None, "artists": [],
                "category": None, "height": None, "weight": None,
                "dex_entry": None, "evolution_uid": None,
            }

        # Fall back to type number → name lookup if the detail page didn't
        # yield a clean chip (rare, but possible).
        if not detail["type1"]:
            detail["type1"] = TYPE_MAP.get(
                item["primary_type_n"], f"Type{item['primary_type_n']}"
            )

        for a in detail["artists"]:
            all_artists.add(a)

        # Download sprite
        gen = generation_for(dex_id)
        sprite_path = GACHAMON_ASSETS / f"generation_{gen}" / f"{dex_id:04d}_{name}.webp"
        fetch_binary(item["sprite_url"], sprite_path)

        # Build gachadex entry (preEvolution filled in after the loop;
        # evolution filled in here from the resolved uid).
        entry = {
            "id": dex_id,
            "name": name,
            "fileStem": name,
            "rarity": "common",  # TODO: tune per-mon for a tiered draw distribution
            "type1": detail["type1"],
        }
        if detail["type2"]:
            entry["type2"] = detail["type2"]
        if detail["category"]:
            entry["category"] = detail["category"]
        if detail["height"]:
            entry["height"] = detail["height"]
        if detail["weight"]:
            entry["weight"] = detail["weight"]
        if detail["dex_entry"]:
            entry["dexEntry"] = detail["dex_entry"]
        # Resolve evolution uid → next dex id (as string, matching Gachamon.uniqueKey).
        if detail["evolution_uid"] and detail["evolution_uid"] in uid_to_id:
            entry["evolution"] = [str(uid_to_id[detail["evolution_uid"]])]
        entries.append(entry)

    # Step 2b: derive preEvolution by inverting the evolution map.
    # If mon X has `evolution: ["Y"]`, then Y's `preEvolution` is "X".
    pre_map: dict[int, int] = {}
    for entry in entries:
        for next_id_str in entry.get("evolution", []):
            try:
                pre_map[int(next_id_str)] = entry["id"]
            except (ValueError, TypeError):
                pass
    for entry in entries:
        if entry["id"] in pre_map:
            entry["preEvolution"] = str(pre_map[entry["id"]])

    # Step 3: write gachadex.json
    GACHADEX_PATH.write_text(json.dumps(entries, indent=2), encoding="utf-8")
    print(f"\nWrote {len(entries)} entries to {GACHADEX_PATH}")

    # Step 4: write credits
    sorted_artists = sorted(all_artists, key=str.casefold)
    with CREDITS_PATH.open("w", encoding="utf-8") as f:
        f.write("# Mongratis artist credits\n\n")
        f.write(f"The {len(entries)} creatures in this gachadex are from the [Mongratis collection]"
                f"(https://pokengine.org/collections/107s7x9x/Mongratis) on Pokengine — a "
                f"community-curated Fakemon dex explicitly licensed for free use in "
                f"non-commercial fan games, with attribution.\n\n")
        f.write(f"## Artists ({len(sorted_artists)} unique)\n\n")
        for name in sorted_artists:
            f.write(f"- {name}\n")
    print(f"Wrote {len(sorted_artists)} unique artists to {CREDITS_PATH}")

    # Step 5: dump type mapping for sanity check
    print(f"\nType number → name mapping (discovered from detail pages):")
    for n in sorted(TYPE_MAP):
        print(f"  type-{n:2d} = {TYPE_MAP[n]}")

    print()
    print("Done. Re-running will refresh the JSON but skip already-downloaded sprites.")
    print("Paste the contents of mongratis_credits.md into README.md to credit the artists.")


if __name__ == "__main__":
    main()
