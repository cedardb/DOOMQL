CREATE OR REPLACE VIEW rays AS
WITH cols AS ( 
    SELECT pc.col FROM settings s, generate_series(0, s.view_w) as pc(col)
  )
  SELECT p.id as player_id, 
    m.x AS player_x, 
    m.y AS player_y,
    c.col, 
    (m.dir - s.fov/2.0 + s.fov * (c.col*1.0 / (s.view_w - 1))) AS angle 
  FROM cols c, settings s, players p, mobs m
  WHERE p.id = m.id;
-- A view for all tiles visible to a given player
-- calculated using raycasting from each player's position
CREATE OR REPLACE VIEW visible_tiles AS 
WITH RECURSIVE raytrace(player_id, col, step_count, fx, fy, angle, dist) AS ( 
    SELECT 
      r.player_id,
      r.col, 
      1, 
      r.player_x + COS(r.angle)*s.step, 
      r.player_y + SIN(r.angle)*s.step, 
      r.angle,
      0
    FROM rays r, settings s 
    UNION ALL 
    SELECT
      rt.player_id as player_id, 
      rt.col as col, 
      rt.step_count + 1 as step_count, 
      rt.fx + COS(rt.angle)*s.step as fx, 
      rt.fy + SIN(rt.angle)*s.step as fy, 
      rt.angle,
      step_count * s.step * COS(rt.angle - m.dir) as dist
    FROM raytrace rt, settings s, players p, mobs m
    WHERE rt.step_count < s.max_steps 
      AND rt.player_id = p.id
      AND m.id = p.id
      AND NOT EXISTS ( -- Culling rays that hit walls
        SELECT 1 
        FROM map m 
        WHERE m.x = CAST(rt.fx AS INT) 
          AND m.y = CAST(rt.fy AS INT) 
          AND m.tile = '#') 
    )
  SELECT DISTINCT
    rt.player_id,
    m.tile,
    CAST(rt.fx AS INT) AS tile_x,
    CAST(rt.fy AS INT) AS tile_y,
    col,
    min(dist) as dist
  FROM raytrace rt, map m
  where m.x = CAST(rt.fx AS INT) 
    AND m.y = CAST(rt.fy AS INT) 
  GROUP BY tile_x, tile_y, m.tile, col, player_id;

-- RENDER VIEW (Walls/Floor/Ceiling only)
CREATE OR REPLACE VIEW render_3d_frame AS
WITH
  cols AS ( 
    SELECT pc.col FROM settings s, generate_series(0, s.view_w) as pc(col)
  ),
  rows_gen AS ( 
    SELECT pr.row FROM settings s, generate_series(0, s.view_h) as pr(row)
  ),
  visible_walls AS ( 
    SELECT 
      player_id,
      vt.col, 
      min(dist) as dist,
    FROM map m, settings s, visible_tiles vt
    where vt.tile_x = m.x 
      AND vt.tile_y = m.y 
      AND m.tile = '#'
    GROUP BY player_id, vt.col
  ),
  distances AS (
    select r.player_id,
      r.col,
      r.angle,
      coalesce(v.dist, s.max_steps * s.step) as dist
    from settings s, rays r left join visible_walls v on r.col = v.col and r.player_id = v.player_id
  ),
  heights AS ( 
    SELECT 
      p.id as player_id, 
      d.col, 
      CASE WHEN d.dist <= 0 
        THEN s.view_h 
        ELSE GREATEST(0, LEAST(s.view_h, CAST(s.view_h / (d.dist * COS(d.angle - m.dir)) AS INT))) 
      END AS height 
    FROM distances d, settings s, players p, mobs m
    WHERE p.id = m.id
      AND d.player_id = p.id),
  pixels AS ( 
    SELECT 
      h.player_id,
      c.col AS x, 
      rg.row AS y, 
      CASE WHEN rg.row < (s.view_h - h.height) / 2 THEN ' ' 
        WHEN rg.row >= (s.view_h + h.height) / 2 THEN '.' 
        WHEN d.dist < s.max_steps * s.step / 4 THEN '█' 
        WHEN d.dist < s.max_steps * s.step * 2 / 4 THEN '▓' 
        WHEN d.dist < s.max_steps * s.step * 3 / 4 THEN '▒' 
        ELSE '░' END AS ch 
      FROM cols c, rows_gen rg, settings s, heights h, distances d
      WHERE c.col = h.col
      AND h.player_id = d.player_id
      AND c.col = d.col)
SELECT player_id, x, y, ch FROM pixels ORDER BY y, x;

----- RENDER 3D FRAME WITH ENTITIES (Bullets and Players)
CREATE OR REPLACE VIEW game_view as 
with 
-- Gather settings and player info as scalars
config as (
  select 
    p.id as player_id,
    s.view_w, s.view_h, s.fov,
    m.x as player_x, m.y as player_y, m.dir as player_dir,
    cos(-m.dir) as cos_dir,
    sin(-m.dir) as sin_dir,
    s.view_w / (2 * tan(s.fov / 2)) as projection_factor
  from settings s, players p, mobs m
  WHERE p.id = m.id
),
-- Compute relative coordinates, depth, screen_x, etc.
projected_mobs as (
  select 
    m.*,
    c.*,
    m.x - c.player_x as dx,
    m.y - c.player_y as dy,
    (m.x - c.player_x) * c.cos_dir - (m.y - c.player_y) * c.sin_dir as depth,
    (m.x - c.player_x) * c.sin_dir + (m.y - c.player_y) * c.cos_dir as horiz
  from mobs m, config c
),


-- Project onto screen, filter invalid/behind-camera entities
screen_mobs as (
  SELECT 
    pm.*,
    ROUND(pm.view_w / 2 + (pm.horiz / pm.depth) * pm.projection_factor) AS screen_x_center,
    FLOOR(pm.view_h / 2) AS screen_y_center
  FROM projected_mobs pm
  WHERE pm.depth > 0.1
),

-- Wall distances per column
column_distances AS (
  SELECT player_id, col, MAX(dist) AS dist
  FROM visible_tiles
  GROUP BY player_id, col
),

-- We have multiple LODs for some sprites, so we need to select the right one
bullet_lods AS (
  SELECT
    (SELECT id FROM sprites WHERE name = 'shot_slug_away_12x12') AS near_id,
    (SELECT id FROM sprites WHERE name = 'shot_slug_away_6x6')  AS far_id
),
marine_lods AS (
  SELECT
    (SELECT id FROM sprites WHERE name = 'marine_outline_16x20') AS near_id,
    (SELECT id FROM sprites WHERE name = 'marine_outline_12x15') AS mid_id,
    (SELECT id FROM sprites WHERE name = 'marine_outline_8x10')  AS far_id
),
screen_mobs_lod AS (
  SELECT
    sm.*,
    CASE
      WHEN sm.kind = 'bullet' AND sm.depth > 4 THEN blod.far_id
      WHEN sm.kind = 'player' AND sm.depth > 6 THEN ml.far_id
      WHEN sm.kind = 'player' AND sm.depth > 3 THEN ml.mid_id
      ELSE sm.sprite_id
    END AS effective_sprite_id
  FROM screen_mobs sm, bullet_lods blod, marine_lods ml
),

-- Project sprite pixels for each visible MOB
expanded_sprite_pixels AS (
  SELECT
    sm.player_id,
    sm.id AS mob_id,
    sm.depth,
    sm.view_w, sm.view_h,
    sp.sx, sp.sy, sp.ch,
    spr.w, spr.h,
    sm.screen_x_center,
    sm.screen_y_center,
    (sm.projection_factor * sm.world_w / sm.depth) / spr.w AS scale_x,
    (sm.projection_factor * sm.world_h / sm.depth) / spr.h AS scale_y
  FROM screen_mobs_lod sm
  JOIN sprites spr ON spr.id = sm.effective_sprite_id
  JOIN sprite_pixels sp ON sp.sprite_id = spr.id
  WHERE sp.ch IS NOT NULL AND sp.ch <> ' ' -- Only non-transparent pixels
),


-- Convert sprite local pixel coords to screen coords (billboard centered horizontally, top-aligned)
sprite_screen_pixels AS (
  WITH base AS (
    SELECT
      esp.player_id,
      esp.mob_id,
      esp.depth,
      esp.ch,
      esp.view_w, esp.view_h,
      esp.sx, esp.sy,
      esp.scale_x,
      esp.scale_y,
      esp.screen_x_center,
      esp.screen_y_center,
      esp.w, esp.h,
      -- top-left anchor of the scaled sprite
      (esp.screen_x_center - ROUND((esp.w/2.0) * esp.scale_x))::int AS ax,
      (esp.screen_y_center - ROUND((esp.h/2.0) * esp.scale_y))::int AS ay
    FROM expanded_sprite_pixels esp
  ),
  spans AS (
    SELECT
      b.*,
      -- horizontal span for this texel
      (b.ax + FLOOR(b.sx * b.scale_x))::int AS x0_raw,
      (b.ax + FLOOR((b.sx + 1) * b.scale_x) - 1)::int AS x1_raw,
      -- vertical span for this texel
      (b.ay + FLOOR(b.sy * b.scale_y))::int AS y0_raw,
      (b.ay + FLOOR((b.sy + 1) * b.scale_y) - 1)::int AS y1_raw
    FROM base b
    WHERE b.ch IS NOT NULL
  ),
  clamped AS (
    SELECT
      s.player_id, s.mob_id, s.depth, s.ch, s.view_w, s.view_h,
      GREATEST(s.x0_raw, 0)                          AS x0,
      LEAST(GREATEST(s.x1_raw, s.x0_raw), s.view_w-1) AS x1,  -- ensure x1 >= x0 and on-screen
      GREATEST(s.y0_raw, 0)                          AS y0,
      LEAST(GREATEST(s.y1_raw, s.y0_raw), s.view_h-1) AS y1   -- ensure y1 >= y0 and on-screen
    FROM spans s
  )
  SELECT
    c.player_id, c.mob_id, c.depth, c.ch,
    px AS px, py AS py
  FROM clamped c
  JOIN LATERAL generate_series(c.x0, c.x1) AS px ON TRUE
  JOIN LATERAL generate_series(c.y0, c.y1) AS py ON TRUE
),

-- Keep only sprite pixels that are in front of the wall
visible_sprite_pixels AS (
  SELECT 
    ssp.*,
    cd.dist AS wall_depth
  FROM sprite_screen_pixels ssp
  LEFT JOIN column_distances cd
    ON cd.player_id = ssp.player_id
   AND cd.col = ssp.px
   WHERE depth < COALESCE(cd.dist, 1e9)
),

-- Keep the closest MOB pixel per screen (x,y)
closest_sprite_pixel AS (
  SELECT DISTINCT ON (player_id, px, py)
    player_id, px, py, ch, depth
  FROM visible_sprite_pixels
  ORDER BY player_id, px, py, depth ASC
),

-- Compose the base 3D frame (your existing walls/floor/ceiling)
base_frame AS (
  SELECT player_id, y, x, ch
  FROM render_3d_frame
),

-- Overlay the MOB sprite pixels on top of the base frame
patched_framebuffer AS (
  SELECT 
    bf.player_id,
    bf.y,
    bf.x,
    COALESCE(csp.ch, bf.ch) AS ch
  FROM base_frame bf
  LEFT JOIN closest_sprite_pixel csp
    ON csp.player_id = bf.player_id AND csp.px = bf.x AND csp.py = bf.y
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
with dimensions as ( -- Find the bounding box of the map, we don't want to allow just rectangular maps
  select max(x) as max_x, max(y) as max_y from map
),
with grid as (  -- Render the bounding box
  select x, y
  from dimensions d,
       generate_series(0, d.max_x) as x,
       generate_series(0, d.max_y) as y
),
-- Get all visible tiles 
tiles_to_display as (
  select player_id, tile_x, tile_y, min(tile) as tile from visible_tiles
  group by player_id, tile_x, tile_y
),
-- Generic MOB overlay, only where tile is visible
mobs_overlay AS (
  SELECT 
    t.player_id,
    FLOOR(m.x)::int AS x,
    FLOOR(m.y)::int AS y,
    COALESCE(m.minimap_icon, '·') AS ch
  FROM mobs m
  JOIN tiles_to_display t 
    ON FLOOR(m.x)::int = t.tile_x AND FLOOR(m.y)::int = t.tile_y
),
-- Step 6: Combine overlays in draw order (player > bullet > tile)
combined as (
  select pl.id as player_id, g.x, g.y,
    coalesce(
      mo.ch,
      t.tile,
      case when base.tile = '.' then ' ' -- erase tiles outside LOS
           else base.tile end,
      ' '
    ) as ch
  from grid g, players pl
  left join map base on g.x = base.x and g.y = base.y
  left join tiles_to_display t on g.x = t.tile_x and g.y = t.tile_y and pl.id = t.player_id
  left join mobs_overlay mo on g.x = mo.x and g.y = mo.y and pl.id = mo.player_id
),
-- Step 7: Reconstruct lines
lines as (
  select 
    player_id,
    y,
    string_agg(ch, '' order by x) as row
  from combined
  group by player_id, y
)
-- Final Output: ordered lines
select *
from lines;

create or replace view screen as 
with minimap as (
  select player_id, y, row as minimap_row
  from minimap
),
player_lines as (
  select 
    row_number() over (order by p.id) - 1 as y, 
    p.id || ': ' || m.name || ' (' || m.minimap_icon || ') score: ' || p.score  as player_row
  from players p, mobs m
  where p.id = m.id
),

-- Step 2: Your 3D framebuffer rows (from the 3D render)
gameview as (
  select player_id, y, row as view_row
  from game_view
),

-- Step 3: Pad minimap to fixed width, concat with game view
combined as (
  select 
    g.player_id,
    coalesce(m.y, g.y) as y,
    rpad(coalesce(g.view_row, ''), 128, ' ') || '   ' || coalesce(m.minimap_row, '')  || '   ' || coalesce(p.player_row, '') as full_row --map width
  from minimap m
  full outer join player_lines p on m.y = p.y
  full outer join gameview g on (m.y = g.y and m.player_id = g.player_id)
)

-- Step 4: Final joined output
select player_id, y, full_row
from combined;