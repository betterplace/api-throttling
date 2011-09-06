require 'rubygems'
require 'rack'
require File.expand_path(File.dirname(__FILE__) + '/handlers/handlers')

class ApiThrottling
  def initialize(app, options={})
    @app = app
    @options = {:requests_per_hour => 60, :cache=>:redis, :auth=>true}.merge(options)
    @handler = Handlers.cache_handler_for(@options[:cache])
    raise "Sorry, we couldn't find a handler for the cache you specified: #{@options[:cache]}" unless @handler
  end
  
  def call(env, options={})
    if @options[:urls]
      req = Rack::Request.new(env)
      # call the app normally cause the path restriction didn't match
      return @app.call(env) unless request_matches?(req)
    end

    if @options[:auth]
      auth = Rack::Auth::Basic::Request.new(env)
      return auth_required unless auth.provided?
      return bad_request unless auth.basic?
    end
    
    begin
      cache = @handler.new(@options[:cache])
      key = generate_key(env, auth)
      cache.increment(key)
      return over_rate_limit if cache.get(key).to_i > @options[:requests_per_hour]
    rescue Exception => e
      handle_exception(e)      
    end

    @app.call(env)   
  end
  
  def request_matches?(req)
    @options[:urls].any? do |url|
      "#{req.request_method} #{req.path}".match(url)
    end    
  end

  def generate_key(env, auth)
    return @options[:key].call(env, auth) if @options[:key]
    auth ? "#{auth.username}_#{Time.now.strftime("%Y-%m-%d-%H")}" : "#{Time.now.strftime("%Y-%m-%d-%H")}"
  end
  
  def bad_request
    body_text = "Bad Request"
    [ 400, { 'Content-Type' => 'text/plain', 'Content-Length' => body_text.size.to_s }, [body_text] ]
  end
  
  def auth_required
    body_text = "Authorization Required"
    [ 401, { 'Content-Type' => 'text/plain', 'Content-Length' => body_text.size.to_s }, [body_text] ]
  end
  
  def over_rate_limit
    body_text = "Over Rate Limit"
    retry_after_in_seconds = (60 - Time.now.min) * 60
    [ 503, 
      { 'Content-Type' => 'text/plain', 
        'Content-Length' => body_text.size.to_s, 
        'Retry-After' => retry_after_in_seconds.to_s 
      }, 
      [body_text]
    ]
  end

  def handle_exception(exception)
    if defined?(Rails) && Rails.env.development?
      raise exception
    else
      # FIXME notify hoptoad?
    end
  end
  
end


