module DontStallMyProcess
  module ProxyRegistry
    def setup_proxy_registry(pid, &block)
      @empty_handler    ||= {}
      @empty_handler[pid] = block

      @proxies          ||= {}
      @proxies[pid]       = {}
    end

    def register(pid, key, object)
      @proxies[pid][key] = object
    end

    def unregister(pid, key)
      if @proxies[pid].key?(key) && block_given?
        yield @proxies[pid]
      end
      @proxies[pid].delete(key)

      # Check if all proxies are gone now and call the process.
      @empty_handler[pid].call if @proxies[pid].empty?
    end

    def each_proxy(pid, &block)
      @proxies[pid].dup.values.each(&block)
    end
  end
end
