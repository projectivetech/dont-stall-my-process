require 'securerandom'
require 'drb'

module DontStallMyProcess
  module Remote
    class DRbServiceRegistry
      def self.initialize!
        @services = {}
      end

      def self.start_server!(instance)
        uri = "drbunix:///tmp/dsmp-#{SecureRandom.hex(8)}"
        @services[uri] = DRb.start_service(uri, instance)
        uri
      end

      def self.stop_server!(uri)
        DRb.remove_service(@services[uri])
        @services.delete(uri)
      end
    end
  end
end
