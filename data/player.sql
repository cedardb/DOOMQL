insert into sprites(id, name, w, h)   VALUES (0, 'marine_outline_16x20', 16, 20);
insert into sprites(id, name, w, h)   VALUES (1, 'marine_outline_12x15', 12, 15);
insert into sprites(id, name, w, h)   VALUES (2, 'marine_outline_8x10', 8, 10);

with art AS (
  SELECT
    0 AS sprite_id,
    t.line,
    t.sy::int - 1 AS sy -- 0-based y
  FROM unnest(ARRAY[
    '.....@@@@@@.....',
    '....##@@@@##....',
    '....#@@##@@#....',
    '....#@#..#@#....',
    '....#@@@@@@#....',
    '...#@@@@@@@@#...',
    '...#@@@&&@@@#...',
    '..##@@&##&@@##..',
    '..#@@@####@@@#..',
    '..#==@@@@@@==#..',
    '..#@@@####@@@#..',
    '..#@@@#..#@@@#..',
    '..#@@#....#@@#..',
    '..#@@#....#@@#..',
    '..#@@#....#@@#..',
    '..#@@#....#@@#..',
    '...##......##...',
    '...##......##...',
    '....#......#....',
    '....##....##....'
  ]) WITH ORDINALITY AS t(line, sy)
),
expanded AS (
  SELECT
    a.sprite_id,
    x % 16 as sx,
    x / 16 as sy,
    SUBSTRING(a.line FROM (x % 16)+1 FOR 1) AS raw_ch
  FROM generate_series(0, 16 * 20) x, art a
  WHERE a.sy = x / 16
)
INSERT INTO sprite_pixels (sprite_id, sx, sy, ch)
SELECT
  sprite_id, sx, sy,
  CASE WHEN raw_ch = '.' THEN NULL ELSE raw_ch END AS ch
FROM expanded;



with art AS (
  SELECT
    1 AS sprite_id,
    t.line,
    t.sy::int - 1 AS sy -- 0-based y
  FROM unnest(ARRAY[
    '...@@@@@@...',
    '..##@@@@##..',
    '..#@@##@@#..',
    '..#@#..#@#..',
    '..#@@@@@@#..',
    '.#@@@@@@@@#.',
    '.#@@@&&@@@#.',
    '.#@@&##&@@#.',
    '.#@@####@@#.',
    '.#==@@@@==#.',
    '.#@@####@@#.',
    '.#@@#..#@@#.',
    '.#@@....@@#.',
    '..##....##..',
    '...#....#...'
  ]) WITH ORDINALITY AS t(line, sy)
),
expanded AS (
  SELECT
    a.sprite_id,
    x % 12 as sx,
    x / 12 as sy,
    SUBSTRING(a.line FROM (x % 12)+1 FOR 1) AS raw_ch
  FROM generate_series(0, 12 * 15) x, art a
  WHERE a.sy = x / 12
)
INSERT INTO sprite_pixels (sprite_id, sx, sy, ch)
SELECT
  sprite_id, sx, sy,
  CASE WHEN raw_ch = '.' THEN NULL ELSE raw_ch END AS ch
FROM expanded;


with art AS (
  SELECT
    2 AS sprite_id,
    t.line,
    t.sy::int - 1 AS sy -- 0-based y
  FROM unnest(ARRAY[
    '..@@@@..',
    '.#@@@@#.',
    '.#@##@#.',
    '.#@..@#.',
    '.#@@@@#.',
    '.#@&&@#.',
    '.#@##@#.',
    '.#==@#..',
    '..##..##',
    '...#..#.'
  ]) WITH ORDINALITY AS t(line, sy)
),
expanded AS (
  SELECT
    a.sprite_id,
    x % 8 as sx,
    x / 8 as sy,
    SUBSTRING(a.line FROM (x % 8)+1 FOR 1) AS raw_ch
  FROM generate_series(0, 8 * 10) x, art a
  WHERE a.sy = x / 8
)
INSERT INTO sprite_pixels (sprite_id, sx, sy, ch)
SELECT
  sprite_id, sx, sy,
  CASE WHEN raw_ch = '.' THEN NULL ELSE raw_ch END AS ch
FROM expanded;