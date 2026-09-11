import datetime as dt
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from hockey_app.data.pwhl_api import PWHLApi
from hockey_app.data.cache import DiskCache
from hockey_app.domain.seasons import games_per_team, season_metadata, season_rule
from hockey_app.domain.teams import pwhl_code, team_key, team_registry
from hockey_app.tools import export_web
from hockey_app.tools.validate_web import validate, validate_complete_nhl


class SecondPassTests(unittest.TestCase):
    @staticmethod
    def round_robin(teams, league, game_type=None):
        rows = []
        for left, home in enumerate(teams):
            for right in range(left + 1, len(teams)):
                game = {'id': len(rows) + 1, 'league': league, 'date': f'2028-01-{len(rows) + 1:02d}',
                        'homeTeam': {'abbrev': home}, 'awayTeam': {'abbrev': teams[right]}}
                if game_type is not None: game['gameType'] = game_type
                rows.append(game)
        return rows

    def test_montreal_alias_and_registry_logo(self):
        self.assertEqual(tuple(pwhl_code(v) for v in ('MON', 'MTL', 'Montréal Victoire', 'Montreal')), ('MTL',) * 4)
        docs = Path(__file__).parents[1] / 'docs'
        for team in team_registry('2026-2027'):
            if not team['provisionalBrand']:
                self.assertTrue((docs / team['logo']).exists(), team)
        team = next(t for t in team_registry('2026-2027') if t['league'] == 'PWHL' and t['code'] == 'MTL')
        self.assertEqual((team['providerCode'], team['assetCode']), ('MON', 'MON'))

    def test_league_qualified_detroit(self):
        registry = {(r['league'], r['code']): r for r in team_registry('2026-2027')}
        self.assertNotEqual(registry[team_key('NHL', 'DET')]['name'], registry[team_key('PWHL', 'DET')]['name'])

    def test_unknown_future_nhl_and_pwhl_derive_rules(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
            nhl = self.round_robin(['A', 'B', 'C', 'D'], 'NHL', 2)
            pwhl = self.round_robin(['W', 'X', 'Y', 'Z'], 'PWHL')
            self.assertIsNone(games_per_team('NHL', '2027-2028'))
            self.assertEqual(games_per_team('NHL', '2027-2028', schedule=nhl, complete=True), 3)
            self.assertEqual(games_per_team('PWHL', '2027-2028', schedule=pwhl, complete=True), 3)
            self.assertEqual(season_rule('NHL', '2027-2028')['team_count'], 4)
            self.assertEqual(season_rule('PWHL', '2027-2028')['total_games'], 6)
            self.assertFalse(season_rule('NHL', '2027-2028')['home_away_balanced'])

    def test_idless_repeat_matchups_survive(self):
        games = [{'league': 'PWHL', 'provider': 'PWHL', 'date': day, 'awayTeam': {'abbrev': 'MON'}, 'homeTeam': {'abbrev': 'TOR'}} for day in ('2027-01-01', '2027-01-08')]
        self.assertEqual(len(export_web._merge_game_rows(games)), 2)

    def test_unresolved_pwhl_bounds_do_not_borrow(self):
        api = PWHLApi.__new__(PWHLApi)
        rows = [{'id': '1', 'label': '2025-26', 'start': dt.date(2025, 11, 1), 'end': dt.date(2026, 5, 1)}]
        with patch.object(api, '_season_candidates', return_value=rows):
            self.assertEqual(api.get_season_boundaries(dt.date(2027, 1, 1), allow_network=False), (None, None))

    def test_pwhl_status_states_and_prior_release(self):
        status = export_web._pwhl_schedule_status
        self.assertEqual(status(has_games=False, diagnostics={'status': 'unpublished'}, rule=None), 'unpublished')
        self.assertEqual(status(has_games=False, diagnostics={'status': 'provider_error'}, rule=None), 'provider_error')
        self.assertEqual(status(has_games=False, diagnostics={'status': 'provider_error'}, rule={'schedule_complete': True}), 'stale')

    def test_pwhl_provider_failure_diagnostic_survives_client_restart(self):
        with tempfile.TemporaryDirectory() as tmp:
            api = PWHLApi(DiskCache(Path(tmp)))
            with patch.object(api, '_season_candidates', side_effect=OSError('offline')), self.assertRaises(OSError):
                api._pick_season_id(dt.date(2027, 1, 1), allow_network=True)
            restarted = PWHLApi(DiskCache(Path(tmp)))
            with patch.object(restarted, '_season_candidates', return_value=[]):
                self.assertIsNone(restarted._pick_season_id(dt.date(2027, 1, 1), allow_network=False))
            self.assertEqual(restarted.season_diagnostics['status'], 'provider_error')

    def test_preseason_is_not_migrated_as_regular_start(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
            Path(tmp, 'season_dates.csv').write_text('season,start_date,regular_season_start\n2027-2028,2027-09-20,2027-09-20\n')
            record = season_metadata()['2027-2028']
            self.assertEqual(record['preseason'], '2027-09-20')
            self.assertNotIn('regular', record)

    def test_javascript_syntax(self):
        node = shutil.which('node')
        if not node: self.skipTest('node unavailable')
        subprocess.run([node, '--check', str(Path(__file__).parents[1] / 'docs' / 'app.js')], check=True)

    def test_general_validator_accepts_known_2026_schedule(self):
        rows = json.loads((Path(__file__).parent / 'fixtures' / 'nhl_2026_2027.json').read_text())['games']
        regular = [game for game in rows if game['gameType'] == 2]
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
            games_per_team('NHL', '2026-2027', schedule=regular, complete=True)
            days = {}
            for game in regular:
                days.setdefault(game['date'], []).append({'id': game['id'], 'league': 'NHL', 'provider': 'NHL',
                    'gameType': 2, 'home': {'code': game['homeTeam']['abbrev']}, 'away': {'code': game['awayTeam']['abbrev']}})
            payload = {'metadata': {'season': '2026-2027', 'generatedAt': dt.datetime.now(dt.timezone.utc).isoformat()},
                       'seasonRules': {'NHL': season_rule('NHL', '2026-2027')}, 'desktop': {'scoreboard': {'days': days}}}
            summary = validate(payload)
            self.assertTrue(validate_complete_nhl(summary))
            self.assertEqual((summary['nhlRule']['team_count'], summary['nhlRule']['games_per_team'], summary['nhlRule']['total_games']), (32, 84, 1344))


if __name__ == '__main__': unittest.main()
