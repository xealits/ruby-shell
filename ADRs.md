# The shell features

The main bit is to have a decent language to fall back on, when it is needed.
Ruby is perfect for that: it is concise, powerful, with a bunch of shell features
like the support for regexps. Some features to enable Ruby more:

* Seamlessly passing pipes between shell and Ruby: create a named pipe in Ruby and
  return its filename, refer to the standard streams of a process via `/proc/`.
  Also, some lookup or completion into the internal state of `Comline` object
  that is available for the evaluation of user commands.

* Multi-line command edditing.

"Discoverability" of the interface: something to guide the user to what
can be done with the interface. Although, I am not sure what's possible here.

Handy features to manipulate shell input and output: split windows for input and output,
handy way to copy bits of output into the input (Vim keys?), send the input
to multiple shells (and eval `#{}` in the target shells). Also, it's nice to have
the shells run inside `screen` by default everywhere, like with `ruby-screen` Gem.

Few bits to manage processes. Not sure if it is worth to require a whole Foreman or God.
But it's handy to have some "domain names" for the processes, and be able to get their
streams and open sockets easily. In principle, this stuff leads to systemd-like,
and Foreman- or God-like features, with dependencies and FSM between commands and processes.
Not sure if that's worth to integrate. It would be massively better if the shell
seamlessly ran these programs on all the hosts on their own. On the other hand,
it typically gets confusing when things aren't integrated, especially if it is
similar things.

The point of so much attention on support of pipes is not to push any text into
them. What's really needed is some serialisation protocol for arbitrary messages
that are sent between processes. I.e. you have: (C/C++) ABI, bindings (Python, Ruby),
serial protocol (JSON, msgpack, etc), text or graphic user interface. And you can
integrate programs at any of these interfaces. Then, it's worth to have examples:
having an ABI, automatically bind it to Ruby, and create a serial protocl out of
its signature, then create an `optparse` commandline UI, and a GUI, maybe a web GUI.
And it's worth to have some handy utilities: small NNG programs to turn a pipe into
different patterns of sockets (pub-sub etc), logger for a pipe, an influxdb data
source, also pipe the data into a `curses_menu` that sorts through the data points.
Also, in principle, at the level of ABI or Python/Ruby bindings, you can create
and OPC server. I.e. from the signatures of the bindings, plus some logic and FSM
code, you can generate a boilerplate for a server. It is a more complex case, but
similar to generating a command line utility.

And I also want to integrate the `uart` Gem, to work with serial interfaces.
It's just for hoppy embedded projects.



# Terminals and pipes

There is a UI, i.e. the terminal, and the pipes, the standard streams of a program.
The terminal serves as both [input and output device](https://unix.stackexchange.com/questions/48103/construct-a-command-by-putting-a-string-into-a-tty).
When you pipe to something like `/dev/pts/0`, you are writing to the output device of the terminal.
To write to the input, one can either use `TIOCSTI`, `man tty_ioctl`, as in
the example `tests/write_tiocsti.py`. Or, as Gilles points out, use `screen`
and its `stuff` command:

```
screen -S mysession -X stuff "cd tests; ls\n"
```

I think there it should be useful to separate pure pipes and work with them directly.
It's just programmable, a point for serialised interface. Things will work with
sockets the same way, etc. Potentially, the UI may be swapped for a GUI.

But how do you connect the terminal when it is neede then?

Is the following a good tradeoff:

* run comline connected to terminal, preferably under `screen`
* `popen3` only processes in background
* if a process needs to go in background but have terminal,
  then launch it in `screen -d -m <prog>`, with a proper `-S` domain name

The point is to use `screen` (or `tmux`) as a terminal-pipe converter, with its `stuff` command.
That's on top of the basic features: the terminal environment, and the session naming.

* If so, then find how to get stdout as a pipe out of `screen` etc.
  GNU [screen buffer](https://askubuntu.com/questions/817007/save-stdout-and-stderr-of-programs-running-under-gnu-screen-when-you-forgot-to-r).
  It can also periodically [log to files](https://www.gnu.org/software/screen/manual/html_node/Log.html).
  You can detach a [nested session](https://wiki.archlinux.org/title/GNU_Screen#Nested_Screen_Sessions)
  with `Ctrl+a a d`.

This way, every process gets its own domain name, including comline itself.
The screen session is not a separate process, but an addition of a terminal
to the process. The screen session name is the same as the process.

If the stdout of a process is requested, it should be possible to recognise
whether the process runs inside a terminal, and pull the stdout from the screen.
Otherwise, the process is connected to pipes.

* Probably the important point is to not need to connect to terminal input & output.
  I.e. the terminal must serve only as the UI. The programmable processes, with pipes,
  should be spawned and connected as background jobs.

  It should also include the dependencies and an FSM between processes? A Foreman or God gem?
  That would be more like "a proper language for FSM", not for shell.

  The application is some kind of automation: the processes print their state updates
  as serial protocol to stdout or something like that. I.e. the basic interface is made of
  just pipes and some simple protocol. The point is that it's a very common infrastructure.

  - How it fits into MQTT? The shell is just a few small useful mechanisms to launch and manage processes.
    Those processes can talk over MQTT or just sockets in any way they want.
  - Check NNG pattern to provide multiple-consumers subscribtions to these stdout Data Points.
    Pipes have limited capacity. So, if real logging is needed, it means something more serious.
    Check Ruby influx gems for a basic logger.
  - Is it worth to just check OPC implementations in Ruby? OPC provides a lot. But at the same time,
    It may not be that flexible. Also to mention, Ruby has Rails. Maybe it's better to just send around
    some protocol, and react to the messages.
  - Check out serialisation protocols. The simpler the better. It is supposed to be "a very common infrastructure".
    And make a simple test app, like barometric sensors on serial console + a protocol + a TUI ASCII typography?
    Or like a bunch of servos on a BeagleBone?
  - Check out GraphQL and API-building on top of it. It seems like the right thing,
    but without the commit time series and the config "branches".

* In UI case, it would be better to always run under screen, with session names,
  to easily track and connect to different sessions.
  If so, it could be better to use [ruby-scree](https://github.com/dpetersen/ruby-screen).

* At the same time, it may make sense to be able to launch comline as `--stdin`?
  Or maybe with a proper input protocol? This is like the `cockpit` for `systemd` thing.
  You don't want to re-make an SSH connection on each command. It's better to have
  a bunch of connections open, showing some heartbeat, with a possibility to browse processes.
  A comline running in `--stdin` mode might also be able to spawn a screen session?

How it will work with launching remote processes?

* connect over SSH to a remote screen with a comline running, or launch a new session, properly named
* launch a background process with pipes, and with ENV variable holding a domain name etc
* now, the remote comline (under screen) can read those pipes,
* and I should also be able to read them remotely, and using the domain name
* to ensure correct pipes, it's probably better to read via the remote comline

Ok, worth to try this mix. If it works, then maybe a Ruby `screen` could be useful,
like the archived [ruby-screen](https://github.com/dpetersen/ruby-screen).

Copy to a remote `stdin`:

```
$ tar -cf - /path/to/backup/dir | ssh remotehost "cat - > backupfile.tar"

> tar -cf - /path/to/backup/dir | #{remote_stdin "remotehost" "domain.name.ruby_shell"}

def remote_stdin hostname domainname
  ssh to hostname
  search a proc with domainname in RBSHELL_NAME env
  return
  ssh hostname "cat - > /proc/<pid>/fd/0
end
```

Remote ruby:

```
RBSHELL_NAME=ruby.name cat - > foobar_test
```

Local:

```
  0 foobar   stdin> echo #{remote_stdin 'ruby.name', 'bubuntu1' }
ssh bubuntu1 cat - > /proc/46554/fd/0
  0 foobar   stdin> echo hey | #{remote_stdin 'ruby.name', 'bubuntu1' }
  0 foobar   stdin> echo hello world! | #{remote_stdin 'ruby.name', 'bubuntu1' }
  0 foobar   stdin> echo "#{ps_list("bubuntu1").join "\n"}"
  0 foobar   stdin> ssh -t bubuntu1 screen -x
```

[Detach a nested screen session](https://wiki.archlinux.org/title/GNU_Screen#Nested_Screen_Sessions) with `Ctrl+a a d`.

Not the best way to address stdout with `tail -f`:

```
  0 foobar   stdin> echo #{remote_stdout 'ruby.name', 'bubuntu1' }
ssh bubuntu1 tail -f /proc/51551/fd/1
```

The addressing could also be something like `remotehost/ruby_shell/domain/name`.



# Addressing processes & domain naming them

Using environment variables to mark a process as named?
It's not great because child processes inherit the variables.

Maintain processes under a running Ruby comline?
Maight be the way to go: the same commands are used interactively and remotely.
How do you interact nicely with a comline that runs in a screen terminal?
The screen `stuff` and `hardcopy` commands are not that great really.



# Multi-line input & probably parsing

How [`fish`](https://fishshell.com/) does it?
Can it be done with just [`reline`](https://github.com/ruby/reline)?
To support quotation marks and `#{}`, it needs to parse the text.
Then you can program [`readline`](https://stackoverflow.com/questions/161495/is-there-a-nice-way-of-handling-multi-line-input-with-gnu-readline) to react to the keys in a custom way.

