"""Offline rollover and schedule regressions. Synthetic schedules are not sports data."""
import datetime as dt
import os
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from unittest.mock import patch

from hockey_app.domain.seasons import games_per_team, nhl_game_type, resolve_season
from hockey_app.domain.teams import TEAM_NAMES, pwhl_team_names, team_registry
from hockey_app.data.pwhl_api import PWHLApi
from hockey_app.data.xml_cache import read_games_day_xml, read_games_populated_bounds, write_games_day_xml
from hockey_app.services.simulations import compile_probability_tables
from hockey_app.tools import export_web as exporter


class SeasonReliabilityTests(unittest.TestCase):
    def test_rollover(self):
        for day, phase in ((8, 'upcoming'), (19, 'preseason'), (29, 'regular'), (30, 'regular')):
            result = resolve_season(dt.date(2026, 9, day), use_env=False)
            self.assertEqual((result.season, result.phase), ('2026-2027', phase))

    def test_override(self):
        with patch.dict(os.environ, {'HOCKEY_SEASON': '2025-26'}):
            self.assertEqual(resolve_season(dt.date(2026, 9, 30)).season, '2025-2026')

    def test_lengths(self):
        for league, season, count in [('NHL', '2025-26', 82), ('NHL', '2026-27', 84), ('PWHL', '2025-26', 30), ('PWHL', '2026-27', None)]:
            self.assertEqual(games_per_team(league, season), count)

    def test_complete_synthetic_nhl_schedule(self):
        teams = list(TEAM_NAMES)
        games = []
        for round_no in range(42):
            for index, team in enumerate(teams):
                games.append({'id': len(games) + 1, 'gameType': 2, 'homeTeam': {'abbrev': team}, 'awayTeam': {'abbrev': teams[(index + 1 + round_no % 31) % 32]}})
        self.assertEqual(len(games), 1344)
        self.assertEqual(set(Counter(g['homeTeam']['abbrev'] for g in games).values()), {42})
        self.assertEqual(set(Counter(g['awayTeam']['abbrev'] for g in games).values()), {42})
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
            self.assertEqual(games_per_team('NHL', '2026-27', schedule=games, complete=True), 84)

    def test_official_nhl_fixture(self):
        import json
        rows = json.loads(Path(__file__).with_name('fixtures').joinpath('nhl_2026_2027.json').read_text())['games']
        regular = [g for g in rows if g['gameType'] == 2]
        self.assertEqual(len(regular), 1344)
        self.assertEqual(sum(g['gameType'] == 1 for g in rows), 65)
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
            self.assertEqual(games_per_team('NHL', '2026-27', schedule=regular, complete=True), 84)
        for side in ('homeTeam', 'awayTeam'):
            self.assertEqual(set(Counter(g[side]['abbrev'] for g in regular).values()), {42})
        self.assertEqual({(g['awayTeam']['abbrev'], g['homeTeam']['abbrev']) for g in regular if g['date'] == '2026-09-29'}, {('FLA', 'CAR'), ('MTL', 'TOR'), ('NYR', 'BOS'), ('VAN', 'EDM'), ('CHI', 'VGK')})
        self.assertTrue({('PIT', 'PHI'), ('LAK', 'COL')} <= {(g['awayTeam']['abbrev'], g['homeTeam']['abbrev']) for g in regular if g['date'] == '2026-09-30'})

    def test_future_preseason_bucket_is_not_published_regular_schedule(self):
        api = PWHLApi(None)
        self.assertIsNone(api._select_season([{'id': '10', 'label': '2026-27 Pre-Season', 'start': dt.date(2026, 10, 1), 'end': dt.date(2026, 11, 30)}], dt.date(2026, 9, 8)))

    def test_game_types_and_precedence(self):
        for year in (2025, 2026):
            for kind in (1, 2, 3):
                self.assertEqual(nhl_game_type({'id': int(f'{year}0{kind}0001')}), kind)
                self.assertEqual(nhl_game_type({'id': int(f'{year}0{kind}0001'), 'gameType': 2}), 2)

    def test_pwhl_registry(self):
        names = pwhl_team_names('2025-26')
        self.assertEqual(len(names), 8)
        self.assertEqual(names['SEA'], 'Seattle Torrent')
        self.assertEqual(names['VAN'], 'Vancouver Goldeneyes')
        self.assertEqual(len(pwhl_team_names('2026-27')), 12)
        expansion = [t for t in team_registry('2026-27') if t['provisionalBrand']]
        self.assertEqual(len(expansion), 4)
        self.assertTrue(all(t['logo'] is None and t['name'].startswith('PWHL ') for t in expansion))

    def test_unpublished_pwhl_never_selects_previous(self):
        api = PWHLApi(None)
        rows = [{'id': '99', 'label': '2025-2026', 'start': dt.date(2025, 11, 21), 'end': dt.date(2026, 4, 25)}]
        self.assertIsNone(api._select_season(rows, dt.date(2026, 9, 8)))
        self.assertEqual(api._select_season(rows, dt.date(2026, 1, 1))['id'], '99')

    def test_reschedules_move_across_days(self):
        for old, new, league, away, home in [('2026-01-07', '2026-01-09', 'PWHL', 'VAN', 'OTT'), ('2026-04-02', '2026-04-01', 'PWHL', 'TOR', 'OTT'), ('2026-02-05', '2026-02-12', 'Olympics', 'FIN', 'CAN')]:
            with self.subTest(away=away), tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
                game = {'id': 1, 'league': league, 'provider': 'official', 'awayTeam': {'abbrev': away}, 'homeTeam': {'abbrev': home}}
                write_games_day_xml(season='2025-2026', day=dt.date.fromisoformat(old), games=[game])
                write_games_day_xml(season='2025-2026', day=dt.date.fromisoformat(new), games=[game, game])
                self.assertEqual(read_games_day_xml(season='2025-2026', day=dt.date.fromisoformat(old)), [])
                self.assertEqual(len(read_games_day_xml(season='2025-2026', day=dt.date.fromisoformat(new))), 1)

    def test_prediction_no_backward_fill(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, 'simulations_2026_09_05.csv').write_text('scenerio,teamCode,madePlayoffs\nALL,BOS,0.5\n')
            table = compile_probability_tables(Path(tmp), dt.date(2026, 9, 1), dt.date(2026, 9, 6), metrics={'p': 'madePlayoffs'}, canon_team_code=str)['p']
            self.assertTrue(table.loc['BOS'].iloc[:4].isna().all())
            self.assertEqual(table.loc['BOS'].iloc[4:].tolist(), [0.5, 0.5])

    def test_export_without_moneypuck_and_provider_failure(self):
        for refresh in (False, True):
            with self.subTest(refresh=refresh), tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}), patch.object(exporter, '_export_desktop_data', return_value={'scoreboard': {'days': {}}}), patch.object(exporter, '_copy_logo_assets'), patch.object(exporter, '_refresh_desktop_xml_data'), patch.object(exporter, 'download_missing_simulations', side_effect=OSError('provider down')):
                result = exporter.export_web(out_dir=Path(tmp) / 'web', season='2026-2027', start=dt.date(2026, 9, 8), end=dt.date(2026, 9, 8), refresh=refresh)
                import json
                payload = json.loads(result.with_suffix('.json').read_text())
                self.assertEqual(payload['metadata']['predictions']['status'], 'unavailable')
                self.assertIn('scoreboard', payload['desktop'])

    def test_export_archives_available_seasons(self):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            historical = {
                'metadata': {'season': '2025-2026', 'generatedAt': '2026-05-01T00:00:00+00:00'},
                'tables': {},
                'desktop': {'scoreboard': {'days': {}}},
            }
            (out / 'data.json').write_text(json.dumps(historical), encoding='utf-8')
            with patch.dict(os.environ, {'HOCKEY_CACHE_DIR': str(out / 'cache')}), \
                 patch.object(exporter, '_export_desktop_data', return_value={'scoreboard': {'days': {}}}), \
                 patch.object(exporter, '_copy_logo_assets'):
                exporter.export_web(
                    out_dir=out,
                    season='2026-2027',
                    start=dt.date(2026, 9, 19),
                    end=dt.date(2026, 9, 20),
                    refresh=False,
                )
            index = json.loads((out / 'season-index.json').read_text())
            current = json.loads((out / 'seasons/2026-2027/data.json').read_text())
            previous = json.loads((out / 'seasons/2025-2026/data.json').read_text())
            self.assertEqual(index['seasons'], ['2026-2027', '2025-2026'])
            self.assertEqual(current['metadata']['availableSeasons'], index['seasons'])
            self.assertEqual(previous['metadata']['availableSeasons'], index['seasons'])

    def test_scoreboard_export_uses_full_cached_schedule_range(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
            first = dt.date(2026, 9, 19)
            playoff = dt.date(2027, 4, 20)
            write_games_day_xml(season='2026-2027', day=first, games=[{'id': 1, 'league': 'NHL'}])
            write_games_day_xml(season='2026-2027', day=playoff, games=[{'id': 2, 'league': 'NHL'}])
            payload = exporter.build_payload(
                season='2026-2027',
                start=first,
                end=dt.date(2026, 9, 20),
                simulations_dir=Path(tmp) / 'simulations',
            )
            days = payload['desktop']['scoreboard']['days']
            self.assertEqual((min(days), max(days)), (str(first), str(playoff)))

    def test_primary_provider_wins(self):
        official = {'id': 1, 'league': 'PWHL', 'statusText': 'new', 'awayTeam': {'abbrev': 'VAN', 'score': 0}}
        stale = {'id': 1, 'league': 'PWHL', 'statusText': 'old', 'awayTeam': {'abbrev': 'VAN', 'score': 9}}
        self.assertEqual(exporter._merge_game_rows([official], [stale])[0], official)


class ProviderFixtureTests(unittest.TestCase):
    def fixture(self, name):
        import json
        return json.loads(Path(__file__).with_name('fixtures').joinpath(name).read_text())['games']

    def test_official_pwhl_schedule(self):
        rows = self.fixture('pwhl_2025_2026.json')
        self.assertEqual(len(rows), 120)
        self.assertEqual(len({g['id'] for g in rows}), 120)
        counts = Counter(g[side]['abbrev'] for g in rows for side in ('homeTeam', 'awayTeam'))
        self.assertEqual(len(counts), 8)
        self.assertEqual(set(counts.values()), {30})
        self.assertEqual((min(g['date'] for g in rows), max(g['date'] for g in rows)), ('2025-11-21', '2026-04-25'))
        for gid, date in ((249, '2026-01-09'), (306, '2026-04-01')):
            self.assertEqual([g['date'] for g in rows if g['id'] == gid], [date])

    def test_olympic_schedule_counts_and_correction(self):
        rows = self.fixture('olympics_2026.json')
        self.assertEqual(len(rows), 58)
        self.assertEqual(len({g['id'] for g in rows}), 58)
        self.assertEqual(Counter(g['division'] for g in rows), {'Men': 30, 'Women': 28})
        for division, start, end in [('Men', '2026-02-11', '2026-02-22'), ('Women', '2026-02-05', '2026-02-19')]:
            dates = [g['date'] for g in rows if g['division'] == division]
            self.assertEqual((min(dates), max(dates)), (start, end))
        self.assertEqual([g['date'] for g in rows if g['id'] == 401845610], ['2026-02-12'])

    def test_snapshot_replaces_changes_and_removes_cancelled_game(self):
        from hockey_app.domain.schedules import reconcile_snapshot
        old = [{'id': 1, 'league': 'NHL', 'date': '2026-09-29', 'venue': 'old'}, {'id': 2, 'league': 'NHL'}, {'id': 1, 'league': 'PWHL'}]
        updated = [{'id': 1, 'league': 'NHL', 'date': '2026-09-30', 'venue': 'new'}]
        self.assertEqual(reconcile_snapshot(old, updated, provider='NHL', complete=True), [old[2], updated[0]])
        self.assertEqual(reconcile_snapshot(old, [], provider='NHL'), old)

    def test_cross_provider_match_requires_time_and_teams(self):
        from hockey_app.domain.schedules import same_cross_provider_game
        first = {'id': 1, 'league': 'PWHL', 'provider': 'PWHL', 'startTimeUTC': '2026-01-09T19:00:00Z', 'awayTeam': {'abbrev': 'VAN'}, 'homeTeam': {'abbrev': 'OTT'}}
        second = {**first, 'id': 999, 'provider': 'ESPN', 'startTimeUTC': '2026-01-09T19:10:00Z'}
        self.assertTrue(same_cross_provider_game(first, second))
        self.assertFalse(same_cross_provider_game(first, {**second, 'startTimeUTC': '2026-01-10T19:00:00Z'}))
        self.assertFalse(same_cross_provider_game(first, {**second, 'awayTeam': {'abbrev': 'TOR'}}))

    def test_empty_nhl_day_is_not_pinned(self):
        from hockey_app.data.nhl_api import NHLApi
        api = NHLApi.__new__(NHLApi)
        self.assertFalse(api._day_is_final({'games': []}))
        self.assertFalse(api._day_is_final({}))
        self.assertTrue(api._day_is_final({'games': [{'gameState': 'FINAL'}]}))

    def test_xml_preserves_provider_namespace(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
            games = [{'id': 1, 'league': 'PWHL', 'provider': provider} for provider in ('PWHL', 'ESPN')]
            day = dt.date(2026, 1, 9)
            write_games_day_xml(season='2025-2026', day=day, games=games)
            rows = read_games_day_xml(season='2025-2026', day=day)
            self.assertEqual(len(rows), 2)
            self.assertEqual({g['provider'] for g in rows}, {'PWHL', 'ESPN'})

    def test_postseason_remains_active_before_summer(self):
        selection = resolve_season(dt.date(2026, 5, 15), use_env=False)
        self.assertEqual((selection.season, selection.phase), ('2025-2026', 'postseason'))

    def test_provider_metadata_overrides_bundled_dates(self):
        metadata = {'2026-2027': {'preseason': '2026-09-17', 'regular': '2026-09-25', 'regular_end': '2027-04-10'}}
        selection = resolve_season(dt.date(2026, 9, 26), metadata=metadata, use_env=False)
        self.assertEqual((selection.phase, selection.source), ('regular', 'metadata'))

    def test_cached_empty_day_distinct_from_missing_and_venue_survives(self):
        from hockey_app.data.xml_cache import read_games_cache_manifest
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
            day = dt.date(2026, 1, 9)
            write_games_day_xml(season='2025-2026', day=day, games=[])
            self.assertEqual(read_games_cache_manifest(season='2025-2026')['days'], [str(day)])
            game = {'id': 1, 'league': 'NHL', 'venue': {'default': 'Updated venue'}}
            write_games_day_xml(season='2025-2026', day=day, games=[game])
            self.assertEqual(read_games_day_xml(season='2025-2026', day=day)[0]['venue'], game['venue'])

    def test_scoreboard_bounds_use_first_and_last_populated_nhl_days(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HOCKEY_CACHE_DIR': tmp}):
            season = '2026-2027'
            write_games_day_xml(season=season, day=dt.date(2023, 11, 1), games=[{'id': 99, 'league': 'NHL'}])
            write_games_day_xml(season=season, day=dt.date(2026, 9, 18), games=[])
            write_games_day_xml(season=season, day=dt.date(2026, 9, 19), games=[{'id': 1, 'league': 'NHL'}])
            write_games_day_xml(season=season, day=dt.date(2027, 4, 10), games=[{'id': 2, 'league': 'NHL'}])
            write_games_day_xml(season=season, day=dt.date(2027, 4, 11), games=[])
            self.assertEqual(
                read_games_populated_bounds(season=season),
                (dt.date(2026, 9, 19), dt.date(2027, 4, 10)),
            )

    def test_desktop_window_imports_registry_before_using_it(self):
        import hockey_app.ui.app_window as window
        self.assertTrue(window.PWHL_TEAM_ORDER)

    def test_desktop_merge_respects_provider_namespaces(self):
        from hockey_app.ui.tabs.games import _dedupe_games, _merge_games_by_id
        official = {'id': 1, 'league': 'PWHL', 'provider': 'PWHL'}
        supplement = {'id': 1, 'league': 'PWHL', 'provider': 'ESPN', 'statusText': 'different game'}
        self.assertEqual(len(_dedupe_games([official, supplement])), 2)
        self.assertEqual(_merge_games_by_id([official], [supplement]), [official])
