require 'erb'
require 'forwardable'
require 'http/parser'
require 'net/http'
require 'rbconfig'
require 'readline'
require 'socket'
require 'stringio'
require 'uri'

require 'capybara'
require 'childprocess'
require 'cookiejar'
require 'eventmachine'
require 'faye'
require 'rack-proxy'
require 'useragent'

module Terminus
  FAYE_MOUNT   = '/messaging'
  DEFAULT_HOST = 'localhost'
  DEFAULT_PORT = 7004
  LOCALHOST    = /^(localhost|0\.0\.0\.0|127\.0\.0\.1)$/
  PING_PATH    = '/favicon.ico'
  RETRY_LIMIT  = 3

  ROOT = File.expand_path('..', __FILE__)
  autoload :Application, ROOT + '/terminus/application'
  autoload :Browser,     ROOT + '/terminus/browser'
  autoload :Client,      ROOT + '/terminus/client'
  autoload :Connector,   ROOT + '/terminus/connector'
  autoload :Controller,  ROOT + '/terminus/controller'
  autoload :Headers,     ROOT + '/terminus/headers'
  autoload :Host,        ROOT + '/terminus/host'
  autoload :Node,        ROOT + '/terminus/node'
  autoload :Proxy,       ROOT + '/terminus/proxy'
  autoload :Server,      ROOT + '/terminus/server'
  autoload :Timeouts,    ROOT + '/terminus/timeouts'

  require ROOT + '/capybara/driver/terminus'

  class ObsoleteElementError < StandardError
  end

  class << self
    attr_accessor :debug, :sockets

    def create(options = {})
      Server.new(options)
    end

    def endpoint(host = DEFAULT_HOST)
      "http://#{host}:#{port}#{FAYE_MOUNT}"
    end

    def ensure_reactor_running
      Thread.new { EM.run unless EM.reactor_running? }
      Thread.pass until EM.reactor_running?
    end

    def port
      @port || DEFAULT_PORT
    end

    def port=(port)
      @port = port.to_i
    end

    def start_browser(options = {})
      Client::Browser.start(options)
    end

    def start_phantomjs(options = {})
      Client::PhantomJS.start(options)
    end

    extend Forwardable
    def_delegators :controller, :browser,
                                :browsers,
                                :browser=,
                                :cookies,
                                :ensure_browsers,
                                :register_local_port,
                                :return_to_dock,
                                :rewrite_local,
                                :rewrite_remote,
                                :save_error,
                                :server_running?,
                                :visited?

  private

    def controller
      @controller ||= Controller.new
    end
  end
end

