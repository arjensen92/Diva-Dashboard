/// Gachadex data for the gachapon game. The active list is loaded at startup
/// from `<projectRoot>/gachadex.json` via [GachadexService]; this file exposes
/// the Gachamon type, rarity enum, weight table, and the hardcoded seed used
/// to initialize that JSON on first run.

enum GachamonRarity {
  common, // base-stage gachamon that evolve
  uncommon, // single-stage gachamon that never evolve
  rare, // evolved forms, starters, mega/G-max
  pseudo, // pseudo-legendary lines (Dratini line, etc.)
  legendary, // Articuno, Zapdos, Moltres, Mewtwo, etc.
  mythical, // Mew, etc.
}

/// Relative weights for the random draw. Members of the same tier are drawn
/// uniformly; tier weight is multiplied by tier population inside the roller.
const rarityWeight = <GachamonRarity, double>{
  GachamonRarity.common: 100,
  GachamonRarity.uncommon: 50,
  GachamonRarity.rare: 25,
  GachamonRarity.pseudo: 12,
  GachamonRarity.legendary: 5,
  GachamonRarity.mythical: 1,
};

/// A single gachadex entry. Immutable — changes happen by rewriting
/// `gachadex.json` (see [GachadexService]) and reloading.
///
/// Form-aware keying: alt forms (Galarian, Mega, etc.) share a numeric
/// [id] with the base form but are stored as distinct entries. The
/// [uniqueKey] getter collapses the base to `"$id"` and an alt form to
/// `"$id:$form"` — that's the key used throughout the game state maps
/// (`caught`, `holo`, `catchOrder`) and for evolution-chain references
/// (`preEvolution`, `evolution`).
class Gachamon {
  final int id;
  final String name; // display name
  final String fileStem; // filename fragment after the ID
  final GachamonRarity rarity;
  /// Alt-form tag (e.g. "Attack" for Deoxys-Attack). `null` means base form.
  /// Alt forms keep their base Gachadex id but still count as a distinct catch.
  final String? form;
  /// Which subfolder of `assets/gachamon/` holds this form's sprite.
  /// Defaults to `alt_forms` when unspecified. Valid options include:
  /// `alolan_forms`, `galarian_forms`, `hisuian_forms`, `paldean_forms`,
  /// `mega_evolutions`, `gigantamax`, `alt_forms`.
  final String? formFolder;
  /// Primary type (e.g. `"Grass"`, `"Fire"`). Null for entries missing from
  /// the types source.
  final String? type1;
  /// Secondary type. Null for single-type gachamon.
  final String? type2;
  /// Short gachadex description shown on the card. Null when we don't have
  /// one (e.g. newly-added gachamon not yet in `gachamon_dex_entries.txt`).
  final String? dexEntry;
  /// Species category (e.g. `"Seed Gachamon"`).
  final String? category;
  /// Height formatted as `X'Y''`.
  final String? height;
  /// Weight formatted as `X.X lbs`.
  final String? weight;
  /// Unique-key of the gachamon that evolves into this one (null for base
  /// forms). Form-aware: `"79:Galar"` points at Galarian Slowpoke.
  final String? preEvolution;
  /// Unique-keys of gachamon that this one evolves into (empty when final form).
  final List<String> evolution;
  const Gachamon(
    this.id,
    this.name,
    this.fileStem,
    this.rarity, {
    this.form,
    this.formFolder,
    this.type1,
    this.type2,
    this.dexEntry,
    this.category,
    this.height,
    this.weight,
    this.preEvolution,
    this.evolution = const [],
  });

  /// Stable identifier used in the caught map & catchOrder list. Base form
  /// collapses to the numeric id; alt forms append `:<form>`.
  String get uniqueKey => form == null ? '$id' : '$id:$form';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fileStem': fileStem,
        'rarity': rarity.name,
        if (form != null) 'form': form,
        if (formFolder != null) 'formFolder': formFolder,
        if (type1 != null) 'Type 1': type1,
        if (type2 != null) 'Type 2': type2,
        if (category != null) 'category': category,
        if (height != null) 'height': height,
        if (weight != null) 'weight': weight,
        if (preEvolution != null) 'preEvolution': preEvolution,
        if (evolution.isNotEmpty) 'evolution': evolution,
        if (dexEntry != null) 'dexEntry': dexEntry,
      };

  static Gachamon fromJson(Map<String, dynamic> j) {
    final rarityStr = j['rarity']?.toString() ?? 'common';
    final rarity = GachamonRarity.values.firstWhere(
      (r) => r.name == rarityStr,
      orElse: () => GachamonRarity.common,
    );
    return Gachamon(
      (j['id'] as num).toInt(),
      j['name']?.toString() ?? '???',
      j['fileStem']?.toString() ?? '',
      rarity,
      form: j['form']?.toString(),
      formFolder: j['formFolder']?.toString(),
      // Accept both the conventional camelCase keys ('type1'/'type2'
      // — what scrape_mongratis.py writes) and the legacy capitalized
      // form ('Type 1'/'Type 2' — what the older hand-authored
      // pokedex.json schema used). Without this fallback the in-memory
      // pk.type1/type2 silently come back null even though the JSON
      // file clearly has the value, which makes the card render as a
      // gray fallback with no type chips.
      type1: (j['type1'] ?? j['Type 1'])?.toString(),
      type2: (j['type2'] ?? j['Type 2'])?.toString(),
      dexEntry: j['dexEntry']?.toString(),
      category: j['category']?.toString(),
      height: j['height']?.toString(),
      weight: j['weight']?.toString(),
      preEvolution: j['preEvolution'] == null ? null : j['preEvolution'].toString(),
      evolution: (j['evolution'] as List?)
              ?.map((v) => v.toString())
              .toList() ??
          const [],
    );
  }
}

/// The active Gachadex — populated at app startup by [GachadexService.load]
/// reading `<projectRoot>/gachadex.json`. Starts empty; anything that
/// accesses it before load completes (or when the JSON is missing/malformed)
/// will see an empty list and callers handle that gracefully — e.g.
/// [gachamonByKey] just returns null.
///
/// There is no hardcoded fallback. The game expects a valid `gachadex.json`
/// at the project root; if it's absent the game simply has zero entries
/// until the user provides one.
List<Gachamon> gachadex = <Gachamon>[];

/// Returns the base-form entry for [id]. Use [gachamonByKey] if you need a
/// specific alt form.
Gachamon? gachamonById(int id) {
  for (final p in gachadex) {
    if (p.id == id && p.form == null) return p;
  }
  // Fall back to any entry with matching id (handles legacy callers that
  // passed an id for a gachamon whose only JSON entry is an alt form).
  for (final p in gachadex) {
    if (p.id == id) return p;
  }
  return null;
}

/// Returns the gachadex entry matching [uniqueKey] (e.g. `"386"` or
/// `"386:Attack"`).
Gachamon? gachamonByKey(String uniqueKey) {
  final colon = uniqueKey.indexOf(':');
  final id = int.tryParse(colon < 0 ? uniqueKey : uniqueKey.substring(0, colon));
  if (id == null) return null;
  final form = colon < 0 ? null : uniqueKey.substring(colon + 1);
  for (final p in gachadex) {
    if (p.id == id && p.form == form) return p;
  }
  return null;
}
