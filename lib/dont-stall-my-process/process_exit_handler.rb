require 'fileutils'

module DontStallMyProcess
  class ProcessExitHandler
    def self.disable_at_exit
      @at_exit_disabled = true
    end

    def self.at_exit_disabled?
      @at_exit_disabled
    end

    at_exit do
      # If we're in a subprocess, this handler should not run.
      unless ProcessExitHandler.at_exit_disabled?

        # Make sure we terminate all subprocesses when
        # the main process exits.
        Local::ChildProcessPool.each do |process|
          process.quit
        end

        # Clean remaining unix sockets from /tmp.
        FileUtils.rm(Dir["/tmp/dsmp-#{Process.pid}*"])
      end
    end
  end
end
