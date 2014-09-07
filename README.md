# DontStallMyProcess

This little gem helps you in case one of your native extensions goes crazy and stalls
your entire Ruby process.

It takes a Ruby class, instantiates it in a forked subprocess and communicates with
it over DRb. You can define timeouts for function execution times. If the timeout is
exceeded, the subprocess is terminated (and killed if necessary).

## Usage

```
obj = DontStallMyProcess.create <klass> [, <configuration>]
```

where `klass` is a class name and `configuration` looks like this:

```
{
  timeout: 120      # Seconds for a method of the SomeClass instance to execute.
  methods: {        # Hash of methods that should get nested DRb services.
    somemethodname: {
      <description of nested remote object; same way but without :klass...>
    },
    ...
  }
}
```

The `:timeout` specifies how long a remote DRb method is allowed to take. When `:timeout`
seconds have passed, the child process along with all of its DRb providers will be
killed (TERM-5sec-KILL) and a TimeoutExceeded exception will be thrown. If not given, `:timeout`
will default to 300 seconds.

Methods not listed in the `:methods` hash will have usual DRb marshall/unmarshall
behaviour. Methods listed in there will return a DRb proxy as well, and you can pass in
another nested `:methods` hash there. You may also overwrite the `:timeout` option, if you don't
the value of the parent configuration will be used.

<strong>Nested DRb services will run in the same child process.</strong>

<strong>Only one instance of nested classes will be created, i.e., the remote method will only be called once! However, if an instance is garbage-collected, or you have manually called the `stop_service!` method, the remote method will be called again.</strong>

Subprocess will be ended automatically after all proxy objects have been garbage-collected or manually disconnected by calling `stop_service!`.

## Global configuration

```
DontStallMyProcess.configure do |config|
  config.sigkill_only = false
  config.close_stdio = true
  config.restore_all_traps = false
  config.process_pool_size = 10
  config.subprocess_name = 'DontStallMyProcess'
  config.after_fork do |pid|
    <...>
  end
end

If the `sigkill_only` flag is set to true, the dead process will be terminated using `SIGKILL` only, so
no `TERM` signal will be sent. This is useful for some parent processes (e.g., Sidekiq) that trap
the `TERM` signal to do some shutdown logic on their own. `sigkill_only` defaults to `false`.

The `close_stdio` flag causes the subprocess to close `$stdout` and `$stderr` after the fork. Defaults to `true`.

When the `restore_all_traps` flag is set, all signal handlers will be reset to the Ruby default signal handlers. See documentation on Ruby `Signal` module for more information.

When `process_pool_size` is set to a value > 0, that number of processes will be kept alive and be re-used when all their DRb services have been terminated (i.e. all local proxies have been garbage-collected). Defaults to `nil` (same as zero) which turns off process pooling.

The `subprocess_name` string is the name of the subprocess. Defaults to `nil` which means the subprocess is
 not renamed at all, but instead keeps the name of the parent process.

The `after_fork` method of the configuration object may be used to register a `Proc` that is called right
when the subprocess has been spawned. This is useful for overwriting signal traps, or closing file descriptors
or the like.

## Caveats

Kernel methods (e.g., `open`, `format`, etc.) are not supported at the moment. Due to the
double indirection of the DRb service (we need a proxy object on both sides of the communication
and a lot of `public_send`s), these methods are called instead of the intended remote methods
as they are privately included into the proxy class (and thus, `method_missing` is not called when
you `send` one of them).
