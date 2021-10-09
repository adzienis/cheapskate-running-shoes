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
  scope :with_size, ->(size:, width: 'D') { from('shoes, json_each(shoes.sizes)').where("json_each.value IS '#{size} #{width}'") }
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
    sized_shoes = Shoe.with_size(size: '10.0')
    all_sized_shoes = Shoe.all_sizes

    shoes = sized_shoes + all_sized_shoes
    
    sorted = shoes.sort{|a,b| a.price <=> b.price}
  end
end

class HTMLFormatter

  def format(shoes)
    <<-HTML
      <html>
      
      <body style='display: flex; flex-direction: column; align-items: center'>
        <div>
          #{shoes.map do |shoe|
            "<div>#{shoe.name}: <b>#{shoe.price}</b> </div>"
          end.join("\n")
           }
        </div>
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

      #.each do |shoe|
      #p "#{shoe.name.to_s.ljust(55)} | #{shoe.link.to_s.ljust(90)} | #{shoe.price}"
      #end
  end

end

def main
  report_generator = ReportGenerator.new

  report_generator.build_report(HTMLFormatter.new)

end and main


require 'rack/cache'
require 'rack/handler/puma'

app = Rack::Builder.app do
  root = File.expand_path(File.dirname(__FILE__))

  use Rack::CommonLogger
  use Rack::ContentLength
  use Rack::ContentType
  use Rack::Lint
  use Rack::Static, :urls => [""], :root => @root, :index => "index.html"
  run lambda {|env| [ 200, {'Content-Type' => 'text/plain'}, File.open('index.html', File::RDONLY) ]}
end

# Rack::Handler::Puma.run app


