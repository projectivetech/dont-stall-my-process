require 'drb'
require 'securerandom'

module DontStallMyProcess
  module Remote

    # RemoteProxy is an decorator class for any of the 'real' classes
    # to be served via DRb. It delegates method calls to the encapsulated
    # instance of the 'real' class. Furthermore, it takes care of creating
    # nested DRb services as requested in the option hash.
    class RemoteProxy
      class << self
        include DontStallMyProcess::ProxyRegistry
      end

      attr_reader :uri

      def initialize(opts, instance, parent = nil)
        @opts     = opts
        @object   = instance

        @uri      = "drbunix:///tmp/dsmp-#{SecureRandom.hex(8)}"
        @server   = DRb.start_service(@uri, self)

        RemoteProxy.register(Process.pid, @uri, self)
      end

      def __local_proxy_destroyed
        __destroy
      end

      def respond_to?(m, ia = false)
        @opts[:methods].keys.include?(m) || @object.respond_to?(m, ia) || super(m, ia)
      end

      def method_missing(meth, *args, &block)
        case
        when (mopts = @opts[:methods][meth])
          __create_nested_proxy(meth, *args, &block)
        when @object.respond_to?(meth)
          # Delegate the method call to the real object.
          @object.public_send(meth, *args, &block)
        else
          super
        end
      end

    private

      def __create_nested_proxy(meth, *args, &block)
        instance = @object.public_send(meth, *args, &block)

        # Start the proxy, convert the object into a DRb service.
        RemoteProxy.new(@opts[:methods][meth], instance, self).uri
      end

      def __destroy
        @server.stop_service

        RemoteProxy.unregister(Process.pid, @uri)
      end
    end
  end
end
