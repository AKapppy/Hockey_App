from __future__ import annotations

TEAM_NAMES: dict[str, str] = {
    "ANA": "Anaheim Ducks",
    "BOS": "Boston Bruins",
    "BUF": "Buffalo Sabres",
    "CAR": "Carolina Hurricanes",
    "CBJ": "Columbus Blue Jackets",
    "CGY": "Calgary Flames",
    "CHI": "Chicago Blackhawks",
    "COL": "Colorado Avalanche",
    "DAL": "Dallas Stars",
    "DET": "Detroit Red Wings",
    "EDM": "Edmonton Oilers",
    "FLA": "Florida Panthers",
    "LAK": "Los Angeles Kings",
    "MIN": "Minnesota Wild",
    "MTL": "Montréal Canadiens",
    "NJD": "New Jersey Devils",
    "NSH": "Nashville Predators",
    "NYI": "New York Islanders",
    "NYR": "New York Rangers",
    "OTT": "Ottawa Senators",
    "PHI": "Philadelphia Flyers",
    "PIT": "Pittsburgh Penguins",
    "SEA": "Seattle Kraken",
    "SJS": "San Jose Sharks",
    "STL": "St. Louis Blues",
    "TBL": "Tampa Bay Lightning",
    "TOR": "Toronto Maple Leafs",
    "UTA": "Utah Mammoth",
    "VAN": "Vancouver Canucks",
    "VGK": "Vegas Golden Knights",
    "WSH": "Washington Capitals",
    "WPG": "Winnipeg Jets",
}

TEAM_CODE_ALIASES: dict[str, str] = {
    "ARI": "UTA",
}


def canon_team_code(code: str) -> str:
    c = str(code).upper()
    return TEAM_CODE_ALIASES.get(c, c)


def canon_team_code_for_season(code: str, season: str) -> str:
    """Canonical display identity without rewriting historical Arizona."""
    c = str(code).upper().strip()
    return "ARI" if str(season).startswith("2023-") and c in {"ARI", "UTA"} else canon_team_code(c)


def nhl_team_names(season: str) -> dict[str, str]:
    names = dict(TEAM_NAMES)
    if str(season).startswith("2023-"):
        names.pop("UTA", None)
        names["ARI"] = "Arizona Coyotes"
    elif str(season).startswith("2024-"):
        names["UTA"] = "Utah Hockey Club"
    return names


def nhl_team_identity(season: str, code: str) -> dict[str, object]:
    canonical = canon_team_code_for_season(code, season)
    names = nhl_team_names(season)
    return {"providerId": 53 if canonical == "ARI" else NHL_PROVIDER_IDS.get(canonical),
            "displayCode": canonical, "displayName": names.get(canonical, canonical),
            "assetCode": canonical, "franchiseId": "ARI-UTA" if canonical in {"ARI", "UTA"} else canonical}


DIVS_MASTER: dict[str, list[str]] = {
    "Pacific": ["ANA", "CGY", "EDM", "LAK", "SEA", "SJS", "VAN", "VGK"],
    "Central": ["CHI", "COL", "DAL", "MIN", "NSH", "STL", "WPG", "UTA"],
    "Atlantic": ["BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR"],
    "Metro": ["CAR", "CBJ", "NJD", "NYI", "NYR", "PHI", "PIT", "WSH"],
}
WEST_DIVS = {"Pacific", "Central"}

TEAM_TO_DIV: dict[str, str] = {}
TEAM_TO_CONF: dict[str, str] = {}
for div, lst in DIVS_MASTER.items():
    for c in lst:
        TEAM_TO_DIV[c] = div
        TEAM_TO_CONF[c] = "West" if div in WEST_DIVS else "East"


def division_columns_for_codes(codes: set[str]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for div, lst in DIVS_MASTER.items():
        present = [c for c in lst if c in codes]
        present.sort(key=lambda c: (TEAM_NAMES.get(c, c), c))
        out[div] = present
    return out

PWHL_BASE_NAMES = {
    "BOS": "Boston Fleet", "MIN": "Minnesota Frost", "MTL": "Montréal Victoire",
    "NY": "New York Sirens", "OTT": "Ottawa Charge", "TOR": "Toronto Sceptres",
    "SEA": "Seattle Torrent", "VAN": "Vancouver Goldeneyes",
}
PWHL_EXPANSION_NAMES = {"DET": "PWHL Detroit", "HAM": "PWHL Hamilton", "LV": "PWHL Las Vegas", "SJ": "PWHL San Jose"}

def pwhl_team_names(season=None):
    from hockey_app.domain.seasons import resolve_season, normalize_season
    key = normalize_season(season) if season else resolve_season().season
    names = dict(PWHL_BASE_NAMES)
    if key and int(key[:4]) >= 2026:
        names.update(PWHL_EXPANSION_NAMES)
    if key and int(key[:4]) < 2025:
        names.pop("SEA", None)
        names.pop("VAN", None)
    return names

NHL_PROVIDER_IDS = {'ANA': 24, 'BOS': 6, 'BUF': 7, 'CAR': 12, 'CBJ': 29, 'CGY': 20, 'CHI': 16, 'COL': 21, 'DAL': 25, 'DET': 17, 'EDM': 22, 'FLA': 13, 'LAK': 26, 'MIN': 30, 'MTL': 8, 'NJD': 1, 'NSH': 18, 'NYI': 2, 'NYR': 3, 'OTT': 9, 'PHI': 4, 'PIT': 5, 'SEA': 55, 'SJS': 28, 'STL': 19, 'TBL': 14, 'TOR': 10, 'UTA': 68, 'VAN': 23, 'VGK': 54, 'WPG': 52, 'WSH': 15}

def team_registry(season):
    rows = []
    for league, names in (("NHL", nhl_team_names(season)), ("PWHL", pwhl_team_names(season))):
        for code, name in names.items():
            provisional = league == "PWHL" and code in PWHL_EXPANSION_NAMES
            asset_code = "MON" if league == "PWHL" and code == "MTL" else code
            provider_code = asset_code if league == "PWHL" else code
            rows.append({"league": league, "code": code, "name": name,
                         "aliases": [name.replace("Montréal", "Montreal"), *PWHL_PROVIDER_ALIASES.get(code, ())] if league == "PWHL" else [name.replace("Montréal", "Montreal")],
                         "providerId": (53 if code == "ARI" else NHL_PROVIDER_IDS.get(code)) if league == "NHL" else None,
                         "providerCode": provider_code if not provisional else None, "assetCode": asset_code if not provisional else None,
                         "activeSeason": season, "provisionalBrand": provisional,
                         "logo": None if provisional else f"assets/{league.lower()}_logos/{asset_code}.png"})
    return rows


PWHL_PROVIDER_ALIASES = {
    "BOS": ("Boston", "Fleet"), "MIN": ("Minnesota", "Frost"),
    "MTL": ("Montreal", "Montréal", "Victoire", "MON"),
    "NY": ("New York", "Sirens", "NYC"), "OTT": ("Ottawa", "Charge"),
    "TOR": ("Toronto", "Sceptres"), "SEA": ("Seattle", "Torrent"),
    "VAN": ("Vancouver", "Goldeneyes"), "DET": ("Detroit",),
    "HAM": ("Hamilton",), "LV": ("Las Vegas",), "SJ": ("San Jose",),
}


def pwhl_code(value):
    import re
    import unicodedata
    def folded(text):
        return unicodedata.normalize("NFKD", str(text)).encode("ascii", "ignore").decode().upper()
    text = folded(value)
    for code, aliases in PWHL_PROVIDER_ALIASES.items():
        if text == code or any(re.search(r"\b" + re.escape(folded(alias)) + r"\b", text) for alias in aliases):
            return code
    return "TBD"


def team_key(league, code):
    """Stable compound identity for maps containing more than one league."""
    league_u = str(league or "NHL").upper()
    canonical = pwhl_code(code) if league_u == "PWHL" else canon_team_code(code)
    return league_u, canonical
