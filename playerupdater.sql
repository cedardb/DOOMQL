BEGIN TRANSACTION;
WITH new_positions AS (
  -- Process all forward movements
  SELECT 
    p.id,
    p.x + cos(p.dir) * (SELECT player_move_speed FROM config) AS new_x,
    p.y + sin(p.dir) * (SELECT player_move_speed FROM config) AS new_y
  FROM player p, inputs i
  WHERE p.id = i.player_id
  AND i.action = 'w'
  UNION ALL 
  -- Process all backward movements
  SELECT 
    p.id,
    p.x - cos(p.dir) * (SELECT player_move_speed FROM config) AS new_x,
    p.y - sin(p.dir) * (SELECT player_move_speed FROM config) AS new_y
  FROM player p, inputs i
  WHERE p.id = i.player_id
  AND i.action = 's'
),
filtered_positions AS (
  -- Only allow positions that are not out of bounds or into walls
  SELECT np.id, np.new_x, np.new_y
  FROM new_positions np, map m
  WHERE m.x = CAST(np.new_x AS INT)
  AND m.y = CAST(np.new_y AS INT)
  AND m.tile != '#'
)
UPDATE player p SET 
x = np.new_x, 
y = np.new_y
FROM filtered_positions np
WHERE p.id = np.id;


-- Process all left turns
UPDATE player e  SET 
dir = dir - (select player_turn_speed from config)
FROM inputs i
WHERE e.id = i.player_id
AND i.action = 'a';

-- Process all right turns
UPDATE player e SET 
dir = dir + (select player_turn_speed from config)
FROM inputs i
WHERE e.id = i.player_id
AND i.action = 'd';

-- Process all players shooting a bullet
INSERT INTO bullets(x, y, dx, dy, owner) 
  SELECT 
    p.x, 
    p.y, 
    cos(p.dir) * 0.5, 
    sin(p.dir) * 0.5,
    p.id
  FROM player p
  JOIN inputs i ON p.id = i.player_id
  WHERE i.action = 'x';

COMMIT;


-- Process all bullets
BEGIN TRANSACTION;

UPDATE bullets SET x = x+dx, y = y+dy;

-- Delete bullets that are out of bounds
DELETE FROM bullets WHERE x < 0 OR x >= 16 OR y < 0 OR y >= 16;

-- Delete bullets that hit walls
DELETE FROM bullets b WHERE EXISTS (SELECT 1 FROM map m WHERE m.x = CAST(b.x AS INT) AND m.y = CAST(b.y AS INT) AND m.tile = '#');


-- The player who shot the bullet is awarded a point
UPDATE player p SET score = score + 1
FROM collisions c
WHERE p.id = c.bullet_owner;

-- Delete the bullets that hit players
DELETE FROM bullets b
USING collisions c
WHERE b.id = c.bullet_id;

COMMIT;

-- TODO: Bounds check for player movement

-- Remove all processed inputs
UPDATE inputs i SET action = '';
