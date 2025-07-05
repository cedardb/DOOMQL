alter user postgres with password 'postgres';

-- GENERAL CONFIG PARAMS
DROP TABLE IF EXISTS config;
CREATE TABLE config(
  player_move_speed NUMERIC DEFAULT 0.3, 
  player_turn_speed NUMERIC DEFAULT 0.2);

insert into config (player_move_speed, player_turn_speed) values (0.3, 0.2);

-- MAP
DROP TABLE IF EXISTS map;
CREATE TABLE map(x INT, y INT, tile CHAR);
-- Needs to be populated with your map data

-- PLAYER
DROP TABLE IF EXISTS player;
CREATE TABLE player(id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY, x DOUBLE, y DOUBLE, dir DOUBLE, icon CHAR, name TEXT, score INT DEFAULT 0);


-- INPUTS
DROP TABLE IF EXISTS inputs;
CREATE TABLE inputs(
  player_id INT PRIMARY KEY,
  action CHAR, -- 'w', 'a', 's', 'd', ' '
  timestamp TIMESTAMP DEFAULT NOW()
);

-- BULLETS
DROP TABLE IF EXISTS bullets;
CREATE TABLE bullets(id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY, x DOUBLE, y DOUBLE, dx DOUBLE, dy DOUBLE, owner int references player(id));

-- COLLISIONS BETWEEN BULLETS AND PLAYERS
DROP VIEW IF EXISTS collisions;
CREATE OR REPLACE VIEW collisions AS 
  SELECT b.id AS bullet_id,
    b.owner as bullet_owner,
    p.id AS player_id, 
    p.x AS player_x, 
    p.y AS player_y 
  FROM bullets b, player p 
  WHERE CAST(b.x AS INT) = CAST(p.x AS INT) 
  AND CAST(b.y AS INT) = CAST(p.y AS INT)
  AND b.owner != p.id; -- Ensure the bullet is not from the player being hit


-- SETTINGS
DROP TABLE IF EXISTS settings;
CREATE TABLE settings(fov DOUBLE, step DOUBLE, max_steps INT, view_w INT, view_h INT);
INSERT INTO settings VALUES (PI()/3, 0.1, 100, 128, 64);

-- RENDER VIEW (Walls/Floor/Ceiling only)
DROP VIEW IF EXISTS render_3d_frame;
CREATE OR REPLACE VIEW render_3d_frame AS
WITH RECURSIVE
  cols AS ( 
    SELECT pc.col FROM settings s, generate_series(0, s.view_w) as pc(col)
  ),
  rows_gen AS ( 
    SELECT pr.row FROM settings s, generate_series(0, s.view_h) as pr(row)
  ),
  rays AS ( 
    SELECT p.id as player_id, 
      p.x AS player_x, 
      p.y AS player_y,
      c.col, 
      (p.dir - s.fov/2.0 + s.fov * (c.col*1.0 / (s.view_w - 1))) AS angle 
    FROM cols c, settings s, player p 
  ),
  raytrace(player_id, col, step_count, fx, fy, angle) AS ( 
    SELECT r.player_id,
      r.col, 
      1, 
      player_x + COS(r.angle)*s.step, 
      player_y + SIN(r.angle)*s.step, 
      r.angle 
    FROM rays r, settings s 
    UNION ALL 
    SELECT rt.player_id, 
      rt.col, 
      rt.step_count + 1, 
      rt.fx + COS(rt.angle)*s.step, 
      rt.fy + SIN(rt.angle)*s.step, 
      rt.angle 
    FROM raytrace rt, settings s 
    WHERE rt.step_count < s.max_steps 
      AND NOT EXISTS (
        SELECT 1 
        FROM map m 
        WHERE m.x = CAST(rt.fx AS INT) 
          AND m.y = CAST(rt.fy AS INT) 
          AND m.tile = '#') 
      ),
  hit_walls AS ( 
    SELECT player_id,
      col, 
      MIN(step_count) as min_steps 
    FROM raytrace rt 
    WHERE EXISTS (
      SELECT 1 
      FROM map m 
      WHERE m.x = CAST(rt.fx AS INT) 
        AND m.y = CAST(rt.fy AS INT) 
        AND m.tile = '#') 
    GROUP BY player_id, col 
  ),
  distances AS ( 
    SELECT p.id as player_id, 
      c.col, 
      COALESCE(hw.min_steps * s.step, s.max_steps * s.step) AS dist 
    FROM player p, cols c, settings s
      LEFT JOIN hit_walls hw ON c.col = hw.col and p.id = hw.player_id
  ),
  heights AS ( 
    SELECT p.id as player_id, 
      d.col, 
      CASE WHEN d.dist <= 0 
        THEN s.view_h 
        ELSE GREATEST(0, LEAST(s.view_h, CAST(s.view_h / (d.dist * COS(r.angle - p.dir)) AS INT))) 
      END AS height 
    FROM distances d, settings s, rays r, player p
    WHERE d.col = r.col 
      AND p.id = r.player_id
      AND p.id = d.player_id),
  pixels AS ( 
    SELECT p.id as player_id,
      c.col AS x, 
      rg.row AS y, 
      CASE WHEN rg.row < (s.view_h - h.height) / 2 THEN ' ' 
        WHEN rg.row >= (s.view_h + h.height) / 2 THEN '.' 
        WHEN d.dist < s.max_steps * s.step / 4 THEN '█' 
        WHEN d.dist < s.max_steps * s.step * 2 / 4 THEN '▓' 
        WHEN d.dist < s.max_steps * s.step * 3 / 4 THEN '▒' 
        ELSE '░' END AS ch 
      FROM player p, cols c, rows_gen rg, settings s, heights h, distances d
      WHERE c.col = h.col
      AND h.player_id = p.id
      AND d.player_id = p.id
      AND c.col = d.col )
SELECT player_id, x, y, ch FROM pixels ORDER BY y, x;

-- VIEW FOR COLUMN DISTANCES (for depth buffer)
DROP VIEW IF EXISTS column_distances;
CREATE VIEW column_distances AS
WITH RECURSIVE
  cols AS ( 
    SELECT pc.col FROM settings s, generate_series(0, s.view_w) as pc(col)
  ),
  rows_gen AS ( 
    SELECT pr.row FROM settings s, generate_series(0, s.view_h) as pr(row)
  ),
  rays AS ( 
    SELECT p.id as player_id, 
      p.x AS player_x, 
      p.y AS player_y,
      c.col, 
      (p.dir - s.fov/2.0 + s.fov * (c.col*1.0 / (s.view_w - 1))) AS angle 
    FROM cols c, settings s, player p 
  ),
  raytrace(player_id, col, step_count, fx, fy, angle) AS ( 
    SELECT r.player_id,
      r.col, 
      1, 
      player_x + COS(r.angle)*s.step, 
      player_y + SIN(r.angle)*s.step, 
      r.angle 
    FROM rays r, settings s 
    UNION ALL 
    SELECT rt.player_id, 
      rt.col, 
      rt.step_count + 1, 
      rt.fx + COS(rt.angle)*s.step, 
      rt.fy + SIN(rt.angle)*s.step, 
      rt.angle 
    FROM raytrace rt, settings s 
    WHERE rt.step_count < s.max_steps 
      AND NOT EXISTS (
        SELECT 1 
        FROM map m 
        WHERE m.x = CAST(rt.fx AS INT) 
          AND m.y = CAST(rt.fy AS INT) 
          AND m.tile = '#') 
      ),
  hit_walls AS ( 
    SELECT player_id,
      col, 
      MIN(step_count) as min_steps 
    FROM raytrace rt 
    WHERE EXISTS (
      SELECT 1 
      FROM map m 
      WHERE m.x = CAST(rt.fx AS INT) 
        AND m.y = CAST(rt.fy AS INT) 
        AND m.tile = '#') 
    GROUP BY player_id, col 
  )
SELECT p.id as player_id,
    c.col AS x,
    COALESCE(hw.min_steps * s.step * COS(r.angle - p.dir), s.max_steps * s.step) AS dist_corrected
FROM cols c, settings s, player p, rays r
LEFT JOIN hit_walls hw ON (c.col = hw.col AND p.id = hw.player_id)
WHERE c.col = r.col 
  AND r.player_id = p.id;



----- RENDER 3D FRAME WITH ENTITIES (Bullets and Players)
CREATE OR REPLACE VIEW game_view as 
with 
-- Gather settings and player info as scalars
config as (
  select 
    p.id as player_id,
    s.view_w, s.view_h, s.fov,
    p.x as player_x, p.y as player_y, p.dir as player_dir,
    cos(-p.dir) as cos_dir,
    sin(-p.dir) as sin_dir,
    s.view_w / (2 * tan(s.fov / 2)) as projection_factor
  from settings s, player p
),

-- Combine bullets and players into one stream
entities as (
  select id, x, y, '🔥' as icon, 'bullet' as type from bullets
  union all
  select id, x, y, icon, 'player' from player
),


-- Compute relative coordinates, depth, screen_x, etc.
projected_entities as (
  select 
    e.*,
    c.*,
    e.x - c.player_x as dx,
    e.y - c.player_y as dy,
    (e.x - c.player_x) * c.cos_dir - (e.y - c.player_y) * c.sin_dir as depth,
    (e.x - c.player_x) * c.sin_dir + (e.y - c.player_y) * c.cos_dir as horizontal_offset
  from entities e, config c
),


-- Project onto screen, filter invalid/behind-camera entities
screen_entities as (
  select *,
    round(view_w / 2 + (horizontal_offset / depth) * projection_factor) as screen_x,
    floor(view_h / 2) as screen_y
  from projected_entities
  where depth > 0.1
),


-- Clamp to screen and get wall depth
clamped as (
  select 
    se.*,
    greatest(0, least(view_h - 1, screen_y)) as final_y,
    cd.dist_corrected as wall_depth
  from screen_entities se
  left join column_distances cd on (
    cd.x = round(view_w / 2 + (horizontal_offset / depth) * projection_factor) 
    and se.player_id = cd.player_id)
  where round(view_w / 2 + (horizontal_offset / depth) * projection_factor) >= 0
  and round(view_w / 2 + (horizontal_offset / depth) * projection_factor) between 0 and view_w - 1
),

-- Select only visible entities closer than the wall
visible_entities as (
  select * from clamped
  where depth < coalesce(wall_depth, 1e9)
),

-- Expand entities based on depth
scaled_entities AS (
  SELECT
    player_id,
    screen_x,
    final_y,
    icon,
    depth,
    view_h,
    view_w,
    ceil(view_h / (depth * 8.0))::int AS radius_y,
    ceil(view_w / (depth * 8.0))::int AS radius_x
  FROM visible_entities
),

-- Project entity based on its size
entity_pixels as (
  select 
    player_id,
    icon,
    depth,
    screen_x + dx AS px,
    final_y + dy AS py
  from scaled_entities,
  generate_series(-15, 15) AS dx,
  generate_series(-15, 15) AS dy
  WHERE 
    (dx * dx * 1.0) / (radius_x * radius_x + 0.01) +
    (dy * dy * 1.0) / (radius_y * radius_y + 0.01) <= 1.0  -- ellipse equation
    AND screen_x + dx >= 0 AND screen_x + dx <= view_w - 1
    AND final_y + dy >= 0 AND final_y + dy <= view_h - 1
),

-- Select the closest entity per (x, y) cell
closest_entity_per_pixel as (
  select distinct on (player_id, px, py)
    player_id, px, py, icon, depth
  from entity_pixels
  order by player_id, px, py, depth asc
),

-- Overlay entity icons
patched_framebuffer as (
  select 
    fc.player_id,
    fc.y,
    fc.x,
    coalesce(ce.icon, fc.ch) as ch
  from render_3d_frame fc
  left join closest_entity_per_pixel ce 
    on (ce.px = fc.x and ce.py = fc.y and fc.player_id = ce.player_id)
),


-- Reconstruct each row from characters
final_frame as (
  select 
    player_id,
    y,
    string_agg(ch, '' order by x) as row
  from patched_framebuffer
  group by player_id, y
)
select * from final_frame order by y;


--- Render Minimap

-- Step 1: Generate empty grid
CREATE OR REPLACE VIEW minimap AS
with dimensions as (
  select max(x) as max_x, max(y) as max_y from map
),
with grid as (
  select x, y
  from dimensions d,
       generate_series(0, d.max_x) as x,
       generate_series(0, d.max_y) as y,
       
),

-- Step 2: Draw map tiles
tiles as (
  select 
    floor(x)::int as x,
    floor(y)::int as y,
    tile
  from map
),

-- Step 3: Draw bullets ('*')
bullets_overlay as (
  select 
    floor(x)::int as x,
    floor(y)::int as y,
    '🔥' as ch
  from bullets
),

-- Step 5: Draw player (single row)
player_overlay as (
  select 
    floor(x)::int as x,
    floor(y)::int as y,
    icon as ch
  from player
),

-- Step 6: Combine overlays in draw order (player > bullet > tile)
combined as (
  select g.x, g.y,
    coalesce(
      p.ch,
      b.ch,
      t.tile,
      ' '
    ) as ch
  from grid g
  left join tiles t on g.x = t.x and g.y = t.y
  left join bullets_overlay b on g.x = b.x and g.y = b.y
  left join player_overlay p on g.x = p.x and g.y = p.y
),

-- Step 7: Reconstruct lines
lines as (
  select 
    y,
    string_agg(ch, '' order by x) as row
  from combined
  group by y
)
-- Final Output: ordered lines
select *
from lines;

create or replace view screen as 
with minimap as (
  select y, row as minimap_row
  from minimap
),
player_lines as (
  select row_number() over () - 1 as y, 
  id || ': ' || name || ' (' || icon || ') score: ' || score  as player_row
  from player
),


-- Step 2: Your 3D framebuffer rows (from the 3D render)
gameview as (
  select player_id, y, row as view_row
  from game_view
),

-- Step 3: Pad minimap to fixed width, concat with game view
combined as (
  select 
    player_id,
    coalesce(m.y, g.y) as y,
    rpad(coalesce(g.view_row, ''), 128, ' ') || '   ' || coalesce(m.minimap_row, '')  || '   ' || coalesce(p.player_row, '') as full_row --map width
  from minimap m
  full outer join player_lines p on m.y = p.y
  full outer join gameview g on m.y = g.y
    
)

-- Step 4: Final joined output
select player_id, y, full_row
from combined;