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
    end
  end
end
