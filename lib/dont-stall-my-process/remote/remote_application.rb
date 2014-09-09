module DontStallMyProcess
  module Remote

    # RemoteObject is the base 'application' class for the child process.
    # It starts the DRb service and goes to sleep.
    class RemoteApplication
      def self.update_process_name(klass_name = '<pool>')
        if Configuration.subprocess_name
          $0 = Configuration.subprocess_name % { klass: klass_name.to_s }
        end
      end

      def initialize(pipe)
        # Do not write to stdout/stderr unless requested by the client.
        if Configuration.close_stdio
          $stdout.reopen('/dev/null', 'w')
          $stderr.reopen('/dev/null', 'w')
        end

        # Reset signal handlers if requested by client.
        if Configuration.restore_all_traps
          # Plenty of signals are not trappable, simply ignore this here.
          Signal.list.keys.each { |sig| Signal.trap(sig, 'DEFAULT') rescue nil }
        end

        if Configuration.skip_at_exit_handlers
          # Clearing the Ruby end proc list is not possible without modifying
          # Ruby itself, see eval_jump.c in current Ruby sources. However,
          # as these handlers get executed in reverse order, simply calling
          # exit! here is enough.
          at_exit { exit! }
        end

        # Call the after_block_handler early, before DRb setup (i.e. before anything
        # can go wrong).
        Configuration.after_fork_handler.call

        # Initially display the process name without a class name (-> '<pool>').
        RemoteApplication.update_process_name

        RemoteProxy.setup_proxy_registry(Process.pid) do
          # This block is called when all RemoteProxies have closed there
          # DRb servers. We're now idling again, waiting for new jobs in the
          # pool *or* are going to be be terminated in a second.

          # Update process name again to indicate availability.
          RemoteApplication.update_process_name
        end

        # Start our controller class, expose via DRb.
        @controller = RemoteApplicationController.new(self)

        # Everything went fine, set up the main process synchronization now.
        @m = Mutex.new
        @c = ConditionVariable.new

        # Tell our parent that setup is done and the new main DRb URI.
        Marshal.dump(@controller.uri, pipe)
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

        # Remote application end.
        exit 0
      rescue SystemExit, Interrupt
        raise
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
