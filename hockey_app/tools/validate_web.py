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
    summary = {'season': meta['season'], 'generatedAt': meta['generatedAt'],
               'games': dict(counts), 'nhlGameTypes': dict(phases),
               'nhlHomeCounts': dict(home_counts), 'nhlAwayCounts': dict(away_counts), 'dateRange': [min(days), max(days)] if days else [],
               'MoneyPuck': meta.get('predictions', {'status': 'unknown'}),
               'PWHL': meta.get('pwhlSchedule', 'unknown'),
               'pwhlSeason': meta.get('pwhlSeason'),
               'warnings': [] if days else ['No cached schedule available']}
    return summary


def main():
    summary = validate(json.loads(Path(sys.argv[1]).read_text()))
    if "--require-nhl" in sys.argv and not summary["games"].get("NHL"):
        raise ValueError("Refusing to deploy an export without any NHL schedule data")
    if "--require-complete-nhl" in sys.argv:
        from hockey_app.domain.seasons import games_per_team
        length = games_per_team('NHL', summary['season'])
        if length is None:
            raise ValueError('Cannot validate unpublished NHL season rules')
        for key in ('nhlHomeCounts', 'nhlAwayCounts'):
            counts = summary[key]
            if len(counts) != 32 or set(counts.values()) != {length // 2}:
                raise ValueError('Official NHL regular-season schedule is incomplete or unbalanced')
    text = json.dumps(summary, indent=2, ensure_ascii=False)
    print(text)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write('```json\n' + text + '\n```\n')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
