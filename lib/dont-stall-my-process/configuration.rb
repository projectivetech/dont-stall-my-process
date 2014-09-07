module DontStallMyProcess
  class Configuration
    DEFAULT_TIMEOUT = 300

    ATTRIBUTES = [:sigkill_only, :close_stdio, :restore_all_traps, :skip_at_exit_handlers,
      :process_pool_size, :subprocess_name, :after_fork_handler]
    attr_writer *(ATTRIBUTES - [:after_fork_handler])

    def initialize
      @sigkill_only          = false
      @close_stdio           = true
      @restore_all_traps     = false
      @skip_at_exit_handlers = false
      @process_pool_size     = nil
      @after_fork_handler    = Proc.new {}
      @subprocess_name       = nil
    end

    def after_fork(p = nil, &block)
      fail 'after_fork needs a block or Proc object' unless (p && p.is_a?(Proc)) || block_given?
      @after_fork_handler = p || block
    end

    class << self
      def get
        @configuration ||= Configuration.new
      end

      ATTRIBUTES.each do |a|
        define_method(a) do
          get.instance_variable_get("@#{a}")
        end
      end
    end
  end
end
