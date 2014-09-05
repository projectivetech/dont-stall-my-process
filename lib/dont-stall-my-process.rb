require 'dont-stall-my-process/local/child_process'
require 'dont-stall-my-process/local/local_proxy'
require 'dont-stall-my-process/remote/remote_application'
require 'dont-stall-my-process/remote/remote_proxy'
require 'dont-stall-my-process/version'

module DontStallMyProcess
  DEFAULT_TIMEOUT = 300

  def self.create(klass, opts = {}, sigkill_only = false)
    fail 'no klass given' unless klass && klass.is_a?(Class)

    # Set default values and validate configuration.
    opts = sanitize_options(opts)

    # Fork the child process.
    p = Local::ChildProcess.new(klass, opts)

    # Return the main proxy class.
    Local::MainLocalProxy.new(p, opts, sigkill_only)
  end

  def self.sanitize_options(opts, default_timeout = DEFAULT_TIMEOUT)
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
  class TimeoutExceeded < StandardError; end

  # This exception is raised when a forbidden Kernel method is called.
  # These methods do not get forwarded over the DRb.
  class KernelMethodCalled < StandardError; end

end
