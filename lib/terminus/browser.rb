module Terminus
  class Browser
    
    include Timeouts
    
    LOCALHOST = /localhost|0\.0\.0\.0|127\.0\.0\.1/
    
    def initialize(controller)
      @controller     = controller
      @attributes     = {}
      @docked         = false
      @namespace      = Faye::Namespace.new
      @ping_callbacks = []
      @results        = {}
      add_timeout(:dead, Timeouts::TIMEOUT) { drop_dead! }
    end
    
    def id
      @attributes['id']
    end
    
    def docked?
      @docked
    end
    
    def ping!(message)
      remove_timeout(:dead)
      add_timeout(:dead, Timeouts::TIMEOUT) { drop_dead! }
      @attributes = @attributes.merge(message)
      detect_dock_host
      @ping_callbacks.each do |ping|
        ping.complete! if ping === message
      end
      @ping_callbacks.delete_if { |p| p.complete? }
    end
    
    def result!(message)
      @results[message['commandId']] = message['result']
    end
    
    def visit(url)
      url = url.gsub(LOCALHOST, @controller.dock_host)
      instruct(:visit, url)
      await_ping('url' => url)
    end
    
    def find(xpath)
      instruct_and_wait(:find, xpath).map { |id| Node.new(self, id) }
    end
    
    def return_to_dock
      visit "http://#{@controller.dock_host}:#{DEFAULT_PORT}/"
    end
    
    def instruct(*command)
      id = @namespace.generate
      messenger.publish(channel, 'command' => command, 'commandId' => id)
      id
    end
    
    def wait_for_result_or_ping(id)
      wait_with_timeout(:result, 2) { @results.has_key?(id) }
      @results.delete(id)
    rescue Timeouts::TimeoutError
      await_ping
    end
    
  private
    
    def messenger
      @controller.messenger
    end
    
    def channel
      "/terminus/clients/#{id}"
    end
    
    def drop_dead!
      @controller.drop_browser(self)
    end
    
    def await_ping(params = {}, &block)
      ping = PingMatch.new(params)
      @ping_callbacks << ping
      done = false
      ping.callback { done = true }
      while not done; sleep 0.1; end
    end
    
    def instruct_and_wait(*command)
      id = instruct(*command)
      wait_with_timeout(:result) { @results.has_key?(id) }
      @results.delete(id)
    end
    
    def detect_dock_host
      uri = URI.parse(@attributes['url'])
      return unless uri.port == DEFAULT_PORT
      @docked = true
      @controller.dock_host = uri.host
    end
    
  end
end
