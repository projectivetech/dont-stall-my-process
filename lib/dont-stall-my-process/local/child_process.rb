module DontStallMyProcess
  module Local

    # The ChildProcess class encapsulates the forked subprocess that
    # provides the DRb service object.
    class ChildProcess
      def initialize
        # Start RemoteApplication in child process, connect to it thru pipe.
        r, w = IO.pipe
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

        # We do not ever want to wait for the subprocess to exit.
        # (This is the sort of the whole point of this gem...)
        Process.detach(@pid)
      ensure
        r.close
      end

      def local_proxy_instantiated(uri)
        @proxies ||= []
        @proxies << uri
      end

      def local_proxy_finalized(uri)
        @proxies.delete(uri)
        ChildProcessPool.free(self) if @proxies.empty?
      end

      def start_service(klass, opts)
        uri = @controller.start_service(klass, opts)
        
        # Create the main proxy class.
        Local::LocalProxy.new(uri, self, opts)
      end

      def quit
        @controller.stop_application
        @controller = nil
      end

      def terminate
        unless Configuration.sigkill_only
          Process.kill('TERM', @pid)
          sleep 5
        end

        # http://stackoverflow.com/questions/325082/how-can-i-check-from-ruby-whether-a-process-with-a-certain-pid-is-running
        Process.kill('KILL', @pid) if Process.waitpid(@pid, Process::WNOHANG).nil?
      rescue
        # Exceptions in these Process.* methods almost always mean the process is already dead.
        nil
      end
    end

  end
end
