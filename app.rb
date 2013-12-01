require 'sinatra/base'
require 'redis'
require 'connection_pool'
require 'json'

REDIS = ConnectionPool.new(size: 5, timeout: 5) do
        if !ENV['REDISCLOUD_URL'].nil?
                uri = URI.parse(ENV["REDISCLOUD_URL"])
                Redis.new(host: uri.host, port: uri.port, password: uri.password)
        else
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
		"OK"
	end	

	def query(site=nil, min_time='-inf', max_time='+inf')
		REDIS.with{ |redis| 			
			redis.zrangebyscore(site, min_time, max_time)
		}.map{|item|
			JSON.parse(item)
		}
	end

	def sort_by_val(data)
		data.sort_by{|k, v|
			-v
		}
	end

	get '/:site/:seconds' do
		bin_count = 50
		content_type 'text/json'

		min_time = Time.now.utc.to_i - params['seconds'].to_i
		max_time = Time.now.utc.to_i		
		bin_width = (1.0*(max_time-min_time)/bin_count).to_i

		puts min_time, max_time

		data = query(params['site'], min_time, max_time)		
		data = data.map{|e| e.to_json }.join("\n<br><br>\n")
	end

	get '/:site/all' do
		content_type 'text/plain'
		REDIS.with{ |redis| 			
			redis.zrangebyscore(params['site'], '-inf', '+inf')
		}.join("\n<br><br>\n")
	end

end