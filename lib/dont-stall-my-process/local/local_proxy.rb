require 'drb'
require 'timeout'

module DontStallMyProcess
  module Local

    # LocalProxy connects to an instance of a class on a child process
    # and watches the execution of remote procedure calls.
    # Furthermore, it takes care of automatically ending the remote DRb
    # service when the proxy object gets garbage-collected.
    class LocalProxy
      def self.register_local_proxy(process, proxy_uri, proxy)
        process.local_proxy_instantiated(proxy_uri)

        @proxies ||= {}
        @proxies[proxy_uri] = proxy
      end

      def self.lookup_local_proxy(proxy_uri)
        @proxies ||= {}
        @proxies[proxy_uri]
      end

      def self.stop_remote_proxy(proxy_uri)
        # We rescue the exception here in case the subprocess is already dead.
        @proxies[proxy_uri].stop_service! rescue nil
        @proxies.delete(proxy_uri)

        process.local_proxy_finalized(proxy_uri)
      end

      def self.stop_remote_proxy_proc(process, proxy_uri)
        # http://www.mikeperham.com/2010/02/24/the-trouble-with-ruby-finalizers/
        proc { LocalProxy.stop_remote_proxy(process, proxy_uri) }
      end

      def initialize(uri, process, opts)
        @process      = process
        @opts         = opts

        # Get a DRb reference to the remote class.
        @proxy       = DRbObject.new_with_uri(uri)

        # Stop the remote DRb service on GC.
        LocalProxy.register_local_proxy(process, uri, @proxy)
        ObjectSpace.define_finalizer(self, self.class.stop_remote_proxy_proc(process, uri))
      end

      def respond_to?(m, ia = false)
        @opts[:methods].keys.include?(m) || @proxy.respond_to?(m, ia) || super(m, ia)
      end

      def method_missing(meth, *args, &block)
        case
        when Kernel.public_methods(false).include?(meth)
          fail KernelMethodCalled, "Method '#{meth}' called. This would run the method that was privately inherited " +
            'from the \'Kernel\' module on the local proxy, which is most certainly not what you want. Kernel methods ' +
            'are not supported at the moment. Please consider adding an alias to your function.'
        when @opts[:methods].keys.include?(meth)
          __create_nested_proxy(meth, *args, &block)
        when @proxy.respond_to?(meth)
          __delegate_with_timeout(meth, *args, &block)
        else
          super
        end
      end

      private

      def __create_nested_proxy(meth, *args, &block)
        # Get the DRb URI from the remote.
        uri = __timed(meth) { @proxy.public_send(meth, *args, &block) }

        # Create a new local proxy and return that.
        # Note: We do not need to cache these here, as there can be multiple
        # clients to a single DRb service.
        LocalProxy.lookup_local_proxy(uri) || LocalProxy.new(uri, @process, @opts[:methods][meth])
      end

      def __delegate_with_timeout(meth, *args, &block)
        __timed(meth) do
          @proxy.public_send(meth, *args, &block)
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
    end
  end
end
