SELECT CARRIER_ID, CARRIER_CODE,
       CONVERT(nvarchar(100), CASE CARRIER_CODE
          WHEN '9E' THEN 'Endeavor Air' WHEN 'AA' THEN 'American Airlines'
          WHEN 'AS' THEN 'Alaska Airlines' WHEN 'B6' THEN 'JetBlue Airways'
          WHEN 'DL' THEN 'Delta Air Lines' WHEN 'F9' THEN 'Frontier Airlines'
          WHEN 'G4' THEN 'Allegiant Air' WHEN 'HA' THEN 'Hawaiian Airlines'
          WHEN 'MQ' THEN 'Envoy Air' WHEN 'NK' THEN 'Spirit Airlines'
          WHEN 'OH' THEN 'PSA Airlines' WHEN 'OO' THEN 'SkyWest Airlines'
          WHEN 'UA' THEN 'United Airlines' WHEN 'WN' THEN 'Southwest Airlines'
          WHEN 'YX' THEN 'Republic Airways' ELSE CARRIER_CODE END) AS CARRIER_NAME
FROM dbo.DIM_CARRIER
