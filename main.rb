#!/bin/ruby

require 'set'
require 'nokogiri'
require 'open-uri'

require 'sqlite3'
require 'active_record'


# Sqlite database for absolutely no reason whatsoever, yet...
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

ActiveRecord::Schema.define do
  create_table "shoes", force: :cascade do |t|
    t.string   "name"
    t.float   "price"
    t.string   "sizes"
    t.text   "link"
  end
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Shoe < ApplicationRecord
  scope :with_sizes, ->(sizes:) { from('shoes, json_each(shoes.sizes)').where("json_each.value IN (#{sizes.map{|size| "'#{size[:length]} #{size[:width]}'"}.join(",")})") }
  scope :all_sizes, -> { where('json_array_length(shoes.sizes) = 0') }
end

class Parser

  def initialize(url: 'https://www.runningwarehouse.com/catpage-SALEMS.html')
    @url = url
  end

  def fetch
    @doc = Nokogiri::HTML(URI.open(@url))
  end

  def parse

    # probably better if we use a strategy or just dependency inject instead of hard coding
    @doc.css('div.product_wrapper').each do |link|
      inner = Nokogiri::HTML(link.to_html)

      href = inner.css('.image_wrap > a').first['href']
      sizes = inner.css('.sizes').first

      inner.css('span.sale').each do |inner_link|
        match = /\$(.*)/.match(inner_link.content)
        sizes_match =  (sizes&.content || '').scan(/(\d+\.?\d+ [A-Z])/).flatten
        shoe_name = link['data-gtm_impression_name']
        price = link['data-gtm_impression_price']
        Shoe.create(name: shoe_name, price: price, sizes: sizes_match.to_json, link: href) if match
      end
    end
  end


  def fetch_and_parse
    fetch
    parse
  end
end

class ShoeStats
  def top_shoes
    sized_shoes = Shoe.with_sizes(sizes: [{ length: '10.0', width: 'D'}, { length: '10.5', width: 'D' }])
    all_sized_shoes = Shoe.all_sizes

    shoes = sized_shoes + all_sized_shoes
    
    sorted = shoes.sort{|a,b| a.price <=> b.price}
  end
end

class HTMLFormatter

  def row_format(shoe)
    cols_arr = [ "<a href='#{shoe.link}'>#{shoe.name} </a>",
            "<b>#{shoe.price}</b>",
            "<b>#{JSON.parse(shoe.sizes).join(", ")}</b>" ]
    
    cols = cols_arr.map{|c| "<td>#{c}</td>"}
    
    "<tr>#{cols.join("\n")}</tr>"
  end

  def table_entries(shoes)
    shoes.map{ |shoe| row_format(shoe) }.join("")
  end

  def format(shoes)
    <<~HTML
      <html>
        <head>
          <link rel="stylesheet" href="https://cdn.simplecss.org/simple.min.css">
        </head>
        <body>
        <h3> Cheapest Shoes </h3>
        <table>
        <tr>
        <th> Shoe </th>
        <th> Price </th>
        <th> Sizes (includes 10.0, 10.5) </th>
        </tr>
        #{table_entries(shoes)}
        </table>
        </body>
      </html>
    HTML
  end
end


class ReportGenerator

  def build_report(formatter)
    parser = Parser.new
    shoe_stats = ShoeStats.new

    parser.fetch_and_parse
    
    top_shoes = shoe_stats.top_shoes.take(10)

    formatted = formatter.format(top_shoes)

    File.open('index.html', 'w') do |f|
      f.write formatted
    end
  end

end

def main
  report_generator = ReportGenerator.new

  report_generator.build_report(HTMLFormatter.new)

end and main

