#!/usr/bin/ruby
##
# a shell

require 'open3'
require 'irb'
require 'readline'

$x = 55
x = 5

$prompt = '#{$last_exit_code.to_s.rjust 3} stdin> '
$last_exit_code = 0
$running_processes = []

$cwd_history = [Dir.pwd]
$cwd_max_length = 5
$home_dir_aliases = ['~', '']

$global_binding  = binding
$current_binding = $global_binding
#puts "#{$global_binding} #{$current_binding}"

def update_cwd_history prev_dir
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
  $running_processes.reject! do |p|
    isdead = !p[3].alive?
    $last_exit_code = p[3].value.exitstatus if isdead
    isdead # the return value of the block, that makes reject! reject
  end
end

# make the shell continue if "terminal stop" SIGTSTP Ctrl-Z is sent (the current process should go to background and sleep)
Signal.trap('TSTP') {
  puts 'received TSTP, (if any) current proc went into background'
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

def eval_cmd usr_command, at_binding
  usr_command.strip!

  # special control cases
  command = usr_command.split
  if command[0] == 'irb'
    at_binding.irb
    return

  elsif command[0] == 'cd'
    directory = usr_command.strip[2...].strip
    cwd directory
    return

  elsif command[0] == 'jobs'
    if command[1] == 'clear'
      clear_dead_jobs
    else # print exiting processes/jobs
      $running_processes.each_with_index {|p, i| puts "#{i}: #{p[3][:pid]} #{p[3]}"}
    end
    return
  end

  # the shell command
  # eval the ruby code in the command, like: ls #{x+5}
  if at_binding
    usr_command = at_binding.eval('"' + usr_command + '"')
  else
    usr_command = eval('"' + usr_command + '"')
  end

  # exec the system process
  begin
    spawn_process = false
    usr_command, spawn_process = usr_command[...-1], true if usr_command.split[-1] == '&'

    stdin, stdout, stderr, wait_thr = Open3.popen3(usr_command)
    # let's save it as a running proc
    $running_processes.append [stdin, stdout, stderr, wait_thr]

    if spawn_process
      puts "launched a process #{wait_thr[:pid]}" # TODO: what if the process quickly exits, like stdbuf -o0 sh ?
      return

    else
      # save this binding point and follow the command
      $current_binding = binding
      read_fd stdout
      $last_exit_code = wait_thr.value.exitstatus
      $running_processes.pop
      $current_binding = $global_binding # restore
      puts "#{stdout.read} #{stderr.read}"
      return $last_exit_code
    end

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
  while usr_command = Readline.readline(eval('"' + $prompt + '"'))
    #puts "#{$global_binding} #{$current_binding} | #{at_binding}"
    if usr_command.strip.empty?
      next
    end

    # if it is not empty -- add it to history
    # or TODO: add it if it succeeded
    Readline::HISTORY.push usr_command
    if usr_command.strip[...4] == 'exit'
      return usr_command.strip[4...].to_i
    else
      eval_cmd usr_command, at_binding
    end
  end
end

exit_code = console $global_binding
$running_processes.each {|p| exit_code = p[3].value.exitstatus}
Kernel.exit exit_code
