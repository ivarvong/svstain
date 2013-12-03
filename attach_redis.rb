require 'redis'
require 'uri'
require 'json'
print "connecting..."
uri = URI.parse(`heroku config | grep REDIS`.split(":")[1..-1].join(":").strip)
redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
print "done "
puts redis.info['used_memory_human']

data = redis.zrangebyscore('dailyemerald.com', '-inf', '+inf').map{|item|
	JSON.parse(item)
}
min = data.map{|i| i['t']}.min
max = data.map{|i| i['t']}.max
delta = max-min
bin_width = delta/30
puts min, max, delta, bin_width


bins = data.inject({}){|obj, item|
	bin_index = (item['t']-min)/bin_width
	bin_start = min + bin_index*bin_width	
	obj[bin_start] ||= []
	obj[bin_start] << item
	obj
}.map{|bin_start, bin|
	{start_time: bin_start, events: bin, count: bin.count}
}

#puts values

#@ticks = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇]
#min, range, scale = values.min, values.max - values.min, @ticks.length - 1
#puts values.map { |x| 
#	@ticks[(((x - min) / range) * scale).round] 
#}.join


#redis.monitor{ |line|
#	puts line
#}