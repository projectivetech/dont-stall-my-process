module DontStallMyProcess
  module Remote
    class RemoteApplicationController
      attr_reader :uri

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

        # Return the DRb URI.
        proxy.uri
      end

      def stop_process
        Thread.new do
          # Wait for DRb answer package to be sent.
          sleep 0.2

          @application.stop!
        end
      end
    end
  end
end
