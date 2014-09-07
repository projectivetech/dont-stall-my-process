module DontStallMyProcess
  module Remote

    # RemoteObject is the base 'application' class for the child process.
    # It starts the DRb service and goes to sleep.
    class RemoteApplication
      def initialize(klass, opts, pipe)
        # Set subprocess name if requested.
        if Configuration.subprocess_name
          $0 = Configuration.subprocess_name % { klass: klass.name }
        end

        # Do not write to stdout/stderr unless requested by the client.
        if Configuration.close_stdio
          $stdout.reopen('/dev/null', 'w')
          $stderr.reopen('/dev/null', 'w')
        end

        # Call the after_block_handler early, before DRb setup (i.e. before anything
        # can go wrong).
        Configuration.after_fork_handler.call

        # Start the main DRb service.
        proxy = MainRemoteProxy.new(self, klass, opts)

        # Everything went fine, set up the main process synchronization now.
        @m = Mutex.new
        @c = ConditionVariable.new

        # Tell our parent that setup is done and the new main DRb URI.
        Marshal.dump(proxy.uri, pipe)
      rescue => e
        # Something went wrong, also tell our parent.
        Marshal.dump(e, pipe)
      ensure
        pipe.close
      end

      def loop!
        # If the mutex wasn't created, something went south and we do
        # not want to let the main thread enter sleep mode.
        if @m

          # Sleep to keep the DRb service running, until woken up.
          @m.synchronize do
            @c.wait(@m)
          end

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
