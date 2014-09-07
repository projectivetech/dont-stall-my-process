require 'drb'
require 'securerandom'

module DontStallMyProcess
  module Remote

    # RemoteProxy is an decorator class for any of the 'real' classes
    # to be served via DRb. It delegates method calls to the encapsulated
    # instance of the 'real' class. Furthermore, it takes care of creating
    # nested DRb services as requested in the option hash.
    class RemoteProxy
      attr_reader :uri

      def initialize(opts, instance, parent = nil)
        @opts     = opts
        @object   = instance
        @parent   = parent
        @children = {}

        @uri      = DRbServiceRegistry.start_server!(self)
      end

      def stop_service!
        DRbServiceRegistry.stop_server!(@uri)
        parent.__nested_proxy_stopped!(@uri) if parent
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
        # Create a new DRb proxy if needed, and save its URI.
        unless @children[meth]
          # Call the object method now, save the returned object.
          instance = @object.public_send(meth, *args, &block)

          # Start the proxy, convert the object 0into a DRb service.
          @children[meth] = RemoteProxy.new(@opts[:methods][meth], instance, self).uri
        end

        # Return the DRb URI.
        @children[meth]
      end

      def __nested_proxy_stopped(uri)
        @children.delete_if { |_, child_uri| child_uri == uri }
      end
    end
  end
end
