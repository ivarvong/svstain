require 'open-uri'
require 'nokogiri'
require 'cgi'
require 'httparty'
require 'json'

RAND = Random.new

links = Nokogiri::HTML(open('http://dailyemerald.com')).css('#home-left-column a')

10000.times.each do 	
	link = links[RAND.rand(links.count)]	
	data = {site: 'dailyemerald.com', url: link.text}
	HTTParty.post('http://localhost:4567/track/json', body: data.to_json)	
end
