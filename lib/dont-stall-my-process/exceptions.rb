module DontStallMyProcess
  DontStallMyProcessError = Class.new(StandardError)

  # This exception is raised when the watchdog bites.
  TimeoutExceeded = Class.new(StandardError)

  # This exception is raised when the subprocess could not be created, or
  # its initialization failed.
  SubprocessInitializationFailed = Class.new(StandardError)

  # This exception is raised when a forbidden Kernel method is called.
  # These methods do not get forwarded over the DRb.
  KernelMethodCalled = Class.new(StandardError)
end
