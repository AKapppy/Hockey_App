"""Provider-aware schedule identities and authoritative snapshot reconciliation."""
import datetime as dt


def provider_for_game(game):
    league = str(game.get('league') or 'NHL').upper()
    return str(game.get('provider') or game.get('sourceProvider') or
               ('ESPN' if league.startswith('OLYMPIC') else league)).upper()


def game_identity(game):
    gid = str(game.get('id') or game.get('gameId') or '')
    league = str(game.get('league') or 'NHL').upper()
    if gid and gid != '0':
        return (league, provider_for_game(game), gid)
    away, home = _team(game, 'away'), _team(game, 'home')
    start = str(game.get('startTimeUTC') or game.get('startUtc') or game.get('startTime') or '').strip()
    day = str(game.get('date') or game.get('gameDate') or '').strip()[:10]
    if not day and start:
        day = start[:10]
    return (league, provider_for_game(game), 'fallback', away, home, day, start) if away and home and day else None


def _team(game, side):
    row = game.get(side + 'Team') or game.get(side) or {}
    code = str(row.get('abbrev') or row.get('code') or '').upper()
    return {'MON': 'MTL', 'NYC': 'NY'}.get(code, code)


def same_cross_provider_game(first, second):
    """Match only dated, timed games; a same-city guess is insufficient."""
    if provider_for_game(first) == provider_for_game(second):
        return game_identity(first) is not None and game_identity(first) == game_identity(second)
    for field in ('league', 'olympicsDivision'):
        if str(first.get(field) or '').upper() != str(second.get(field) or '').upper():
            return False
    if any(not _team(first, side) or _team(first, side) != _team(second, side) for side in ('away', 'home')):
        return False
    try:
        times = [dt.datetime.fromisoformat(str(g.get('startTimeUTC') or g.get('startUtc')).replace('Z', '+00:00')) for g in (first, second)]
        return times[0].date() == times[1].date() and abs((times[0] - times[1]).total_seconds()) <= 1800
    except (ValueError, TypeError):
        return False


def reconcile_snapshot(existing, incoming, *, provider, complete=False):
    """Complete means the caller verified the whole provider scope, not an error/empty response."""
    by_id = {game_identity(g): g for g in incoming if game_identity(g)}
    result = []
    for game in existing:
        if game_identity(game) in by_id:
            continue
        if complete and provider_for_game(game) == provider.upper():
            continue
        result.append(game)
    return result + list(by_id.values()) + [g for g in incoming if not game_identity(g)]
