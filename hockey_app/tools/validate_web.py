"""Validate a Pages artifact and emit a concise provider summary."""
import collections
import datetime as dt
import json
import os
import sys
from pathlib import Path


def validate(payload):
    meta = payload['metadata']
    dt.datetime.fromisoformat(meta['generatedAt'])
    days = payload.get('desktop', {}).get('scoreboard', {}).get('days', {})
    counts = collections.Counter()
    phases = collections.Counter()
    home_counts = collections.Counter()
    away_counts = collections.Counter()
    seen = set()
    regular_ids = set()
    for day, games in days.items():
        dt.date.fromisoformat(day)
        for game in games:
            key = (game.get('league'), game.get('provider'), game.get('id'))
            if game.get('id') and key in seen:
                raise ValueError(f'Duplicate exported game: {key}')
            seen.add(key)
            league = game.get('league', 'NHL')
            counts[league] += 1
            if league == 'NHL':
                from hockey_app.domain.seasons import nhl_game_type
                kind = nhl_game_type(game)
                phases[str(kind)] += 1
                if kind == 2:
                    home = (game.get('home') or {}).get('code')
                    away = (game.get('away') or {}).get('code')
                    if not home or not away or home == away:
                        raise ValueError('Invalid official game opponents')
                    home_counts[home] += 1
                    away_counts[away] += 1
                    if game.get('id'):
                        if str(game['id']) in regular_ids:
                            raise ValueError(f'Duplicate official NHL game ID: {game["id"]}')
                        regular_ids.add(str(game['id']))
    raw_rule = (payload.get('seasonRules') or {}).get('NHL')
    rule = raw_rule if isinstance(raw_rule, dict) else ({'games_per_team': raw_rule} if raw_rule else None)
    summary = {'season': meta['season'], 'generatedAt': meta['generatedAt'],
               'games': dict(counts), 'nhlGameTypes': dict(phases),
               'nhlHomeCounts': dict(home_counts), 'nhlAwayCounts': dict(away_counts), 'dateRange': [min(days), max(days)] if days else [],
               'MoneyPuck': meta.get('predictions', {'status': 'unknown'}),
               'PWHL': meta.get('pwhlSchedule', 'unknown'),
               'pwhlSeason': meta.get('pwhlSeason'),
               'nhlRule': rule,
               'warnings': [] if days else ['No cached schedule available']}
    return summary


def validate_complete_nhl(summary):
    rule = summary.get('nhlRule') or {}
    length = rule.get('games_per_team')
    teams = set(rule.get('teams') or [])
    if length is None or not rule.get('schedule_complete'):
        raise ValueError('Cannot validate unpublished NHL season rules')
    totals = collections.Counter(summary['nhlHomeCounts'])
    totals.update(summary['nhlAwayCounts'])
    if teams and set(totals) != teams:
        raise ValueError('Official NHL active team set does not match season metadata')
    if not totals or set(totals.values()) != {length}:
        raise ValueError('Official NHL regular-season totals are incomplete')
    if rule.get('total_games') != sum(totals.values()) // 2:
        raise ValueError('Official NHL league game total does not match season metadata')
    for field, summary_key in (('home_games', 'nhlHomeCounts'), ('away_games', 'nhlAwayCounts')):
        expected = rule.get(field)
        if expected and expected != summary[summary_key]:
            raise ValueError(f'Official NHL {field} distribution does not match season metadata')
    return True


def main():
    summary = validate(json.loads(Path(sys.argv[1]).read_text()))
    if "--require-nhl" in sys.argv and not summary["games"].get("NHL"):
        raise ValueError("Refusing to deploy an export without any NHL schedule data")
    if "--require-complete-nhl" in sys.argv:
        validate_complete_nhl(summary)
    text = json.dumps(summary, indent=2, ensure_ascii=False)
    print(text)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write('```json\n' + text + '\n```\n')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
