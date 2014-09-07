require 'drb'
require 'timeout'

module DontStallMyProcess
  module Local

    # LocalProxy connects to an instance of a class on a child process
    # and watches the execution of remote procedure calls.
    class LocalProxy
      def initialize(uri, process, opts)
        @process      = process
        @opts         = opts

        # Get a DRb reference to the remote class.
        @object  = DRbObject.new_with_uri(uri)
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

      private

      def __create_nested_proxy(meth, *args, &block)
        # Get the DRb URI from the remote.
        uri = __timed(meth) { @object.public_send(meth, *args, &block) }

        # Create a new local proxy and return that.
        # Note: We do not need to cache these here, as there can be multiple
        # clients to a single DRb service.
        LocalProxy.new(uri, @process, @opts[:methods][meth])
      end

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
        __kill_child_process!
        fail TimeoutExceeded, "Method #{meth} took more than #{@opts[:timeout]} seconds to process! Child process killed."
      end

      def __kill_child_process!
        unless Configuration.sigkill_only
          @process.term
          sleep 5
        end

        @process.kill if @process.alive?
      end
    end

    # MainLocalProxy encapsulates the main DRb client, i.e. the top-level
    # client class requested by the user. It takes care of initially starting
    # the DRb service for callbacks and cleaning up child processes on
    # garbage collection.
    class MainLocalProxy < LocalProxy
      def self.register_remote_proxy(main_uri, object)
        @objects ||= {}
        @objects[main_uri] = object
      end

      def self.stop_remote_application(main_uri)
        @objects[main_uri].stop! rescue nil
      end

      def self.stop_remote_application_proc(main_uri)
        # See also: http://www.mikeperham.com/2010/02/24/the-trouble-with-ruby-finalizers/
        proc { MainLocalProxy.stop_remote_application(main_uri) }
      end

      def initialize(process, opts)
        # Start a local DRbServer (unnamed?) for callbacks (blocks!).
        # Each new Watchdog will overwrite the main master DRbServer.
        # This looks weird, but doesn't affect concurrent uses of multiple
        # Watchdogs, I tested it. Trust me.
        DRb.start_service

        # Initialize the base class, connect to the DRb service or the main client class.
        super(process.main_uri, process, opts)

        # Stop the child process on GC.
        MainLocalProxy.register_remote_proxy(process.main_uri, @object)
        ObjectSpace.define_finalizer(self, self.class.stop_remote_application_proc(process.main_uri))
      end
    end
  end
end
