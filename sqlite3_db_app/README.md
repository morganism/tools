# mgmt — SQLite3 Table Manager

Generic SQLite3 CRUD CLI + library. Works out of the box with the bundled
`repo` table; trivially extended to any table you define.

## Install

```sh
gem install sqlite3 thor
chmod +x mgmt
```

## Quick start

```sh
# Create the database and repo table
./mgmt init

# Add a repo
./mgmt repo add --name memvault --url https://github.com/morganism/memvault \
                --directory ~/src/memvault

# List all repos
./mgmt repo list

# Show a single row (short UUID prefix works too if unique)
./mgmt repo show <uuid>

# Filter by column
./mgmt repo list --name memvault

# Update
./mgmt repo update <uuid> --url https://github.com/morganism/memvault-v2

# Delete
./mgmt repo delete <uuid>

# Count
./mgmt repo count
```

## Meta commands

```sh
./mgmt tables              # list all tables in the DB
./mgmt schema repo         # show column layout
./mgmt sql "SELECT * FROM repo WHERE url LIKE '%github%'"
./mgmt version
```

## Use a different database

```sh
./mgmt --db /var/db/tools.db init
./mgmt --db /var/db/tools.db repo list
```

## Adding a new table

1. Add a DDL entry to `Management::SCHEMAS` in `management.rb`:

```ruby
SCHEMAS = {
  'repo' => <<~SQL ... SQL,

  'project' => <<~SQL
    CREATE TABLE IF NOT EXISTS project (
      id       TEXT PRIMARY KEY,
      name     TEXT NOT NULL,
      status   TEXT DEFAULT 'active',
      notes    TEXT,
      created  TEXT,
      modified TEXT
    );
  SQL
}.freeze
```

2. Run `./mgmt init` — the new table is created if it doesn't exist.

3. All CRUD commands work immediately:

```sh
./mgmt project add --name "lambda-api-webhook" --status wip
./mgmt project list
./mgmt project list --status wip
```

`id`, `created`, and `modified` are handled automatically when those column
names exist in the table.

## Library usage

```ruby
require_relative 'management'

db = Management.new('management.db')
db.init_schema!

id = db.insert('repo', name: 'dotforge', url: 'https://github.com/morganism/dotforge')
db.list('repo', where: { name: 'dotforge' })
db.update('repo', id, directory: '~/src/dotforge')
db.delete('repo', id)
db.close
```

## Tests

```sh
gem install rspec
rspec spec/management_spec.rb
```

## Files

| File                        | Purpose                         |
|-----------------------------|---------------------------------|
| `management.rb`             | Core library (no CLI deps)      |
| `mgmt`                      | Thor CLI entry point            |
| `Gemfile`                   | Gem dependencies                |
| `spec/management_spec.rb`   | RSpec test suite                |
