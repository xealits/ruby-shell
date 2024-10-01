#!/usr/bin/ruby
##
# a shell

require 'open3'
#require 'tty-command'
require 'irb'
require 'readline'

require 'logger'


def read_fd fd
  # so, it's like just a pipe
  while s = fd.gets
    puts s
  end
end

def is_int? s
  true if Integer(s) rescue false
end

class Comline
  def initialize
    @logger = Logger.new($stdout) # create a new logger that writes to the console

    #$tty_cmd = TTY::Command.new

    # a test thing
    @x = 55

    @prompt = '#{$last_exit_code.to_s.rjust 3} stdin> '
    @last_exit_code = 0
    @running_processes = []

    @command_history = []
    @command_history_max = 50 # TODO: they might have a data structure for this in Ruby - or just make a class
    @cwd_history = [Dir.pwd + '/']
    @cwd_max_length = 5
    @home_dir_aliases = ['~', '']

    @aliases = {}

    @global_binding  = binding
    @current_binding = $global_binding
    #puts "#{$global_binding} #{$current_binding}"

    # make the shell continue if "terminal stop" SIGTSTP Ctrl-Z is sent (the current process should go to background and sleep)
    # TODO: figure out how to handle this
    Signal.trap('TSTP') {
      @logger.debug('received TSTP, (if any) current proc went into background')

      #console binding # this launches a new console, inside of the original that got stopped
      # return from the stopped binding
      #puts "#{$global_binding} #{$current_binding}"

      if @current_binding != @global_binding
        proc_binding = @current_binding
        @current_binding = @global_binding
        proc_binding.eval("return 0")
      end
    }

    @last_completion_line = ''
    @check_history = true
    # my completion proc:
    # TODO: it should be able to return to the previous completion
    Readline.completion_proc = proc do |cur_word|
      # def completion_proc cur_word
      cur_line = Readline.line_buffer
      @logger.debug("\ncompletion: #{cur_line} and #{cur_word} and #{@check_history}")

      completion_list = []

      # if already tried o complete this line
      # maybe the user gets a history prompt and does not want it
      # skip history and go for files
      if @last_completion_line == cur_line
        @check_history = !@check_history
      else
        @last_completion_line = cur_line
        @check_history = true
      end

      # try history completion first
      if @check_history
        completion_list = match_history cur_line, cur_word
        #if completion_list.length == 0
        #  completion_list = match_local_files cur_word
        #end
      end

      if completion_list.length == 0
        completion_list = match_local_files cur_word
        #if completion_list.length == 0
        #  completion_list = match_history cur_line
        #end
      end

      completion_list
    end
  end

  def set_log_level loggerLevel
    @logger.level = loggerLevel
  end

  def jobs_exit_code
    exit_code = nil
    @running_processes.each {|p| exit_code = p[3].value.exitstatus}
    return exit_code
  end


  def proc_pid proc_num
    @logger.debug("proc_pid from jobs #{proc_num}")

    if proc_num > @running_processes.length
      puts "proc_num > $running_processes.length"
    end

    return @running_processes[proc_num][3][:pid]
  end

  def proc_stdin proc_id
    if proc_id.is_a? String and proc_id[0] == '%'
      proc_id = proc_pid proc_id[1..].to_i
    end

    return "/proc/#{proc_id}/fd/0"
  end

  def update_cmd_history new_command
    @logger.debug("update_cmd_history with #{new_command}")

    if @command_history.count >= @command_history_max
      command_history.shift
    end

    # push new element, if it is new
    if new_command != @command_history[-1]
      @command_history.push new_command
    end

    @logger.debug("update_cmd_history done: #{@command_history}")
  end

  def update_cwd_history prev_dir
    @logger.debug("update_cwd_history with #{prev_dir}")

    # update cwd history
    # make place in history, if it's at max
    if @cwd_history.count >= @cwd_max_length
      @cwd_history.shift
    end

    # push new element, if it is new
    if prev_dir != @cwd_history[-1]
      @cwd_history.push prev_dir
    end
  end

  def cwd_chdir directory
    @logger.debug("cwd_chdir #{directory}")

    #
    begin
      cur_pwd = Dir.pwd
      abs_new_pwd = File.expand_path(directory) + '/'
      # TODO: adding / is britle: what is the user asks for dir/// ?
      #       and it won't match with history dir/
      #       I need a common minimal way: collapse /// into one / is probably the best
      Dir.chdir abs_new_pwd
      update_cwd_history abs_new_pwd

    rescue Errno::ENOENT, Errno::ENOTDIR => error
      puts error.message
    end
  end

  def cwd dir
    @logger.debug("cwd #{dir}")

    dir.strip!

    # special cases
    if @home_dir_aliases.include? dir
      directory = Dir.home

    # prev dir
    elsif dir == '-'
      directory = @cwd_history[-1]

    # if directory does not exist, try to match it to one in history
    elsif (!Dir.exist? dir)
      # among all the matches, pick the smallest one
      #match = $cwd_history.find {|e| e.include? dir}
      matches = @cwd_history.filter {|e| e.include? dir}
      match   = matches.sort_by {|s| s.length} [0]
      directory = if match then match else dir end
      @logger.debug "tried a directory from histry: #{dir} #{match} : #{matches} : #{@cwd_history}"

    else
      directory = dir
    end

    cwd_chdir directory
  end

  def clear_dead_jobs
    @logger.debug("clear_dead_jobs")

    n_jobs = @running_processes.length

    @running_processes.reject! do |p|
      isdead = !p[3].alive?
      @last_exit_code = p[3].value.exitstatus if isdead
      isdead # the return value of the block, that makes reject! reject
    end

    puts "cleared #{n_jobs - @running_processes.length} dead jobs"
  end

  # TODO turn it into an autonomous process signal handler
  # without the external kill command
  def shell_kill_cmd command
    @logger.debug("shell_kill_cmd #{command}")

    # this is a mess:
    # command is a list of user_command.split
    # and shell_kill_cmd is called only if the first word in the command is kill

    # substitute all occurances of %i job number with the PID if possible
    command.map! do |e|
      if e[0] == '%' and is_int?(e[1..])
        i = Integer(e[1..])
        if @running_processes[i]
          @running_processes[i][3][:pid]
        else
          STDERR.puts "no job process is running at index #{i}"
          return
        end
      else
        # if it is not a %i -- just leave it as is
        e
      end
    end

    # rebuild the command string and launch the external kill command
    usr_command = command.join ' '
    puts usr_command
    _, stdout, stderr, wait_thr = Open3.popen3(usr_command)
    @last_exit_code = wait_thr.value.exitstatus
    puts "#{stdout.read} #{stderr.read}"
    return @last_exit_code
  end

  def eval_cmd usr_command, at_binding
    @logger.debug("usr_command #{usr_command}")

    usr_command.strip!
    update_cmd_history usr_command

    # special control cases
    command = usr_command.split
    if command[0] == 'irb'
      at_binding.irb
      return

    elsif command[0] == 'cd'
      directory = usr_command.strip[2...].strip
      cwd directory
      return

    elsif command[0] == 'alias'
      alias_name = command[1]
      alias_val  = command[2..].join ' '
      @aliases[alias_name] = alias_val
      return

    elsif command[0] == 'jobs'
      if command[1] == 'clear'
        clear_dead_jobs

      # if it acts on a process number
      elsif command[1] and /(\D+)/.match(command[1]).nil?
        proc_num = Integer(command[1])
        if proc_num >= @running_processes.length
          puts "there is no background process #{proc_num} see: jobs"
          return
        end

        field = command[2]
        if field == 'stdout'
          puts "proc #{proc_num} stdout:"
          puts @running_processes[proc_num][1].read

        elsif field == 'stderr'
          puts "proc #{proc_num} stdout:"
          @running_processes[proc_num][2].read

        elsif field == 'connect'
          # TODO: not sure if the following works
          #       it does not work with vim or nvim
          wait_thr = @running_processes[proc_num][3]
          pid = wait_thr[:pid]
          puts "connecting STDIN and STDOUT to proc #{proc_num} PID=#{pid}..."
          process_stdin = File.open("/proc/#{pid}/fd/0", "r+")
          process_stdout = File.open("/proc/#{pid}/fd/1", "w+")
          STDIN.reopen(process_stdin)
          STDOUT.reopen(process_stdout)
          #puts "connected STDIN and STDOUT to proc #{proc_num} PID=#{pid}..."
          @last_exit_code = wait_thr.value.exitstatus
        end

      else # print exiting processes/jobs
        @running_processes.each_with_index do |p, i|
          pid = p[3][:pid]
          #cmd = `cat /proc/#{pid}/comm`
          cmd = p[4]
          puts "#{i}: #{pid} #{cmd} #{p[3]}"
        end
      end
      return

    elsif command[0] == 'kill' # handle %1 sort of ID
      return shell_kill_cmd command
    end

    # the shell command
    # eval the ruby code in the command, like: ls #{x+5}
    # TODO: what happens here if people use %{} in their command line string?
    usr_command = '%{' + usr_command + '}'
    if at_binding
      usr_command = at_binding.eval(usr_command)
    else
      usr_command = eval(usr_command)
    end

    # TODO: so, how good is this for actual Ruby code? How does it work now?
    # There is the environment of Ruby interpreter, which spawns the system commands.
    # The irb keyword gets you straight into the Ruby interpreter.
    # You can run some Ruby code in #{} and get the outputs.
    # How to get the data back: from the system commands to Ruby?
    # Currently, you enter irb, it gets you into Ruby interpreter,
    # and you can call any system command from there.
    # To have a mixed language, you'd probably add something like #{x + `echo bar`}.
    #
    # The protocol interface, serialisation, should pop up somewhere there.
    # System commands return some parseable data, Ruby easily picks it up.

    # substitute aliases
    @aliases.each {|k, v| usr_command.sub! k, v}

    # exec the system process
    begin
      # this works for vim, but no control over streams:
      #@last_exit_code = system(usr_command)
      spawn_process = false
      usr_command, spawn_process = usr_command[...-1], true if usr_command.split[-1] == '&'

      if spawn_process

        stdin, stdout, stderr, wait_thr = Open3.popen3(usr_command)
        puts "stdin.tty? #{stdin.tty?}"
        # TODO this won't work for vim
        #      I guess I need a thread for spawned background processes.
        #      The point is that Vim connects to stdin, stdout and goes to sleep
        #      in the background. Then, you wake it up to send to foreground.
        #      In my case, I kind of want to really connect-disconnect file descriptors.
        #      I.e. the should be a command to connect current STDIN and STDOUT to the background running process.
        #      Like in the example with xterm.
        #      Then you need some signal to disconnect from the process file descriptors.

        # let's save it as a running proc
        @running_processes.append [stdin, stdout, stderr, wait_thr, usr_command]

        puts "launched a process #{wait_thr[:pid]}"
        # TODO: what if the process quickly exits, like stdbuf -o0 sh ?
        # then it shows up as dead in jobs listing
        # and I save its stdout and stdin, but there is no command to display them?
        # the only command I have is jobs clear.
        #
        # Should there be a common way to connect to stdout of a running process
        # and log it into some ringbuffer/pipe like data structure?
        # I.e. the point is to just work with Linux and /proc instead of creating
        # a new layer of jobs management system in the shell.
        # Linux runs processes by their PIDs. What's needed are some domain names,
        # like unit name in systemd, groups of processes, etc. Also resources:
        # ports, sockets, files, locks.
        #
        # Then also, attach event handlers to that data structure?
        # What Open3.popen3 returns? Are these some stream generators or already
        # the whole text from the file descriptors?
        # yeah, its an IO object:
        #   0 stdin> jobs 0 stdout
        #   proc 0 stdout:
        #   #<IO:0x000077c296ed2508>
        return

      else
        # save this binding point and follow the command
        @current_binding = binding #TODO: why do I save the binding here? for Ctrl-C?

        # just use Process.spawn
        pid = Process.spawn(usr_command, :in=>STDIN, :out=>STDOUT, :err=>STDERR)
        Process.wait(pid)
        @last_exit_code = $?.exitstatus

        @current_binding = @global_binding # restore
        return @last_exit_code
      end

      # TODO: retry this:
      # does not really work:
      # xterm, screen, etc launch something and do not matter themselves
      # how to get the pid of the screen session, shell/fish that they opened?
      # this works:
      #   0 stdin> stdbuf -o0 sh
      # launched a process 24148
      #   0 stdin> xterm -fg grey -bg black -e ./ruby_read_fd.rb 24148
      # launched a process 24151
      #   0 stdin> xterm -fg grey -bg black -e 'cat >> /proc/24148/fd/0'
      # launched a process 24154

    rescue Errno::ENOENT => error
      # command not found
      #puts "command not found: #{usr_command}"
      puts error.message
    end
  end

  def console (at_binding = nil)
    @logger.debug("launch a console")

    while usr_command = Readline.readline(eval('"' + @prompt + '"'))
      #puts "#{@global_binding} #{@current_binding} | #{at_binding}"
      if usr_command.strip.empty?
        next
      end

      # if it is not empty -- add it to history
      # or TODO: add it if it succeeded
      Readline::HISTORY.push usr_command
      if usr_command.strip[...4] == 'exit'
        @logger.debug("exit command")
        # clear dead jobs and kill the running background processes
        clear_dead_jobs

        if @running_processes.length > 0
          puts "killing #{@running_processes.length} active backgroun processes"
          @running_processes.each do |_, _, _, wait_thr|
            `kill -KILL #{wait_thr[:pid]}`
            @last_exit_code = wait_thr.value.exitstatus
          end
          clear_dead_jobs
        end

        return usr_command.strip[4...].to_i

      else
        eval_cmd usr_command, at_binding
      end
    end
  end


#
# an attempt at readline completion for history
# from https://stackoverflow.com/questions/10791060/how-can-i-do-readline-arguments-completion

# TODO: whenever the script throws, it messes up readline for the shell too
#       it kind of works, but needs testing - it messed up one ls and substituted it with s

  def match_history comline, completion_word
    @logger.debug("\nmatch_history: #{comline} and #{completion_word}")
    completion_list = []

    # try history completion first
    completion_list = @command_history.grep /^#{Regexp.escape(comline)}/ 

    #if completion_list.length == 1
    #  # if completion returns 1 thing, it adds it to the readline buffer
    #  # so, it cannot be the whole history line
    #  #completion_list[0].sub! comline, ''
    #  # this does not work right either
    #  # let's try this:
    #  completion_list = completion_list[0]
    #end
    # no
    # if it is completing the word, then it has to return 
    if completion_list.length > 0 # and completion_word.strip.empty?
      @logger.debug("\nmatch_history: matched commands, strip prefix: #{completion_list}")
      # OK, this should work:
      completion_list = completion_list.map do |cmd_record|
        # the prefix is everything in the completion comline until the current completion word
        #
        # completion is supposed to return a list of substitutions
        # for _the current completion word_
        #
        cmd_record[(comline.length - completion_word.length)..]
      end
      @logger.debug("\nmatch_history: striped prefix: #{completion_list}")
    end

    @logger.debug("\nmatch_history: return #{completion_list}")
    completion_list
  end

  def match_local_files cur_word
    @logger.debug("\nmatch_local_files: not a history match")

    completion_list = []

    #local_files = `ls #{cur_word}*`.split
    completion_list = [] # local_files
    if cur_word == ' '
      completion_list = `ls`.split
      #completion_list = local_files
    else
      #local_files = `ls -d #{cur_word}*`.split
      stdin, stdout, stderr, wait_thr = Open3.popen3("ls -d #{cur_word}*")
      _ = wait_thr.value.exitstatus
      local_files = stdout.read.split
      #completion_list = local_files.grep /^#{cur_word}/
      # if it returns only 1 match and it is a directory - list directory contents
      if local_files.length == 1 and File.directory? local_files[0]
        local_files = `ls -d #{local_files[0]}/*`.split
      end
      completion_list = local_files
      #puts "completion: #{last_word} in #{local_files} -> #{completion_list}"
    end

    completion_list
  end
end

=begin
$last_completion_line = ''
$check_history = true
Readline.completion_proc = proc do |cur_word|
  cur_line = Readline.line_buffer
  $logger.debug("\ncompletion: #{cur_line} and #{cur_word} and #{$check_history}")

  completion_list = []

  # if already tried o complete this line
  # maybe the user gets a history prompt and does not want it
  # skip history and go for files
  if $last_completion_line == cur_line
    $check_history = !$check_history
  else
    $last_completion_line = cur_line
    $check_history = true
  end

  # try history completion first
  if $check_history
    completion_list = match_history cur_line, cur_word
    #if completion_list.length == 0
    #  completion_list = match_local_files cur_word
    #end
  end

  if completion_list.length == 0
    completion_list = match_local_files cur_word
    #if completion_list.length == 0
    #  completion_list = match_history cur_line
    #end
  end

  completion_list
end
=end

=begin
TODO:

The point to turn comline into a class
is the need to launch multiple shells,
possibly remote ones too.
Then, I'd need to communicate between
the shells. So, it needs some thinking.
Shell is a wrapped Ruby interpreter.
It changes Readline completion, and
sets signal capture. But what if you
launch multiple objects of it inside
one process?

Let's prototype it. Try to do something, then encode.
Remote streams:
https://unix.stackexchange.com/questions/34273/can-i-pipe-stdout-on-one-server-to-stdin-on-another-server
Try:
$ tar -cf - /path/to/backup/dir | ssh remotehost "cat - > backupfile.tar"
-- I could compress it into one Ruby call like
   tar .. > #{ssh_file "hostname:~/.../file"}
   which which does whatever to make it work.

And netcat:
Similarly, netcat on both ends makes for a great simple, easy communication channel. tar cf - /path/to/dir | nc 1.2.3.4 5000 on one server, nc -l -p 5000 > backupfile.tar on the other.

And implement a pipe into Ruby. I.e. stuff like
echo hello > #{proc_stdin ...}
It should be able to launch a thread or a process running some Ruby code, like SSH lib,
with a stdin pipe open for the shell call.
There are a bunch of moving pieces here.
=end
