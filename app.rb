require 'sinatra/base'
require 'redis'
require 'connection_pool'
require 'json'
require 'dotenv'

if !ENV['REDISCLOUD_URL'].nil?
	redis_connection_string = ENV["REDISCLOUD_URL"] 
end

if ENV['REMOTE_REDIS'] == "true"
	redis_connection_string =`heroku config | grep REDIS`.split(":")[1..-1].join(":").strip
end

REDIS = ConnectionPool.new(size: 5, timeout: 5) do
        if !redis_connection_string.nil?
        		puts "connecting to #{redis_connection_string}"
                uri = URI.parse(redis_connection_string)
                Redis.new(host: uri.host, port: uri.port, password: uri.password)
        else
        		puts "connecting to local redis"
                Redis.new
        end
end


class App < Sinatra::Base

	def get_id
		 REDIS.with{ |redis| redis.incr('next_id') }
	end

	get '/' do
		erb :index
	end

	post '/track/:site/json' do				
		request.body.rewind
		body = request.body.read
		data = (JSON.parse(body)).merge({t: Time.now.utc.to_i, id: get_id(), ip: request.ip})
		data[:event] = 'page' if data[:event].nil?		
		REDIS.with{ |redis| 
			redis.zadd(params['site'], "#{data[:t]}", data.to_json)					
			redis.sadd('sites', params['site'])
		}		
		headers['Access-Control-Allow-Origin'] = '*'		
		headers["Access-Control-Allow-Methods"] = 'POST'
		puts data
		"OK"
	end	

	def query(site=nil, min_time='-inf', max_time='+inf')
		starttime = Time.now.utc.to_f
		data = REDIS.with{ |redis| 			
			redis.zrangebyscore(site, min_time, max_time)
		}.map{|item|
			JSON.parse(item)
		}
	 	puts "query(#{site}, #{min_time}, #{max_time}) returning #{data.count} records in #{Time.now.utc.to_f-starttime} seconds"
	 	data
	end

	get '/:site/sessions_freq/:seconds?' do
		seconds = params['seconds'].to_i
		seconds = 60*60 if seconds == 0
		records = query(params['site'], Time.now.utc.to_i-seconds, Time.now.utc.to_i)

		data = records.inject({}){|obj, item|
			sid = item['sid']
			obj[sid] ||= 0
			obj[sid] += 1
			obj
		}.sort_by{|sid, count| 
			-count 
		}.map{|sid, count|
			urls = records.map{|event|
				[event['t'], event['url']] if event['sid'] == sid
			}.compact
			{sid: sid, count: count, urls: urls}
		}

		stats = {
			multi_page_visits: data.map{|session| 
				1 if session[:count] > 1 
			}.compact.reduce(:+),
			total_visits: data.map{|session| 
				1 if session[:count] 
			}.compact.reduce(:+),
			total_pages: records.count
		}	

		erb :site_sessions, locals: { data: data, stats: stats }
	end


	get '/:site/recent/:seconds' do
		bin_count = 50
		content_type 'text/json'

		min_time = Time.now.utc.to_i - params['seconds'].to_i
		max_time = Time.now.utc.to_i		
		bin_width = (1.0*(max_time-min_time)/bin_count).to_i

		data = query(params['site'], min_time, max_time)
	end

end