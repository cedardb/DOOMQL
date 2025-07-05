#!/bin/bash
export LC_ALL=C
# === CONFIGURATION ===
DB_NAME="postgres"
DB_USER="postgres"
DB_HOST="localhost"
DB_PORT="5432"
export PGPASSWORD="postgres"

# Load the schema
psql -qtAX -h /tmp -U postgres -c '\timing' -f gamestate.sql


# Load custom data
for file in data/*; do
  psql -qtAX -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c '\timing' -f $file
done


# Game loop @ 30 FPS
while true; do
  psql -qtAX -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -p "$DB_PORT" -c '\timing' -f playerupdater.sql
  sleep 0.03
done
