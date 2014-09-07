require 'drb'
require 'timeout'

module DontStallMyProcess
  module Local

    # LocalProxy connects to an instance of a class on a child process
    # and watches the execution of remote procedure calls.
    # Furthermore, it takes care of automatically ending the remote DRb
    # service when the proxy object gets garbage-collected.
    class LocalProxy
      class << self
        include DontStallMyProcess::ProxyRegistry

        def gc_finalize_proxy(pid, uri)
          LocalProxy.unregister(pid, proxy_uri) { |proxy| proxy.__destroy }
        end

        def gc_finalize_proxy_proc(pid, uri)
          # http://www.mikeperham.com/2010/02/24/the-trouble-with-ruby-finalizers/
          proc { LocalProxy.gc_finalize_proxy(pid, uri) }
        end
      end

      def initialize(uri, process, opts)
        @uri     = uri
        @process = process
        @opts    = opts

        # Get a DRb reference to the remote class.
        @object   = DRbObject.new_with_uri(uri)

        # Store this proxy in the registry for book-keeping.
        LocalProxy.register(process.pid, uri, self)

        # Destroy the proxy on GC.
        ObjectSpace.define_finalizer(self, self.class.gc_finalize_proxy_proc(process.pid, uri))
      end

      def stop_service!
        LocalProxy.each_proxy(@process.pid) { |proxy| proxy.send(:__destroy) }
      end

      def respond_to?(m, ia = false)
        @opts[:methods].keys.include?(m) || @object.respond_to?(m, ia) || super(m, ia)
      end

      def method_missing(meth, *args, &block)
        case
        when Kernel.public_methods(false).include?(meth)
          fail KernelMethodCalled, "Method '#{meth}' called. This would run the method that was privately inherited " +
            'from the \'Kernel\' module on the local proxy, which is most certainly not what you want. Kernel methods ' +
            'are not supported at the moment. Please consider adding an alias to your function.'
        when @opts[:methods].keys.include?(meth)
          __create_nested_proxy(meth, *args, &block)
        when @object.respond_to?(meth)
          __delegate_with_timeout(meth, *args, &block)
        else
          super
        end
      end

      def inspect
        self.to_s.gsub('>', " URI=#{@uri} CHILD_PID=#{@process.pid}>") 
      end

    private

      def __delegate_with_timeout(meth, *args, &block)
        __timed(meth) do
          @object.public_send(meth, *args, &block)
        end
      end

      def __timed(meth)
        Timeout.timeout(@opts[:timeout]) do
          yield
        end
      rescue Timeout::Error
        @process.terminate
        fail TimeoutExceeded, "Method #{meth} took more than #{@opts[:timeout]} seconds to process! Child process killed."
      end

      def __create_nested_proxy(meth, *args, &block)
        # Get the DRb URI from the remote.
        uri = __timed(meth) { @object.public_send(meth, *args, &block) }

        # Create a new local proxy and return that.
        LocalProxy.new(uri, @process, @opts[:methods][meth])
      end

      def __destroy
        # We rescue the exception here in case the subprocess is already dead.
        @object.__local_proxy_destroyed rescue nil

        LocalProxy.unregister(@process.pid, @uri)
      end
    end
  end
end
