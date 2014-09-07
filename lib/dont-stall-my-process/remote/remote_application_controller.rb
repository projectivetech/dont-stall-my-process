require 'drb'

module DontStallMyProcess
  module Remote
    class RemoteApplicationController
      attr_reader :uri

      def self.update_process_name(klass_name = 'unused')

      end

      def initialize(application)
        @applicarion = application
        @uri         = "drbunix:///tmp/dsmp-controller-#{Process.pid}"

        DRb.start_service(uri, self)
      end

      def start_service(klass, opts)
        # Instantiate the main class now to get early failures.
        instance = klass.new

        # Start the main DRb service.
        proxy = RemoteProxy.new(opts, instance)

        # Set subprocess name if requested.
        RemoteApplication.update_process_name(klass.name.to_s)

        # Return the DRb URI.
        proxy.uri
      end

      def stop_application
        Thread.new do
          # Wait for DRb answer package to be sent.
          sleep 0.2

          @application.stop!
        end
      end
    end
  end
end
