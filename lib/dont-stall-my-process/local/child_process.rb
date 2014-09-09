module DontStallMyProcess
  module Local

    # The ChildProcess class encapsulates the forked subprocess that
    # provides the DRb service object.
    class ChildProcess
      attr_reader :pid

      def initialize
        r, w = IO.pipe

        # Call the before_fork handler now, so the client can clean up the main
        # process a bit.
        Configuration.before_fork_handler.call

        # Start RemoteApplication in child process, connect to it thru pipe.
        @pid = fork do
          r.close

          app = DontStallMyProcess::Remote::RemoteApplication.new(w)
          app.loop!
        end
        w.close

        # Wait for the RemoteApplication to finish its setup, and retrieve
        # the URI to the RemoteApplicationController.
        ctrl_uri = Marshal.load(r)

        # RemoteApplication sends us the URI or an Exception instance if anything
        # went wrong.
        if ctrl_uri.is_a?(Exception)
          e = SubprocessInitializationFailed.new(ctrl_uri)
          e.set_backtrace(ctrl_uri.backtrace)
          raise e
        end

        # Connect to and store the controller DRb client.
        @controller = DRbObject.new_with_uri(ctrl_uri)

        # Setup LocalProxy registry for this pid.
        LocalProxy.setup_proxy_registry(@pid) do
          # This block will be called when all LocalProxies
          # of this pid are gone (either garbage-collected or
          # manually destroyed by 'stop_service!').

          # Hand back ourself to the ChildProcessPool to get new jobs.
          ChildProcessPool.free(self)
        end

        @alive = true
      ensure
        r.close
      end

      def start_service(klass, opts)
        uri = @controller.start_service(klass, opts)
        
        # Create the main proxy class.
        Local::LocalProxy.new(uri, self, opts)
      end

      def alive?
        @alive && @controller.alive? rescue false
      end

      def quit
        @controller.stop_application rescue nil
        @controller = nil
        sleep 0.5
        terminate(false, 0.5)
      end

      def terminate(sigkill = true, term_sleep = 5)
        unless Configuration.sigkill_only
          Process.kill('TERM', @pid)
          sleep term_sleep
        end

        # http://stackoverflow.com/questions/325082/how-can-i-check-from-ruby-whether-a-process-with-a-certain-pid-is-running
        Process.kill('KILL', @pid) if sigkill && Process.waitpid(@pid, Process::WNOHANG).nil?

        # Collect process status to not have a zombie hanging around.
        Process.wait(@pid)

        # Do not reuse this process ever again.
        @alive = false
      rescue
        # Exceptions in these Process.* methods almost always mean the process is already dead.
        nil
      end
    end

  end
end
