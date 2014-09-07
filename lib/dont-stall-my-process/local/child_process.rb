module DontStallMyProcess
  module Local

    # The ChildProcess class encapsulates the forked subprocess that
    # provides the DRb service object.
    class ChildProcess
      attr_reader :main_uri

      def initialize(klass, opts)
        # Start RemoteApplication in child process, connect to it thru pipe.
        r, w = IO.pipe
        @pid = fork do
          r.close
          DontStallMyProcess::Remote::RemoteApplication.new(klass, opts, w).loop!
        end
        w.close

        # Wait for the RemoteApplication to finish its setup.
        @main_uri = Marshal.load(r)

        # RemoteApplication sends us the DRb URI or an Exception.
        raise SubprocessInitializationFailed.new(@main_uri) if @main_uri.is_a?(Exception)

        # We do not ever want to wait for the subprocess to exit.
        # (This is the sort of the whole point of this gem...)
        Process.detach(@pid)
      ensure
        r.close
      end

      def term
        # Exceptions in these methods almost always mean the process is already dead.
        Process.kill('TERM', @pid) rescue nil
      end

      def kill
        Process.kill('KILL', @pid) rescue nil
      end

      def alive?
        # http://stackoverflow.com/questions/325082/how-can-i-check-from-ruby-whether-a-process-with-a-certain-pid-is-running
        Process.waitpid(@pid, Process::WNOHANG).nil?
      end
    end

  end
end
