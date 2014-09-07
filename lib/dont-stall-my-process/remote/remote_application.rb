module DontStallMyProcess
  module Remote

    # RemoteObject is the base 'application' class for the child process.
    # It starts the DRb service and goes to sleep.
    class RemoteApplication
      def initialize(pipe)
        # Set subprocess name if requested.
        $0 = Configuration.subprocess_name if Configuration.subprocess_name

        # Do not write to stdout/stderr unless requested by the client.
        if Configuration.close_stdio
          $stdout.reopen('/dev/null', 'w')
          $stderr.reopen('/dev/null', 'w')
        end

        # Reset signal handlers if requested by client.
        if Configuration.restore_all_traps
          Signal.list.keys.each { |sig| Signal.trap(sig, 'DEFAULT') }
        end

        # Call the after_block_handler early, before DRb setup (i.e. before anything
        # can go wrong).
        Configuration.after_fork_handler.call

        # Initialize the DRbServiceRegistry, clearing its state.
        DRbServiceRegistry.initialize!

        # Start our controller class, expose via DRb.
        controller = RemoteApplicationController.new(self)

        # Everything went fine, set up the main process synchronization now.
        @m = Mutex.new
        @c = ConditionVariable.new

        # Tell our parent that setup is done and the new main DRb URI.
        Marshal.dump(controller.uri, pipe)
      rescue => e
        # Something went wrong, also tell our parent.
        Marshal.dump(e, pipe)
        raise
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
        # End main thread -> exit.
        @m.synchronize do
          @c.signal
        end
      end
    end

  end
end
