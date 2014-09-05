# DontStallMyProcess

This little gem helps you in case one of your native extensions goes crazy and stalls
your entire Ruby process.

It takes a Ruby class, instantiates it in a forked subprocess and communicates with
it over DRb. You can define timeouts for function execution times. If the timeout is
exceeded, the subprocess is terminated (and killed if necessary).

## Usage

```
obj = DontStallMyProcess.create <klass> [, <configuration> [, sigkill_only = false]]
```

where `klass` is a class name and `configuration` looks like this:

```
{
  timeout: 120      # Seconds for a method of the SomeClass instance to execute.
  methods: {
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

If the `sigkill_only` flag is set to true, the dead process will be terminated using `SIGKILL` only, so
no `TERM` signal will be sent. This is useful for some parent processes (e.g., Sidekiq) that trap
the `TERM` signal to do some shutdown logic on their own.

Methods not listed in the `:methods` hash will have usual DRb marshall/unmarshall
behaviour. Methods listed in there will return a DRb proxy as well, and you can pass in
another nested `:methods` hash there. You may also overwrite the `:timeout` option, if you don't
the value of the parent configuration will be used.

<strong>Nested DRb services will run in the same child process.</strong>

<strong>Only one instance of nested classes will be created, i.e., the remote method will only be called once!</strong>

If you want to end the subprocess manually, simply call `obj.stop!` on your proxy object. It will
be done automatically when the object is garbage collected.

## Caveats

Kernel methods (e.g., `open`, `format`, etc.) are not supported at the moment. Due to the
double indirection of the DRb service (we need a proxy object on both sides of the communication
and a lot of `public_send`s), these methods are called instead of the intended remote methods
as they are privately included into the proxy class (and thus, `method_missing` is not called when
you `send` one of them).
