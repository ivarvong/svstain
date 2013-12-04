require 'sinatra/base'
require 'redis'
require 'connection_pool'
require 'json'
require 'celluloid/autostart'
require 'active_support/all'

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
		"Hello there."
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

	get '/:site/top/:seconds?' do
		seconds = params['seconds'].to_i
		seconds = 3600 if seconds == 0 # 10 minutes if no param
		data = query(params['site'], Time.now.utc.to_i-seconds, Time.now.utc.to_i)
		data = data.inject({}){|obj, item|
			obj[item['url']] ||= 0
			obj[item['url']] += 1
			obj
		}.sort_by{|k, v| -v}
		erb :top, locals: {data: data, seconds: seconds, site: params['site']}
	end

	get '/:site/recent/:seconds' do
		bin_count = 50
		content_type 'text/json'

		min_time = Time.now.utc.to_i - params['seconds'].to_i
		max_time = Time.now.utc.to_i		
		bin_width = (1.0*(max_time-min_time)/bin_count).to_i

		data = query(params['site'], min_time, max_time)
	end

	get '/:site/today' do
		erb :site_today, locals: {site: params['site'], sum: !params['sum'].nil?}				
	end

	get '/:site/v1/day/:datestr' do
		content_type 'text/json'
		
		start_time = Date.parse(params['datestr']).in_time_zone('Pacific Time (US & Canada)')		
		start_time = start_time.at_midnight()		
		start_time = start_time.to_i 
		
		end_time = start_time + 24.hours.to_i - 1
		
		records = query(params['site'], start_time, end_time)

		processing_start = Time.now.utc.to_f

		bin_width = 60 # seconds		
		bins = (start_time..end_time).step(bin_width).inject({}){|obj, start_time| 
			obj[start_time] = {records: [], count: 0}
			obj
		}
		records.each do |record|			
			# find the "left hand side" of the current minute. 
			# bin_width MUST BE 60 for this to work.
			start_time = Time.at(record['t']).change(sec: 0).to_i 
			bins[start_time][:count] += 1
		end
		
		output = bins.keys.map{|start_time|
			[start_time, bins[start_time][:count]]
		}

		output_str = output.to_json

		puts "#{request.path} for #{records.count} events in #{Time.now.utc.to_f - processing_start} sec."

		output_str
	end

	get "/:site/daily-1" do
		min_time = Time.now.utc.to_i - 1.5*43200
		data = query(params['site'], min_time)	
		total_views = data.count
		average_rate = total_views/(1.0*data.last['t']-data.first['t'])
		puts ({total: total_views, average_rate: average_rate}.to_json)
		data.map!{|event|
			delta = event['t']-min_time
			total_so_far = data.select{|item| item['t'] < event['t']}.count
			pace = (total_so_far) - (average_rate*delta)
			event.merge!({delta: delta, total_so_far: total_so_far, pace: pace})
		}
		data.map{|event|
			[event['t'], event[:delta], event[:total_so_far], event[:pace]].join("\t")
		}.join("\n")
	end

end