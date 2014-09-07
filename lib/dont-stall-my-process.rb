require 'dont-stall-my-process/local/child_process'
require 'dont-stall-my-process/local/child_process_pool'
require 'dont-stall-my-process/local/local_proxy'
require 'dont-stall-my-process/remote/drb_service_registry'
require 'dont-stall-my-process/remote/remote_application'
require 'dont-stall-my-process/remote/remote_application_controller'
require 'dont-stall-my-process/remote/remote_proxy'
require 'dont-stall-my-process/configuration'
require 'dont-stall-my-process/version'

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

    # Start the DRb service for the main class, and return the proxy.
    process.start_service(klass, opts)
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

  # This exception is raised when the watchdog bites.
  TimeoutExceeded = Class.new(StandardError)

  # This exception is raised when the subprocess could not be created, or
  # its initialization failed.
  SubprocessInitializationFailed = Class.new(StandardError)

  # This exception is raised when a forbidden Kernel method is called.
  # These methods do not get forwarded over the DRb.
  KernelMethodCalled = Class.new(StandardError)

end
