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

      def initialize(opts, instance)
        @opts     = opts
        @object   = instance
        @children = {}

        @uri      = "drbunix:///tmp/dsmp-#{SecureRandom.hex(8)}"
        DRb.start_service(uri, self)
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
          @children[meth] = RemoteProxy.new(@opts[:methods][meth], instance).uri
        end

        # Return the DRb URI.
        @children[meth]
      end
    end

    # The MainRemoteProxy is the first DRb object to be created in
    # the child process. In addition to the real class' methods it
    # provides a 'stop!' method that brings down the child process
    # gracefully.
    class MainRemoteProxy < RemoteProxy
      def initialize(mother, klass, opts)
        @mother = mother

        # Instantiate the main class now, initialize the base class with
        # the new instance, create the DRb service.
        super(opts, klass.new)
      end

      def stop!
        @mother.stop!
      end
    end

  end
end
