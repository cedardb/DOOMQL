import os

EXAMPLE_MAP = """\
################
#......#.......#
#..##..#..###..#
#......#.......#
#####..#######.#
#..............#
#..##########..#
#..............#
################
"""

def write_example_map(filepath):
    with open(filepath, 'w') as f:
        f.write(EXAMPLE_MAP)

def txt_to_sql(filepath, output_sql="map_output.sql", table_name="map"):
    with open(filepath, 'r') as f:
        lines = [line.rstrip('\n') for line in f]

    sql_statements = [
        f"INSERT INTO {table_name} (x, y, tile) VALUES"
    ]

    inserts = []
    for y, line in enumerate(lines):
        for x, char in enumerate(line):
            if char in ('.', '#', ' '):  # Allowed tiles
                inserts.append(f"({x}, {y}, '{char}')")

    # Add inserts and semicolon at the end
    sql_statements.append(",\n  ".join(inserts) + ";")

    with open(output_sql, 'w') as f:
        f.write("\n".join(sql_statements))

    print(f"Map from '{filepath}' successfully written to '{output_sql}'.")

if __name__ == "__main__":
    map_file = "example_map.txt"
    sql_output_file = "map_output.sql"

    if not os.path.exists(map_file):
        print("Writing demo map to example_map.txt...")
        write_example_map(map_file)

    txt_to_sql(map_file, sql_output_file)