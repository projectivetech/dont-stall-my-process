require 'dont-stall-my-process/configuration'
require 'dont-stall-my-process/exceptions'
require 'dont-stall-my-process/proxy_registry'
require 'dont-stall-my-process/version'
require 'dont-stall-my-process/local/child_process'
require 'dont-stall-my-process/local/child_process_pool'
require 'dont-stall-my-process/local/local_proxy'
require 'dont-stall-my-process/remote/remote_application'
require 'dont-stall-my-process/remote/remote_application_controller'
require 'dont-stall-my-process/remote/remote_proxy'

module DontStallMyProcess
  def self.configure
    yield Configuration.get if block_given?
  end

  def self.create(klass, opts = {})
    fail 'no klass given' unless klass && klass.is_a?(Class)

    # Set default values and validate configuration.
    opts = sanitize_options(opts)

    # Start a local DRbServer (unnamed?) for callbacks (blocks!).
    # Each new DontStallMyProcess object will overwrite the main master DRbServer.
    # This looks weird, but doesn't affect concurrent uses of multiple
    # Watchdogs, I tested it. Trust me.
    DRb.start_service

    # Fork the child process.
    process = Local::ChildProcessPool.alloc

    # Start the DRb service for the main class and create a proxy.
    proxy = process.start_service(klass, opts)

    # If a block is given, we finalize the service immediately after its return.
    if block_given?
      yield proxy
      proxy.stop_service!
      proxy = nil
    end
    
    proxy
  end

  def self.sanitize_options(opts, default_timeout = Configuration::DEFAULT_TIMEOUT)
    fail 'opts is not a hash' unless opts.is_a?(Hash)

    opts[:timeout] ||= default_timeout
    opts[:methods] ||= {}

    fail 'no timeout given' unless opts[:timeout] && opts[:timeout].is_a?(Fixnum)
    fail 'timeout too low' unless opts[:timeout] > 0
    fail 'methods is not a hash' if opts[:methods] && !opts[:methods].is_a?(Hash)

    {
      timeout: opts[:timeout],
      methods: Hash[
        opts[:methods].map { |meth, mopts| [meth, sanitize_options(mopts, opts[:timeout])] }
      ]
    }
  end
end
