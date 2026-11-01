from pathlib import Path
import json
import pandas as pd

import argparse
parser=argparse.ArgumentParser()
parser.add_argument('--raw',type=Path,required=True)
parser.add_argument('--csv',type=Path,default=Path(__file__).resolve().parents[2]/'flight_cleaned_50k.csv')
args=parser.parse_args()
project=Path(__file__).resolve().parents[1]
raw=args.raw
sample=pd.read_csv(args.csv,usecols=['origin','dest','origin_city_name','dest_city_name'],dtype=str,keep_default_na=False)
airports=set(sample.origin)|set(sample.dest)
states={a:set() for a in airports}
rows=0
for chunk in pd.read_csv(raw,usecols=['origin','origin_state_nm','dest','dest_state_nm'],dtype=str,keep_default_na=False,chunksize=300000):
 rows+=len(chunk)
 for airport_col,state_col in [('origin','origin_state_nm'),('dest','dest_state_nm')]:
  pairs=chunk.loc[chunk[airport_col].isin(airports),[airport_col,state_col]].drop_duplicates()
  for code,name in pairs.itertuples(index=False,name=None):states[code].add(name)
bad={a:sorted(v) for a,v in states.items() if len(v)!=1 or '' in v}
if bad:raise RuntimeError(bad)
# Official USPS abbreviations for states/possessions; TT is the BTS source code.
codes=dict(line.split('|') for line in '''Alabama|AL
Alaska|AK
Arizona|AZ
Arkansas|AR
California|CA
Colorado|CO
Connecticut|CT
Delaware|DE
District of Columbia|DC
Florida|FL
Georgia|GA
Hawaii|HI
Idaho|ID
Illinois|IL
Indiana|IN
Iowa|IA
Kansas|KS
Kentucky|KY
Louisiana|LA
Maine|ME
Maryland|MD
Massachusetts|MA
Michigan|MI
Minnesota|MN
Mississippi|MS
Missouri|MO
Montana|MT
Nebraska|NE
Nevada|NV
New Hampshire|NH
New Jersey|NJ
New Mexico|NM
New York|NY
North Carolina|NC
North Dakota|ND
Ohio|OH
Oklahoma|OK
Oregon|OR
Pennsylvania|PA
Puerto Rico|PR
Rhode Island|RI
South Carolina|SC
South Dakota|SD
Tennessee|TN
Texas|TX
Utah|UT
Vermont|VT
Virginia|VA
Washington|WA
West Virginia|WV
Wisconsin|WI
Wyoming|WY
U.S. Virgin Islands|VI
U.S. Pacific Trust Territories and Possessions|TT'''.splitlines())
names=sorted({next(iter(v)) for v in states.values()})
print('Observed state/territory names:',names,flush=True)
unknown=set(names)-codes.keys()
if unknown:raise RuntimeError('Unmapped state names: '+str(unknown))
reference=pd.DataFrame([{'AIRPORT_CODE':a,'STATE_CODE':codes[next(iter(states[a]))],'STATE_NAME':next(iter(states[a]))} for a in sorted(airports)])
out=project/'reference';out.mkdir(exist_ok=True)
reference.to_csv(out/'airport_states.csv',index=False,encoding='utf-8')
values=',\n'.join("(N'%s',N'%s',N'%s')"%(r.AIRPORT_CODE,r.STATE_CODE,r.STATE_NAME.replace("'","''")) for r in reference.itertuples())
query='''-- Airport states extracted from the original dataset, not market-city suffixes.
SELECT a.AIRPORT_ID, a.AIRPORT_CODE, a.CITY_NAME,
       CONVERT(nvarchar(2), s.STATE_CODE) AS STATE_CODE,
       CONVERT(nvarchar(100), s.STATE_NAME) AS STATE_NAME,
       CONVERT(nvarchar(100), RTRIM(LEFT(a.CITY_NAME, LEN(RTRIM(a.CITY_NAME)) - 4))) AS CITY_LABEL
FROM dbo.DIM_AIRPORT a
JOIN (VALUES
'''+values+'''
) s(AIRPORT_CODE, STATE_CODE, STATE_NAME) ON a.AIRPORT_CODE=s.AIRPORT_CODE
'''
(project/'model'/'DimAirport.sql').write_text(query,encoding='utf-8')
metadata={'source_file':raw.name,'source_bytes':raw.stat().st_size,'source_rows_scanned':rows,'columns_used':['origin','origin_state_nm','dest','dest_state_nm'],'airports':len(reference),'state_names':names,'notes':'No flight rows or dates generated. State names are read from the original CSV. Full original CSV is not published.'}
(out/'provenance.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
print('Extracted',len(reference),'airport states from',rows,'real flight rows. DCA/IAD:',reference[reference.AIRPORT_CODE.isin(['DCA','IAD'])].to_dict('records'))
