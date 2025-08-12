-- Process all player inputs
BEGIN TRANSACTION;

WITH new_positions AS (
  -- Process all forward movements
  SELECT 
    p.id,
    m.x + cos(m.dir) * (SELECT player_move_speed FROM config) AS new_x,
    m.y + sin(m.dir) * (SELECT player_move_speed FROM config) AS new_y
  FROM players p, mobs m, inputs i
  WHERE p.id = i.player_id
  AND m.id = p.id
  AND i.action = 'w'
  UNION ALL 
  -- Process all backward movements
  SELECT 
    p.id,
    m.x - cos(m.dir) * (SELECT player_move_speed FROM config) AS new_x,
    m.y - sin(m.dir) * (SELECT player_move_speed FROM config) AS new_y
  FROM players p, mobs m, inputs i
  WHERE p.id = i.player_id
  AND m.id = p.id
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
UPDATE mobs m SET 
x = np.new_x, 
y = np.new_y
FROM filtered_positions np
WHERE m.id = np.id;


-- Process all left turns
UPDATE mobs m SET 
dir = dir - (select player_turn_speed from config)
FROM inputs i, players p
WHERE m.id = p.id
AND m.id = i.player_id
AND i.action = 'a';

-- Process all right turns
UPDATE mobs m SET 
dir = dir + (select player_turn_speed from config)
FROM inputs i, players p
WHERE m.id = p.id
AND m.id = i.player_id
AND i.action = 'd';

-- Process all players shooting a bullet
INSERT INTO mobs(kind, owner, x, y, dir, name, sprite_id, minimap_icon, world_w, world_H) 
  SELECT 
    'bullet',
    p.id,
    source.x, 
    source.y, 
    source.dir,
    null,
    (SELECT id FROM sprites WHERE name = 'shot_slug_away_12x12'),
    '*',
    .5,
    .5
  FROM players p, mobs source, inputs i
  WHERE p.id = source.id
  AND i.player_id = p.id
  AND p.ammo > 0
  AND i.action = 'x';

-- Remember to decrease ammo for players who shot
UPDATE players p SET ammo = ammo - 1
FROM inputs i
WHERE p.id = i.player_id
AND p.ammo > 0
AND i.action = 'x';


COMMIT;


-- Process all bullets
BEGIN TRANSACTION;

-- Move bullets forward
UPDATE mobs SET x = x + cos(dir) * 0.5, y = y + sin(dir) * 0.5 WHERE kind = 'bullet';

-- Delete bullets that are out of bounds
DELETE FROM mobs WHERE x < 0 OR x >= (select max(x) from map) OR y < 0 OR y >= (select max(y) from map) AND kind = 'bullet';

-- Delete bullets that hit walls
DELETE FROM mobs b WHERE EXISTS (SELECT 1 FROM map m WHERE m.x = CAST(b.x AS INT) AND m.y = CAST(b.y AS INT) AND m.tile = '#') AND kind = 'bullet';


-- Players hit by a bullet loses 50 HP
UPDATE players p SET hp = hp - 50
FROM collisions c
WHERE p.id = c.player_id;

-- If a player has 0 or less HP, the player killing them gets a point
UPDATE players p SET score = score + 1
FROM collisions c
WHERE p.id = c.bullet_owner
AND EXISTS (SELECT 1 FROM players p2 WHERE p2.id = c.player_id AND p2.hp <= 0);

-- Delete bullets that hit players
DELETE FROM mobs m
USING collisions c
WHERE m.id = c.bullet_id;

-- Respawn players whose HP is 0 or less
UPDATE mobs m
SET x = r.x, y = r.y, dir = 0
FROM players p
CROSS JOIN (
  SELECT x, y
  FROM map
  WHERE tile = 'R'
  ORDER BY random()
  LIMIT 1
) AS r
WHERE m.id = p.id
  AND p.hp <= 0;

-- Reset players' HP to 100 and ammo to 10 after respawn
UPDATE players p SET
  hp = 100,
  ammo = 10
FROM mobs m
WHERE p.id = m.id
AND p.hp <= 0;

COMMIT;


WITH d AS (
  SELECT
    p.id,
    -- how many bullets should we refill?
    FLOOR((EXTRACT(EPOCH FROM (now())) - p.last_ammo_refill) / c.ammo_refill_interval_seconds)::int AS steps,
  FROM players p, config c
  WHERE p.ammo != c.ammo_max
)
UPDATE players p
SET
  ammo = GREATEST(0, LEAST(c.ammo_max, p.ammo + d.steps)),
  last_ammo_refill = EXTRACT(EPOCH FROM (now()))::int
FROM d, config c
WHERE p.id = d.id
  AND d.steps > 0;

-- Remove all processed inputs
UPDATE inputs i SET action = '';