# Terminals and pipes

There is a UI, i.e. the terminal, and the pipes. the standard streams of programs.
A terminal serves as both [input and output device](https://unix.stackexchange.com/questions/48103/construct-a-command-by-putting-a-string-into-a-tty).
When you pipe to something like `/dev/pts/0`, you are writing to the output device of the terminal.
To write to the input, one can either use `TIOCSTI`, `man tty_ioctl`, as in
the example `tests/write_tiocsti.py`. Or, as Gilles pointed out, use `screen`
and its `stuff` command:

```
screen -S mysession -X stuff "cd tests; ls\n"
```

I think there might be something in separating pure pipes and working with them.
It should be more programmable. Things will work with sockets the same way, also
it kind of leads to serialised interfaces. There is no mix with terminal, a weird
interface with its own set of rules.

But how do you connect the terminal when it is needed?

Is it a good tradeoff:

* run comline connected to terminal, preferably under `screen`
* `popen3` only processes in background
* if a process needs to go in background but have terminal,
  then launch it in `screen -d -m <prog>`, with a proper `-S` domain name

The point is to use `screen` (or `tmux`) as a terminal-pipe converter, with its `stuff` command.
That's on top of the basic features: the terminal environment, and the session naming.

How it will work with launching remote processes?

* connect over SSH to a remote screen with a comline running, or launch a new session, properly named
* launch a background process with pipes, and with ENV variable holding a domain name etc
* now, the remote comline (under screen) can read those pipes,
* and I should also be able to read them remotely, and using the domain name
* to ensure correct pipes, it's probably better to read via the remote comline

Ok, worth to think about this mix. If it works, then maybe a Ruby `screen` could be useful,
like the archived [ruby-screen](https://github.com/dpetersen/ruby-screen).

