import psycopg2
import sys
import tty
import termios
import select
import time
import os
from psycopg2 import errors

DB_NAME = "postgres"
DB_USER = "postgres"
DB_PASSWORD = "postgres"
DB_HOST = "localhost"
DB_PORT = "5432"

FRAME_INTERVAL = 0.05  # ~20 FPS

def getch(timeout=0.01):
    dr, _, _ = select.select([sys.stdin], [], [], timeout)
    if dr:
        return sys.stdin.read(1)
    return None

def move_cursor_top():
    print("\033[H", end='')

def clear():
    print("\033[2J\033[H", end='')

def init_terminal():
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    os.system("stty -echo")
    tty.setcbreak(fd)
    return fd, old_settings

def reset_terminal(fd, old_settings):
    termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

def connect_db():
    return psycopg2.connect(
        dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD,
        host=DB_HOST, port=DB_PORT
    )

def get_or_create_player(cur, name, icon):
    cur.execute("SELECT p.id FROM players p, mobs m WHERE p.id = m.id AND m.name = %s", (name,))
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute("INSERT INTO mobs(kind, x, y, dir, name, sprite_id, minimap_icon) VALUES ('player', 4, 4, 0, %s, 0, %s) RETURNING id", (name, icon))
    id = cur.fetchone()[0]
    cur.execute("INSERT INTO players(id) VALUES (%s)", (id,))
    return id

def read_state(cur, player_id):
    cur.execute("SELECT m.x, m.y, m.dir FROM players p, mobs m WHERE p.id = m.id AND p.id = %s", (player_id,))
    return cur.fetchone()

def read_metadata(cur, pid):
    cur.execute("SELECT m.name, m.x, m.y, m.dir FROM players p, mobs m WHERE p.id = m.id AND p.id = %s", (pid,))
    return cur.fetchone()  # returns (name, x, y, dir)

def render_screen(cur, player_id):
    cur.execute("SELECT full_row FROM screen WHERE player_id = %s ORDER BY y", (player_id,))
    rows = cur.fetchall()
    for i, (full_row,) in enumerate(rows):
        print(full_row, end='\033[K\n')
    print()

def safe_update_input(cur, player_id, key, retries=3):
    attempt = 0
    while attempt < retries:
        try:
            cur.execute("""
                INSERT INTO inputs(player_id, action)
                VALUES (%s, %s)
                ON CONFLICT(player_id)
                DO UPDATE SET action = EXCLUDED.action
            """, (player_id, key))
            return  # success
        except errors.SerializationFailure as e:
            attempt += 1
            time.sleep(0.01 * (2 ** attempt))  # exponential backoff
        except Exception as e:
            print(f"Unexpected error: {e}")
            break

def main():

    try:
        name = input("Enter player name: ")
        icon = input("Choose icon (1 char): ")

        fd, old_settings = init_terminal()

        conn = connect_db()
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute("SET implicit_cross_products = ON")
        player_id = get_or_create_player(cur, name, icon)
        viewer_id = player_id  # start by watching yourself
        clear()

        held_key = None
        key_timestamp = time.time()

        last_frame = time.time()
        while True:
            key = getch(timeout=0.01)
            if key:
                if key.lower() == 'q':
                    break
                elif key in '123456789':
                    viewer_id = int(key)
                elif key in '0' or key == str(player_id):
                    viewer_id = player_id
                else:
                    held_key = key  # update held key
                    key_timestamp = time.time()

            # Clear after 0.1 seconds of no press
            if time.time() - key_timestamp > 0.1:
                held_key = None

            now = time.time()
            if now - last_frame >= FRAME_INTERVAL:
                if held_key:
                    safe_update_input(cur, player_id, held_key)
                try:
                    name, x, y, dir_ = read_metadata(cur, viewer_id)                
                except Exception:
                    print(f"Cannot observe player {viewer_id} — does not exist?")
                    viewer_id = player_id
                    continue
                move_cursor_top()
                print("WASD to move, X to shoot, Q to quit,\n 1-9 to switch view to player with that ID, 0 to watch yourself")
                print()
                if name:
                    print(f"Viewing player {viewer_id}: {name}", end='\033[K\n')
                else:
                    print(f"Cannot view player {viewer_id} — does not exist.", end='\033[K\n')
                    viewer_id = player_id
                    continue  # skip rest of loop
                print()
                print(f"x={x:.2f}, y={y:.2f}, dir={dir_}", end='\033[K\n')
                print("\n=== Game View ===")
                render_screen(cur, viewer_id)
                last_frame = now

    finally:
        reset_terminal(fd, old_settings)
        os.system("stty echo")
        print("\nExiting...")

if __name__ == "__main__":
    main()
