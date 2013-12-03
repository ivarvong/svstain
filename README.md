#svstain

There are two parts to this code:

- Push incoming events (pageviews) to a Redis sorted set
- Write Ruby code to analyze it.

Why reinvent a database in Ruby, you say? For fun, basically. It's a spike.

---

How to get data into it: 
	```POST /track/somesite.com/json``` with a JSON payload. The app will inject a unique ID, a timestamp, and the request's IP. It then saves this hashmap as a JSON blob into a sorted set in Redis by the UTC seconds, allowing dumb but fairly performant range queries based on event time.
	
The ```query()``` function takes three params (site, min_time, max_time) and runs a query. It returns an array of hashmaps.

So far, I'm focused on two kinds of data wrangling:

#### Event-based analysis

The JavaScript creates a 2-year cookie for the "user id" -- hopefully this persists close to forever for a user. A second "session id" is created for the length of the browser session. These are sent in the JSON payload, along with the current path and referrer.

One of the questions I'm taking a swing at is how people move through the site, how the pages they visit are related, which pages they navigate through (topic pages, author pages, home page, etc) in a effort to improve those experiences.

I also want to be able to calculate metrics like [DAU/MAU](http://stdout.be/2013/08/26/cargo-cult-analytics/) and after a while, I hope I'll be able to do this.

Essentially, we want to do a group by for a user id or session id, or both, and poke at the events within those bins.

#### Time-based analysis

I started with 60-second bins. The code is not super fast, but it'll do ~25,000 events/seconds right now. This is just fast enough to be useable in a web request without something more clever. It is not efficent -- basically all of the data is in the past and isn't going to change, so caching would make sense. But I don't want to juggle different coarsenesses of bins for now. Probably will eventually.

And that's about it for now. More to come.