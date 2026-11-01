"""Independently recompute all 15 answers from the untouched 18-column CSV.

Run Run-MDXQueries.ps1 first, then this script. Requires pandas.
Compares member sets and raw numeric values, not formatted/rounded strings.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import pandas as pd

parser = argparse.ArgumentParser()
parser.add_argument('--csv', type=Path, default=Path(__file__).resolve().parents[2] / 'flight_cleaned_50k.csv')
parser.add_argument('--results', type=Path, default=Path(__file__).resolve().parents[1] / 'results')
args = parser.parse_args()
d = pd.read_csv(args.csv, dtype=str, keep_default_na=False)
for col in ['cancelled', 'dep_delay', 'arr_delay', 'distance', 'crs_dep_time', 'carrier_delay', 'weather_delay', 'nas_delay', 'late_aircraft_delay']:
    d[col] = pd.to_numeric(d[col].replace('', float('nan')), errors='raise')
d['date'] = pd.to_datetime(d.fl_date, errors='raise')
d = d[d.date.dt.year.eq(2024)].copy()
d['carrier'] = d.op_unique_carrier
d['airport'] = d.origin
reference_path = Path(__file__).resolve().parents[1] / 'reference' / 'airport_states.csv'
reference = pd.read_csv(reference_path, dtype=str, keep_default_na=False).set_index('AIRPORT_CODE')
d['state'] = d.origin.map(reference.STATE_CODE)
assert d.state.notna().all(), 'A source airport has no verified state mapping.'
d['month'] = d.date.dt.strftime('%m/%Y')
d['quarter'] = 'Q' + d.date.dt.quarter.astype(str) + '/' + d.date.dt.year.astype(str)
d['route'] = d.origin + ' - ' + d.dest
hour = (d.crs_dep_time // 100) % 24
d['band'] = 'Tối'
d.loc[hour.between(6, 11), 'band'] = 'Sáng'
d.loc[hour.between(12, 13), 'band'] = 'Trưa'
d.loc[hour.between(14, 17), 'band'] = 'Chiều'
operated = d.cancelled.eq(0)
d['operated'] = operated.astype(int)
d['arr_obs'] = (operated & d.arr_delay.notna()).astype(int)
d['dep_obs'] = (operated & d.dep_delay.notna()).astype(int)
d['late15'] = (operated & d.dep_delay.ge(15)).astype(int)
d['dep_late'] = d.dep_delay.clip(lower=0).where(operated, 0).fillna(0)
d['arr_value'] = d.arr_delay.where(operated)

def aggregate(keys, frame=d):
    g = frame.groupby(keys, observed=True, sort=True, dropna=False)
    out = g.agg(**{
        'Total Flights': ('fl_date', 'size'), 'Operated Flights': ('operated', 'sum'),
        'Cancelled Flights': ('cancelled', 'sum'), 'Departure Delay Minutes': ('dep_late', 'sum'),
        'Average Arrival Delay': ('arr_value', 'mean'), 'Arrival Observations': ('arr_obs', 'sum'),
        'Departure Observations': ('dep_obs', 'sum'), 'Delayed Departures': ('late15', 'sum'),
        'Weather Delay Minutes': ('weather_delay', 'sum'), 'Carrier Delay Minutes': ('carrier_delay', 'sum'),
        'NAS Delay Minutes': ('nas_delay', 'sum'), 'Late Aircraft Delay Minutes': ('late_aircraft_delay', 'sum'),
        'Route Distance Miles': ('distance', 'mean'),
    })
    out['Cancellation Rate'] = out['Cancelled Flights'] / out['Total Flights']
    out['Departure Delay Rate'] = out['Delayed Departures'] / out['Departure Observations'].replace(0, float('nan'))
    return out

def top(frame, score, n, ascending=False):
    return frame.sort_index().sort_values(score, ascending=ascending, kind='stable').head(n)

carriers = aggregate(['carrier'])
airports = aggregate(['airport'])
routes = aggregate(['route'])
answers = {}
answers[1] = carriers.loc[['AA']]
answers[2] = pd.concat([aggregate(['quarter']), aggregate(['month'])])
answers[3] = top(airports, 'Operated Flights', 5)
answers[4] = carriers[carriers['Cancelled Flights'].ge(100)]
answers[5] = top(aggregate(['carrier'], d[d.date.dt.quarter.eq(2)]), 'Departure Delay Minutes', 3)
answers[6] = carriers
answers[7] = aggregate(['state', 'month'], d[~d.state.isin(['CA', 'TX'])])
answers[8] = routes[routes['Route Distance Miles'].between(1000, 2000) & routes['Total Flights'].ge(50)]
answers[9] = pd.concat([top(carriers, 'Total Flights', 1), top(carriers, 'Total Flights', 1, True)]).drop_duplicates()
answers[10] = airports[airports['Operated Flights'].gt(200) & airports['Average Arrival Delay'].gt(15)]
summer = aggregate(['state', 'airport'], d[d.date.dt.month.isin([6, 7, 8])])
answers[11] = summer.sort_index().sort_values('Operated Flights', ascending=False, kind='stable').groupby(level=0, sort=False).head(3)
answers[12] = carriers[carriers.index.to_series().ne('WN') & carriers['Total Flights'].ge(300)]
december = aggregate(['route'], d[d.date.dt.month.eq(12)])
answers[13] = top(december[december['Route Distance Miles'].ge(1500)], 'Late Aircraft Delay Minutes', 5)
eligible = aggregate(['airport'], d[~d.state.isin(['AK', 'HI'])])
answers[14] = pd.concat([top(eligible, 'Carrier Delay Minutes', 3), top(eligible, 'NAS Delay Minutes', 3)])
answers[14] = answers[14][~answers[14].index.duplicated()]
bands = aggregate(['band', 'carrier'])
bands = bands[bands['Operated Flights'].ge(100) & bands['Departure Observations'].gt(0)]
answers[15] = bands.sort_index().sort_values('Departure Delay Rate', ascending=False, kind='stable').groupby(level=0, sort=False).head(2)

manifest = json.loads((Path(__file__).resolve().parents[1] / 'queries' / 'manifest.json').read_text(encoding='utf-8'))
checks = []
for entry in manifest:
    number = entry['number']
    actual = json.loads((args.results / (Path(entry['file']).stem + '.json')).read_text(encoding='utf-8-sig'))
    actual_map = {tuple(m['caption'] for m in row['members']): row['values'] for row in actual['rows']}
    expected_map = {(key if isinstance(key, tuple) else (key,)): row for key, row in answers[number].iterrows()}
    if actual_map.keys() != expected_map.keys():
        missing = expected_map.keys() - actual_map.keys()
        extra = actual_map.keys() - expected_map.keys()
        raise AssertionError(f'Query {number}: different result members; missing={list(missing)[:8]}, extra={list(extra)[:8]}')
    for key, values in actual_map.items():
        for measure, value in values.items():
            expected = expected_map[key][measure]
            if pd.isna(expected):
                assert value is None, (number, key, measure, value, expected)
            elif value is None or not math.isclose(float(value), float(expected), rel_tol=1e-10, abs_tol=1e-8):
                raise AssertionError((number, key, measure, value, expected))
    sort_measures = {3: 'Operated Flights', 4: 'Cancelled Flights', 5: 'Departure Delay Minutes',
                     6: 'Cancellation Rate', 8: 'Total Flights', 10: 'Average Arrival Delay',
                     12: 'Weather Delay Minutes', 13: 'Late Aircraft Delay Minutes'}
    if number in sort_measures:
        scores = [row['values'][sort_measures[number]] for row in actual['rows']]
        assert all(a >= b for a,b in zip(scores,scores[1:])), f'Query {number}: incorrect descending order'
    checks.append({'query': number, 'rows': len(actual_map), 'result': 'PASS'})
    print(f'Query {number}: PASS ({len(actual_map)} rows; every returned measure matches the CSV)')
report = {
    'source_sha256': hashlib.sha256(args.csv.read_bytes()).hexdigest(),
    'source_rows_2024': len(d), 'delay_threshold_minutes': 15,
    'comparison': 'Independent pandas aggregation of the original 18 CSV columns versus actual SSAS MDX results',
    'checks': checks, 'passed': True,
}
(args.results / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
