module DontStallMyProcess
  module Local
    class ChildProcessPool
      def self.alloc
        if !@pool || @pool.empty?
          ChildProcess.new
        else
          @pool.shift
        end
      end

      def self.free(process)
        if Configuration.process_pool_size && Configuration.process_pool_size > 0
          @pool ||= []

          if @pool.size < Configuration.process_pool_size
            @pool << process
          else
            process.quit
          end
        end
      end

      def self.each(&block)
        @pool.each(&block) if @pool
      end

      def self.disable_at_exit
        @at_exit_disabled = true
      end

      def self.at_exit_disabled?
        @at_exit_disabled
      end

      at_exit do
        # If we're in a subprocess, this handler should not run.
        unless ChildProcessPool.at_exit_disabled?
          # Make sure we terminate all subprocesses when
          # the main process exits.
          ChildProcessPool.each do |process|
            process.quit
          end
        end
      end
    end
  end
end
