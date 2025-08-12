insert into sprites(id, name, w, h)   VALUES (3, 'shot_slug_away_12x12', 12, 12);
insert into sprites(id, name, w, h)   VALUES (4, 'shot_slug_away_6x6', 6, 6);

with art AS (
  SELECT
    3 AS sprite_id,
    t.line,
    t.sy::int - 1 AS sy -- 0-based y
  FROM unnest(ARRAY[
    '.....++.....',
    '....+@@+....',
    '...+@@@@+...',
    '..+@@@@@@+..',
    '..+@@@@@@+..',
    '.+@@@@@@@@+.',
    '.+@@@@@@@@+.',
    '..+@@@@@@+..',
    '..+@@@@@@+..',
    '...+@@@@+...',
    '....+@@+....',
    '.....++.....'
  ]) WITH ORDINALITY AS t(line, sy)
),
expanded AS (
  SELECT
    a.sprite_id,
    x % 12 as sx,
    x / 12 as sy,
    SUBSTRING(a.line FROM sx+1 FOR 1) AS raw_ch
  FROM generate_series(0, 12 * 12) x, art a
  WHERE a.sy = x / 12
)
INSERT INTO sprite_pixels (sprite_id, sx, sy, ch)
SELECT
  sprite_id, sx, sy,
  CASE WHEN raw_ch = '.' THEN NULL ELSE raw_ch END AS ch
FROM expanded;



with art AS (
  SELECT
    4 AS sprite_id,
    t.line,
    t.sy::int - 1 AS sy -- 0-based y
  FROM unnest(ARRAY[
    '..+...',
    '.+@@..',
    '+@@@+.',
    '+@@@+.',
    '.+@@..',
    '..+...'
  ]) WITH ORDINALITY AS t(line, sy)
),
expanded AS (
  SELECT
    a.sprite_id,
    x % 6 as sx,
    x / 6 as sy,
    SUBSTRING(a.line FROM sx+1 FOR 1) AS raw_ch
  FROM generate_series(0, 6 * 6) x, art a
  WHERE a.sy = x / 6
)
INSERT INTO sprite_pixels (sprite_id, sx, sy, ch)
SELECT
  sprite_id, sx, sy,
  CASE WHEN raw_ch = '.' THEN NULL ELSE raw_ch END AS ch
FROM expanded;