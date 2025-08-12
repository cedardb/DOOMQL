TRUNCATE TABLE map;

WITH params AS (
  SELECT 64::int AS w, 32::int AS h
),

-- Full grid (defaults to walls) ------------------------------------------
grid AS (
  SELECT x, y
  FROM params p,
       generate_series(0, p.w - 1) AS x,
       generate_series(0, p.h - 1) AS y
),

-- Rectangles to carve as FLOOR (rooms + corridors) -----------------------
-- Format: (x1,y1,x2,y2), all inclusive; corridors are just skinny rects (>= 2 wide)
areas AS (
  SELECT * FROM (VALUES
    -- ROOMS (big rectangles)
    (  2,  2, 14, 10),   -- Room A
    ( 20,  2, 34,  9),   -- Room B
    ( 40,  3, 60, 12),   -- Room C
    (  4, 14, 20, 28),   -- Room D
    ( 26, 16, 38, 28),   -- Room E
    ( 44, 16, 60, 28),   -- Room F

    -- CORRIDORS (>= 2 tiles wide)
    ( 15,  6, 20,  7),   -- A ↔ B (horizontal, 2 high)
    ( 35,  6, 40,  7),   -- B ↔ C (horizontal, 2 high)
    ( 10, 11, 11, 14),   -- A ↔ D (vertical, 2 wide: x=10..11)
    ( 20, 21, 26, 22),   -- D ↔ E (horizontal, 2 high)
    ( 38, 22, 44, 23),   -- E ↔ F (horizontal, 2 high)
    ( 28,  9, 29, 16),   -- B ↔ E (vertical, 2 wide)
    ( 52, 12, 53, 16)    -- C ↔ F (vertical, 2 wide)
  ) AS t(x1,y1,x2,y2)
),

-- Normalize any reversed coords
normalized AS (
  SELECT LEAST(x1,x2) AS x1, LEAST(y1,y2) AS y1,
         GREATEST(x1,x2) AS x2, GREATEST(y1,y2) AS y2
  FROM areas
),

-- Find rooms that are at least 6 by 6 (i.e., rooms that are suitable for spawn points).
room_boxes AS (
  SELECT *
  FROM normalized
  WHERE (x2 - x1 + 1) >= 6 AND (y2 - y1 + 1) >= 6
),

-- One respawn at the center of each room (floored to integer coords)
respawns AS (
  SELECT floor((x1 + x2) / 2.0)::int AS x,
         floor((y1 + y2) / 2.0)::int AS y
  FROM room_boxes
),

-- Expand rectangles into floor cells 
floors AS (
  SELECT x, y
  FROM normalized a
  JOIN LATERAL generate_series(a.x1, a.x2) AS x ON TRUE
  JOIN LATERAL generate_series(a.y1, a.y2) AS y ON TRUE
),

-- Compose final map: floors '.' else walls '#'
map_rows AS (
  SELECT g.x, g.y,
         CASE 
          WHEN EXISTS (SELECT 1 FROM respawns r WHERE r.x = g.x AND r.y = g.y)
             THEN 'R'::char
          WHEN EXISTS (SELECT 1 FROM floors f WHERE f.x = g.x AND f.y = g.y)
              THEN '.'::char 
          ELSE '#'::char END AS tile
  FROM grid g
)

INSERT INTO map(x, y, tile)
SELECT x, y, tile FROM map_rows;