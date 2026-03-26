# frozen_string_literal: true

# spec/management_spec.rb

require 'tmpdir'
require_relative '../management'

RSpec.describe Management do
  let(:db_path) { File.join(Dir.tmpdir, "mgmt_test_#{SecureRandom.hex(4)}.db") }
  let(:db)      { described_class.new(db_path) }

  after { db.close; File.unlink(db_path) if File.exist?(db_path) }

  describe '#init_schema!' do
    it 'creates the repo table' do
      db.init_schema!
      expect(db.tables).to include('repo')
    end

    it 'is idempotent' do
      2.times { db.init_schema! }
      expect(db.tables.count('repo')).to eq(1)
    end
  end

  describe '#columns' do
    before { db.init_schema! }

    it 'returns column metadata for repo' do
      cols = db.columns('repo')
      names = cols.map { |c| c[:name] }
      expect(names).to eq(%w[id name directory url created modified])
    end

    it 'identifies the primary key' do
      pk = db.columns('repo').find { |c| c[:pk] }
      expect(pk[:name]).to eq('id')
    end
  end

  describe '#insert' do
    before { db.init_schema! }

    it 'inserts a row and returns a UUID' do
      id = db.insert('repo', name: 'dotforge', url: 'https://github.com/morganism/dotforge')
      expect(id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'auto-populates created and modified timestamps' do
      id  = db.insert('repo', name: 'test')
      row = db.find('repo', id)
      expect(row['created']).not_to be_nil
      expect(row['modified']).not_to be_nil
    end

    it 'allows custom id override' do
      custom = '00000000-0000-0000-0000-000000000001'
      db.insert('repo', id: custom, name: 'custom')
      row = db.find('repo', custom)
      expect(row['id']).to eq(custom)
    end
  end

  describe '#list' do
    before do
      db.init_schema!
      db.insert('repo', name: 'alpha', url: 'http://a.com')
      db.insert('repo', name: 'beta',  url: 'http://b.com')
      db.insert('repo', name: 'gamma', url: 'http://b.com')
    end

    it 'returns all rows' do
      expect(db.list('repo').size).to eq(3)
    end

    it 'filters by column value' do
      rows = db.list('repo', where: { url: 'http://b.com' })
      expect(rows.map { |r| r['name'] }).to contain_exactly('beta', 'gamma')
    end

    it 'respects limit' do
      expect(db.list('repo', limit: 2).size).to eq(2)
    end
  end

  describe '#find' do
    before { db.init_schema! }

    it 'returns the row by id' do
      id  = db.insert('repo', name: 'find_me')
      row = db.find('repo', id)
      expect(row['name']).to eq('find_me')
    end

    it 'returns nil for unknown id' do
      expect(db.find('repo', 'nosuchid')).to be_nil
    end
  end

  describe '#update' do
    before { db.init_schema! }

    it 'updates specified fields' do
      id = db.insert('repo', name: 'old_name', url: 'http://old.com')
      db.update('repo', id, name: 'new_name')
      expect(db.find('repo', id)['name']).to eq('new_name')
    end

    it 'bumps the modified timestamp' do
      id  = db.insert('repo', name: 'ts_test')
      old = db.find('repo', id)['modified']
      sleep(1.1)
      db.update('repo', id, name: 'ts_test_2')
      expect(db.find('repo', id)['modified']).not_to eq(old)
    end

    it 'returns 0 for unknown id' do
      expect(db.update('repo', 'nosuchid', name: 'x')).to eq(0)
    end
  end

  describe '#delete' do
    before { db.init_schema! }

    it 'removes the row' do
      id = db.insert('repo', name: 'to_delete')
      db.delete('repo', id)
      expect(db.find('repo', id)).to be_nil
    end

    it 'returns 1 on success and 0 on miss' do
      id = db.insert('repo', name: 'x')
      expect(db.delete('repo', id)).to eq(1)
      expect(db.delete('repo', id)).to eq(0)
    end
  end

  describe '#count' do
    before { db.init_schema! }

    it 'counts rows' do
      3.times { |i| db.insert('repo', name: "repo_#{i}") }
      expect(db.count('repo')).to eq(3)
    end
  end

  describe 'SQL injection guard' do
    it 'rejects table names with dangerous characters' do
      expect { db.list('repo; DROP TABLE repo--') }.to raise_error(ArgumentError)
    end
  end
end
