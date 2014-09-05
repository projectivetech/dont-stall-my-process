module DontStallMyProcess
  module Remote

    # RemoteObject is the base 'application' class for the child process.
    # It starts the DRb service and goes to sleep.
    class RemoteApplication
      def initialize(klass, opts, pipe)
        @m = Mutex.new
        @c = ConditionVariable.new

        # Start the main DRb service.
        proxy = MainRemoteProxy.new(self, klass, opts)

        # Tell our parent that setup is done and the new main DRb URI.
        pipe.write(Marshal.dump(proxy.uri))
      rescue => e
        # Something went wrong, also tell our parent.
        pipe.write(Marshal.dump(e))
      ensure
        pipe.close
      end

      def loop!
        # Sleep to keep the DRb service running, until woken up.
        @m.synchronize do
          @c.wait(@m)
        end
      end

      def stop!
        Thread.new do
          # Wait for DRb answer package to be sent.
          sleep 0.2

          # End main thread -> exit.
          @m.synchronize do
            @c.signal
          end
        end
      end
    end

  end
end
