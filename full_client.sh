#!/bin/bash
export LC_ALL=C
DB_NAME="postgres"
DB_USER="postgres"
DB_HOST="localhost"
DB_PORT="5432"
export PGPASSWORD="postgres"

# === SQL Helpers ===
get_player_id_query() {
  echo "SELECT id FROM player WHERE name = '$1';"
}
create_player_query() {
  echo "INSERT INTO player(x, y, dir, icon, name) VALUES (random() * 9 + 1, random() * 9 + 1, 0, '$2', '$1') RETURNING id;"
}
update_query() {
  echo "INSERT INTO inputs(player_id, action) VALUES ($player_id,'$key') ON CONFLICT(player_id) DO UPDATE SET action = '$key';"
}
read_state() {
  IFS='|' read -r player_x player_y player_dir <<< "$(psql -qtAX -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c "SELECT x, y, dir FROM player WHERE id = $player_id LIMIT 1;")"
}
render_view() {
  psql -qX -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c '\timing' -c "select * from screen where player_id = $player_id order by y;"
}

# === Setup ===
cleanup() {
  stty sane
  tput cnorm
  echo -e "\nExiting..."
  exit 0
}
trap cleanup SIGINT SIGTERM SIGKILL

# === Initialization ===
echo -n "Enter player name: "
read player_name
echo -n "Choose icon (1 char): "
read icon

tput civis
stty -echo -icanon time 0 min 0


# Try to get player ID
player_id=$(psql -qtAX -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c "$(get_player_id_query "$player_name")")

if [[ -z "$player_id" ]]; then
  echo "Creating new player '$player_name'..."
  player_id=$(psql -qtAX -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c "$(create_player_query "$player_name" "$icon")")
else
  echo "Reconnected as '$player_name' (ID=$player_id)"
fi

read_state || { echo "Failed to read player state."; cleanup; }

# === Main Loop ===
echo "W/S to move up/down, A/D to rotate. Q to quit."

while true; do
  key=""
  read -rsn1 -t 0.0005 key  # non-blocking read with 50ms timeout

  if [[ "$key" == "q" || "$key" == "Q" ]]; then
    cleanup
  elif [[ -n "$key" ]]; then
    sql=$(update_query "$key")
    psql -qtAX -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c "$sql" >/dev/null
  fi

  read_state || { echo "Failed to read player state."; cleanup; }

    # Move cursor to top-left corner (without clearing screen)
    printf "\033[H"

    echo "W/S to move up/down, A/D to rotate. Q to quit."
    echo "x=$player_x"
    echo "y=$player_y"
    echo "dir=$player_dir"
    echo -e "\n=== Game View ==="
    render_view
  #sleep 0.01  # control render frame rate (10 FPS)
done