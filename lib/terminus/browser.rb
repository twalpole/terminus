module Terminus
  class Browser

    include Timeouts
    attr_reader :connector
    attr_writer :sockets

    extend Forwardable
    def_delegators :@user_agent, :os, :version

    def initialize(controller, id)
      @controller = controller
      @attributes = {'id' => id}
      @docked     = false
      @frames     = Set.new
      @namespace  = Faye::Namespace.new
      @results    = {}

      add_timeout(:dead, Timeouts::TIMEOUT) { drop_dead! }
    end

    def ===(params)
      return docked? if params == :docked
      return params == id if String === params
      return false if @parent
      return false unless @user_agent

      params.all? do |name, value|
        property = __send__(name)
        value === property
      end
    end

    def ask(command, retries = RETRY_LIMIT)
      debug(:ask, id, command)
      value = if @connector
        message = Yajl::Encoder.encode('commandId' => '_', 'command' => command)
        response = @connector.request(message)
        if response.nil?
          retries == false ? false : ask(command)
        else
          result_hash = Yajl::Parser.parse(response)
          result_hash['value']
        end
      else
        command_id = tell(command)
        result_hash = wait_with_timeout(:result) { result(command_id) }
        result_hash[:value]
      end
      debug(:val, id, command, value)
      raise ObsoleteElementError if value.nil?
      value
    rescue Timeouts::TimeoutError => e
      raise e if retries == 1
      ask(command, retries - 1)
    end

    def current_path
      URI.parse(current_url).path
    end

    def current_url
      url = @attributes['url']
      return '' unless url
      rewrite_local(ask([:current_url]))
    end

    def debug(*args)
      p args if Terminus.debug
    end

    def debugger
      Client::PhantomJS.debugger if name == 'PhantomJS'
      Readline.readline('Driver paused, press ENTER to continue')
    end

    def docked?
      @docked
    end

    def evaluate_script(expression)
      ask([:evaluate, expression])
    end

    def execute_script(expression)
      @connector ? ask([:execute, expression]) : tell([:execute, expression])
      nil
    end

    def find_css(css, driver = nil)
      ask([:find_css, css, false]).map { |id| Node.new(self, id, driver) }
    end

    def find_xpath(xpath, driver = nil)
      ask([:find_xpath, xpath, false]).map { |id| Node.new(self, id, driver) }
    end

    def frame!(frame_browser)
      @frames.add(frame_browser)
    end

    def frames
      @frames.to_a
    end

    def html
      ask([:body])
    end
    alias :body :html

    def id
      @attributes['id']
    end

    def infinite_redirect?
      return @infinite_redirect unless @connector
      evaluate_script('!!window.TERMINUS_INFINITE_REDIRECT')
    end

    def name
      return 'PhantomJS' if @user_agent.to_str =~ /\bPhantomJS\b/
      @user_agent.browser
    end

    def page_id
      @attributes['page']
    end

    def ping!(message)
      debug(:ping, id)
      debug(:recv, message)

      remove_timeout(:dead)
      add_timeout(:dead, Timeouts::TIMEOUT) { drop_dead! }

      @attributes['raw_url'] = message['url']
      message['url'] = rewrite_local(message['url'])

      @attributes = @attributes.merge(message)
      @user_agent = UserAgent.parse(message['ua'])
      detect_dock_host

      @infinite_redirect = message['infinite']

      if id =~ /\//
        @parent = Terminus.browser(id.gsub(/\/[^\/]+$/, ''))
        @parent.frame!(self) unless @parent == self
      end

      start_connector if message['sockets'] and sockets?

      @ping = true
    end

    def raw_url
      @attributes['raw_url']
    end

    def reset!
      if url = @attributes['url']
        uri = URI.parse(url)
        visit("http://#{uri.host}:#{uri.port}/")
      end
      ask([:clear_cookies])

      @attributes.delete('url')
    end

    def response_headers
      Headers.new(evaluate_script('TERMINUS_HEADERS'))
    end

    def result!(message)
      debug(:result, id, message['commandId'], message['result'])
      @results[message['commandId']] = {:value => message['result']}
    end

    def result(id)
      return nil unless @results.has_key?(id)
      @results.delete(id)
    end

    def return_to_dock
      return unless @dock_host
      visit("http://#{@dock_host}:#{Terminus.port}/")
    end

    def save_screenshot(path, options = {})
      raise Capybara::NotSupportedByDriverError.new unless name == 'PhantomJS'
      Client::PhantomJS.save_screenshot(path, options)
    end

    def sockets?
      @sockets.nil? ? Terminus.sockets != false : @sockets
    end

    def source
      evaluate_script('TERMINUS_SOURCE')
    end

    def status_code
      evaluate_script('TERMINUS_STATUS')
    end

    def tell(command)
      command_id = @namespace.generate
      debug(:tell, id, command, command_id)
      messenger.publish(command_channel, 'command' => command, 'commandId' => command_id)
      command_id
    end

    def title
      ask([:title])
    end

    def visit(url, retries = RETRY_LIMIT)
      close_frames!
      uri = @controller.rewrite_remote(url, @dock_host)
      uri.host = @dock_host if uri.host =~ LOCALHOST
      @controller.visit_url(uri.to_s)

      if @connector
        ask([:visit, uri.to_s], false)
        @connector.drain_socket
        @attributes['url'] = rewrite_local(uri)
      else
        tell([:visit, uri.to_s])
        wait_for_ping
      end

      if infinite_redirect?
        @infinite_redirect = nil
        raise Capybara::InfiniteRedirectError
      end

    rescue Timeouts::TimeoutError => e
      raise e if retries.zero?
      visit(url, retries - 1)
    end

    def wait_for_ping
      @ping = false
      wait_with_timeout(:ping) { @ping or @dead }
    end

    def to_s
      "<#{self.class.name} #{name} #{version} (#{os})>"
    end
    alias :inspect :to_s

  protected

    def drop_dead!
      remove_timeout(:dead)
      close_frames!
      @connector.close if @connector
      @dead = true
      @controller.drop_browser(self)
    end

  private

    def command_channel
      "/terminus/clients/#{id}"
    end

    def socket_channel
      "/terminus/sockets/#{id}"
    end

    def close_frames!
      @frames.each { |frame| frame.drop_dead! }
      @frames = Set.new
    end

    def detect_dock_host
      uri = URI.parse(@attributes['url'])
      @docked = (uri.port == Terminus.port)
      @dock_host = @attributes['host']
    end

    def rewrite_local(url)
      @controller.rewrite_local(url.to_s, @dock_host).to_s
    end

    def start_connector
      return if @connector or @dock_host.nil? or Terminus.browser != self
      @connector = Connector::Server.new(self)
      url = "ws://#{@dock_host}:#{@connector.port}/"
      debug(:connect, id, url)
      messenger.publish(socket_channel, 'url' => url)
    end

    def messenger
      @controller.messenger
    end

  end
end

