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

-- PLAYER
DROP TABLE IF EXISTS player;
CREATE TABLE player(
  id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY, 
  x DOUBLE, 
  y DOUBLE, 
  dir DOUBLE, 
  icon CHAR, 
  name TEXT, 
  score INT DEFAULT 0);


-- INPUTS
DROP TABLE IF EXISTS inputs;
CREATE TABLE inputs(
  player_id INT PRIMARY KEY,
  action CHAR, -- 'w', 'a', 's', 'd', ' '
  timestamp TIMESTAMP DEFAULT NOW()
);

-- BULLETS
DROP TABLE IF EXISTS bullets;
CREATE TABLE bullets(
  id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY, 
  x DOUBLE, 
  y DOUBLE, 
  dx DOUBLE, 
  dy DOUBLE,
   owner int references player(id));

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


