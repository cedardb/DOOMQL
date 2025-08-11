CREATE OR REPLACE VIEW rays AS
WITH cols AS ( 
    SELECT pc.col FROM settings s, generate_series(0, s.view_w) as pc(col)
  )
  SELECT p.id as player_id, 
    p.x AS player_x, 
    p.y AS player_y,
    c.col, 
    (p.dir - s.fov/2.0 + s.fov * (c.col*1.0 / (s.view_w - 1))) AS angle 
  FROM cols c, settings s, player p;

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
      step_count * s.step * COS(rt.angle - p.dir) as dist
    FROM raytrace rt, settings s, player p
    WHERE rt.step_count < s.max_steps 
      AND rt.player_id = p.id
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
    select v.player_id,
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
        ELSE GREATEST(0, LEAST(s.view_h, CAST(s.view_h / (d.dist * COS(d.angle - p.dir)) AS INT))) 
      END AS height 
    FROM distances d, settings s, player p
    WHERE p.id = d.player_id),
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

column_distances AS (
select
  player_id,
  col,
  max(dist) as dist
from visible_tiles
group by player_id, col
),


-- Clamp to screen and get wall depth
clamped as (
  select 
    se.*,
    greatest(0, least(view_h - 1, screen_y)) as final_y,
    cd.dist as wall_depth
  from screen_entities se
  left join column_distances cd on (
    cd.col = round(view_w / 2 + (horizontal_offset / depth) * projection_factor) 
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
  generate_series(-15, 15) AS dx, -- ellipse size
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
-- Step 3: Draw bullets ('*')
bullets_overlay as (
  select 
    t.player_id,
    floor(x)::int as x,
    floor(y)::int as y,
    '🔥' as ch
  from bullets b, tiles_to_display t
  where floor(x)::int = t.tile_x and floor(y)::int = t.tile_y -- only for tiles that are visible
),
-- Step 5: Draw player (single row)
player_overlay as (
  select
    t.player_id,
    floor(x)::int as x,
    floor(y)::int as y,
    icon as ch
  from player, tiles_to_display t
  where floor(x)::int = t.tile_x and floor(y)::int = t.tile_y -- only for tiles that are visible
),
-- Step 6: Combine overlays in draw order (player > bullet > tile)
combined as (
  select pl.id as player_id, g.x, g.y,
    coalesce(
      p.ch,
      b.ch,
      t.tile,
      case when base.tile = '.' then ' ' -- erase tiles outside LOS
           else base.tile end,
      ' '
    ) as ch
  from grid g, player pl
  left join map base on g.x = base.x and g.y = base.y
  left join tiles_to_display t on g.x = t.tile_x and g.y = t.tile_y and pl.id = t.player_id
  left join bullets_overlay b on g.x = b.x and g.y = b.y and pl.id = b.player_id
  left join player_overlay p on g.x = p.x and g.y = p.y and pl.id = p.player_id
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
    row_number() over () - 1 as y, 
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