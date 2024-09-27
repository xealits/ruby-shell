#!/usr/bin/ruby
##
# a shell

require 'open3'
#require 'tty-command'
require 'irb'
require 'readline'

require 'logger'

$logger = Logger.new($stdout) # create a new logger that writes to the console

#$tty_cmd = TTY::Command.new

$x = 55
x = 5

$prompt = '#{$last_exit_code.to_s.rjust 3} stdin> '
$last_exit_code = 0
$running_processes = []

$command_history = []
$command_history_max = 50 # TODO: they might have a data structure for this in Ruby - or just make a class
$cwd_history = [Dir.pwd]
$cwd_max_length = 5
$home_dir_aliases = ['~', '']

$aliases = {}

$global_binding  = binding
$current_binding = $global_binding
#puts "#{$global_binding} #{$current_binding}"

def proc_pid proc_num
  $logger.debug("proc_pid from jobs #{proc_num}")

  if proc_num > $running_processes.length
    puts "proc_num > $running_processes.length"
  end

  return $running_processes[proc_num][3][:pid]
end

def update_cmd_history new_command
  $logger.debug("update_cmd_history with #{new_command}")

  if $command_history.count >= $command_history_max
    command_history.shift
  end

  # push new element, if it is new
  if new_command != $command_history[-1]
    $command_history.push new_command
  end
end

def update_cwd_history prev_dir
  $logger.debug("update_cwd_history with #{prev_dir}")

  # update cwd history
  # make place in history, if it's at max
  if $cwd_history.count >= $cwd_max_length
    $cwd_history.shift
  end

  # push new element, if it is new
  if prev_dir != $cwd_history[-1]
    $cwd_history.push prev_dir
  end
end

def cwd_chdir directory
  $logger.debug("cwd_chdir #{directory}")

  #
  begin
    prev_dir = Dir.pwd
    Dir.chdir directory
    update_cwd_history prev_dir

  rescue Errno::ENOENT => error
    puts error.message
  end
end

def cwd dir
  $logger.debug("cwd #{dir}")

  dir.strip!

  # special cases
  if $home_dir_aliases.include? dir
    directory = Dir.home

  # prev dir
  elsif dir == '-'
    directory = $cwd_history[-1]

  # if directory does not exist, try to match it to one in history
  elsif (!Dir.exists? dir)
    match = $cwd_history.find {|e| e.include? dir}
    directory = if match then match else dir end
  else
    directory = dir
  end

  cwd_chdir directory
end

def clear_dead_jobs
  $logger.debug("clear_dead_jobs")

  n_jobs = $running_processes.length

  $running_processes.reject! do |p|
    isdead = !p[3].alive?
    $last_exit_code = p[3].value.exitstatus if isdead
    isdead # the return value of the block, that makes reject! reject
  end

  puts "cleared #{n_jobs - $running_processes.length} dead jobs"
end

# make the shell continue if "terminal stop" SIGTSTP Ctrl-Z is sent (the current process should go to background and sleep)
Signal.trap('TSTP') {
  $logger.debug('received TSTP, (if any) current proc went into background')

  #console binding # this launches a new console, inside of the original that got stopped
  # return from the stopped binding
  #puts "#{$global_binding} #{$current_binding}"

  if $current_binding != $global_binding
    proc_binding = $current_binding
    $current_binding = $global_binding
    proc_binding.eval("return 0")
  end

}

def read_fd fd
  # so, it's like just a pipe
  while s = fd.gets
    puts s
  end
end

def is_int? s
  true if Integer(s) rescue false
end

# TODO turn it into an autonomous process signal handler
# without the external kill command
def shell_kill_cmd command
  $logger.debug("shell_kill_cmd #{command}")

  # this is a mess:
  # command is a list of user_command.split
  # and shell_kill_cmd is called only if the first word in the command is kill

  # substitute all occurances of %i job number with the PID if possible
  command.map! do |e|
    if e[0] == '%' and is_int?(e[1..])
      i = Integer(e[1..])
      if $running_processes[i]
        $running_processes[i][3][:pid]
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
  $last_exit_code = wait_thr.value.exitstatus
  puts "#{stdout.read} #{stderr.read}"
  return $last_exit_code
end

def eval_cmd usr_command, at_binding
  $logger.debug("usr_command #{usr_command}")

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
    $aliases[alias_name] = alias_val
    return

  elsif command[0] == 'jobs'
    if command[1] == 'clear'
      clear_dead_jobs

    # if it acts on a process number
    elsif command[1] and /(\D+)/.match(command[1]).nil?
      proc_num = Integer(command[1])
      if proc_num >= $running_processes.length
        puts "there is no background process #{proc_num} see: jobs"
        return
      end

      field = command[2]
      if field == 'stdout'
        puts "proc #{proc_num} stdout:"
        puts $running_processes[proc_num][1].read

      elsif field == 'stderr'
        puts "proc #{proc_num} stdout:"
        $running_processes[proc_num][2].read

      elsif field == 'connect'
        # TODO: not sure if the following works
        #       it does not work with vim or nvim
        wait_thr = $running_processes[proc_num][3]
        pid = wait_thr[:pid]
        puts "connecting STDIN and STDOUT to proc #{proc_num} PID=#{pid}..."
        process_stdin = File.open("/proc/#{pid}/fd/0", "r+")
        process_stdout = File.open("/proc/#{pid}/fd/1", "w+")
        STDIN.reopen(process_stdin)
        STDOUT.reopen(process_stdout)
        #puts "connected STDIN and STDOUT to proc #{proc_num} PID=#{pid}..."
        $last_exit_code = wait_thr.value.exitstatus
      end

    else # print exiting processes/jobs
      $running_processes.each_with_index do |p, i|
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
  $aliases.each {|k, v| usr_command.sub! k, v}

  # exec the system process
  begin
    # this works for vim, but no control over streams:
    #$last_exit_code = system(usr_command)
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
      $running_processes.append [stdin, stdout, stderr, wait_thr, usr_command]

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
      $current_binding = binding #TODO: why do I save the binding here? for Ctrl-C?

      # just use Process.spawn
      pid = Process.spawn(usr_command, :in=>STDIN, :out=>STDOUT, :err=>STDERR)
      Process.wait(pid)
      $last_exit_code = $?.exitstatus

      $current_binding = $global_binding # restore
      return $last_exit_code
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
  $logger.debug("launch a console")

  while usr_command = Readline.readline(eval('"' + $prompt + '"'))
    #puts "#{$global_binding} #{$current_binding} | #{at_binding}"
    if usr_command.strip.empty?
      next
    end

    # if it is not empty -- add it to history
    # or TODO: add it if it succeeded
    Readline::HISTORY.push usr_command
    if usr_command.strip[...4] == 'exit'
      $logger.debug("exit command")
      # clear dead jobs and kill the running background processes
      clear_dead_jobs

      if $running_processes.length > 0
        puts "killing #{$running_processes.length} active backgroun processes"
        $running_processes.each do |_, _, _, wait_thr|
          `kill -KILL #{wait_thr[:pid]}`
          $last_exit_code = wait_thr.value.exitstatus
        end
        clear_dead_jobs
      end

      return usr_command.strip[4...].to_i

    else
      eval_cmd usr_command, at_binding
    end
  end
end


# comline executable
require 'optparse'
parser = OptionParser.new

$logger.level = Logger::WARN
parser.on('-d', '--debug', 'DEBUG logging level') do |value|
  $logger.level = Logger::DEBUG
end

parser.parse!

#
# an attempt at readline completion for history
# from https://stackoverflow.com/questions/10791060/how-can-i-do-readline-arguments-completion

# TODO: whenever the script throws, it messes up readline for the shell too
#       it kind of works, but needs testing - it messed up one ls and substituted it with s
Readline.completion_proc = proc do |cur_word|
  cur_line = Readline.line_buffer
  $logger.debug("\ncompletion: #{cur_line} and #{cur_word}")

  completion_list = []

  # try history completion first
  completion_list = $command_history.grep /^#{Regexp.escape(cur_line)}/ 

  if completion_list.length == 1
    # if completion returns 1 thing, it adds it to the readline buffer
    # so, it cannot be the whole history line
    completion_list[0].sub! cur_line, ''

  # if no match, do the default file completion
  elsif completion_list.length == 0
    $logger.debug("\ncompletion: not a history match")

    local_files = `ls`.split
    if cur_word == ' '
      completion_list = local_files
    else
      completion_list = local_files.grep /^#{cur_word}/
      #puts "completion: #{last_word} in #{local_files} -> #{completion_list}"
    end
  end

  completion_list
end

# TODO: make a proper command line utility here and then turn everything into a gem
exit_code = console $global_binding
$running_processes.each {|p| exit_code = p[3].value.exitstatus}
Kernel.exit exit_code
