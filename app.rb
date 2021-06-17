#!/home/nagonago/.rbenv/versions/2.7.3/bin/ruby
# #!/usr/bin/ruby
# encoding: utf-8

require 'bundler'
Bundler.require
# require 'bundler/setup'
require 'active_support'
require 'active_support/core_ext'
require 'sinatra'
require 'sqlite3'
require 'gruff'

interval = 5.minutes

def db
  _db = SQLite3::Database.new('db/temp.db')
  sql = <<-SQL
    create table data (
      datetime TIMESTAMP primary key,
      temp real,
      hemi real
    );
  SQL

  begin
    _db.execute(sql)
  rescue SQLite3::SQLException => e
    raise if e.message != 'table data already exists'
  end
  _db
end

def last_timestamp
  select_sql = 'SELECT max(datetime) FROM data'
  db.execute(select_sql) do |row|
    return row[0]
  end
  nil
end

def select_data(limit, order = 'desc')
  rows = []
  if order == 'asc'
    select_sql = 'SELECT min(datetime) FROM data order by datetime desc limit ?'
    min = 0
    db.execute(select_sql, limit) do |row|
      min = row[0]
    end
    select_sql = 'SELECT * FROM data where datetime >= ? order by datetime asc limit ?'
    db.execute(select_sql, min, limit) do |row|
      rows << row
    end
  else
    select_sql = "SELECT * FROM data order by datetime #{order} limit ?"
    db.execute(select_sql, limit) do |row|
      rows << row
    end
  end
  rows
end

def calc_discomfort(temp, hemi)
  0.81 * temp + hemi * 0.01 * (0.99 * temp - 14.3) + 46.3
end

def insert_data(temp, hemi)
  insert_sql = 'INSERT INTO data VALUES(?, ?, ?)'
  begin
    db.execute(insert_sql, Time.now.to_i, temp, hemi)
  rescue SQLite3::ConstraintException
    raise
  end
end

get '/' do
  timestamp = last_timestamp
  temp = params['temp']
  hemi = params['hemi']
  if timestamp.nil?
    insert_data(temp, hemi) unless temp.nil? || hemi.nil?
  elsif Time.at(timestamp) + interval < Time.now
    insert_data(temp, hemi) unless temp.nil? || hemi.nil?
  end
  limit = params['limit'].to_i || 1
  if limit > 1
    rows = select_data(limit, order = 'asc')
    hash_map = {}
    rows.each_with_index do |r, idx|
      size = if (rows.size / 10).zero?
               1
             else
               rows.size / 10
             end
      hash_map[idx] = Time.at(r[0]).strftime('%H:%M') if (idx % size).zero?
    end
    g = Gruff::Line.new
    g.title = 'Temperature'
    g.labels = hash_map
    g.data :Temperature, rows.map { |r| r[1] }
    g.write('db/temp.png')

    g = Gruff::Line.new
    g.title = 'Humidity'
    g.labels = hash_map
    g.data :Humidity, rows.map { |r| r[2] }
    g.write('db/hemi.png')

    g = Gruff::Line.new
    g.title = 'Discomfort Index'
    g.labels = hash_map
    g.data :DiscomfortIndex, rows.map { |r| calc_discomfort(r[1], r[2]) }
    g.write('db/index.png')
  end

  [
    '<html><head><title>温度・湿度</title></head><body>',
    '不快指数: <br />
・55以下：寒い<br />
・55～60：肌寒い<br />
・60～65：何も感じない<br />
・65～70：快い<br />
・70～75：暑くない<br />
・75～80：やや暑い<br />
・80～85：暑くて汗が出る<br />
・85以上：暑くてたまらない<br />
GET で ?limit=288 を付けるとちょうど1日分くらいになる<br />
',

    '<br />',
    limit > 1 ? '<img src="db/temp.png"><br /><img src="db/hemi.png"><br /><img src="db/index.png"><br />' : '',
    # select_data(limit, 'asc').map do |row|
    #  "#{Time.at(row[0])}, 温度: #{row[1]}℃, 湿度: #{row[2]}%, 不快指数: #{calc_discomfort(row[1], row[2])}"
    # end.join('<br />'),
    '</body></html>'
  ].join("\n")
end
