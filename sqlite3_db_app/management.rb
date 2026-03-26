# frozen_string_literal: true

# management.rb — Generic SQLite3 table manager
# Supports any table; auto-UUID and auto-timestamps where columns exist.
#
# Usage (library):
#   db = Management.new('management.db')
#   db.init_schema!           # create repo table
#   db.insert('repo', name: 'dotforge', url: 'https://github.com/morganism/dotforge')
#   db.list('repo')
#   db.update('repo', '<uuid>', name: 'dotforge-v2')
#   db.delete('repo', '<uuid>')

require 'sqlite3'
require 'securerandom'
require 'time'

class Management
  VERSION = '1.0.0'

  # --- Schema definitions ---------------------------------------------------
  # Add new tables here; the CLI will pick them up automatically.
  SCHEMAS = {
    'repo' => <<~SQL
      CREATE TABLE IF NOT EXISTS repo (
        id        TEXT PRIMARY KEY,
        name      TEXT NOT NULL,
        directory TEXT,
        url       TEXT,
        created   TEXT,
        modified  TEXT
      );
    SQL
  }.freeze

  # Columns that get special auto-handling
  UUID_COL      = 'id'
  CREATED_COL   = 'created'
  MODIFIED_COL  = 'modified'

  attr_reader :db_path

  def initialize(db_path = 'management.db')
    @db_path = db_path
    @db = SQLite3::Database.new(db_path)
    @db.results_as_hash = true
    @db.execute('PRAGMA journal_mode=WAL;')
    @db.execute('PRAGMA foreign_keys=ON;')
  end

  # --- Schema management ----------------------------------------------------

  # Create all known tables that don't yet exist.
  def init_schema!
    SCHEMAS.each_value { |ddl| @db.execute(ddl) }
    self
  end

  # Create a single known table.
  def init_table!(table)
    ddl = SCHEMAS[table] or raise ArgumentError, "Unknown schema: #{table}"
    @db.execute(ddl)
    self
  end

  # Execute arbitrary DDL/DML. Use with care.
  def exec_sql(sql, *binds)
    @db.execute(sql, binds.flatten)
  end

  # Return list of user tables in the database.
  def tables
    @db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
        .map { |r| r['name'] }
  end

  # Return column info for a table: [{name:, type:, notnull:, pk:}, ...]
  def columns(table)
    validate_table!(table)
    @db.execute("PRAGMA table_info(#{quote_ident(table)});").map do |row|
      { name: row['name'], type: row['type'], notnull: row['notnull'] == 1, pk: row['pk'] == 1 }
    end
  end

  # Human-readable schema string.
  def schema(table)
    cols = columns(table)
    max  = cols.map { |c| c[:name].length }.max
    cols.map { |c|
      flags = []
      flags << 'PK'      if c[:pk]
      flags << 'NOT NULL' if c[:notnull]
      "  %-#{max}s  %-12s %s" % [c[:name], c[:type], flags.join(' ')]
    }.join("\n")
  end

  # --- CRUD -----------------------------------------------------------------

  # List rows. Optional WHERE clause built from a hash of {col => val}.
  # Returns array of hashes.
  def list(table, where: {}, order: nil, limit: nil)
    validate_table!(table)
    sql    = "SELECT * FROM #{quote_ident(table)}"
    binds  = []
    unless where.empty?
      clauses = where.map { |k, _| "#{quote_ident(k.to_s)} = ?" }
      sql    += " WHERE #{clauses.join(' AND ')}"
      binds   = where.values
    end
    sql += " ORDER BY #{order}" if order
    sql += " LIMIT #{limit.to_i}" if limit
    @db.execute(sql, binds)
  end

  # Find a single row by id column. Returns hash or nil.
  def find(table, id)
    validate_table!(table)
    col_names = columns(table).map { |c| c[:name] }
    id_col    = col_names.include?(UUID_COL) ? UUID_COL : col_names.first
    rows = @db.execute(
      "SELECT * FROM #{quote_ident(table)} WHERE #{quote_ident(id_col)} = ? LIMIT 1;",
      [id]
    )
    rows.first
  end

  # Insert a row. Automatically sets id (UUID) and created/modified timestamps
  # if those columns exist and no value is provided.
  # Returns the new row's id.
  def insert(table, data)
    validate_table!(table)
    data      = normalise(data)
    col_names = columns(table).map { |c| c[:name] }

    if col_names.empty?
      raise ArgumentError,
            "Table '#{table}' does not exist or has no columns. Run: mgmt init"
    end

    data[UUID_COL]     = SecureRandom.uuid if col_names.include?(UUID_COL)     && !data.key?(UUID_COL)
    now = Time.now.utc.iso8601
    data[CREATED_COL]  = now               if col_names.include?(CREATED_COL)  && !data.key?(CREATED_COL)
    data[MODIFIED_COL] = now               if col_names.include?(MODIFIED_COL) && !data.key?(MODIFIED_COL)

    # Only keep keys that exist as columns
    data = data.select { |k, _| col_names.include?(k) }

    if data.empty?
      raise ArgumentError,
            "None of the supplied keys match columns in '#{table}'. " \
            "Columns are: #{col_names.join(', ')}"
    end

    cols  = data.keys.map { |k| quote_ident(k) }.join(', ')
    marks = (['?'] * data.size).join(', ')
    @db.execute("INSERT INTO #{quote_ident(table)} (#{cols}) VALUES (#{marks});", data.values)
    data[UUID_COL] || @db.last_insert_row_id
  end

  # Update a row by id. Automatically updates the modified timestamp if column exists.
  # Returns number of rows affected.
  def update(table, id, data)
    validate_table!(table)
    data      = normalise(data)
    col_names = columns(table).map { |c| c[:name] }
    id_col    = col_names.include?(UUID_COL) ? UUID_COL : col_names.first

    data[MODIFIED_COL] = Time.now.utc.iso8601 if col_names.include?(MODIFIED_COL)

    # Only keep keys that exist as columns and are not the PK
    data = data.select { |k, _| col_names.include?(k) && k != id_col }
    raise ArgumentError, 'Nothing to update' if data.empty?

    sets  = data.keys.map { |k| "#{quote_ident(k)} = ?" }.join(', ')
    @db.execute(
      "UPDATE #{quote_ident(table)} SET #{sets} WHERE #{quote_ident(id_col)} = ?;",
      data.values + [id]
    )
    @db.changes
  end

  # Delete a row by id. Returns number of rows affected.
  def delete(table, id)
    validate_table!(table)
    col_names = columns(table).map { |c| c[:name] }
    id_col    = col_names.include?(UUID_COL) ? UUID_COL : col_names.first
    @db.execute(
      "DELETE FROM #{quote_ident(table)} WHERE #{quote_ident(id_col)} = ?;",
      [id]
    )
    @db.changes
  end

  # Row count for a table.
  def count(table)
    validate_table!(table)
    @db.execute("SELECT COUNT(*) AS n FROM #{quote_ident(table)};").first['n']
  end

  # --- Helpers --------------------------------------------------------------

  def close
    @db.close
  end

  private

  def normalise(data)
    data.transform_keys(&:to_s)
  end

  # Raises if table name contains suspicious characters (SQL injection guard).
  def validate_table!(name)
    raise ArgumentError, "Invalid table name: #{name}" unless name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
  end

  # Double-quote an identifier (table/column name).
  def quote_ident(name)
    %("#{name.gsub('"', '""')}")
  end
end
